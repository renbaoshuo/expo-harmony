import { LifecycleState, RNInstanceImpl, RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import type common from '@ohos.app.ability.common';
import type { UIContext } from '@kit.ArkUI';
import { ExpoPlatformServiceError, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import bundleManager from '@ohos.bundle.bundleManager';
import deviceInfo from '@ohos.deviceInfo';
import hidebug from '@ohos.hidebug';
import i18n from '@ohos.i18n';
import process from '@ohos.process';

import { EXPO_APP_METRICS_VERSION, REACT_NATIVE_VERSION } from './AppMetricsBuildConfig';
import {
  AppMetadata,
  AVAILABLE_MEMORY_METRIC,
  FrameRateMetrics,
  MEMORY_CATEGORY,
  MemoryUsageSnapshot,
  Metric,
  PHYSICAL_MEMORY_METRIC,
} from './AppMetricsModels';
import {
  AppMetricsServiceLifecycle,
  kilobytesToBytes,
  processAgeMilliseconds,
  processUptimeMilliseconds,
  remainingKilobytes,
} from './AppMetricsSemantics';
import { ProcessClock, StartupCoordinator } from './AppMetricsStartupCoordinator';
import { appMetricsStorage, AppMetricsStorage } from './AppMetricsStorage';
import { FrameMetricsRecorder } from './FrameMetricsRecorder';

const SERVICE_NAME: string = 'ExpoAppMetricsService';
const HARMONY_OS_NAME: string = 'HarmonyOS';
const MILLISECONDS_PER_SECOND: number = 1000;
const JS_BUNDLE_EXECUTION_FINISH = 'JS_BUNDLE_EXECUTION_FINISH';
let registered: boolean = false;
const startupScopes: WeakMap<common.UIAbilityContext, StartupScope> = new WeakMap<common.UIAbilityContext, StartupScope>();

class MetricAttributes {
  routeName?: string;
  params?: Record<string, ESObject>;
}

class StartupScope {
  readonly coordinator: StartupCoordinator;
  private readonly contexts: Map<number, UITurboModuleContext> = new Map<number, UITurboModuleContext>();

  constructor(context: UITurboModuleContext, storage: AppMetricsStorage, metadata: () => Promise<AppMetadata>) {
    const warn = (message: string): void => context.logger.warn(message);
    const clock = new ProcessClock((): number => Date.now(), monotonicNowMs(warn));

    this.coordinator = new StartupCoordinator({
      storage,
      frameRecorder: new FrameMetricsRecorder((): UIContext | null => this.getUIContext(), warn),
      processClock: clock,
      metadata,
      now: (): number | undefined => monotonicNowMs(warn),
      warn,
    });
  }

  retain(context: UITurboModuleContext): number {
    const id = this.coordinator.retain();

    this.contexts.set(id, context);

    return id;
  }

  release(id: number): boolean {
    this.contexts.delete(id);

    return this.coordinator.release(id);
  }

  private getUIContext(): UIContext | null {
    const contexts = Array.from(this.contexts.values());
    for (let index = contexts.length - 1; index >= 0; index -= 1) {
      try {
        const context = contexts[index].getUIContext();
        if (context !== null && context !== undefined) return context;
      } catch (_) {}
    }

    return null;
  }
}

function startupScope(context: UITurboModuleContext, storage: AppMetricsStorage, metadata: () => Promise<AppMetadata>): StartupScope {
  const abilityContext = context.uiAbilityContext;
  const current = startupScopes.get(abilityContext);
  if (current !== undefined && !current.coordinator.isShutdown()) return current;

  const scope = new StartupScope(context, storage, metadata);

  startupScopes.set(abilityContext, scope);

  return scope;
}

class ExpoAppMetricsService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;
  private readonly storage: AppMetricsStorage;
  private readonly scope: StartupScope;
  private readonly startup: StartupCoordinator;
  private readonly startupClientId: number;
  private readonly lifecycle: AppMetricsServiceLifecycle = new AppMetricsServiceLifecycle();
  private readonly cleanups: Array<() => void> = [];
  private readonly sessionIds: Set<string> = new Set<string>();
  private readonly snapshots: Set<Promise<MemoryUsageSnapshot>> = new Set<Promise<MemoryUsageSnapshot>>();
  private metadataTask?: Promise<AppMetadata>;

  constructor(context: UITurboModuleContext) {
    this.context = context;
    this.storage = appMetricsStorage(context.uiAbilityContext);
    this.scope = startupScope(context, this.storage, (): Promise<AppMetadata> => this.metadata());
    this.startup = this.scope.coordinator;
    this.startupClientId = this.scope.retain(context);

    this.cleanups.push(
      context.rnInstance.subscribeToLifecycleEvents('FOREGROUND', (): void => this.onForeground()),
      context.rnInstance.subscribeToLifecycleEvents('BACKGROUND', (): void => this.onBackground()),
      context.rnInstance.subscribeToLifecycleEvents(JS_BUNDLE_EXECUTION_FINISH, (): void => this.onBundleExecutionFinish()),
    );

    const warn = (message: string): void => context.logger.warn(message);
    const state = context.rnInstance.getLifecycleState();
    if (state === LifecycleState.READY) {
      this.onForeground();
    } else if (state === LifecycleState.BEFORE_CREATE) {
      this.startup.primeForeground(this.startupClientId, monotonicNowMs(warn));
    }
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    this.assertActive();

    if (method === 'getStoredEntries') return await this.storage.getAllSessions();

    if (method === 'clearStoredEntries') {
      await this.storage.clear();

      return null;
    }

    if (method === 'addCustomMetricToSession') {
      const id = requireSessionId(args[0]);
      const metric = parseCustomMetric(this.storage, id, args[1]);

      await this.storage.addMetrics(id, [metric]);

      return null;
    }

    if (method === 'takeMemoryUsageSnapshotAsync') {
      const sessionId = optionalSessionId(args[0]);

      return await this.captureMemorySnapshot(sessionId);
    }

    if (method === 'getMemoryUsageSnapshotAsync') return await this.captureMemorySnapshot();
    if (method === 'getAppStartupTimesAsync') return this.startup.getAppStartupTimes();
    if (method === 'getFrameRateMetricsAsync') return new FrameRateMetrics(this.startup.currentFrameMetrics());

    throw new ExpoPlatformServiceError('ERR_APP_METRICS_UNKNOWN_METHOD', `Unknown Expo App Metrics Harmony method '${method}'.`);
  }

  invokeSync(method: string, args: ESObject[]): ESObject {
    this.assertActive();

    if (method === 'markFirstRender') {
      this.startup.markFirstRender();

      return null;
    }

    if (method === 'markInteractive') {
      this.startup.markInteractive(parseMetricAttributes(args[0]));

      return null;
    }

    if (method === 'startSession') {
      const id = this.storage.createSessionId();

      this.sessionIds.add(id);
      this.storage.scheduleStartSession(id, new Date().toISOString(), this.metadata());

      return id;
    }

    if (method === 'stopSession') {
      const id = requireSessionString(args[0]);

      this.scheduleStopSession(id);

      return null;
    }

    throw new ExpoPlatformServiceError('ERR_APP_METRICS_UNKNOWN_METHOD', `Unknown synchronous Expo App Metrics Harmony method '${method}'.`);
  }

  onDestroy(): void {
    const ids = this.beginShutdown();

    ids.forEach((sessionId: string): void => {
      this.storage.scheduleStopSession(sessionId);
    });
  }

  async prepareForReload(): Promise<void> {
    const ids = this.beginShutdown();

    await Promise.all(
      Array.from(this.snapshots).map(async (snapshot: Promise<MemoryUsageSnapshot>): Promise<void> => {
        try {
          await snapshot;
        } catch (_) {}
      }),
    );

    await Promise.all(
      ids.map((sessionId: string): Promise<void> => {
        return this.storage.stopSession(sessionId).then((): void => {
          this.sessionIds.delete(sessionId);
        });
      }),
    );
  }

  private onForeground(): void {
    if (!this.lifecycle.isActive()) return;

    this.startup.onForeground(this.startupClientId);
  }

  private onBackground(): void {
    if (!this.lifecycle.isActive()) return;

    this.startup.onBackground(this.startupClientId);
  }

  private onBundleExecutionFinish(): void {
    if (!this.lifecycle.isActive()) return;

    this.startup.recordBundleLoad(readBundleLoadTime(this.context));
    this.startup.onForeground(this.startupClientId);
  }

  private scheduleStopSession(sessionId: string): void {
    this.storage
      .stopSession(sessionId)
      .then((): void => {
        this.sessionIds.delete(sessionId);
      })
      .catch((error: Object): void => {
        this.context.logger.warn(`Unable to stop Expo App Metrics session: ${String(error)}`);
      });
  }

  private beginShutdown(): string[] {
    const started = this.lifecycle.beginShutdown();
    const ids: string[] = Array.from(this.sessionIds);
    if (!started) return ids;

    if (this.scope.release(this.startupClientId)) ids.unshift(this.startup.appSessionId);

    this.cleanups.forEach((cleanup: () => void): void => {
      try {
        cleanup();
      } catch (error) {
        this.context.logger.warn(`Unable to remove an Expo App Metrics lifecycle subscription: ${String(error)}`);
      }
    });
    this.cleanups.length = 0;

    return ids;
  }

  private assertActive(): void {
    if (!this.lifecycle.isActive()) {
      throw new ExpoPlatformServiceError('ERR_APP_METRICS_DESTROYED', 'The Expo App Metrics Harmony service has already begun shutting down.');
    }
  }

  private async captureMemorySnapshot(sessionId?: string): Promise<MemoryUsageSnapshot> {
    const snapshot = this.takeMemorySnapshot(sessionId);

    this.snapshots.add(snapshot);

    try {
      return await snapshot;
    } finally {
      this.snapshots.delete(snapshot);
    }
  }

  private async takeMemorySnapshot(sessionId?: string): Promise<MemoryUsageSnapshot> {
    try {
      const info = await readNativeMemoryInfo();

      const physical = kilobytesToBytes(info.pss);
      const available = availableMemoryBytes();
      const snapshot = new MemoryUsageSnapshot(physical, available);

      if (sessionId !== undefined) {
        this.assertActive();

        const timestamp = new Date().toISOString();

        await this.storage.addMetrics(sessionId, [
          new Metric(this.storage.createSessionId(), sessionId, timestamp, MEMORY_CATEGORY, PHYSICAL_MEMORY_METRIC, physical),
          new Metric(this.storage.createSessionId(), sessionId, timestamp, MEMORY_CATEGORY, AVAILABLE_MEMORY_METRIC, available),
        ]);
      }

      return snapshot;
    } catch (error) {
      if (error instanceof ExpoPlatformServiceError) {
        throw new ExpoPlatformServiceError(error.code, error.message);
      }

      throw new ExpoPlatformServiceError('ERR_APP_METRICS_MEMORY_SNAPSHOT', `Unable to capture a HarmonyOS memory usage snapshot: ${String(error)}`);
    }
  }

  private metadata(): Promise<AppMetadata> {
    if (this.metadataTask === undefined) {
      this.metadataTask = readAppMetadata(this.context).catch((error: Object): AppMetadata => {
        this.context.logger.warn(`Unable to collect Expo App Metrics metadata: ${String(error)}`);

        return new AppMetadata();
      });
    }

    return this.metadataTask;
  }
}

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext): ExpoAppMetricsService => new ExpoAppMetricsService(context),
  });

  registered = true;
}

export class ExpoAppMetricsPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerService();
    super(context);
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-app-metrics';
  }
}

function monotonicNowMs(warn?: (message: string) => void): number | undefined {
  try {
    if (typeof process.uptime !== 'function' || typeof process.getStartRealtime !== 'function') {
      return undefined;
    }

    const systemUptimeMs = processUptimeMilliseconds(process.uptime());
    if (systemUptimeMs === undefined) return undefined;

    return processAgeMilliseconds(systemUptimeMs, process.getStartRealtime());
  } catch (error) {
    warn?.(`Unable to read the HarmonyOS monotonic process clock: ${String(error)}`);

    return undefined;
  }
}

function requireSessionId(value: ESObject): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new ExpoPlatformServiceError('ERR_APP_METRICS_INVALID_SESSION', 'Expo App Metrics expected a non-empty session ID.');
  }

  return value;
}

function requireSessionString(value: ESObject): string {
  if (typeof value !== 'string') {
    throw new ExpoPlatformServiceError('ERR_APP_METRICS_INVALID_SESSION', 'Expo App Metrics expected a session ID string.');
  }

  return value;
}

function optionalSessionId(value: ESObject): string | undefined {
  if (value === undefined || value === null) return undefined;

  return requireSessionId(value);
}

function parseMetricAttributes(value: ESObject): MetricAttributes {
  if (value === undefined || value === null) return new MetricAttributes();

  const input = requireRecord(value, 'metric attributes');
  const result = new MetricAttributes();
  result.routeName = optionalString(input['routeName'], 'routeName');
  result.params = optionalParams(input['params']);

  return result;
}

function parseCustomMetric(storage: AppMetricsStorage, sessionId: string, raw: ESObject): Metric {
  const input = requireRecord(raw, 'custom metric');
  const category = requireString(input['category'], 'category');
  const name = requireString(input['name'], 'name');
  const value: ESObject = input['value'] as ESObject;
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new ExpoPlatformServiceError('ERR_APP_METRICS_INVALID_METRIC', "Expo App Metrics expected custom metric 'value' to be a finite number.");
  }

  return new Metric(
    storage.createSessionId(),
    sessionId,
    new Date().toISOString(),
    category,
    name,
    value,
    optionalString(input['routeName'], 'routeName'),
    optionalParams(input['params']),
  );
}

function requireRecord(value: ESObject, label: string): Record<string, ESObject> {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoPlatformServiceError('ERR_APP_METRICS_INVALID_ARGUMENT', `Expo App Metrics expected ${label} to be an object.`);
  }

  return value as Record<string, ESObject>;
}

function requireString(value: ESObject, field: string): string {
  if (typeof value !== 'string') {
    throw new ExpoPlatformServiceError('ERR_APP_METRICS_INVALID_METRIC', `Expo App Metrics expected custom metric '${field}' to be a string.`);
  }

  return value;
}

function optionalString(value: ESObject, field: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') {
    throw new ExpoPlatformServiceError('ERR_APP_METRICS_INVALID_ARGUMENT', `Expo App Metrics expected '${field}' to be a string when provided.`);
  }

  return value;
}

function optionalParams(value: ESObject): Record<string, ESObject> | undefined {
  if (value === undefined || value === null) return undefined;

  const params = requireRecord(value, "'params'");

  try {
    const json = JSON.stringify(params);
    const result: ESObject = JSON.parse(json);

    return result as Record<string, ESObject>;
  } catch (error) {
    throw new ExpoPlatformServiceError(
      'ERR_APP_METRICS_INVALID_ARGUMENT',
      `Expo App Metrics expected 'params' to contain JSON-serializable values: ${String(error)}`,
    );
  }
}

function availableMemoryBytes(): number {
  if (typeof hidebug.getAppVMMemoryInfo !== 'function') {
    throw new ExpoPlatformServiceError(
      'ERR_APP_METRICS_MEMORY_API',
      'HarmonyOS HiDebug does not expose the application VM memory information required by Expo App Metrics.',
    );
  }

  try {
    const info = hidebug.getAppVMMemoryInfo();

    return kilobytesToBytes(remainingKilobytes(info.heapUsed, info.totalHeap));
  } catch (error) {
    throw new ExpoPlatformServiceError('ERR_APP_METRICS_MEMORY_API', `Unable to read HarmonyOS application VM memory information: ${String(error)}`);
  }
}

async function readNativeMemoryInfo(): Promise<hidebug.NativeMemInfo> {
  // ArkTS requires a literal here so it can validate and narrow API availability at compile time.
  if (!deviceInfo.apiAvailable(20)) {
    throw new ExpoPlatformServiceError(
      'ERR_APP_METRICS_MEMORY_API',
      'HarmonyOS HiDebug does not expose the asynchronous application memory API required to avoid blocking the UI thread.',
    );
  }
  if (typeof hidebug.getAppNativeMemInfoAsync !== 'function') {
    throw new ExpoPlatformServiceError(
      'ERR_APP_METRICS_MEMORY_API',
      'HarmonyOS HiDebug does not expose the asynchronous application memory API required to avoid blocking the UI thread.',
    );
  }

  return await hidebug.getAppNativeMemInfoAsync();
}

function readBundleLoadTime(context: UITurboModuleContext): number | undefined {
  try {
    const snapshot = (context.rnInstance as RNInstanceImpl).getPerformanceMetricsSnapshot();
    const duration = snapshot?.SCRIPT_EXECUTION;
    if (duration === undefined || !Number.isFinite(duration) || duration <= 0) {
      context.logger.warn('RNOH did not provide a valid SCRIPT_EXECUTION duration after the JavaScript bundle finished.');

      return undefined;
    }

    return duration / MILLISECONDS_PER_SECOND;
  } catch (error) {
    context.logger.warn(`Unable to read the completed RNOH JavaScript bundle duration: ${String(error)}`);

    return undefined;
  }
}

async function readAppMetadata(context: UITurboModuleContext): Promise<AppMetadata> {
  const result = new AppMetadata();
  result.deviceOs = HARMONY_OS_NAME;
  result.deviceOsVersion = nonEmpty(deviceInfo.displayVersion);
  result.deviceModel = nonEmpty(deviceInfo.marketName) ?? nonEmpty(deviceInfo.productModel);
  result.deviceName = nonEmpty(deviceInfo.productModel);
  result.reactNativeVersion = REACT_NATIVE_VERSION;
  result.clientVersion = EXPO_APP_METRICS_VERSION;

  try {
    if (typeof i18n.System.getSystemLanguage === 'function') {
      result.languageTag = nonEmpty(i18n.System.getSystemLanguage());
    }
  } catch (error) {
    context.logger.warn(`Unable to read the HarmonyOS system language for Expo App Metrics: ${String(error)}`);
  }

  try {
    const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);

    result.appName = resolveApplicationName(context, info);
    result.appIdentifier = nonEmpty(info.name);
    result.appVersion = nonEmpty(info.versionName);
    result.appBuildNumber = Number.isSafeInteger(info.versionCode) ? String(info.versionCode) : undefined;
  } catch (error) {
    context.logger.warn(`Unable to read HarmonyOS app metadata for Expo App Metrics: ${String(error)}`);
  }

  return result;
}

function resolveApplicationName(context: UITurboModuleContext, info: bundleManager.BundleInfo): string | undefined {
  const labelId = info.appInfo.labelId;
  if (Number.isSafeInteger(labelId) && labelId > 0) {
    try {
      const label = nonEmpty(context.uiAbilityContext.resourceManager.getStringSync(labelId) as string);
      if (label !== undefined) return label;
    } catch (error) {
      context.logger.warn(`Unable to resolve the HarmonyOS app label for Expo App Metrics: ${String(error)}`);
    }
  }

  const label = nonEmpty(info.appInfo.label);
  return label !== undefined && !label.startsWith('$') ? label : undefined;
}

function nonEmpty(value: string | undefined): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

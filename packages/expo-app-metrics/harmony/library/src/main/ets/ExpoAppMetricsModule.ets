import type common from '@ohos.app.ability.common';
import type { UIContext } from '@kit.ArkUI';
import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoValueType,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import bundleManager from '@ohos.bundle.bundleManager';
import deviceInfo from '@ohos.deviceInfo';
import hidebug from '@ohos.hidebug';
import i18n from '@ohos.i18n';
import process from '@ohos.process';
import { HAR_VERSION } from '../../../BuildProfile';

import {
  AppMetadata,
  AVAILABLE_MEMORY_METRIC,
  FrameRateMetrics,
  MEMORY_CATEGORY,
  MemoryUsageSnapshot,
  Metric,
  PHYSICAL_MEMORY_METRIC,
  SessionWithMetrics,
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
import { ExpoAppMetricsError } from './ExpoAppMetricsError';
import { FrameMetricsRecorder } from './FrameMetricsRecorder';

const HARMONY_OS_NAME: string = 'HarmonyOS';
const MAX_PARAMS_CODE_UNITS: number = 256_000;
let processStartupScope: StartupScope | undefined = undefined;
type Warn = (message: string) => void;

class MetricAttributes {
  routeName?: string;
  params?: Record<string, ESObject>;
}

class CustomMetric {
  category: string;
  name: string;
  value: number;
  routeName?: string;
  params?: Record<string, ESObject>;

  constructor(category: string, name: string, value: number, routeName?: string, params?: Record<string, ESObject>) {
    this.category = category;
    this.name = name;
    this.value = value;
    this.routeName = routeName;
    this.params = params;
  }
}

class StartupScope {
  readonly coordinator: StartupCoordinator;
  private readonly uiContexts: Map<number, UIContext> = new Map<number, UIContext>();
  private readonly foregroundClients: Set<number> = new Set<number>();
  private readonly mainFrameRecorder: FrameMetricsRecorder;

  constructor(storage: AppMetricsStorage, metadata: () => Promise<AppMetadata>, warn: Warn) {
    const clock = new ProcessClock((): number => Date.now(), monotonicNowMs(warn));
    const context = (): UIContext | null => this.getUIContext();

    this.coordinator = new StartupCoordinator({
      storage,
      frameRecorder: new FrameMetricsRecorder(context, warn),
      processClock: clock,
      metadata,
      now: (): number | undefined => monotonicNowMs(warn),
      warn,
    });
    this.mainFrameRecorder = new FrameMetricsRecorder(context, warn);
    // Keep startup ownership process-scoped across module reloads and abilities.
    this.coordinator.retain();
  }

  retain(): number {
    return this.coordinator.retain();
  }

  setUIContext(id: number, context: UIContext): void {
    this.uiContexts.set(id, context);
    this.coordinator.onUIContextAvailable();
    if (this.foregroundClients.size > 0) this.mainFrameRecorder.start();
  }

  onForeground(id: number): void {
    this.foregroundClients.add(id);
    this.coordinator.onForeground(id);
    this.mainFrameRecorder.start();
  }

  primeForeground(id: number, ageMs: number | undefined): void {
    this.foregroundClients.add(id);
    this.coordinator.primeForeground(id, ageMs);
    this.mainFrameRecorder.start();
  }

  onBackground(id: number): void {
    this.foregroundClients.delete(id);
    this.coordinator.onBackground(id);
    if (this.foregroundClients.size === 0) this.mainFrameRecorder.pause();
  }

  currentFrameMetrics(): FrameRateMetrics {
    if (!this.mainFrameRecorder.hasStarted()) {
      throw new ExpoAppMetricsError(
        'ERR_APP_METRICS_FRAME_METRICS_UNAVAILABLE',
        'HarmonyOS frame metrics are not available until an active React Native UI context has been observed.',
      );
    }

    return new FrameRateMetrics(this.mainFrameRecorder.snapshot());
  }

  release(id: number): boolean {
    this.uiContexts.delete(id);
    this.foregroundClients.delete(id);
    if (this.foregroundClients.size === 0) this.mainFrameRecorder.pause();

    return this.coordinator.release(id);
  }

  private getUIContext(): UIContext | null {
    const contexts = Array.from(this.uiContexts.values());
    for (let index = contexts.length - 1; index >= 0; index -= 1) {
      const context = contexts[index];
      if (context !== null && context !== undefined) return context;
    }

    return null;
  }
}

function startupScope(storage: AppMetricsStorage, metadata: () => Promise<AppMetadata>, warn: Warn): StartupScope {
  if (processStartupScope === undefined) {
    processStartupScope = new StartupScope(storage, metadata, warn);
  }

  return processStartupScope;
}

export class ExpoAppMetricsModule extends ExpoModule {
  private storage?: AppMetricsStorage;
  private scope?: StartupScope;
  private startup?: StartupCoordinator;
  private startupClientId: number = -1;
  private readonly lifecycle: AppMetricsServiceLifecycle = new AppMetricsServiceLifecycle();
  private readonly sessionIds: Set<string> = new Set<string>();
  private readonly snapshots: Set<Promise<MemoryUsageSnapshot>> = new Set<Promise<MemoryUsageSnapshot>>();
  private metadataTask?: Promise<AppMetadata>;
  private warn: Warn = (message: string): void => console.warn(message);

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoAppMetrics')
      .syncFunction('markFirstRender', (): void => {
        this.requireStartup().markFirstRender();
      })
      .syncFunction(
        'markInteractive',
        ExpoFunction.typed1(METRIC_ATTRIBUTES_TYPE.nullable().optional(), (attributes?: MetricAttributes | null): void => {
          this.requireStartup().markInteractive(attributes ?? new MetricAttributes());
        }),
      )
      .asyncFunction('getStoredEntries', async (): Promise<Metric[]> => {
        this.assertActive();
        const sessions = await this.requireStorage().getAllSessions();
        const metrics: Metric[] = [];
        sessions.forEach((entry: SessionWithMetrics): void => {
          metrics.push(...entry.metrics);
        });
        return metrics;
      })
      .asyncFunction('clearStoredEntries', async (): Promise<void> => {
        this.assertActive();
        await this.requireStorage().clear();
      })
      .syncFunction('startSession', ExpoFunction.typed0((): string => this.startSession()).returns(ExpoValueTypes.string()))
      .syncFunction(
        'stopSession',
        ExpoFunction.typed1(ExpoValueTypes.string(), (sessionId: string): void => this.scheduleStopSession(sessionId)),
      )
      .asyncFunction(
        'addCustomMetricToSession',
        ExpoFunction.typed2(ExpoValueTypes.string(), CUSTOM_METRIC_TYPE, async (sessionId: string, metric: CustomMetric): Promise<void> => {
          this.assertActive();
          requireSessionId(sessionId);
          const storage = this.requireStorage();
          await storage.addMetrics(sessionId, [createCustomMetric(storage, sessionId, metric)]);
        }),
      )
      .asyncFunction(
        'takeMemoryUsageSnapshotAsync',
        ExpoFunction.typed1(ExpoValueTypes.string().nullable().optional(), async (sessionId?: string | null): Promise<MemoryUsageSnapshot> => {
          return await this.captureMemorySnapshot(optionalSessionId(sessionId));
        }),
      )
      .asyncFunction('getMemoryUsageSnapshotAsync', async (): Promise<MemoryUsageSnapshot> => {
        return await this.captureMemorySnapshot();
      })
      .asyncFunction('getAppStartupTimesAsync', async (): Promise<Record<string, number>> => {
        this.assertActive();
        return this.requireStartup().getAppStartupTimes();
      })
      .asyncFunction('getFrameRateMetricsAsync', async (): Promise<FrameRateMetrics> => {
        this.assertActive();
        return this.requireScope().currentFrameMetrics();
      })
      .onCreate((): void => this.initialize())
      .onForeground((): void => this.onForeground())
      .onBackground((): void => this.onBackground())
      .onJavaScriptBundleLoaded((durationSeconds?: number): void => {
        this.onJavaScriptBundleLoaded(durationSeconds);
      })
      .onPrepareForReload(async (): Promise<void> => {
        await this.prepareForReload();
      })
      .onDestroy((): void => this.destroy());
  }

  private initialize(): void {
    const logger = this.context.logger;
    this.warn = (message: string): void => logger.warn(message);
    const abilityContext = this.context.uiAbilityContext;
    const storage = appMetricsStorage(abilityContext);
    const scope = startupScope(storage, (): Promise<AppMetadata> => readAppMetadata(abilityContext, this.warn), this.warn);
    this.storage = storage;
    this.scope = scope;
    this.startup = scope.coordinator;
    this.startupClientId = scope.retain();
    const state = this.context.appLifecycleState;
    if (state === ExpoAppLifecycleState.FOREGROUND) {
      this.onForeground();
    } else {
      if (state === ExpoAppLifecycleState.BEFORE_CREATE) {
        scope.primeForeground(this.startupClientId, monotonicNowMs(this.warn));
      }
      this.refreshUIContext();
    }
  }

  private startSession(): string {
    this.assertActive();
    const storage = this.requireStorage();
    const id = storage.createSessionId();
    this.sessionIds.add(id);
    storage.scheduleStartSession(id, new Date().toISOString(), this.metadata());
    return id;
  }

  private onForeground(): void {
    if (!this.lifecycle.isActive()) return;
    this.refreshUIContext();
    this.requireScope().onForeground(this.startupClientId);
  }

  private onBackground(): void {
    if (!this.lifecycle.isActive()) return;
    this.requireScope().onBackground(this.startupClientId);
  }

  private onJavaScriptBundleLoaded(durationSeconds?: number): void {
    if (!this.lifecycle.isActive()) return;
    const startup = this.requireStartup();
    startup.recordBundleLoad(durationSeconds);
    this.requireScope().onForeground(this.startupClientId);
  }

  private refreshUIContext(): void {
    if (!this.lifecycle.isActive()) return;
    this.context
      .getReactNativeWindow()
      .then((target): void => {
        if (!this.lifecycle.isActive()) return;
        this.requireScope().setUIContext(this.startupClientId, target.getUIContext());
      })
      .catch((error: Object): void => {
        if (this.lifecycle.isActive()) {
          this.warn(`Unable to obtain the React Native UI context for frame metrics: ${String(error)}`);
        }
      });
  }

  private scheduleStopSession(sessionId: string): void {
    this.assertActive();
    this.requireStorage()
      .stopSession(sessionId)
      .then((): void => {
        this.sessionIds.delete(sessionId);
      })
      .catch((error: Object): void => {
        this.warn(`Unable to stop Expo App Metrics session: ${String(error)}`);
      });
  }

  private destroy(): void {
    const storage = this.storage;
    if (storage === undefined) return;
    this.beginShutdown().forEach((sessionId: string): void => {
      storage.scheduleStopSession(sessionId);
    });
  }

  private async prepareForReload(): Promise<void> {
    const storage = this.storage;
    if (storage === undefined) return;
    const ids = this.beginShutdown();
    await Promise.all(
      Array.from(this.snapshots).map(async (snapshot: Promise<MemoryUsageSnapshot>): Promise<void> => {
        try {
          await snapshot;
        } catch (_) {}
      }),
    );
    await Promise.all(
      ids.map(async (sessionId: string): Promise<void> => {
        await storage.stopSession(sessionId);
        this.sessionIds.delete(sessionId);
      }),
    );
  }

  private beginShutdown(): string[] {
    const scope = this.scope;
    const startup = this.startup;
    const started = this.lifecycle.beginShutdown();
    const ids: string[] = Array.from(this.sessionIds);
    if (!started) return ids;
    if (scope !== undefined && startup !== undefined && scope.release(this.startupClientId)) {
      ids.unshift(startup.appSessionId);
    }
    return ids;
  }

  private assertActive(): void {
    if (!this.lifecycle.isActive()) {
      throw new ExpoAppMetricsError('ERR_APP_METRICS_DESTROYED', 'The Expo App Metrics Harmony module has already begun shutting down.');
    }
  }

  private async captureMemorySnapshot(sessionId?: string): Promise<MemoryUsageSnapshot> {
    this.assertActive();
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

      const physical = kilobytesToBytes(info.rss);
      const available = availableMemoryBytes(info.rss);
      const snapshot = new MemoryUsageSnapshot(physical, available);

      if (sessionId !== undefined) {
        this.assertActive();

        const timestamp = new Date().toISOString();

        const storage = this.requireStorage();
        await storage.addMetrics(sessionId, [
          new Metric(storage.createSessionId(), sessionId, timestamp, MEMORY_CATEGORY, PHYSICAL_MEMORY_METRIC, physical),
          new Metric(storage.createSessionId(), sessionId, timestamp, MEMORY_CATEGORY, AVAILABLE_MEMORY_METRIC, available),
        ]);
      }

      return snapshot;
    } catch (error) {
      if (error instanceof ExpoAppMetricsError) {
        throw new ExpoAppMetricsError(error.code, error.message);
      }

      throw new ExpoAppMetricsError('ERR_APP_METRICS_MEMORY_SNAPSHOT', `Unable to capture a HarmonyOS memory usage snapshot: ${String(error)}`);
    }
  }

  private metadata(): Promise<AppMetadata> {
    if (this.metadataTask === undefined) {
      this.metadataTask = readAppMetadata(this.context.uiAbilityContext, this.warn).catch((error: Object): AppMetadata => {
        this.warn(`Unable to collect Expo App Metrics metadata: ${String(error)}`);

        return new AppMetadata();
      });
    }

    return this.metadataTask;
  }

  private requireStorage(): AppMetricsStorage {
    this.assertActive();
    if (this.storage === undefined) {
      throw new ExpoAppMetricsError('ERR_APP_METRICS_NOT_READY', 'Expo App Metrics has not finished module creation.');
    }
    return this.storage;
  }

  private requireScope(): StartupScope {
    this.assertActive();
    if (this.scope === undefined) {
      throw new ExpoAppMetricsError('ERR_APP_METRICS_NOT_READY', 'Expo App Metrics has not finished module creation.');
    }
    return this.scope;
  }

  private requireStartup(): StartupCoordinator {
    this.assertActive();
    if (this.startup === undefined) {
      throw new ExpoAppMetricsError('ERR_APP_METRICS_NOT_READY', 'Expo App Metrics has not finished module creation.');
    }
    return this.startup;
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

function requireSessionId(value: string): string {
  if (value.length === 0) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_SESSION', 'Expo App Metrics expected a non-empty session ID.');
  }

  return value;
}

function optionalSessionId(value: string | null | undefined): string | undefined {
  if (value === undefined || value === null) return undefined;

  return requireSessionId(value);
}

function parseMetricAttributes(value: ESObject, path: string): MetricAttributes {
  const input = requireRecord(value, path, 'metric attributes');
  const result = new MetricAttributes();
  result.routeName = optionalString(input['routeName'], `${path}.routeName`, 'routeName');
  result.params = optionalParams(input['params'], `${path}.params`);

  return result;
}

function parseCustomMetric(value: ESObject, path: string): CustomMetric {
  const input = requireRecord(value, path, 'custom metric');
  const category = requireString(input['category'], `${path}.category`, 'category');
  const name = requireString(input['name'], `${path}.name`, 'name');
  const amount: ESObject = input['value'] as ESObject;
  if (typeof amount !== 'number' || !Number.isFinite(amount)) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_METRIC', `${path}.value expected a finite number.`);
  }

  return new CustomMetric(
    category,
    name,
    amount,
    optionalString(input['routeName'], `${path}.routeName`, 'routeName'),
    optionalParams(input['params'], `${path}.params`),
  );
}

function createCustomMetric(storage: AppMetricsStorage, sessionId: string, input: CustomMetric): Metric {
  return new Metric(
    storage.createSessionId(),
    sessionId,
    new Date().toISOString(),
    input.category,
    input.name,
    input.value,
    input.routeName,
    input.params,
  );
}

function requireRecord(value: ESObject, path: string, label: string): Record<string, ESObject> {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', `${path} expected ${label} to be an object.`);
  }

  return value as Record<string, ESObject>;
}

function requireString(value: ESObject, path: string, field: string): string {
  if (typeof value !== 'string') {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_METRIC', `${path} expected custom metric '${field}' to be a string.`);
  }

  return value;
}

function optionalString(value: ESObject, path: string, field: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', `${path} expected '${field}' to be a string when provided.`);
  }

  return value;
}

function optionalParams(value: ESObject, path: string): Record<string, ESObject> | undefined {
  if (value === undefined || value === null) return undefined;

  const params = requireRecord(value, path, "'params'");

  try {
    const json = JSON.stringify(params);
    if (json.length > MAX_PARAMS_CODE_UNITS) {
      throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', `${path} exceeds the safe Expo App Metrics parameter size.`);
    }
    const result: ESObject = JSON.parse(json);

    return result as Record<string, ESObject>;
  } catch (error) {
    if (error instanceof ExpoAppMetricsError) throw error;
    throw new ExpoAppMetricsError(
      'ERR_APP_METRICS_INVALID_ARGUMENT',
      `${path} expected 'params' to contain JSON-serializable values: ${String(error)}`,
    );
  }
}

function encodeMetricAttributes(value: MetricAttributes): ESObject {
  const result: Record<string, ESObject> = {};
  if (value.routeName !== undefined) result['routeName'] = value.routeName;
  if (value.params !== undefined) result['params'] = value.params;
  return result;
}

function encodeCustomMetric(value: CustomMetric): ESObject {
  const result: Record<string, ESObject> = {};
  result['category'] = value.category;
  result['name'] = value.name;
  result['value'] = value.value;
  if (value.routeName !== undefined) result['routeName'] = value.routeName;
  if (value.params !== undefined) result['params'] = value.params;
  return result;
}

const METRIC_ATTRIBUTES_TYPE: ExpoValueType<MetricAttributes> = new ExpoValueType<MetricAttributes>(
  'metric attributes object',
  (value: ESObject, path: string): MetricAttributes => parseMetricAttributes(value, path),
  (value: MetricAttributes, _path: string): ESObject => encodeMetricAttributes(value),
);

const CUSTOM_METRIC_TYPE: ExpoValueType<CustomMetric> = new ExpoValueType<CustomMetric>(
  'custom metric object',
  (value: ESObject, path: string): CustomMetric => parseCustomMetric(value, path),
  (value: CustomMetric, _path: string): ESObject => encodeCustomMetric(value),
);

function availableMemoryBytes(residentKilobytes: bigint): number {
  if (typeof hidebug.getAppMemoryLimit !== 'function') {
    throw new ExpoAppMetricsError(
      'ERR_APP_METRICS_MEMORY_API',
      'HarmonyOS HiDebug does not expose the application RSS limit required by Expo App Metrics.',
    );
  }

  try {
    const limit = hidebug.getAppMemoryLimit();

    return kilobytesToBytes(remainingKilobytes(residentKilobytes, limit.rssLimit));
  } catch (error) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_MEMORY_API', `Unable to read the HarmonyOS application RSS limit: ${String(error)}`);
  }
}

async function readNativeMemoryInfo(): Promise<hidebug.NativeMemInfo> {
  // ArkTS requires a literal here so it can validate and narrow API availability at compile time.
  if (!deviceInfo.apiAvailable(20)) {
    throw new ExpoAppMetricsError(
      'ERR_APP_METRICS_MEMORY_API',
      'HarmonyOS HiDebug does not expose the asynchronous application memory API required to avoid blocking the UI thread.',
    );
  }
  if (typeof hidebug.getAppNativeMemInfoAsync !== 'function') {
    throw new ExpoAppMetricsError(
      'ERR_APP_METRICS_MEMORY_API',
      'HarmonyOS HiDebug does not expose the asynchronous application memory API required to avoid blocking the UI thread.',
    );
  }

  return await hidebug.getAppNativeMemInfoAsync();
}

async function readAppMetadata(context: common.UIAbilityContext, warn: Warn): Promise<AppMetadata> {
  const result = new AppMetadata();
  result.deviceOs = HARMONY_OS_NAME;
  result.deviceOsVersion = nonEmpty(deviceInfo.displayVersion);
  result.deviceModel = nonEmpty(deviceInfo.marketName) ?? nonEmpty(deviceInfo.productModel);
  result.deviceName = nonEmpty(deviceInfo.productModel);
  result.clientVersion = HAR_VERSION.split('-harmony.', 1)[0];

  try {
    if (typeof i18n.System.getSystemLanguage === 'function') {
      result.languageTag = nonEmpty(i18n.System.getSystemLanguage());
    }
  } catch (error) {
    warn(`Unable to read the HarmonyOS system language for Expo App Metrics: ${String(error)}`);
  }

  try {
    const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);

    result.appName = resolveApplicationName(context, info, warn);
    result.appIdentifier = nonEmpty(info.name);
    result.appVersion = nonEmpty(info.versionName);
    result.appBuildNumber = Number.isSafeInteger(info.versionCode) ? String(info.versionCode) : undefined;
  } catch (error) {
    warn(`Unable to read HarmonyOS app metadata for Expo App Metrics: ${String(error)}`);
  }

  return result;
}

function resolveApplicationName(context: common.UIAbilityContext, info: bundleManager.BundleInfo, warn: Warn): string | undefined {
  const labelId = info.appInfo.labelId;
  if (Number.isSafeInteger(labelId) && labelId > 0) {
    try {
      const label = nonEmpty(context.resourceManager.getStringSync(labelId) as string);
      if (label !== undefined) return label;
    } catch (error) {
      warn(`Unable to resolve the HarmonyOS app label for Expo App Metrics: ${String(error)}`);
    }
  }

  const label = nonEmpty(info.appInfo.label);
  return label !== undefined && !label.startsWith('$') ? label : undefined;
}

function nonEmpty(value: string | undefined): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

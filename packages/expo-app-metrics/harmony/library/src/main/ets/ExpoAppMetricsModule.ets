/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type common from '@ohos.app.ability.common';
import type { UIContext, window } from '@kit.ArkUI';
import { taskpool } from '@kit.ArkTS';
import { systemDateTime } from '@kit.BasicServicesKit';
import {
  ExpoAppLifecycleSubscriber,
  ExpoAbilityLifecycleSubscriber,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoSharedObjectClassDefinition,
  ExpoValueType,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import {
  UpdatesControllerRegistry,
  UpdatesInterface,
  UpdatesStateChangeListener,
  UpdatesStateChangeSubscription,
} from '@expo-harmony/expo-updates-interface';
import bundleManager from '@ohos.bundle.bundleManager';
import deviceInfo from '@ohos.deviceInfo';
import hidebug from '@ohos.hidebug';
import i18n from '@ohos.i18n';
import process from '@ohos.process';
import { HAR_VERSION } from '../../../BuildProfile';

import {
  AppMetadata,
  DebugSession,
  LogRecord,
  AVAILABLE_MEMORY_METRIC,
  FrameRateMetrics,
  MEMORY_CATEGORY,
  MemoryUsageSnapshot,
  Metric,
  PHYSICAL_MEMORY_METRIC,
  SessionWithMetrics,
  UPDATES_CATEGORY,
} from './AppMetricsModels';
import {
  AppMetricsServiceLifecycle,
  kilobytesToBytes,
  processAgeMilliseconds,
  remainingKilobytes,
} from './AppMetricsSemantics';
import { ProcessClock, StartupCoordinator } from './AppMetricsStartupCoordinator';
import { appMetricsStorage, AppMetricsStorage } from './AppMetricsStorage';
import { ExpoAppMetricsError } from './ExpoAppMetricsError';
import { AppMetricsCrashObserver } from './AppMetricsCrashObserver';
import { CrashReport } from './AppMetricsCrashReport';
import { appMetricsSessionClass, AppMetricsSession, METRICS_RECORD } from './AppMetricsSession';
import { makeErrorLog, makeLogEvent, optionalMap, sanitizeAttributes, mergeAttributes } from './AppMetricsLogging';
import { persistFatalError, recoverFatalErrors } from './AppMetricsPendingErrors';
import { getNetworkRequestMonitor, networkRequestObserverClass } from './NetworkRequestObserver';
import { readDeviceConditions } from './AppMetricsDeviceConditions';
import { FrameMetricsRecorder } from './FrameMetricsRecorder';

const HARMONY_OS_NAME: string = 'HarmonyOS';
const MAX_PARAMS_CODE_UNITS: number = 256_000;
let scope: StartupScope | undefined = undefined;
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
  updateId?: string;

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
  readonly appClientId: number;
  private readonly uiContexts: Map<number, UIContext> = new Map<number, UIContext>();
  private readonly foregroundWindows: Set<number> = new Set<number>();
  private readonly foregroundClients: Set<number> = new Set<number>();
  private readonly mainFrameRecorder: FrameMetricsRecorder;
  private readonly crashObserver: AppMetricsCrashObserver;
  private readonly storage: AppMetricsStorage;
  private readonly metadata: () => Promise<AppMetadata>;
  private lastUpdateDownload?: string;
  foregroundSessionId?: string;
  foregroundStartDate?: string;

  constructor(storage: AppMetricsStorage, metadata: () => Promise<AppMetadata>, warn: Warn, filesDir: string) {
    this.storage = storage;
    this.metadata = metadata;

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
    this.appClientId = this.coordinator.retain();

    this.crashObserver = new AppMetricsCrashObserver(storage, this.coordinator.appSessionId, warn, filesDir);
    recoverFatalErrors(filesDir, storage, warn).catch((error: Object): void => warn(`Unable to recover App Metrics fatal errors: ${String(error)}`));
  }

  retain(): number {
    return this.coordinator.retain();
  }

  async recordUpdateDownload(updateId: string, start: number, finish: number): Promise<void> {
    const key = `${updateId}:${start}:${finish}`;
    if (this.lastUpdateDownload === key) return;

    this.lastUpdateDownload = key;
    const sessionId = this.coordinator.appSessionId;
    const metric = new Metric(this.storage.createSessionId(), sessionId, new Date().toISOString(),
      UPDATES_CATEGORY, 'updateDownloadTime', (finish - start) / 1000);
    metric.updateId = updateId;

    try {
      await this.storage.addMetrics(sessionId, [metric]);
    } catch (error) {
      if (this.lastUpdateDownload === key) this.lastUpdateDownload = undefined;
      throw error as Error;
    }
  }

  setUIContext(id: number, context: UIContext): void {
    this.uiContexts.set(id, context);
    this.refreshUIContext();
  }

  setUIForeground(id: number, foreground: boolean): void {
    this.foregroundWindows.delete(id);
    if (foreground) this.foregroundWindows.add(id);
    this.refreshUIContext();
  }

  onForeground(id: number): void {
    if (this.foregroundClients.size === 0) {
      this.foregroundSessionId = this.storage.createSessionId();
      this.foregroundStartDate = new Date().toISOString();
      this.storage.scheduleStartSession(this.foregroundSessionId, this.foregroundStartDate, this.metadata(), 'foreground');
    }
    this.foregroundClients.add(id);
    this.coordinator.onForeground(id);
    if (this.getUIContext() !== null) this.mainFrameRecorder.start();
  }

  onBackground(id: number): void {
    this.foregroundClients.delete(id);
    this.coordinator.onBackground(id);
    if (this.foregroundClients.size === 0) {
      this.mainFrameRecorder.pause();
      if (this.foregroundSessionId !== undefined) this.storage.scheduleStopSession(this.foregroundSessionId);
      this.foregroundSessionId = undefined;
      this.foregroundStartDate = undefined;
    }
  }

  currentFrameMetrics(): FrameRateMetrics {
    if (!this.mainFrameRecorder.hasStarted()) {
      throw new ExpoAppMetricsError(
        'ERR_APP_METRICS_FRAME_METRICS_UNAVAILABLE',
        'HarmonyOS frame metrics are not available until an active native window UI context has been observed.',
      );
    }

    return new FrameRateMetrics(this.mainFrameRecorder.snapshot());
  }

  clearUIContext(id: number): void {
    if (!this.uiContexts.delete(id)) return;
    this.refreshUIContext();
  }

  private refreshUIContext(): void {
    this.coordinator.onUIContextUnavailable();
    this.mainFrameRecorder.pause();
    if (this.getUIContext() !== null) {
      this.coordinator.onUIContextAvailable();
      if (this.foregroundClients.size > 0) this.mainFrameRecorder.start();
    }
  }

  release(id: number): boolean {
    this.foregroundWindows.delete(id);
    this.clearUIContext(id);
    this.foregroundClients.delete(id);
    if (this.foregroundClients.size === 0) this.mainFrameRecorder.pause();

    return this.coordinator.release(id);
  }

  private getUIContext(): UIContext | null {
    const ids = Array.from(this.foregroundWindows.values());

    for (let index = ids.length - 1; index >= 0; index -= 1) {
      const context = this.uiContexts.get(ids[index]);
      if (context !== null && context !== undefined) return context;
    }

    return null;
  }
}

function requireStartupScope(): StartupScope {
  if (scope === undefined) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_NOT_INITIALIZED', 'Expo App Metrics requires its autolinked application lifecycle subscriber.');
  }
  return scope;
}

export class ExpoAppMetricsAppLifecycleSubscriber extends ExpoAppLifecycleSubscriber {
  override onCreate(): void {
    const warn: Warn = (message: string): void => console.warn(message);
    scope = new StartupScope(appMetricsStorage(this.context), (): Promise<AppMetadata> => readAppMetadata(this.context, warn), warn, this.context.filesDir);
  }

  override onForeground(): void {
    const scope = requireStartupScope();
    scope.onForeground(scope.appClientId);
  }

  override onBackground(): void {
    const scope = requireStartupScope();
    scope.onBackground(scope.appClientId);
  }
}

export class ExpoAppMetricsAbilityLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  private readonly scope: StartupScope = requireStartupScope();
  private readonly id: number = this.scope.retain();
  private stage?: window.WindowStage;
  private destroyed: boolean = false;

  override onForeground(): void {
    this.scope.setUIForeground(this.id, true);
  }
  override onBackground(): void {
    this.scope.setUIForeground(this.id, false);
  }
  override onWindowStageCreate(stage: window.WindowStage): void {
    this.stage = stage;
  }
  override onWindowStageRestore(stage: window.WindowStage): void {
    this.stage = stage;
  }
  override async onWindowStageReady(stage: window.WindowStage): Promise<void> {
    const target = await stage.getMainWindow();
    if (!this.destroyed && this.stage === stage) this.scope.setUIContext(this.id, target.getUIContext());
  }
  override onWindowStageWillDestroy(): void {
    this.stage = undefined;
    this.scope.clearUIContext(this.id);
  }
  override onWindowStageDestroy(): void {
    this.onWindowStageWillDestroy();
  }
  override onDestroy(): void {
    this.destroyed = true;
    this.stage = undefined;
    this.scope.release(this.id);
  }
}

export class ExpoAppMetricsModule extends ExpoModule implements UpdatesStateChangeListener {
  private storage?: AppMetricsStorage;
  private scope?: StartupScope;
  private startup?: StartupCoordinator;
  private readonly lifecycle: AppMetricsServiceLifecycle = new AppMetricsServiceLifecycle();
  private readonly sessionIds: Set<string> = new Set<string>();
  private readonly snapshots: Set<Promise<MemoryUsageSnapshot>> = new Set<Promise<MemoryUsageSnapshot>>();
  private metadataTask?: Promise<AppMetadata>;
  private updatesController?: UpdatesInterface;
  private updatesSubscription?: UpdatesStateChangeSubscription;
  private readonly sessionClass: ExpoSharedObjectClassDefinition<AppMetricsSession> = appMetricsSessionClass();
  private readonly sessionObjects: Map<string, AppMetricsSession> = new Map<string, AppMetricsSession>();
  private readonly pendingWrites: Set<Promise<void>> = new Set<Promise<void>>();
  private warn: Warn = (message: string): void => console.warn(message);

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoAppMetrics')
      .sharedObjectClass(this.sessionClass)
      .sharedObjectClass(networkRequestObserverClass())
      .syncFunction('getMainSession', ExpoFunction.typed0((): AppMetricsSession => {
        const startup = this.requireStartup();
        return this.sessionObject(startup.appSessionId, 'main', startup.getAppSessionStartTimestamp());
      }).returns(this.sessionClass.valueType()))
      .asyncFunction('getForegroundSession', ExpoFunction.typed0(async (): Promise<AppMetricsSession | null> => {
        const scope = this.requireScope();
        if (scope.foregroundSessionId === undefined || scope.foregroundStartDate === undefined) return null;
        return this.sessionObject(scope.foregroundSessionId, 'foreground', scope.foregroundStartDate);
      }).returns(this.sessionClass.valueType().nullable()))
      .asyncFunction('getAllCrashReports', async (): Promise<CrashReport[]> => this.requireStorage().getAllCrashReports())
      .asyncFunction('getInactiveSessions', async (): Promise<DebugSession[]> => {
        const entries = await this.requireStorage().getAllSessions();
        return entries.filter((entry: SessionWithMetrics): boolean => !entry.session.isActive)
          .sort((left: SessionWithMetrics, right: SessionWithMetrics): number => Date.parse(right.session.startTimestamp) - Date.parse(left.session.startTimestamp))
          .map((entry: SessionWithMetrics): DebugSession => new DebugSession(entry));
      })
      .syncFunction('logEvent', ExpoFunction.typed2(
        ExpoValueTypes.string(), METRICS_RECORD.nullable().optional(),
        (name: string, options?: Record<string, ESObject> | null): void => {
          this.assertActive();
          validateLogOptions(options ?? undefined);
          const log = makeLogEvent(name, options ?? undefined, this.warn);
          if (log !== undefined) this.saveLog(log);
        },
      ))
      .syncFunction('setGlobalAttributes', ExpoFunction.typed1(
        METRICS_RECORD.nullable().optional(), (attributes?: Record<string, ESObject> | null): void => {
          this.requireStorage().setGlobalAttributes(sanitizeAttributes(attributes ?? undefined, this.warn).attributes);
        },
      ))
      .syncFunction('reportError', ExpoFunction.typed1(METRICS_RECORD, (report: Record<string, ESObject>): void => {
        this.assertActive();
        validateErrorReport(report);
        const log = makeErrorLog(report);
        if (report['isFatal'] === true) {
          try {
            log.attributes = this.requireStorage().mergeGlobals(log.attributes);
          } catch (_) {
            // Preserve the fatal report even if a user-supplied global attribute cannot be encoded.
          }
          persistFatalError(this.context.uiAbilityContext.filesDir, this.requireStartup().appSessionId, log, this.warn);
        } else this.saveLog(log);
      }))
      .syncFunction('markFirstRender', (): void => {
        this.requireStartup().markFirstRender();
      })
      .syncFunction(
        'markInteractive',
        ExpoFunction.typed1(METRIC_ATTRIBUTES_TYPE.nullable().optional(), (attributes?: MetricAttributes | null): void => {
          this.requireStartup().markInteractive(attributes ?? new MetricAttributes(), (start: number, end: number): Record<string, ESObject> => {
            const requests = getNetworkRequestMonitor(this.context.runtimeId)?.summarize(start, end);
            return mergeAttributes(readDeviceConditions(this.warn), requests);
          });
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
      .asyncFunction('addCustomMetricToSession', ExpoFunction.typed1(METRICS_RECORD, async (metric: Record<string, ESObject>): Promise<void> => {
        const id = requireSessionId(requireString(metric['sessionId'], 'metric.sessionId', 'sessionId'));
        const input = parseCustomMetric(metric, 'metric');
        const timestamp = optionalString(metric['timestamp'], 'metric.timestamp', 'timestamp') ?? new Date().toISOString();
        if (!Number.isFinite(Date.parse(timestamp))) throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_METRIC', 'Metric timestamp must be an ISO date.');

        const storage = this.requireStorage();
        const record = createCustomMetric(storage, id, input);
        record.timestamp = timestamp;
        await storage.addMetrics(id, [record]);
      }))
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
    const scope = requireStartupScope();

    this.storage = storage;
    this.scope = scope;
    this.startup = scope.coordinator;
    this.observeUpdates();
  }

  updatesStateDidChange(event: Record<string, ESObject>): void {
    if (this.lifecycle.isActive() && event['type'] === 'downloadCompleteWithUpdate') this.recordUpdateDownload();
  }

  private observeUpdates(): void {
    const controller = UpdatesControllerRegistry.controller;
    try {
      if (controller !== this.updatesController) {
        this.updatesSubscription?.remove();
        this.updatesSubscription = undefined;
        this.updatesController = undefined;
        if (controller !== undefined) {
          this.updatesSubscription = controller.subscribeToUpdatesStateChanges(this);
          this.updatesController = controller;
          // Startup can finish downloading before the JS module is installed.
          this.recordUpdateDownload();
        }
      }
      const metadata = new AppMetadata();
      applyUpdatesMetadata(metadata, controller);
      if (metadata.appUpdateId !== undefined || metadata.appUpdateRuntimeVersion !== undefined) {
        this.trackWrite(this.requireStorage().patchUpdatesMetadata(metadata));
      }
    } catch (error) {
      this.warn(`Unable to observe Expo Updates metrics: ${String(error)}`);
    }
  }

  private recordUpdateDownload(): void {
    const context = this.updatesSubscription?.getContext();
    const updateId: ESObject = context?.downloadedManifest?.['id'];
    const start = context?.downloadStartTime?.getTime();
    const finish = context?.downloadFinishTime?.getTime();
    if (typeof updateId !== 'string' || updateId.length === 0 || start === undefined || finish === undefined
      || !Number.isFinite(start) || !Number.isFinite(finish) || finish < start) return;
    this.trackWrite(this.requireScope().recordUpdateDownload(updateId, start, finish));
  }

  private sessionObject(id: string, type: string, timestamp: string): AppMetricsSession {
    let session = this.sessionObjects.get(id);
    if (session === undefined) {
      session = this.sessionClass.instance(new AppMetricsSession(this.context, this.requireStorage(), id, type, timestamp,
        (released: AppMetricsSession): void => {
          if (this.sessionObjects.get(released.id) === released) this.sessionObjects.delete(released.id);
        }));
      this.sessionObjects.set(id, session);
    }

    return session;
  }

  private saveLog(log: LogRecord): void {
    this.trackWrite(this.requireStorage().addLogs(this.requireStartup().appSessionId, [log]));
  }

  private trackWrite(task: Promise<void>): void {
    this.pendingWrites.add(task);
    task.catch((error: Object): void => this.warn(`Unable to persist Expo App Metrics data: ${String(error)}`))
      .finally((): void => { this.pendingWrites.delete(task); });
  }

  private startSession(): string {
    this.assertActive();

    const storage = this.requireStorage();
    const id = storage.createSessionId();

    this.sessionIds.add(id);
    storage.scheduleStartSession(id, new Date().toISOString(), this.metadata());

    return id;
  }

  private onJavaScriptBundleLoaded(durationSeconds?: number): void {
    if (!this.lifecycle.isActive()) return;

    const startup = this.requireStartup();

    startup.recordBundleLoad(durationSeconds);
    this.observeUpdates();
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
    const ids = this.beginShutdown();
    const storage = this.storage;
    if (storage === undefined) return;

    ids.forEach((sessionId: string): void => {
      storage.scheduleStopSession(sessionId);
    });
  }

  private async prepareForReload(): Promise<void> {
    const ids = this.beginShutdown();
    const storage = this.storage;
    if (storage === undefined) return;

    await Promise.all(
      Array.from(this.snapshots).map(async (snapshot: Promise<MemoryUsageSnapshot>): Promise<void> => {
        try {
          await snapshot;
        } catch (_) {}
      }),
    );
    await Promise.all(Array.from(this.pendingWrites).map(async (task: Promise<void>): Promise<void> => {
      try { await task; } catch (_) {}
    }));
    await Promise.all(
      ids.map(async (sessionId: string): Promise<void> => {
        await storage.stopSession(sessionId);
        this.sessionIds.delete(sessionId);
      }),
    );
  }

  private beginShutdown(): string[] {
    if (this.lifecycle.beginShutdown()) {
      this.updatesSubscription?.remove();
      this.updatesSubscription = undefined;
      this.updatesController = undefined;
    }
    return Array.from(this.sessionIds);
  }

  private assertActive(): void {
    if (!this.lifecycle.isActive()) {
      throw new ExpoAppMetricsError('ERR_APP_METRICS_DESTROYED', 'The Expo App Metrics Harmony module has already begun shutting down.');
    }
  }

  private async captureMemorySnapshot(sessionId?: string): Promise<MemoryUsageSnapshot> {
    this.assertActive();

    // Resolve the storage before yielding so a snapshot accepted before reload
    // can finish while the module stops admitting new calls.
    const storage = sessionId === undefined ? undefined : this.requireStorage();
    const snapshot = this.takeMemorySnapshot(sessionId, storage);

    this.snapshots.add(snapshot);
    try {
      return await snapshot;
    } finally {
      this.snapshots.delete(snapshot);
    }
  }

  private async takeMemorySnapshot(sessionId?: string, storage?: AppMetricsStorage): Promise<MemoryUsageSnapshot> {
    try {
      const resident = await readResidentMemory();
      const physical = kilobytesToBytes(resident);
      const available = availableMemoryBytes(resident);
      const snapshot = new MemoryUsageSnapshot(physical, available);

      if (sessionId !== undefined && storage !== undefined) {
        const timestamp = new Date().toISOString();
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
    const uptimeMs = systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE);
    return processAgeMilliseconds(uptimeMs, process.getStartRealtime());
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

  const metric = new CustomMetric(
    category,
    name,
    amount,
    optionalString(input['routeName'], `${path}.routeName`, 'routeName'),
    optionalParams(input['params'], `${path}.params`),
  );
  metric.updateId = optionalString(input['updateId'], `${path}.updateId`, 'updateId');

  return metric;
}

function createCustomMetric(storage: AppMetricsStorage, sessionId: string, input: CustomMetric): Metric {
  const metric = new Metric(
    storage.createSessionId(),
    sessionId,
    new Date().toISOString(),
    input.category,
    input.name,
    input.value,
    input.routeName,
    input.params,
  );
  metric.updateId = input.updateId;

  return metric;
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
    if (error instanceof ExpoAppMetricsError) {
      throw new ExpoAppMetricsError(error.code, error.message, error);
    }

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

const METRIC_ATTRIBUTES_TYPE: ExpoValueType<MetricAttributes> = new ExpoValueType<MetricAttributes>(
  'metric attributes object',
  (value: ESObject, path: string): MetricAttributes => parseMetricAttributes(value, path),
  (value: MetricAttributes, _path: string): ESObject => encodeMetricAttributes(value),
);

function availableMemoryBytes(resident: bigint): number {
  if (typeof hidebug.getAppMemoryLimit !== 'function' || typeof hidebug.getSystemMemInfo !== 'function') {
    throw new ExpoAppMetricsError(
      'ERR_APP_METRICS_MEMORY_API',
      'HarmonyOS HiDebug does not expose the application and system memory information required by Expo App Metrics.',
    );
  }

  try {
    const limit = hidebug.getAppMemoryLimit();
    const system = hidebug.getSystemMemInfo();
    const remaining = remainingKilobytes(resident, limit.rssLimit);

    // An unlimited RSS limit exceeds JS integer precision; available RAM still bounds allocations.
    return kilobytesToBytes(remaining < system.availableMem ? remaining : system.availableMem);
  } catch (error) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_MEMORY_API', `Unable to read available HarmonyOS application memory: ${String(error)}`);
  }
}

async function readResidentMemory(): Promise<bigint> {
  if (deviceInfo.sdkApiVersion >= 20 && typeof hidebug.getAppNativeMemInfoAsync === 'function') {
    return (await hidebug.getAppNativeMemInfoAsync()).rss;
  }
  return BigInt(await taskpool.execute(readResidentMemoryInTask) as string);
}

@Concurrent
function readResidentMemoryInTask(): string {
  return hidebug.getAppNativeMemInfo().rss.toString();
}

async function readAppMetadata(context: common.Context, warn: Warn): Promise<AppMetadata> {
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

  try {
    applyUpdatesMetadata(result, UpdatesControllerRegistry.controller);
  } catch (error) {
    warn(`Unable to read Expo Updates metadata for Expo App Metrics: ${String(error)}`);
  }

  return result;
}

function applyUpdatesMetadata(metadata: AppMetadata, controller?: UpdatesInterface): void {
  if (controller === undefined) return;

  const launchedId = controller.launchedUpdateId?.toLowerCase();
  if (launchedId !== controller.embeddedUpdateId?.toLowerCase()) metadata.appUpdateId = launchedId;
  metadata.appUpdateRuntimeVersion = controller.runtimeVersion ?? undefined;
  metadata.appUpdateRequestHeaders = controller.requestHeaders ?? undefined;
}

function resolveApplicationName(context: common.Context, info: bundleManager.BundleInfo, warn: Warn): string | undefined {
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

function validateLogOptions(options?: Record<string, ESObject>): void {
  if (options === undefined) return;
  ['body', 'displayName', 'severity'].forEach((key: string): void => {
    const value: ESObject = options[key];
    if (value !== undefined && value !== null && typeof value !== 'string') {
      throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', `Log option '${key}' must be a string.`);
    }
  });
  const severity: ESObject = options['severity'];
  if (typeof severity === 'string' && !['trace', 'debug', 'info', 'warn', 'error', 'fatal'].includes(severity)) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', 'Invalid log severity.');
  }
  const attributes: ESObject = options['attributes'];
  if (attributes !== undefined && attributes !== null && optionalMap(attributes) === undefined) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', 'Log attributes must be an object.');
  }
}

function validateErrorReport(report: Record<string, ESObject>): void {
  ['source', 'type', 'message', 'stacktrace', 'componentStack'].forEach((key: string): void => {
    const value: ESObject = report[key];
    if (value !== undefined && value !== null && typeof value !== 'string') {
      throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', `Error '${key}' must be a string.`);
    }
  });
  const source: ESObject = report['source'];
  if (source !== undefined && !['global', 'errorBoundary', 'reportedByUser'].includes(source as string)) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', 'Invalid error report source.');
  }
  const fatal: ESObject = report['isFatal'];
  if (fatal !== undefined && typeof fatal !== 'boolean') throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', 'isFatal must be a boolean.');
}

import { ExpoRuntimeDirectoriesKey } from './appcontext/ExpoRuntimeDirectories';
import type { ExpoServiceClass } from './appcontext/ExpoServicesRegistry';
import { ExpoRuntimeConfig } from './appcontext/ExpoRuntimeConfig';
import type { ExpoRuntimeSession } from './appcontext/ExpoRuntimeSession';
import { EtsUITurboModule, RNInstanceImpl, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import type { ExpoHarmonyHostBinding, ExpoHarmonyHostState } from './appcontext/HarmonyHostLifecycle';
import { ExpoViewAdapterRegistry } from './views/ExpoViewTypes';
import { ExpoModuleDescriptor, ExpoModuleRegistration, ExpoModulesRegistry } from './modules/ExpoModule';
import { ExpoModuleError } from './modules/ExpoModuleError';
import {
  EXPO_CONTENT_APPEARED,
  EXPO_LIFECYCLE_BACKGROUND,
  EXPO_LIFECYCLE_CONTENT_APPEARED,
  EXPO_LIFECYCLE_DESTROY,
  EXPO_LIFECYCLE_DESTROY_ACK,
  EXPO_LIFECYCLE_EVENT,
  EXPO_LIFECYCLE_FOREGROUND,
  EXPO_LIFECYCLE_JAVASCRIPT_BUNDLE_LOADED,
} from './protocol/Protocol';
import { ensureDirectoryUri } from './appcontext/FileUri';
import { ExpoHostReload } from './appcontext/ExpoHostReload';
import { installRnohDestroyBarrier } from './appcontext/RnohDestroyAdapter';

const DESTROY_ACK_WARNING_MS: number = 5000;
let nextDestroyRequestId: number = 1;

/** Copy-value platform adapter for the C++ Expo Modules runtime. */
export class ExpoModulesCoreTurboModule extends EtsUITurboModule {
  static readonly NAME: string = 'ExpoModulesCore';
  private readonly unsubscribeLifecycle: (() => void)[] = [];
  private readonly coreContext: UITurboModuleContext;
  private readonly modules: ExpoModulesRegistry;
  private lastAppLifecycleEvent?: string = undefined;
  private destroyStarted: boolean = false;
  private destroyFinished: boolean = false;

  static async create(
    coreContext: UITurboModuleContext,
    registrations: ExpoModuleRegistration[],
    hostState: ExpoHarmonyHostState,
    runtimeConfig: ExpoRuntimeConfig = new ExpoRuntimeConfig(),
    services: ExpoServiceClass[] = [],
  ): Promise<ExpoModulesCoreTurboModule> {
    let hostBinding: ExpoHarmonyHostBinding | undefined = undefined;
    try {
      hostBinding = hostState.openHost(coreContext.uiAbilityContext, coreContext.rnInstance.getId(), runtimeConfig.session);

      const modules = ExpoModulesRegistry.createScope(
        coreContext,
        registrations,
        hostBinding.initialWant,
        hostBinding.hostId,
        hostBinding.runtimeGeneration,
        runtimeConfig,
        services,
      );

      return new ExpoModulesCoreTurboModule(coreContext, modules, hostState, hostBinding, runtimeConfig.session);
    } catch (error) {
      if (hostBinding !== undefined) hostState.releaseHost(hostBinding);

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      if (error instanceof Error) throw new Error(error.message);
      throw new Error(String(error));
    }
  }

  private readonly session?: ExpoRuntimeSession;

  constructor(coreContext: UITurboModuleContext, modules: ExpoModulesRegistry, hostState: ExpoHarmonyHostState, hostBinding: ExpoHarmonyHostBinding, session?: ExpoRuntimeSession) {
    super(coreContext);
    this.coreContext = coreContext;
    this.session = session;
    this.modules = modules;

    this.modules.configureReloadHost(
      async (reason: string): Promise<void> => {
        if (this.destroyStarted) {
          throw new Error('The Expo modules Host is already being destroyed.');
        }

        await ExpoHostReload.require(this.coreContext.rnInstance.getId())(reason);
      },
      (): void => {
        if (this.destroyStarted) {
          throw new Error('The Expo modules Host is already being destroyed.');
        }
        ExpoHostReload.require(this.coreContext.rnInstance.getId());
      },
    );

    this.unsubscribeLifecycle.push(hostState.bindHost(hostBinding, this));
    this.unsubscribeLifecycle.push(
      coreContext.rnInstance.subscribeToLifecycleEvents('FOREGROUND', () => this.dispatchExpoModuleLifecycle(EXPO_LIFECYCLE_FOREGROUND)),
      coreContext.rnInstance.subscribeToLifecycleEvents('BACKGROUND', () => this.dispatchExpoModuleLifecycle(EXPO_LIFECYCLE_BACKGROUND)),
      coreContext.rnInstance.subscribeToLifecycleEvents('JS_BUNDLE_EXECUTION_FINISH', (): void => {
        if (this.destroyStarted) return;
        this.dispatchExpoModuleLifecycle(EXPO_LIFECYCLE_JAVASCRIPT_BUNDLE_LOADED, readJavaScriptBundleDurationSeconds(coreContext));
        // RNOH drops foreground/background events while BEFORE_CREATE and only
        // emits bundle completion when it becomes READY. Replay the Ability's
        // current state, since the bundle may have finished in the background.
        this.dispatchExpoModuleLifecycle(coreContext.getUIAbilityState() === 'FOREGROUND' ? EXPO_LIFECYCLE_FOREGROUND : EXPO_LIFECYCLE_BACKGROUND);
      }),
      coreContext.rnInstance.cppEventEmitter.subscribe(EXPO_CONTENT_APPEARED, (payload: ESObject): void => {
        if (this.destroyStarted) return;
        const runtimeEpoch: ESObject = payload?.runtimeEpoch;
        if (typeof runtimeEpoch !== 'string') return;
        this.modules.dispatchLifecycleForRuntime(runtimeEpoch, EXPO_LIFECYCLE_CONTENT_APPEARED);
      }),
    );

    installRnohDestroyBarrier(coreContext.rnInstance, (): Promise<void> => this.prepareForDestroy());
  }

  bindExpoModuleRuntime(runtimeEpoch: string): void {
    this.modules.bindRuntime(runtimeEpoch);
  }

  getExpoModuleDescriptors(runtimeEpoch: string): ExpoModuleDescriptor[] {
    return this.modules.descriptors(runtimeEpoch);
  }

  /** Returns a queued event payload through the typed NAPI bridge. */
  takeExpoTypedEventArguments(runtimeEpoch: string, transportId: number): ESObject[] {
    return this.modules.takeTypedEventArguments(runtimeEpoch, transportId);
  }

  /** Releases staged SharedObject values when native routing has no live target. */
  discardExpoTypedEventArguments(runtimeEpoch: string, transportId: number): void {
    this.modules.discardTypedEventArguments(runtimeEpoch, transportId);
  }

  getExpoModuleConstant(runtimeEpoch: string, moduleName: string, constantName: string): ESObject {
    return this.modules.getConstant(runtimeEpoch, moduleName, constantName);
  }

  getExpoSharedObjectConstant(runtimeEpoch: string, moduleName: string, className: string, constantName: string): ESObject {
    return this.modules.getSharedObjectConstant(runtimeEpoch, moduleName, className, constantName);
  }

  invokeExpoModuleSync(runtimeEpoch: string, moduleName: string, functionName: string, args: ESObject[]): ESObject | void {
    return this.modules.invokeSync(runtimeEpoch, moduleName, functionName, args);
  }

  async invokeExpoModuleAsync(runtimeEpoch: string, moduleName: string, functionName: string, args: ESObject[]): Promise<ESObject | void> {
    return await this.modules.invokeAsync(runtimeEpoch, moduleName, functionName, args);
  }

  getExpoModuleProperty(runtimeEpoch: string, moduleName: string, propertyName: string): ESObject {
    return this.modules.getProperty(runtimeEpoch, moduleName, propertyName);
  }

  setExpoModuleProperty(runtimeEpoch: string, moduleName: string, propertyName: string, value: ESObject): void {
    this.modules.setProperty(runtimeEpoch, moduleName, propertyName, value);
  }

  async invokeExpoViewAsync(
    runtimeEpoch: string,
    tag: number,
    componentName: string,
    propsRevision: number,
    functionName: string,
    args: ESObject[],
  ): Promise<ESObject | void> {
    return await this.modules.invokeViewAsync(runtimeEpoch, tag, componentName, propsRevision, functionName, args);
  }

  constructExpoSharedObject(
    runtimeEpoch: string,
    objectId: number,
    moduleName: string,
    className: string,
    nativeRefType: string,
    args: ESObject[],
  ): void {
    this.modules.constructSharedObject(runtimeEpoch, objectId, moduleName, className, nativeRefType, args);
  }

  bindExpoSharedObject(
    runtimeEpoch: string,
    authorId: number,
    objectId: number,
    moduleName: string,
    className: string,
    nativeRefType: string,
  ): number {
    return this.modules.bindSharedObject(runtimeEpoch, authorId, objectId, moduleName, className, nativeRefType);
  }

  discardExpoSharedObjects(runtimeEpoch: string, authorIds: number[]): void {
    this.modules.discardSharedObjects(runtimeEpoch, authorIds);
  }

  invokeExpoSharedObjectSync(
    runtimeEpoch: string,
    objectId: number,
    moduleName: string,
    className: string,
    functionName: string,
    args: ESObject[],
  ): ESObject {
    return this.modules.invokeSharedObjectSync(runtimeEpoch, objectId, moduleName, className, functionName, args);
  }

  async invokeExpoSharedObjectAsync(
    runtimeEpoch: string,
    objectId: number,
    moduleName: string,
    className: string,
    functionName: string,
    args: ESObject[],
  ): Promise<ESObject> {
    return await this.modules.invokeSharedObjectAsync(runtimeEpoch, objectId, moduleName, className, functionName, args);
  }

  invokeExpoSharedObjectStaticSync(runtimeEpoch: string, moduleName: string, className: string, functionName: string, args: ESObject[]): ESObject {
    return this.modules.invokeSharedObjectStaticSync(runtimeEpoch, moduleName, className, functionName, args);
  }

  async invokeExpoSharedObjectStaticAsync(
    runtimeEpoch: string,
    moduleName: string,
    className: string,
    functionName: string,
    args: ESObject[],
  ): Promise<ESObject> {
    return await this.modules.invokeSharedObjectStaticAsync(runtimeEpoch, moduleName, className, functionName, args);
  }

  getExpoSharedObjectProperty(runtimeEpoch: string, objectId: number, moduleName: string, className: string, propertyName: string): ESObject {
    return this.modules.getSharedObjectProperty(runtimeEpoch, objectId, moduleName, className, propertyName);
  }

  setExpoSharedObjectProperty(
    runtimeEpoch: string,
    objectId: number,
    moduleName: string,
    className: string,
    propertyName: string,
    value: ESObject,
  ): void {
    this.modules.setSharedObjectProperty(runtimeEpoch, objectId, moduleName, className, propertyName, value);
  }

  setExpoSharedObjectObserving(
    runtimeEpoch: string,
    objectId: number,
    moduleName: string,
    className: string,
    eventName: string,
    observing: boolean,
  ): void {
    this.modules.setSharedObjectObserving(runtimeEpoch, objectId, moduleName, className, eventName, observing);
  }

  setExpoModuleObserving(runtimeEpoch: string, moduleName: string, eventName: string, observing: boolean): void {
    this.modules.setObserving(runtimeEpoch, moduleName, eventName, observing);
  }

  releaseExpoSharedObject(runtimeEpoch: string, objectId: number): void {
    this.modules.releaseSharedObject(runtimeEpoch, objectId);
  }

  expoSharedObjectWillRelease(runtimeEpoch: string, objectId: number): void {
    this.modules.sharedObjectWillRelease(runtimeEpoch, objectId);
  }

  getExpoSharedObjectMemoryPressure(runtimeEpoch: string, objectId: number): number {
    return this.modules.sharedObjectMemoryPressure(runtimeEpoch, objectId);
  }

  invalidateExpoModuleRuntime(runtimeEpoch: string): void {
    // Global teardown waits for the native invalidation ACK.
    if (this.destroyStarted) return;
    this.modules.invalidateRuntime(runtimeEpoch);
  }

  dispatchExpoModuleLifecycle(eventName: string, payload?: ESObject): void {
    this.postLifecycleEvent(eventName, payload);
  }

  getCacheDirectory(): string {
    this.session?.assertOpen();
    return ensureDirectoryUri(this.modules.services.require(ExpoRuntimeDirectoriesKey).directory(this.coreContext.uiAbilityContext.cacheDir));
  }

  getDocumentsDirectory(): string {
    this.session?.assertOpen();
    return ensureDirectoryUri(this.modules.services.require(ExpoRuntimeDirectoriesKey).directory(this.coreContext.uiAbilityContext.filesDir));
  }

  getRuntimeId(): number {
    return this.coreContext.rnInstance.getId();
  }

  async reloadAppAsync(reason: string): Promise<void> {
    await this.modules.reloadAppAsync(reason);
  }

  override __onDestroy__(): void {
    if (this.destroyFinished) return;

    this.destroyStarted = true;
    this.destroyFinished = true;

    try {
      ExpoViewAdapterRegistry.destroyInstance(this.coreContext.rnInstance.getId());
    } catch (error) {
      reportDestroyFailure('view registry', error);
    }

    const unsubscribers = this.unsubscribeLifecycle.splice(0);
    unsubscribers.forEach((unsubscribe: () => void, index: number): void => {
      try {
        unsubscribe();
      } catch (error) {
        reportDestroyFailure(`lifecycle subscription ${index}`, error);
      }
    });

    try {
      this.modules.invalidate();
    } catch (error) {
      reportDestroyFailure('ArkTS Expo modules', error);
    }
  }

  private async prepareForDestroy(): Promise<void> {
    if (this.destroyFinished) return;
    this.destroyStarted = true;
    // RNOH must retain its native instance and JS executor through the ACK.
    // The owning destruction promise retains this Host without a global map.
    await this.beginNativeDestroyHandshake();
    this.__onDestroy__();
  }

  private async beginNativeDestroyHandshake(): Promise<void> {
    const requestId = `${this.coreContext.rnInstance.getId()}:${Date.now()}:${nextDestroyRequestId++}`;
    let warningTimer: number = -1;
    let unsubscribeAck: () => void = (): void => {};

    try {
      await new Promise<void>((resolve: () => void): void => {
        unsubscribeAck = this.coreContext.rnInstance.cppEventEmitter.subscribe(EXPO_LIFECYCLE_DESTROY_ACK, (payload: ESObject): void => {
          if (payload?.requestId === requestId) resolve();
        });

        warningTimer = setTimeout((): void => {
          warningTimer = -1;
          reportDestroyFailure(
            'native lifecycle acknowledgement',
            new Error(
              `Still waiting after ${DESTROY_ACK_WARNING_MS}ms for ${requestId}; RNOH destruction is paused until native invalidation completes.`,
            ),
          );
        }, DESTROY_ACK_WARNING_MS);

        this.postLifecycleEvent(EXPO_LIFECYCLE_DESTROY, { requestId });
      });
    } finally {
      if (warningTimer >= 0) {
        clearTimeout(warningTimer);
      }
      try {
        unsubscribeAck();
      } catch (error) {
        reportDestroyFailure('native lifecycle acknowledgement subscription', error);
      }
    }
  }

  postLifecycleEvent(eventName: string, payload?: ESObject): void {
    if (this.destroyStarted && eventName !== EXPO_LIFECYCLE_DESTROY) return;
    if (eventName === EXPO_LIFECYCLE_FOREGROUND || eventName === EXPO_LIFECYCLE_BACKGROUND) {
      if (this.lastAppLifecycleEvent === eventName) return;
      this.lastAppLifecycleEvent = eventName;
    }
    // DESTROY is owned by the native invalidation handshake.
    if (eventName !== EXPO_LIFECYCLE_DESTROY && !this.modules.dispatchLifecycle(eventName, payload)) {
      return;
    }

    if (eventName !== EXPO_LIFECYCLE_DESTROY) return;

    this.coreContext.rnInstance.postMessageToCpp(EXPO_LIFECYCLE_EVENT, {
      eventName,
      payload,
    });
  }
}

function readJavaScriptBundleDurationSeconds(context: UITurboModuleContext): number | undefined {
  try {
    const snapshot = (context.rnInstance as RNInstanceImpl).getPerformanceMetricsSnapshot();
    const durationMs = snapshot?.SCRIPT_EXECUTION;

    if (durationMs === undefined || !Number.isFinite(durationMs) || durationMs <= 0) {
      context.logger.warn('RNOH did not provide a valid JavaScript bundle execution duration.');

      return undefined;
    }

    return durationMs / 1000;
  } catch (error) {
    context.logger.warn(`Unable to read the completed RNOH JavaScript bundle duration: ${String(error)}`);

    return undefined;
  }
}

function reportDestroyFailure(step: string, error: Object): void {
  let message = 'unknown error';
  try {
    message = String(error);
  } catch (_) {}

  try {
    console.error(`Expo Modules teardown failed for ${step}: ${message}`);
  } catch (_) {}
}

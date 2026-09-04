import { AbilityConstant, abilityAccessCtrl, common, PermissionRequestResult, Permissions, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { lang } from '@kit.ArkTS';
import deviceInfo from '@ohos.deviceInfo';
import { LifecycleState, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import {
  EXPO_LIFECYCLE_ACTIVITY_DESTROY,
  EXPO_LIFECYCLE_ACTIVITY_RESULT,
  EXPO_LIFECYCLE_BACKGROUND,
  EXPO_LIFECYCLE_CONTENT_APPEARED,
  EXPO_LIFECYCLE_DESTROY,
  EXPO_LIFECYCLE_FOREGROUND,
  EXPO_LIFECYCLE_JAVASCRIPT_BUNDLE_LOADED,
  EXPO_LIFECYCLE_MEMORY_LEVEL,
  EXPO_LIFECYCLE_NEW_INTENT,
  EXPO_LIFECYCLE_WINDOW_STAGE_SETUP,
  EXPO_LIFECYCLE_WINDOW_STAGE_WILL_DESTROY,
  EXPO_MODULE_EVENT,
  EXPO_SHARED_OBJECT_EVENT,
} from '../protocol/Protocol';
import {
  ExpoSharedObjectClassDefinition,
  ExpoSharedObjectClassDescriptor,
  ExpoSharedObjectClassRuntime,
  ExpoSharedObject,
  ExpoSharedObjectRegistry,
} from './ExpoSharedObject';
import { ExpoView, ExpoViewDefinition, ExpoViewDefinitionRuntime, ExpoViewDescriptor } from '../views/ExpoViewDefinition';
import { ExpoViewAdapterRegistry } from '../views/ExpoViewTypes';
import {
  ExpoAsyncFunctionBody,
  ExpoAsyncFunction,
  ExpoFunction0,
  ExpoFunction1,
  ExpoFunction2,
  ExpoFunction3,
  ExpoFunction4,
  ExpoFunction5,
  ExpoFunction6,
  ExpoFunction7,
  ExpoFunction8,
  ExpoFunctionArityRange,
  ExpoFunctionSpec,
  ExpoSyncFunction,
  ExpoSyncFunctionBody,
  ExpoValueConverter,
  ExpoValueType,
  functionArity,
  invokeAsyncFunction,
  invokeSyncFunction,
  writableFunctionArguments,
} from './ExpoValueConverter';
import { ExpoModuleError } from './ExpoModuleError';
import { createExpoModuleLogger, ExpoModuleLogger } from '../appcontext/ExpoModuleLogger';
import { ExpoLifecycleEventQueue, ExpoLifecycleSink } from '../appcontext/LifecycleDispatcher';
import { snapshotExpoEventArguments } from './ExpoEventValueSnapshot';
import { ensureDirectoryUri } from '../appcontext/FileUri';
import { ExpoRnohWorkerParams, ExpoRnohWorkerTask, runOnRnohWorker } from '../appcontext/RnohWorkerAdapter';

export type ExpoModuleLifecycleBody = () => void;

export type ExpoModuleAsyncLifecycleBody = () => Promise<void>;
export type ExpoModuleJavaScriptBundleLoadedBody = (durationSeconds?: number) => void;
export type ExpoModuleObservationBody = (eventName: string) => void;
export type ExpoModuleNewWantBody = (want: Want) => void;

export interface ExpoModuleAbilityResult {
  readonly requestCode: number;
  readonly resultCode: number;
  readonly data?: Want;
}

export type ExpoModuleAbilityResultBody = (result: ExpoModuleAbilityResult) => void;
export type ExpoModuleMemoryLevelBody = (level: AbilityConstant.MemoryLevel) => void;
export type ExpoModuleWindowStageBody = (windowStage: window.WindowStage) => void;
type ExpoRuntimeLifecycleDispatcher = (eventName: string, payload?: ESObject) => void;
type ExpoRuntimeReload = (reason: string) => Promise<void>;

/** Semantic app state for the current RNOH instance without exposing RNOH internals. */
export enum ExpoAppLifecycleState {
  BEFORE_CREATE = 'beforeCreate',
  BACKGROUND = 'background',
  FOREGROUND = 'foreground',
}

/** API-level-independent permission state exposed to module authors. */
export enum ExpoPermissionStatus {
  DENIED = -1,
  GRANTED = 0,
  NOT_DETERMINED = 1,
  INVALID = 2,
  RESTRICTED = 3,
}

/** A closure that remains on the current Modules/UI ArkTS actor. */
export type ExpoModuleActorTask<Result> = () => Result | Promise<Result>;

/** Parameters that the Harmony structured-clone boundary permits on the RNOH worker. */
export type ExpoBackgroundTaskParams = ExpoRnohWorkerParams;

/** Results that the Harmony structured-clone boundary permits from the RNOH worker. */
export type ExpoBackgroundTaskResult = lang.ISendable | void;

/** Minimal runtime identity visible to an explicitly sendable background task. */
export interface ExpoBackgroundTaskContext {
  getId(): number;
}

/** Sendable work executed by RNOH's worker actor. */
export interface ExpoBackgroundTask<
  Params extends ExpoBackgroundTaskParams = undefined,
  Result extends ExpoBackgroundTaskResult = ExpoBackgroundTaskResult,
> extends ExpoRnohWorkerTask<Params, Result> {
  run(context: ExpoBackgroundTaskContext, params: Params): Result;
}

export interface ExpoModuleConstantDescriptor {
  readonly name: string;
}

type ExpoModuleConstantGetter = () => ESObject | void;

interface ExpoModuleConstantRegistration {
  readonly name: string;
  readonly getter: ExpoModuleConstantGetter;
}

export interface ExpoModuleFunctionDescriptor {
  readonly name: string;
  readonly arity: number;
  readonly requiredArity: number;
  readonly async: boolean;
  readonly writableArguments: number[];
}

export interface ExpoModulePropertyDescriptor {
  readonly name: string;
  readonly writable: boolean;
}

/** Copy-value metadata consumed by the common C++ Host adapter. */
export interface ExpoModuleDescriptor {
  readonly name: string;
  readonly constants: ExpoModuleConstantDescriptor[];
  readonly functions: ExpoModuleFunctionDescriptor[];
  readonly properties: ExpoModulePropertyDescriptor[];
  readonly events: string[];
  readonly classes: ExpoSharedObjectClassDescriptor[];
  readonly views: ExpoViewDescriptor[];
}

interface ExpoModuleFunctionRegistration {
  readonly descriptor: ExpoModuleFunctionDescriptor;
  readonly syncBody?: ExpoSyncFunction;
  readonly asyncBody?: ExpoAsyncFunction;
}

type ExpoModulePropertyGetter = () => ESObject | void;
type ExpoModulePropertySetter = (value: ESObject) => void;

interface ExpoModulePropertyRegistration {
  readonly descriptor: ExpoModulePropertyDescriptor;
  readonly getter: ExpoModulePropertyGetter;
  readonly setter?: ExpoModulePropertySetter;
}

export type ExpoModuleFactory = (context: ExpoModuleContext) => ExpoModule;

/** Application-level registration emitted by Expo Modules autolinking. */
export interface ExpoModuleRegistration {
  readonly registrationId: string;
  readonly moduleClassName: string;
  readonly factory: ExpoModuleFactory;
}

interface ExpoResolvedModuleRegistration {
  readonly registrationId: string;
  readonly moduleClassName: string;
  readonly factory: ExpoModuleFactory;
}

class ExpoTypedEventEnvelope {
  readonly runtimeEpoch: string;
  readonly args: ESObject[];

  constructor(runtimeEpoch: string, args: ESObject[]) {
    this.runtimeEpoch = runtimeEpoch;
    this.args = args;
  }
}

class ExpoTypedModuleEventMessage {
  readonly runtimeEpoch: string;
  readonly moduleName: string;
  readonly eventName: string;
  readonly transportId: number;

  constructor(runtimeEpoch: string, moduleName: string, eventName: string, transportId: number) {
    this.runtimeEpoch = runtimeEpoch;
    this.moduleName = moduleName;
    this.eventName = eventName;
    this.transportId = transportId;
  }
}

class ExpoTypedSharedObjectEventMessage {
  readonly runtimeEpoch: string;
  readonly objectId: number;
  readonly moduleName: string;
  readonly className: string;
  readonly eventName: string;
  readonly transportId: number;

  constructor(runtimeEpoch: string, objectId: number, moduleName: string, className: string, eventName: string, transportId: number) {
    this.runtimeEpoch = runtimeEpoch;
    this.objectId = objectId;
    this.moduleName = moduleName;
    this.className = className;
    this.eventName = eventName;
    this.transportId = transportId;
  }
}

/** Host-owned queue for values outside RNOH's dynamic message format. */
class ExpoTypedEventQueue {
  private readonly coreContext: UITurboModuleContext;
  private readonly pending: Map<number, ExpoTypedEventEnvelope> = new Map<number, ExpoTypedEventEnvelope>();
  private nextTransportId: number = 1;
  private valid: boolean = true;

  constructor(coreContext: UITurboModuleContext) {
    this.coreContext = coreContext;
  }

  emitModule(runtimeEpoch: string, moduleName: string, eventName: string, args: ESObject[]): void {
    const transportId: number = this.stage(runtimeEpoch, args);

    try {
      this.coreContext.rnInstance.postMessageToCpp(
        EXPO_MODULE_EVENT,
        new ExpoTypedModuleEventMessage(runtimeEpoch, moduleName, eventName, transportId),
      );
    } catch (error) {
      this.pending.delete(transportId);

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      if (error instanceof Error) {
        throw new Error(error.message);
      }
      throw new Error(errorMessage(error));
    }
  }

  emitSharedObject(runtimeEpoch: string, objectId: number, moduleName: string, className: string, eventName: string, args: ESObject[]): void {
    const transportId: number = this.stage(runtimeEpoch, args);

    try {
      this.coreContext.rnInstance.postMessageToCpp(
        EXPO_SHARED_OBJECT_EVENT,
        new ExpoTypedSharedObjectEventMessage(runtimeEpoch, objectId, moduleName, className, eventName, transportId),
      );
    } catch (error) {
      this.pending.delete(transportId);

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      if (error instanceof Error) {
        throw new Error(error.message);
      }
      throw new Error(errorMessage(error));
    }
  }

  take(runtimeEpoch: string, transportId: number): ESObject[] {
    this.assertValid();
    requireRuntimeEpoch(runtimeEpoch);
    if (!Number.isSafeInteger(transportId) || transportId <= 0) {
      throw new Error('Expo typed event transport ID must be a positive safe integer.');
    }

    const envelope: ExpoTypedEventEnvelope | undefined = this.pending.get(transportId);
    if (envelope === undefined || envelope.runtimeEpoch !== runtimeEpoch) {
      throw new Error(`Cannot find Expo typed event ${transportId} for runtime '${runtimeEpoch}'.`);
    }

    this.pending.delete(transportId);

    return envelope.args;
  }

  discardRuntime(runtimeEpoch: string): ESObject[][] {
    const discarded: ESObject[][] = [];

    this.pending.forEach((envelope: ExpoTypedEventEnvelope, transportId: number): void => {
      if (envelope.runtimeEpoch !== runtimeEpoch) return;
      discarded.push(envelope.args);
      this.pending.delete(transportId);
    });

    return discarded;
  }

  invalidate(): void {
    if (!this.valid) return;
    this.valid = false;
    this.pending.clear();
  }

  private stage(runtimeEpoch: string, args: ESObject[]): number {
    this.assertValid();
    requireRuntimeEpoch(runtimeEpoch);

    if (this.nextTransportId > Number.MAX_SAFE_INTEGER) {
      if (this.pending.size > 0) {
        throw new Error('Expo typed event transport ID space is exhausted.');
      }
      this.nextTransportId = 1;
    }

    const transportId: number = this.nextTransportId;

    this.nextTransportId += 1;
    this.pending.set(transportId, new ExpoTypedEventEnvelope(runtimeEpoch, snapshotExpoEventArguments(args)));

    return transportId;
  }

  private assertValid(): void {
    if (!this.valid) throw new Error('The Expo typed event queue was invalidated.');
  }
}

/** Runtime-scoped capabilities for an ArkTS Expo Module. */
export class ExpoModuleContext {
  readonly uiAbilityContext: common.UIAbilityContext;
  readonly runtimeId: number;
  /** Provider-scoped identity that remains stable across RN runtime reloads. */
  readonly hostId: string;
  /** Monotonic generation of the RN Host within the owning UIAbility. */
  readonly hostRuntimeGeneration: number;
  private readonly coreContext: UITurboModuleContext;
  private readonly dispatchRuntimeLifecycle: ExpoRuntimeLifecycleDispatcher;
  private readonly reloadRuntime: ExpoRuntimeReload;
  private readonly epoch: string;
  private readonly initialWantValue?: Want;
  private moduleName?: string = undefined;
  private declaredEvents: Set<string> = new Set<string>();
  private declaredEventPayloadTypes: Map<string, ExpoValueType<ESObject>> = new Map<string, ExpoValueType<ESObject>>();
  private sharedObjects?: ExpoSharedObjectRegistry = undefined;
  private typedEvents?: ExpoTypedEventQueue = undefined;
  private moduleResolver?: (name: string) => ExpoModule | undefined = undefined;
  private scopedLogger?: ExpoModuleLogger = undefined;
  private acceptsEvents: boolean = true;
  private valid: boolean = true;

  constructor(
    coreContext: UITurboModuleContext,
    runtimeEpoch: string,
    hostId: string,
    hostRuntimeGeneration: number,
    dispatchRuntimeLifecycle: ExpoRuntimeLifecycleDispatcher,
    reloadRuntime: ExpoRuntimeReload,
    initialWant?: Want,
  ) {
    this.coreContext = coreContext;
    this.epoch = runtimeEpoch;
    this.uiAbilityContext = coreContext.uiAbilityContext;
    this.runtimeId = coreContext.rnInstance.getId();
    this.hostId = hostId;
    this.hostRuntimeGeneration = hostRuntimeGeneration;
    this.dispatchRuntimeLifecycle = dispatchRuntimeLifecycle;
    this.reloadRuntime = reloadRuntime;
    this.initialWantValue = initialWant;
  }

  /** @internal Called exactly once by ExpoModulesRegistry. */
  bindModule(
    name: string,
    events: string[],
    eventPayloadTypes: Map<string, ExpoValueType<ESObject>>,
    sharedObjects: ExpoSharedObjectRegistry,
    typedEvents: ExpoTypedEventQueue,
    moduleResolver: (name: string) => ExpoModule | undefined,
  ): void {
    this.assertValid();
    if (this.moduleName !== undefined) {
      throw new Error('An ExpoModuleContext cannot be bound more than once.');
    }
    this.moduleName = name;
    this.declaredEvents = new Set<string>(events);
    this.declaredEventPayloadTypes = new Map<string, ExpoValueType<ESObject>>(eventPayloadTypes);
    this.sharedObjects = sharedObjects;
    this.typedEvents = typedEvents;
    this.moduleResolver = moduleResolver;
    this.scopedLogger = createExpoModuleLogger(this.coreContext.logger, name);
  }

  /** Stable identity for this RuntimeContext generation. */
  get runtimeEpoch(): string {
    this.assertValid();
    return this.epoch;
  }

  /** Initial launch URI captured by RNOH when this Host/runtime was created. */
  get launchUri(): string | undefined {
    this.assertValid();
    return this.coreContext.launchUri;
  }

  /** Initial Ability Want for modules that need launch parameters beyond the URI. */
  get initialWant(): Want | undefined {
    this.assertValid();
    return this.initialWantValue;
  }

  /** Debug state of the consuming RNOH application, not the prebuilt module HAR. */
  get isDebug(): boolean {
    this.assertValid();
    return this.coreContext.isDebugModeEnabled;
  }

  /** Initial/current app state for lifecycle-sensitive module initialization. */
  get appLifecycleState(): ExpoAppLifecycleState {
    this.assertValid();
    const state = this.coreContext.rnInstance.getLifecycleState();
    if (state === LifecycleState.READY) return ExpoAppLifecycleState.FOREGROUND;
    if (state === LifecycleState.BEFORE_CREATE) return ExpoAppLifecycleState.BEFORE_CREATE;
    return ExpoAppLifecycleState.BACKGROUND;
  }

  /** The window that owns the current RN surface. */
  async getReactNativeWindow(): Promise<window.Window> {
    this.assertValid();

    const current = await this.coreContext.rnInstance.getRNWindow();

    this.assertValid();

    return current;
  }

  /** Registers a font that its owning module has already validated with RNOH. */
  registerReactNativeFont(family: string, path: string): void {
    this.assertValid();
    this.coreContext.rnInstance.registerFont(family, path);
  }

  /** `file://` URI for disposable cache files. */
  get cacheDirectory(): string {
    this.assertValid();
    return ensureDirectoryUri(this.uiAbilityContext.cacheDir);
  }

  /** `file://` URI for persistent application files. */
  get persistentFilesDirectory(): string {
    this.assertValid();
    return ensureDirectoryUri(this.uiAbilityContext.filesDir);
  }

  /** `file://` URI for temporary files owned by the current application. */
  get temporaryDirectory(): string {
    this.assertValid();
    return ensureDirectoryUri(this.uiAbilityContext.tempDir);
  }

  get logger(): ExpoModuleLogger {
    this.assertValid();
    if (this.scopedLogger === undefined) {
      throw new ExpoModuleError('ERR_MODULE_CONTEXT_NOT_BOUND', 'The Expo module logger is unavailable before its definition is registered.');
    }
    return this.scopedLogger;
  }

  get isValid(): boolean {
    return this.valid;
  }

  permissionStatus(permission: Permissions): ExpoPermissionStatus {
    this.assertValid();

    const manager = abilityAccessCtrl.createAtManager();

    if (deviceInfo.apiAvailable(20)) {
      return manager.getSelfPermissionStatus(permission) as number as ExpoPermissionStatus;
    }

    const token = this.uiAbilityContext.applicationInfo.accessTokenId;
    const granted = manager.checkAccessTokenSync(token, permission) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;

    return granted ? ExpoPermissionStatus.GRANTED : ExpoPermissionStatus.DENIED;
  }

  async requestPermissions(permissions: Permissions[]): Promise<PermissionRequestResult> {
    this.assertValid();
    return await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.uiAbilityContext, permissions);
  }

  async startAbilityForResult(want: Want, requestCode: number = 0): Promise<ExpoModuleAbilityResult> {
    this.assertValid();

    const response = await this.uiAbilityContext.startAbilityForResult(want);

    this.assertValid();

    const result: ExpoModuleAbilityResult = {
      requestCode,
      resultCode: response.resultCode,
      data: response.want,
    };

    this.dispatchRuntimeLifecycle(EXPO_LIFECYCLE_ACTIVITY_RESULT, result);

    return result;
  }

  /** Requests one Host reload after every scoped module prepared for teardown. */
  async reloadAppAsync(reason: string = 'Reload from ExpoModuleContext'): Promise<void> {
    this.assertValid();
    await this.reloadRuntime(reason);
  }

  /** Runs a closure on the current Modules/UI actor. */
  async runOnModulesQueue<Result>(body: ExpoModuleActorTask<Result>): Promise<Result> {
    return await this.runOnCurrentActor(body);
  }

  /** Harmony's Modules and UI queues share the same ArkTS actor. */
  async runOnUIQueue<Result>(body: ExpoModuleActorTask<Result>): Promise<Result> {
    return await this.runOnCurrentActor(body);
  }

  /** Harmony's main and UI queues share the same ArkTS actor. */
  async runOnMainQueue<Result>(body: ExpoModuleActorTask<Result>): Promise<Result> {
    return await this.runOnCurrentActor(body);
  }

  /** Runs a sendable task on RNOH's worker actor. */
  async runInBackground<
    Params extends ExpoBackgroundTaskParams,
    Result extends ExpoBackgroundTaskResult,
    Task extends ExpoBackgroundTask<Params, Result>,
  >(task: Task, params: Params): Promise<Result> {
    this.assertValid();

    let result: Result;
    try {
      result = await runOnRnohWorker<Params, Result, Task>(this.coreContext, task, params);
    } catch (error) {
      throw new ExpoModuleError(
        'ERR_BACKGROUND_QUEUE_UNAVAILABLE',
        error instanceof Error ? error.message : 'The current RNOH context does not provide a worker task runner.',
      );
    }

    this.assertValid();

    return result;
  }

  /** Controlled lookup within the same Host/runtime scope. */
  getModule(name: string): ExpoModule | undefined {
    this.assertValid();
    return this.moduleResolver?.(name);
  }

  requireModule(name: string): ExpoModule {
    const module = this.getModule(name);
    if (module === undefined) {
      throw new ExpoModuleError('ERR_MODULE_NOT_FOUND', `Cannot find Expo module '${name}' in runtime '${this.epoch}'.`);
    }
    return module;
  }

  /** Finds an author-owned mounted View in this RN instance and runtime. */
  findView(tag: number, componentName?: string): ExpoView | undefined {
    this.assertValid();

    if (!Number.isSafeInteger(tag) || tag <= 0) {
      throw new ExpoModuleError('ERR_INVALID_VIEW_TAG', `Expo view lookup requires a positive safe-integer tag; received ${tag}.`);
    }

    const view: ESObject | undefined = ExpoViewAdapterRegistry.findContent(this.runtimeId, this.epoch, tag, componentName);

    return view as ExpoView | undefined;
  }

  /** Runtime converter for mounted Expo Views owned by this Host/runtime. */
  nativeViewType<ViewType extends ExpoView = ExpoView>(componentName?: string): ExpoValueType<ViewType> {
    const expected: string = componentName === undefined ? 'mounted Expo View tag' : `mounted Expo View '${componentName}' tag`;
    return new ExpoValueType<ViewType>(
      expected,
      (value: ESObject, path: string): ViewType => {
        if (typeof value !== 'number' || !Number.isSafeInteger(value) || value <= 0) {
          throw new ExpoModuleError('ERR_INVALID_VIEW_TAG', `${path} expected ${expected}, received ${ExpoValueConverter.actualType(value)}.`);
        }
        const view = this.findView(value, componentName);
        if (view === undefined) {
          throw new ExpoModuleError('ERR_VIEW_NOT_FOUND', `${path} cannot resolve ${expected} ${value} in the current runtime.`);
        }
        return view as ViewType;
      },
      (_value: ViewType, path: string): ESObject => {
        throw new ExpoModuleError('ERR_INVALID_RETURN_VALUE', `${path} cannot return an ArkTS Expo View to JavaScript.`);
      },
    );
  }

  sendEvent(eventName: string): void;
  sendEvent<Payload>(eventName: string, payload: Payload): void;
  sendEvent<Payload>(eventName: string, payload?: Payload): void {
    this.assertEventAdmission();
    if (this.moduleName === undefined) {
      throw new Error('An Expo module cannot send events before its definition is registered.');
    }
    if (!this.declaredEvents.has(eventName)) {
      throw new Error(`Expo module '${this.moduleName}' did not declare event '${eventName}'.`);
    }

    const sharedObjects = this.sharedObjects;
    if (sharedObjects === undefined) {
      throw new Error('The Expo module SharedObject registry is not bound.');
    }

    const moduleName: string = this.moduleName;
    const value: ESObject | void = ExpoValueConverter.toBridge(
      payload as ESObject,
      this.declaredEventPayloadTypes.get(eventName),
      `Expo module event '${moduleName}.${eventName}' payload`,
    );

    const typedEvents = this.typedEvents;
    if (typedEvents === undefined) {
      throw new Error('The Expo module typed event transport is not bound.');
    }

    const encoded: ESObject[] = sharedObjects.encodeArguments(value === undefined ? [] : [value]);

    try {
      typedEvents.emitModule(this.epoch, moduleName, eventName, encoded);
    } catch (error) {
      sharedObjects.discardEncodedArguments(encoded);

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      if (error instanceof Error) {
        throw new Error(error.message);
      }
      throw new Error(errorMessage(error));
    }
  }

  /** @internal */
  sendSharedObjectEvent(runtimeEpoch: string, objectId: number, moduleName: string, className: string, eventName: string, args: ESObject[]): void {
    this.assertEventAdmission();
    this.assertRuntimeEpoch(runtimeEpoch);

    const sharedObjects = this.sharedObjects;
    if (sharedObjects === undefined) {
      throw new Error('The Expo module SharedObject registry is not bound.');
    }

    const typedEvents = this.typedEvents;
    if (typedEvents === undefined) {
      throw new Error('The Expo module typed event transport is not bound.');
    }

    const encoded: ESObject[] = sharedObjects.encodeArguments(args);

    try {
      typedEvents.emitSharedObject(runtimeEpoch, objectId, moduleName, className, eventName, encoded);
    } catch (error) {
      sharedObjects.discardEncodedArguments(encoded);

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      if (error instanceof Error) {
        throw new Error(error.message);
      }
      throw new Error(errorMessage(error));
    }
  }

  /** @internal */
  runtimeEpochValue(): string {
    this.assertValid();
    return this.epoch;
  }

  /** @internal */
  assertRuntimeEpoch(runtimeEpoch: string): void {
    this.assertValid();
    if (runtimeEpoch !== this.epoch) {
      throw new Error('The Expo module value belongs to another runtime epoch.');
    }
  }

  /** @internal Invalidates the public author surface after onDestroy returns. */
  invalidate(): void {
    this.acceptsEvents = false;
    this.valid = false;
    this.declaredEvents.clear();
    this.declaredEventPayloadTypes.clear();
    this.sharedObjects = undefined;
    this.typedEvents = undefined;
    this.moduleResolver = undefined;
    this.scopedLogger = undefined;
    this.moduleName = undefined;
  }

  /** @internal Stops new event admission while keeping cleanup capabilities live. */
  beginInvalidation(): void {
    if (!this.valid) return;
    this.acceptsEvents = false;
  }

  private assertValid(): void {
    if (!this.valid) {
      throw new Error('The Expo module runtime has been invalidated.');
    }
  }

  private assertEventAdmission(): void {
    this.assertValid();
    if (!this.acceptsEvents) {
      throw new ExpoModuleError('ERR_RUNTIME_INVALIDATED', 'The Expo module runtime is invalidating and no longer accepts events.');
    }
  }

  private async runOnCurrentActor<Result>(body: ExpoModuleActorTask<Result>): Promise<Result> {
    this.assertValid();

    await Promise.resolve();

    this.assertValid();

    const result: Result = await body();

    this.assertValid();

    return result;
  }
}

/** Public ArkTS module base class. */
export abstract class ExpoModule {
  readonly context: ExpoModuleContext;
  readonly appContext: ExpoModuleContext;

  constructor(context: ExpoModuleContext) {
    this.context = context;
    this.appContext = context;
  }

  abstract definition(): ExpoModuleDefinition;

  protected sendEvent(eventName: string): void;
  protected sendEvent<Payload>(eventName: string, payload: Payload): void;
  protected sendEvent<Payload>(eventName: string, payload?: Payload): void {
    if (payload === undefined) {
      this.context.sendEvent(eventName);
      return;
    }
    this.context.sendEvent(eventName, payload);
  }
}

/** ArkTS-native module definition builder. */
export class ExpoModuleDefinition {
  private moduleName?: string = undefined;
  private readonly constantValues: Map<string, ExpoModuleConstantRegistration> = new Map<string, ExpoModuleConstantRegistration>();
  private readonly functionValues: Map<string, ExpoModuleFunctionRegistration> = new Map<string, ExpoModuleFunctionRegistration>();
  private readonly propertyValues: Map<string, ExpoModulePropertyRegistration> = new Map<string, ExpoModulePropertyRegistration>();
  private readonly eventNames: Set<string> = new Set<string>();
  private readonly eventPayloadTypes: Map<string, ExpoValueType<ESObject>> = new Map<string, ExpoValueType<ESObject>>();
  private readonly classValues: ExpoSharedObjectClassRuntime[] = [];
  private readonly classNames: Set<string> = new Set<string>();
  private readonly viewValues: ExpoViewDefinitionRuntime[] = [];
  private readonly viewNames: Set<string> = new Set<string>();
  private createBody?: ExpoModuleLifecycleBody = undefined;
  private destroyBody?: ExpoModuleLifecycleBody = undefined;
  private foregroundBody?: ExpoModuleLifecycleBody = undefined;
  private backgroundBody?: ExpoModuleLifecycleBody = undefined;
  private contentAppearedBody?: ExpoModuleLifecycleBody = undefined;
  private javaScriptBundleLoadedBody?: ExpoModuleJavaScriptBundleLoadedBody = undefined;
  private prepareForReloadBody?: ExpoModuleAsyncLifecycleBody = undefined;
  private abilityDestroyBody?: ExpoModuleLifecycleBody = undefined;
  private newWantBody?: ExpoModuleNewWantBody = undefined;
  private activityResultBody?: ExpoModuleAbilityResultBody = undefined;
  private memoryLevelBody?: ExpoModuleMemoryLevelBody = undefined;
  private windowStageSetupBody?: ExpoModuleWindowStageBody = undefined;
  private windowStageWillDestroyBody?: ExpoModuleLifecycleBody = undefined;
  private readonly startObservingBodies: ExpoModuleObservationBody[] = [];
  private readonly stopObservingBodies: ExpoModuleObservationBody[] = [];
  private readonly startObservingByEvent: Map<string, ExpoModuleLifecycleBody[]> = new Map<string, ExpoModuleLifecycleBody[]>();
  private readonly stopObservingByEvent: Map<string, ExpoModuleLifecycleBody[]> = new Map<string, ExpoModuleLifecycleBody[]>();

  name(value: string): ExpoModuleDefinition {
    if (value.length === 0) throw new Error('Expo module names cannot be empty.');
    this.moduleName = value;
    return this;
  }

  constant<Value>(name: string, getter: ExpoFunction0<Value>): ExpoModuleDefinition;
  constant(name: string, value: ESObject): ExpoModuleDefinition;
  constant<Value>(name: string, valueOrGetter: ESObject | ExpoFunction0<Value>): ExpoModuleDefinition {
    requireMemberName(name, 'constant');
    this.requireAvailableModuleMember(name);

    const getter: ExpoModuleConstantGetter =
      typeof valueOrGetter === 'function'
        ? (): ESObject | void =>
            ExpoValueConverter.toBridge((valueOrGetter as ExpoFunction0<Value>)(), undefined, `Expo module '${this.requireName()}.${name}' constant`)
        : (): ESObject | void =>
            ExpoValueConverter.toBridge(valueOrGetter as ESObject, undefined, `Expo module '${this.requireName()}.${name}' constant`);

    this.constantValues.set(name, { name, getter });

    return this;
  }

  typedConstant<Value>(name: string, type: ExpoValueType<Value>, getter: ExpoFunction0<Value>): ExpoModuleDefinition {
    requireMemberName(name, 'constant');
    this.requireAvailableModuleMember(name);

    this.constantValues.set(name, {
      name,
      getter: (): ESObject | void => ExpoValueConverter.toBridge(getter(), type, `Expo module '${this.requireName()}.${name}' constant`),
    });

    return this;
  }

  constants(values: Record<string, ESObject>): ExpoModuleDefinition {
    Object.keys(values).forEach((name: string): void => {
      this.constant(name, values[name]);
    });
    return this;
  }

  syncFunction<Result>(name: string, body: ExpoFunction0<Result>): ExpoModuleDefinition;
  syncFunction<Body extends ExpoSyncFunctionBody>(name: string, body: ExpoFunctionSpec<Body>): ExpoModuleDefinition;
  syncFunction(name: string, body: ExpoSyncFunction): ExpoModuleDefinition {
    this.registerFunction(name, functionArity(body), false, body, undefined);
    return this;
  }

  asyncFunction<Result>(name: string, body: ExpoFunction0<Promise<Result>>): ExpoModuleDefinition;
  asyncFunction<Body extends ExpoAsyncFunctionBody>(name: string, body: ExpoFunctionSpec<Body>): ExpoModuleDefinition;
  asyncFunction(name: string, body: ExpoAsyncFunction): ExpoModuleDefinition {
    this.registerFunction(name, functionArity(body), true, undefined, body);
    return this;
  }

  property<Value>(name: string, getter: ExpoFunction0<Value>): ExpoModuleDefinition;
  property<Value>(name: string, type: ExpoValueType<Value>, getter: ExpoFunction0<Value>, setter?: ExpoFunction1<Value, void>): ExpoModuleDefinition;
  property<Value>(
    name: string,
    typeOrGetter: ExpoValueType<Value> | ExpoFunction0<Value>,
    getterOrSetter?: ExpoFunction0<Value> | ExpoFunction1<Value, void>,
    maybeSetter?: ExpoFunction1<Value, void>,
  ): ExpoModuleDefinition {
    requireMemberName(name, 'property');
    this.requireAvailableModuleMember(name);

    let type: ExpoValueType<Value> | undefined = undefined;
    let getter: ExpoFunction0<Value>;
    let setter: ExpoFunction1<Value, void> | undefined = undefined;

    if (typeOrGetter instanceof ExpoValueType) {
      type = typeOrGetter;
      getter = getterOrSetter as ExpoFunction0<Value>;
      setter = maybeSetter;
    } else {
      getter = typeOrGetter;
      setter = getterOrSetter as ExpoFunction1<Value, void> | undefined;
    }

    let bridgeSetter: ExpoModulePropertySetter | undefined = undefined;

    if (setter !== undefined) {
      const propertySetter: ExpoFunction1<Value, void> = setter;
      bridgeSetter = (value: ESObject): void =>
        propertySetter(ExpoValueConverter.fromBridge<Value>(value, type, `Expo module property '${this.requireName()}.${name}'`));
    }

    this.propertyValues.set(name, {
      descriptor: { name, writable: setter !== undefined },
      getter: (): ESObject | void => ExpoValueConverter.toBridge(getter(), type, `Expo module property '${this.requireName()}.${name}'`),
      setter: bridgeSetter,
    });

    return this;
  }

  events(names: string[]): ExpoModuleDefinition {
    names.forEach((name: string): void => {
      requireMemberName(name, 'event');
      this.eventNames.add(name);
    });
    return this;
  }

  /** Declares an event whose outbound payload is validated and encoded by Core. */
  event<Payload>(name: string, payloadType: ExpoValueType<Payload>): ExpoModuleDefinition {
    requireMemberName(name, 'event');
    if (this.eventPayloadTypes.has(name)) {
      throw new Error(`Expo module event '${name}' already has a payload type.`);
    }
    this.eventNames.add(name);
    this.eventPayloadTypes.set(name, payloadType as ExpoValueType<ESObject>);
    return this;
  }

  sharedObjectClass<ObjectType extends ExpoSharedObject>(definition: ExpoSharedObjectClassDefinition<ObjectType>): ExpoModuleDefinition {
    const name: string = definition.name();

    this.requireAvailableModuleMember(name);

    this.classNames.add(name);
    this.classValues.push(definition);

    return this;
  }

  view<ViewType extends ExpoView>(definition: ExpoViewDefinition<ViewType>): ExpoModuleDefinition {
    if (this.viewNames.has(definition.name)) {
      throw new Error(`Expo module view '${definition.name}' was defined more than once.`);
    }
    this.viewNames.add(definition.name);
    this.viewValues.push(definition);
    return this;
  }

  onCreate(body: ExpoModuleLifecycleBody): ExpoModuleDefinition {
    this.createBody = body;
    return this;
  }

  onDestroy(body: ExpoModuleLifecycleBody): ExpoModuleDefinition {
    this.destroyBody = body;
    return this;
  }

  onForeground(body: ExpoModuleLifecycleBody): ExpoModuleDefinition {
    this.foregroundBody = body;
    return this;
  }

  onBackground(body: ExpoModuleLifecycleBody): ExpoModuleDefinition {
    this.backgroundBody = body;
    return this;
  }

  /** Called once per RuntimeContext epoch when this RN surface first appears. */
  onContentAppeared(body: ExpoModuleLifecycleBody): ExpoModuleDefinition {
    this.contentAppearedBody = body;
    return this;
  }

  /** Called after RNOH finishes evaluating the JavaScript bundle. */
  onJavaScriptBundleLoaded(body: ExpoModuleJavaScriptBundleLoadedBody): ExpoModuleDefinition {
    this.javaScriptBundleLoadedBody = body;
    return this;
  }

  /** Awaited by the Core reload API before the current RN instance reloads. */
  onPrepareForReload(body: ExpoModuleAsyncLifecycleBody): ExpoModuleDefinition {
    this.prepareForReloadBody = body;
    return this;
  }

  onAbilityDestroy(body: ExpoModuleLifecycleBody): ExpoModuleDefinition {
    this.abilityDestroyBody = body;
    return this;
  }

  /** Reserved for a future exact Harmony user-leave signal. */
  onUserLeaves(_body: ExpoModuleLifecycleBody): ExpoModuleDefinition {
    throw new ExpoModuleError(
      'ERR_UNSUPPORTED_LIFECYCLE_EVENT',
      'HarmonyOS does not expose an exact equivalent of Android onUserLeaveHint. ' + 'onUserLeaves cannot be registered.',
    );
  }

  onNewWant(body: ExpoModuleNewWantBody): ExpoModuleDefinition {
    this.newWantBody = body;
    return this;
  }

  onActivityResult(body: ExpoModuleAbilityResultBody): ExpoModuleDefinition {
    this.activityResultBody = body;
    return this;
  }

  onMemoryLevel(body: ExpoModuleMemoryLevelBody): ExpoModuleDefinition {
    this.memoryLevelBody = body;
    return this;
  }

  onWindowStageSetup(body: ExpoModuleWindowStageBody): ExpoModuleDefinition {
    this.windowStageSetupBody = body;
    return this;
  }

  onWindowStageWillDestroy(body: ExpoModuleLifecycleBody): ExpoModuleDefinition {
    this.windowStageWillDestroyBody = body;
    return this;
  }

  onStartObserving(body: ExpoModuleObservationBody): ExpoModuleDefinition;
  onStartObserving(eventName: string, body: ExpoModuleLifecycleBody): ExpoModuleDefinition;
  onStartObserving(bodyOrEventName: ExpoModuleObservationBody | string, eventBody?: ExpoModuleLifecycleBody): ExpoModuleDefinition {
    if (typeof bodyOrEventName !== 'string') {
      this.startObservingBodies.push(bodyOrEventName);
      return this;
    }
    this.registerObservationBody(this.startObservingByEvent, 'onStartObserving', bodyOrEventName, eventBody);
    return this;
  }

  onStopObserving(body: ExpoModuleObservationBody): ExpoModuleDefinition;
  onStopObserving(eventName: string, body: ExpoModuleLifecycleBody): ExpoModuleDefinition;
  onStopObserving(bodyOrEventName: ExpoModuleObservationBody | string, eventBody?: ExpoModuleLifecycleBody): ExpoModuleDefinition {
    if (typeof bodyOrEventName !== 'string') {
      this.stopObservingBodies.push(bodyOrEventName);
      return this;
    }
    this.registerObservationBody(this.stopObservingByEvent, 'onStopObserving', bodyOrEventName, eventBody);
    return this;
  }

  /** @internal Returns metadata only; implementation bodies never leave ArkTS. */
  descriptor(): ExpoModuleDescriptor {
    const name = this.requireName();
    const constants: ExpoModuleConstantDescriptor[] = [];

    this.constantValues.forEach((constant: ExpoModuleConstantRegistration): void => {
      constants.push({ name: constant.name });
    });

    const functions: ExpoModuleFunctionDescriptor[] = [];

    this.functionValues.forEach((registration: ExpoModuleFunctionRegistration): void => {
      functions.push(registration.descriptor);
    });

    const properties: ExpoModulePropertyDescriptor[] = [];

    this.propertyValues.forEach((registration: ExpoModulePropertyRegistration): void => {
      properties.push(registration.descriptor);
    });

    const classes = this.classValues.map((definition: ExpoSharedObjectClassRuntime): ExpoSharedObjectClassDescriptor => definition.descriptor());
    const views = this.viewValues.map((definition: ExpoViewDefinitionRuntime): ExpoViewDescriptor => definition.descriptor());

    return {
      name,
      constants,
      functions,
      properties,
      events: Array.from(this.eventNames),
      classes,
      views,
    };
  }

  /** @internal */
  bindModuleContext(context: ExpoModuleContext, sharedObjects: ExpoSharedObjectRegistry): (() => void)[] {
    const moduleName = this.requireName();

    this.classValues.forEach((definition: ExpoSharedObjectClassRuntime): void => {
      definition.bindModule(context, moduleName, sharedObjects);
      sharedObjects.registerClass(moduleName, definition);
    });

    const disposers: (() => void)[] = [];
    try {
      this.viewValues.forEach((definition: ExpoViewDefinitionRuntime, index: number): void => {
        disposers.push(definition.bindModule(moduleName, index === 0, context.runtimeId, context.runtimeEpochValue()));
      });

      return disposers;
    } catch (error) {
      disposeViewRegistrations(disposers);

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      if (error instanceof Error) {
        throw new Error(error.message);
      }
      throw new Error(errorMessage(error));
    }
  }

  /** @internal */
  eventNamesValue(): string[] {
    return Array.from(this.eventNames);
  }

  /** @internal Tokens remain in ArkTS and are never emitted into descriptors or generated glue. */
  eventPayloadTypesValue(): Map<string, ExpoValueType<ESObject>> {
    return new Map<string, ExpoValueType<ESObject>>(this.eventPayloadTypes);
  }

  /** @internal */
  moduleNameValue(): string {
    return this.requireName();
  }

  /** @internal Invoked by the runtime-scoped registry. */
  getConstant(constantName: string): ESObject | void {
    const constant = this.constantValues.get(constantName);
    if (constant === undefined) {
      throw new ExpoModuleError('ERR_CONSTANT_NOT_FOUND', `Cannot find Expo module constant '${this.requireName()}.${constantName}'.`);
    }
    return constant.getter();
  }

  /** @internal Invoked by the runtime-scoped registry. */
  invokeSync(functionName: string, args: ESObject[]): ESObject | void {
    const registration = this.requireFunction(functionName, false, args.length);
    const body = registration.syncBody;

    if (body === undefined) {
      throw new Error(`Expo module sync function '${this.requireName()}.${functionName}' has no implementation.`);
    }

    return invokeSyncFunction(body, args, `Expo module '${this.requireName()}.${functionName}'`);
  }

  /** @internal Invoked by the runtime-scoped registry. */
  async invokeAsync(functionName: string, args: ESObject[]): Promise<ESObject | void> {
    const registration = this.requireFunction(functionName, true, args.length);
    const body = registration.asyncBody;

    if (body === undefined) {
      throw new Error(`Expo module async function '${this.requireName()}.${functionName}' has no implementation.`);
    }

    return await invokeAsyncFunction(body, args, `Expo module '${this.requireName()}.${functionName}'`);
  }

  /** @internal Invoked by the Host property adapter. */
  getProperty(propertyName: string): ESObject | void {
    return this.requireProperty(propertyName).getter();
  }

  /** @internal Invoked by the Host property adapter. */
  setProperty(propertyName: string, value: ESObject): void {
    const property = this.requireProperty(propertyName);

    if (property.setter === undefined) {
      throw new Error(`Expo module property '${this.requireName()}.${propertyName}' is read-only.`);
    }

    property.setter(value);
  }

  /** @internal */
  dispatchLifecycle(eventName: string, payload?: ESObject): void {
    if (eventName === EXPO_LIFECYCLE_FOREGROUND) {
      this.foregroundBody?.();
    } else if (eventName === EXPO_LIFECYCLE_BACKGROUND) {
      this.backgroundBody?.();
    } else if (eventName === EXPO_LIFECYCLE_CONTENT_APPEARED) {
      this.contentAppearedBody?.();
    } else if (eventName === EXPO_LIFECYCLE_JAVASCRIPT_BUNDLE_LOADED) {
      this.javaScriptBundleLoadedBody?.(typeof payload === 'number' ? payload : undefined);
    } else if (eventName === EXPO_LIFECYCLE_ACTIVITY_DESTROY) {
      this.abilityDestroyBody?.();
    } else if (eventName === EXPO_LIFECYCLE_NEW_INTENT && payload !== undefined) {
      this.newWantBody?.(payload as Want);
    } else if (eventName === EXPO_LIFECYCLE_ACTIVITY_RESULT && payload !== undefined) {
      this.activityResultBody?.(payload as ExpoModuleAbilityResult);
    } else if (eventName === EXPO_LIFECYCLE_MEMORY_LEVEL && payload !== undefined) {
      this.memoryLevelBody?.(payload as AbilityConstant.MemoryLevel);
    } else if (eventName === EXPO_LIFECYCLE_WINDOW_STAGE_SETUP && payload !== undefined) {
      this.windowStageSetupBody?.(payload as window.WindowStage);
    } else if (eventName === EXPO_LIFECYCLE_WINDOW_STAGE_WILL_DESTROY) {
      this.windowStageWillDestroyBody?.();
    } else if (eventName === EXPO_LIFECYCLE_DESTROY) {
      this.destroyBody?.();
    }
  }

  /** @internal EventEmitter calls this only for an individual 0 -> 1 transition. */
  setObserving(eventName: string, observing: boolean): void {
    if (!this.eventNames.has(eventName)) {
      throw new ExpoModuleError('ERR_UNDECLARED_EVENT', `Expo module '${this.requireName()}' did not declare event '${eventName}'.`);
    }
    if (observing) {
      this.startObservingBodies.forEach((body: ExpoModuleObservationBody): void => body(eventName));
      this.startObservingByEvent.get(eventName)?.forEach((body: ExpoModuleLifecycleBody): void => body());
      return;
    }
    this.stopObservingByEvent.get(eventName)?.forEach((body: ExpoModuleLifecycleBody): void => body());
    this.stopObservingBodies.forEach((body: ExpoModuleObservationBody): void => body(eventName));
  }

  /** @internal */
  notifyCreated(): void {
    this.createBody?.();
  }

  /** @internal Awaited before an explicit Core-driven runtime reload. */
  async prepareForReload(): Promise<void> {
    if (this.prepareForReloadBody !== undefined) {
      await this.prepareForReloadBody();
    }
  }

  private registerFunction(
    name: string,
    arity: ExpoFunctionArityRange,
    async: boolean,
    syncBody?: ExpoSyncFunction,
    asyncBody?: ExpoAsyncFunction,
  ): void {
    requireMemberName(name, 'function');
    this.requireAvailableModuleMember(name);
    const writableArguments: number[] = writableFunctionArguments(async ? asyncBody : syncBody);
    if (async && writableArguments.length > 0) {
      throw new ExpoModuleError('ERR_WRITABLE_ARGUMENT', 'Writable arguments are supported only by synchronous module functions.');
    }
    this.functionValues.set(name, {
      descriptor: { name, arity: arity.maximum, requiredArity: arity.required, async, writableArguments },
      syncBody,
      asyncBody,
    });
  }

  private requireName(): string {
    if (this.moduleName === undefined) {
      throw new Error('ExpoModuleDefinition.name(...) is required.');
    }
    return this.moduleName;
  }

  private requireAvailableModuleMember(name: string): void {
    if (this.constantValues.has(name) || this.functionValues.has(name) || this.propertyValues.has(name) || this.classNames.has(name)) {
      throw new ExpoModuleError('ERR_MODULE_MEMBER_CONFLICT', `Expo module member '${name}' was defined more than once.`);
    }
  }

  /** @internal Applies the module class simple name only when no explicit Name was declared. */
  applyNameFallback(moduleClassName: string): void {
    if (this.moduleName !== undefined) return;
    requireMemberName(moduleClassName, 'class');
    this.moduleName = moduleClassName;
  }

  private requireFunction(functionName: string, async: boolean, receivedArity: number): ExpoModuleFunctionRegistration {
    const registration = this.functionValues.get(functionName);

    if (registration === undefined || registration.descriptor.async !== async) {
      throw new Error(`Expo module '${this.requireName()}' does not expose ${async ? 'async' : 'sync'} function '${functionName}'.`);
    }

    requireArity(
      `Expo module function '${this.requireName()}.${functionName}'`,
      registration.descriptor.requiredArity,
      registration.descriptor.arity,
      receivedArity,
    );

    return registration;
  }

  private requireProperty(propertyName: string): ExpoModulePropertyRegistration {
    const property = this.propertyValues.get(propertyName);
    if (property === undefined) {
      throw new Error(`Expo module '${this.requireName()}' does not expose property '${propertyName}'.`);
    }
    return property;
  }

  private registerObservationBody(
    registrations: Map<string, ExpoModuleLifecycleBody[]>,
    hookName: string,
    eventName: string,
    body?: ExpoModuleLifecycleBody,
  ): void {
    requireMemberName(eventName, 'event');
    if (body === undefined) {
      throw new Error(`Expo module ${hookName}('${eventName}', ...) requires a callback.`);
    }
    let bodies = registrations.get(eventName);
    if (bodies === undefined) {
      bodies = [];
      registrations.set(eventName, bodies);
    }
    bodies.push(body);
  }
}

function requireArity(path: string, required: number, maximum: number, received: number): void {
  if (received >= required && received <= maximum) return;
  const expectation: string = required === maximum ? `${required}` : `${required} to ${maximum}`;
  throw new ExpoModuleError('ERR_INVALID_ARGS_NUMBER', `${path} expected ${expectation} arguments, received ${received}.`);
}

class ScopedExpoModule {
  readonly registrationId: string;
  readonly module: ExpoModule;
  readonly definition: ExpoModuleDefinition;
  readonly descriptor: ExpoModuleDescriptor;
  readonly viewDisposers: (() => void)[];
  created: boolean = false;

  constructor(
    registrationId: string,
    module: ExpoModule,
    definition: ExpoModuleDefinition,
    descriptor: ExpoModuleDescriptor,
    viewDisposers: (() => void)[],
  ) {
    this.registrationId = registrationId;
    this.module = module;
    this.definition = definition;
    this.descriptor = descriptor;
    this.viewDisposers = viewDisposers;
  }
}

/** Module instances and SharedObject state for one RuntimeContext epoch. */
class ExpoModulesRuntimeScope implements ExpoLifecycleSink {
  private readonly runtimeEpoch: string;
  private readonly runtimeId: number;
  private readonly modules: Map<string, ScopedExpoModule> = new Map<string, ScopedExpoModule>();
  private readonly order: ScopedExpoModule[] = [];
  readonly sharedObjects: ExpoSharedObjectRegistry;
  private valid: boolean = true;

  constructor(
    coreContext: UITurboModuleContext,
    runtimeEpoch: string,
    registrations: ExpoResolvedModuleRegistration[],
    typedEvents: ExpoTypedEventQueue,
    hostId: string,
    hostRuntimeGeneration: number,
    dispatchRuntimeLifecycle: ExpoRuntimeLifecycleDispatcher,
    reloadRuntime: ExpoRuntimeReload,
    initialWant?: Want,
  ) {
    this.runtimeEpoch = runtimeEpoch;
    this.runtimeId = coreContext.rnInstance.getId();
    this.sharedObjects = new ExpoSharedObjectRegistry(runtimeEpoch);

    try {
      registrations.forEach((registration: ExpoResolvedModuleRegistration): void => {
        const registrationId = registration.registrationId;
        const context = new ExpoModuleContext(
          coreContext,
          runtimeEpoch,
          hostId,
          hostRuntimeGeneration,
          dispatchRuntimeLifecycle,
          reloadRuntime,
          initialWant,
        );
        let viewDisposers: (() => void)[] = [];
        let registrationPhase: string = 'constructing the module';

        try {
          const module = registration.factory(context);
          registrationPhase = 'evaluating the module definition';
          const definition = module.definition();

          registrationPhase = 'resolving the module name';
          definition.applyNameFallback(registration.moduleClassName);
          const moduleName = definition.moduleNameValue();
          if (this.modules.has(moduleName)) {
            throw new Error(`Expo module '${moduleName}' was registered more than once.`);
          }

          registrationPhase = 'binding the module context';
          context.bindModule(
            moduleName,
            definition.eventNamesValue(),
            definition.eventPayloadTypesValue(),
            this.sharedObjects,
            typedEvents,
            (name: string): ExpoModule | undefined => this.modules.get(name)?.module,
          );
          registrationPhase = 'binding shared objects and views';
          viewDisposers = definition.bindModuleContext(context, this.sharedObjects);

          registrationPhase = 'creating the module descriptor';
          const descriptor = definition.descriptor();
          const scopedModule = new ScopedExpoModule(registrationId, module, definition, descriptor, viewDisposers);
          this.modules.set(descriptor.name, scopedModule);
          this.order.push(scopedModule);
        } catch (error) {
          disposeViewRegistrations(viewDisposers);
          context.invalidate();

          if (error instanceof ExpoModuleError) {
            throw new ExpoModuleError(
              error.code,
              `Unable to register Expo module '${registrationId}' while ${registrationPhase}: ${error.message}`,
              error.cause,
              error.path,
            );
          }
          if (error instanceof Error) {
            throw new Error(`Unable to register Expo module '${registrationId}' while ${registrationPhase}: ${error.message}`);
          }
          throw new Error(`Unable to register Expo module '${registrationId}' while ${registrationPhase}: ${errorMessage(error)}`);
        }
      });

      this.order.forEach((entry: ScopedExpoModule): void => {
        try {
          entry.definition.notifyCreated();
          entry.created = true;
        } catch (error) {
          throw new Error(`Unable to create Expo module '${entry.registrationId}': ${errorMessage(error)}`);
        }
      });
    } catch (error) {
      this.invalidate();

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      if (error instanceof Error) {
        throw new Error(error.message);
      }
      throw new Error(errorMessage(error));
    }
  }

  descriptors(): ExpoModuleDescriptor[] {
    this.assertValid();
    return this.order.map((entry: ScopedExpoModule): ExpoModuleDescriptor => {
      const descriptor = entry.descriptor;
      const classes: ExpoSharedObjectClassDescriptor[] = descriptor.classes.map(
        (classDescriptor: ExpoSharedObjectClassDescriptor): ExpoSharedObjectClassDescriptor => {
          return {
            name: classDescriptor.name,
            baseClassName: classDescriptor.baseClassName,
            nativeRefType: this.sharedObjects.resolveNativeRefType(descriptor.name, classDescriptor.name),
            constructible: classDescriptor.constructible,
            constructorArity: classDescriptor.constructorArity,
            constructorRequiredArity: classDescriptor.constructorRequiredArity,
            constants: classDescriptor.constants,
            functions: classDescriptor.functions,
            staticFunctions: classDescriptor.staticFunctions,
            properties: classDescriptor.properties,
            events: classDescriptor.events,
          };
        },
      );
      return {
        name: descriptor.name,
        constants: descriptor.constants,
        functions: descriptor.functions,
        properties: descriptor.properties,
        events: descriptor.events,
        classes,
        views: descriptor.views,
      };
    });
  }

  getConstant(moduleName: string, constantName: string): ESObject {
    const result: ESObject | void = this.requireModule(moduleName).definition.getConstant(constantName);

    return this.sharedObjects.encodeResult(result);
  }

  getSharedObjectConstant(moduleName: string, className: string, constantName: string): ESObject {
    return this.sharedObjects.getConstant(moduleName, className, constantName);
  }

  invokeSync(moduleName: string, functionName: string, args: ESObject[]): ESObject {
    const decoded: ESObject[] = this.sharedObjects.decodeArguments(args);
    const result: ESObject | void = this.requireModule(moduleName).definition.invokeSync(functionName, decoded);

    return this.sharedObjects.encodeResult(result);
  }

  async invokeAsync(moduleName: string, functionName: string, args: ESObject[]): Promise<ESObject> {
    const decoded: ESObject[] = this.sharedObjects.decodeArguments(args);
    const result: ESObject | void = await this.requireModule(moduleName).definition.invokeAsync(functionName, decoded);

    this.assertValid();

    return this.sharedObjects.encodeResult(result);
  }

  getProperty(moduleName: string, propertyName: string): ESObject {
    const result: ESObject | void = this.requireModule(moduleName).definition.getProperty(propertyName);

    return this.sharedObjects.encodeResult(result);
  }

  setProperty(moduleName: string, propertyName: string, value: ESObject): void {
    const decoded: ESObject = this.sharedObjects.decodeArguments([value])[0];

    this.requireModule(moduleName).definition.setProperty(propertyName, decoded);
  }

  async invokeViewAsync(tag: number, componentName: string, propsRevision: number, functionName: string, args: ESObject[]): Promise<ESObject> {
    this.assertValid();

    const decoded: ESObject[] = this.sharedObjects.decodeArguments(args);
    const result: ESObject | void = await ExpoViewAdapterRegistry.invokeAsync(
      this.runtimeId,
      this.runtimeEpoch,
      tag,
      componentName,
      propsRevision,
      functionName,
      decoded,
    );

    this.assertValid();

    return this.sharedObjects.encodeResult(result);
  }

  dispatchLifecycle(eventName: string, payload?: ESObject): void {
    this.assertValid();

    this.order.forEach((entry: ScopedExpoModule): void => {
      try {
        entry.definition.dispatchLifecycle(eventName, payload);
      } catch (error) {
        reportModuleLifecycleFailure(entry.descriptor.name, eventName, error);
      }
    });
  }

  postLifecycleEvent(eventName: string, payload?: ESObject): void {
    this.dispatchLifecycle(eventName, payload);
  }

  async prepareForReload(): Promise<void> {
    this.assertValid();

    for (let index = 0; index < this.order.length; index += 1) {
      const entry = this.order[index];
      if (!entry.created) continue;
      try {
        await entry.definition.prepareForReload();
      } catch (error) {
        if (error instanceof ExpoModuleError) {
          throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
        }
        if (error instanceof Error) {
          throw new Error(error.message);
        }
        throw new Error(errorMessage(error));
      }
    }
  }

  setObserving(moduleName: string, eventName: string, observing: boolean): void {
    this.requireModule(moduleName).definition.setObserving(eventName, observing);
  }

  invalidate(): void {
    if (!this.valid) return;

    // Close the public gate before author cleanup.
    this.valid = false;

    this.order.forEach((entry: ScopedExpoModule): void => {
      entry.module.context.beginInvalidation();
    });

    ExpoViewAdapterRegistry.destroyRuntime(this.runtimeId, this.runtimeEpoch);

    for (let index = this.order.length - 1; index >= 0; --index) {
      const entry = this.order[index];
      if (entry.created) {
        try {
          entry.definition.dispatchLifecycle(EXPO_LIFECYCLE_DESTROY);
        } catch (error) {
          reportModuleLifecycleFailure(entry.descriptor.name, 'onDestroy', error);
        }
      }
    }
    // Release SharedObjects while their AppContext is still live.
    this.sharedObjects.invalidate();

    for (let index = this.order.length - 1; index >= 0; --index) {
      const entry = this.order[index];
      entry.module.context.invalidate();
      disposeViewRegistrations(entry.viewDisposers);
    }

    this.modules.clear();
    this.order.length = 0;
  }

  private requireModule(name: string): ScopedExpoModule {
    this.assertValid();
    const module = this.modules.get(name);
    if (module === undefined) throw new Error(`Cannot find ArkTS Expo module '${name}'.`);
    return module;
  }

  private assertValid(): void {
    if (!this.valid) throw new Error(`The ArkTS Expo module scope '${this.runtimeEpoch}' was invalidated.`);
  }
}

/** Host-owned module factories and runtime-scoped instances. */
export class ExpoModulesRegistry {
  private readonly coreContext: UITurboModuleContext;
  private readonly typedEvents: ExpoTypedEventQueue;
  private readonly registrations: ExpoResolvedModuleRegistration[];
  private readonly initialWant?: Want;
  private readonly hostId: string;
  private readonly hostRuntimeGeneration: number;
  private readonly pendingLifecycle: ExpoLifecycleEventQueue = new ExpoLifecycleEventQueue();
  private readonly scopes: Map<string, ExpoModulesRuntimeScope> = new Map<string, ExpoModulesRuntimeScope>();
  private reloadHost?: ExpoRuntimeReload = undefined;
  private reloadInProgress: boolean = false;
  private abilityDestroyed: boolean = false;
  private valid: boolean = true;

  private constructor(
    coreContext: UITurboModuleContext,
    registrations: ExpoModuleRegistration[],
    initialWant: Want | undefined,
    hostId: string,
    hostRuntimeGeneration: number,
  ) {
    this.coreContext = coreContext;
    this.typedEvents = new ExpoTypedEventQueue(coreContext);
    this.initialWant = initialWant;
    this.hostId = hostId;
    this.hostRuntimeGeneration = hostRuntimeGeneration;

    const identifiers: Set<string> = new Set<string>();

    this.registrations = registrations.map((registration: ExpoModuleRegistration): ExpoResolvedModuleRegistration => {
      if (registration.registrationId.length === 0) {
        throw new Error('Expo module registration IDs cannot be empty.');
      }
      if (registration.moduleClassName.length === 0) {
        throw new Error('Expo module class names cannot be empty.');
      }
      if (identifiers.has(registration.registrationId)) {
        throw new Error(`Expo module registration '${registration.registrationId}' was registered more than once.`);
      }

      identifiers.add(registration.registrationId);

      return {
        registrationId: registration.registrationId,
        moduleClassName: registration.moduleClassName,
        factory: registration.factory,
      };
    });
  }

  /** @internal Creates fresh module instances for one UITurboModuleContext. */
  static createScope(
    coreContext: UITurboModuleContext,
    registrations: ExpoModuleRegistration[],
    initialWant: Want | undefined,
    hostId: string,
    hostRuntimeGeneration: number,
  ): ExpoModulesRegistry {
    return new ExpoModulesRegistry(coreContext, registrations, initialWant, hostId, hostRuntimeGeneration);
  }

  /** @internal Binds the owning TurboModule's cleanup-aware reload operation. */
  configureReloadHost(reloadHost: ExpoRuntimeReload): void {
    this.assertValid();

    if (this.reloadHost !== undefined) {
      throw new Error('The Expo modules Host reload operation was configured more than once.');
    }

    this.reloadHost = reloadHost;
  }

  bindRuntime(runtimeEpoch: string): void {
    this.assertValid();
    requireRuntimeEpoch(runtimeEpoch);

    if (this.scopes.has(runtimeEpoch)) return;

    if (this.abilityDestroyed) {
      throw new ExpoModuleError('ERR_ABILITY_DESTROYED', `Cannot bind runtime '${runtimeEpoch}' after its UIAbility was destroyed.`);
    }

    const scope = new ExpoModulesRuntimeScope(
      this.coreContext,
      runtimeEpoch,
      this.registrations,
      this.typedEvents,
      this.hostId,
      this.hostRuntimeGeneration,
      (eventName: string, payload?: ESObject): void => {
        this.dispatchLifecycleForRuntime(runtimeEpoch, eventName, payload);
      },
      async (reason: string): Promise<void> => await this.reloadAppAsync(reason),
      this.initialWant,
    );

    this.scopes.set(runtimeEpoch, scope);
    this.pendingLifecycle.drain(scope);
  }

  descriptors(runtimeEpoch: string): ExpoModuleDescriptor[] {
    this.assertValid();
    return this.requireScope(runtimeEpoch).descriptors();
  }

  getConstant(runtimeEpoch: string, moduleName: string, constantName: string): ESObject {
    return this.requireScope(runtimeEpoch).getConstant(moduleName, constantName);
  }

  getSharedObjectConstant(runtimeEpoch: string, moduleName: string, className: string, constantName: string): ESObject {
    return this.requireScope(runtimeEpoch).getSharedObjectConstant(moduleName, className, constantName);
  }

  invokeSync(runtimeEpoch: string, moduleName: string, functionName: string, args: ESObject[]): ESObject {
    return this.requireScope(runtimeEpoch).invokeSync(moduleName, functionName, args);
  }

  async invokeAsync(runtimeEpoch: string, moduleName: string, functionName: string, args: ESObject[]): Promise<ESObject> {
    return await this.requireScope(runtimeEpoch).invokeAsync(moduleName, functionName, args);
  }

  getProperty(runtimeEpoch: string, moduleName: string, propertyName: string): ESObject {
    return this.requireScope(runtimeEpoch).getProperty(moduleName, propertyName);
  }

  setProperty(runtimeEpoch: string, moduleName: string, propertyName: string, value: ESObject): void {
    this.requireScope(runtimeEpoch).setProperty(moduleName, propertyName, value);
  }

  async invokeViewAsync(
    runtimeEpoch: string,
    tag: number,
    componentName: string,
    propsRevision: number,
    functionName: string,
    args: ESObject[],
  ): Promise<ESObject> {
    return await this.requireScope(runtimeEpoch).invokeViewAsync(tag, componentName, propsRevision, functionName, args);
  }

  dispatchLifecycle(eventName: string, payload?: ESObject): boolean {
    this.assertValid();

    if (this.abilityDestroyed) return false;

    if (eventName === EXPO_LIFECYCLE_ACTIVITY_DESTROY) {
      this.abilityDestroyed = true;
      this.pendingLifecycle.clear();
    }

    if (this.scopes.size === 0) {
      if (!this.abilityDestroyed) this.pendingLifecycle.enqueue(eventName, payload);
      return true;
    }

    this.scopes.forEach((scope: ExpoModulesRuntimeScope): void => {
      scope.dispatchLifecycle(eventName, payload);
    });

    return true;
  }

  /** @internal Dispatches a Host event only to its owning RuntimeContext. */
  dispatchLifecycleForRuntime(runtimeEpoch: string, eventName: string, payload?: ESObject): void {
    this.assertValid();

    if (this.abilityDestroyed) return;

    const scope: ExpoModulesRuntimeScope | undefined = this.scopes.get(runtimeEpoch);

    if (scope === undefined) return;

    scope.dispatchLifecycle(eventName, payload);
  }

  async prepareForReload(): Promise<void> {
    this.assertValid();

    const scopes = Array.from(this.scopes.values());

    for (let index = 0; index < scopes.length; index += 1) {
      await scopes[index].prepareForReload();
    }
  }

  /** @internal Shared implementation for JS Core and ArkTS AppContext reloads. */
  async reloadAppAsync(reason: string): Promise<void> {
    this.assertValid();
    const reloadHost: ExpoRuntimeReload | undefined = this.reloadHost;
    if (reloadHost === undefined) {
      throw new ExpoModuleError('ERR_RELOAD_UNAVAILABLE', 'The Expo modules Host does not provide a reload operation.');
    }
    if (this.reloadInProgress) {
      throw new ExpoModuleError('ERR_RELOAD_IN_PROGRESS', 'An Expo modules Host reload is already in progress.');
    }

    this.reloadInProgress = true;
    try {
      await this.prepareForReload();

      this.assertValid();
      await reloadHost(reason);
    } catch (error) {
      if (this.valid) this.reloadInProgress = false;

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      if (error instanceof Error) {
        throw new Error(error.message);
      }
      throw new Error(errorMessage(error));
    }
  }

  setObserving(runtimeEpoch: string, moduleName: string, eventName: string, observing: boolean): void {
    this.requireScope(runtimeEpoch).setObserving(moduleName, eventName, observing);
  }

  constructSharedObject(
    runtimeEpoch: string,
    objectId: number,
    moduleName: string,
    className: string,
    nativeRefType: string,
    args: ESObject[],
  ): void {
    this.requireScope(runtimeEpoch).sharedObjects.construct(objectId, moduleName, className, nativeRefType, args);
  }

  bindSharedObject(runtimeEpoch: string, authorId: number, objectId: number, moduleName: string, className: string, nativeRefType: string): number {
    return this.requireScope(runtimeEpoch).sharedObjects.bindStaged(authorId, objectId, moduleName, className, nativeRefType);
  }

  discardSharedObjects(runtimeEpoch: string, authorIds: number[]): void {
    const scope = this.scopes.get(runtimeEpoch);
    if (scope !== undefined) scope.sharedObjects.discardStaged(authorIds);
  }

  invokeSharedObjectSync(
    runtimeEpoch: string,
    objectId: number,
    moduleName: string,
    className: string,
    functionName: string,
    args: ESObject[],
  ): ESObject {
    return this.requireScope(runtimeEpoch).sharedObjects.invokeSync(objectId, moduleName, className, functionName, args);
  }

  async invokeSharedObjectAsync(
    runtimeEpoch: string,
    objectId: number,
    moduleName: string,
    className: string,
    functionName: string,
    args: ESObject[],
  ): Promise<ESObject> {
    return await this.requireScope(runtimeEpoch).sharedObjects.invokeAsync(objectId, moduleName, className, functionName, args);
  }

  invokeSharedObjectStaticSync(runtimeEpoch: string, moduleName: string, className: string, functionName: string, args: ESObject[]): ESObject {
    return this.requireScope(runtimeEpoch).sharedObjects.invokeStaticSync(moduleName, className, functionName, args);
  }

  async invokeSharedObjectStaticAsync(
    runtimeEpoch: string,
    moduleName: string,
    className: string,
    functionName: string,
    args: ESObject[],
  ): Promise<ESObject> {
    return await this.requireScope(runtimeEpoch).sharedObjects.invokeStaticAsync(moduleName, className, functionName, args);
  }

  getSharedObjectProperty(runtimeEpoch: string, objectId: number, moduleName: string, className: string, propertyName: string): ESObject {
    return this.requireScope(runtimeEpoch).sharedObjects.getProperty(objectId, moduleName, className, propertyName);
  }

  setSharedObjectProperty(
    runtimeEpoch: string,
    objectId: number,
    moduleName: string,
    className: string,
    propertyName: string,
    value: ESObject,
  ): void {
    this.requireScope(runtimeEpoch).sharedObjects.setProperty(objectId, moduleName, className, propertyName, value);
  }

  setSharedObjectObserving(
    runtimeEpoch: string,
    objectId: number,
    moduleName: string,
    className: string,
    eventName: string,
    observing: boolean,
  ): void {
    this.requireScope(runtimeEpoch).sharedObjects.setObserving(objectId, moduleName, className, eventName, observing);
  }

  releaseSharedObject(runtimeEpoch: string, objectId: number): void {
    const scope = this.scopes.get(runtimeEpoch);
    if (scope !== undefined) scope.sharedObjects.release(objectId);
  }

  sharedObjectWillRelease(runtimeEpoch: string, objectId: number): void {
    const scope = this.scopes.get(runtimeEpoch);
    if (scope !== undefined) scope.sharedObjects.willRelease(objectId);
  }

  sharedObjectMemoryPressure(runtimeEpoch: string, objectId: number): number {
    return this.requireScope(runtimeEpoch).sharedObjects.memoryPressure(objectId);
  }

  /** @internal Consumed once by the C++ Host through the typed JSI/NAPI bridge. */
  takeTypedEventArguments(runtimeEpoch: string, transportId: number): ESObject[] {
    this.assertValid();
    this.requireScope(runtimeEpoch);
    return this.typedEvents.take(runtimeEpoch, transportId);
  }

  /** @internal Drops an event whose native receiver was already invalidated. */
  discardTypedEventArguments(runtimeEpoch: string, transportId: number): void {
    this.assertValid();
    const scope: ExpoModulesRuntimeScope = this.requireScope(runtimeEpoch);
    const args: ESObject[] = this.typedEvents.take(runtimeEpoch, transportId);
    scope.sharedObjects.discardEncodedArguments(args);
  }

  /** @internal Releases one independently retired RuntimeContext scope. */
  invalidateRuntime(runtimeEpoch: string): void {
    if (!this.valid) return;

    requireRuntimeEpoch(runtimeEpoch);

    const scope = this.scopes.get(runtimeEpoch);

    if (scope === undefined) return;

    this.discardTypedEventsForScope(runtimeEpoch, scope);
    scope.invalidate();

    this.scopes.delete(runtimeEpoch);
  }

  /** @internal Called only after the native destroy acknowledgement. */
  invalidate(): void {
    if (!this.valid) return;

    this.valid = false;

    this.scopes.forEach((scope: ExpoModulesRuntimeScope, runtimeEpoch: string): void => {
      this.discardTypedEventsForScope(runtimeEpoch, scope);
      scope.invalidate();
    });

    this.typedEvents.invalidate();
    this.scopes.clear();
    this.pendingLifecycle.clear();

    this.reloadHost = undefined;
    this.abilityDestroyed = true;
  }

  private requireScope(runtimeEpoch: string): ExpoModulesRuntimeScope {
    this.assertValid();
    requireRuntimeEpoch(runtimeEpoch);

    const scope = this.scopes.get(runtimeEpoch);

    if (scope === undefined) throw new Error(`Cannot find ArkTS Expo module runtime '${runtimeEpoch}'.`);

    return scope;
  }

  private discardTypedEventsForScope(runtimeEpoch: string, scope: ExpoModulesRuntimeScope): void {
    const batches: ESObject[][] = this.typedEvents.discardRuntime(runtimeEpoch);

    batches.forEach((args: ESObject[]): void => {
      try {
        scope.sharedObjects.discardEncodedArguments(args);
      } catch (error) {
        reportModuleLifecycleFailure('ExpoTypedEventQueue', 'discard', error);
      }
    });
  }

  private assertValid(): void {
    if (!this.valid) {
      throw new Error('The ArkTS Expo modules scope has been invalidated.');
    }
  }
}

function requireRuntimeEpoch(runtimeEpoch: string): void {
  if (runtimeEpoch.length === 0) throw new Error('Expo module runtime epoch cannot be empty.');
  for (let index = 0; index < runtimeEpoch.length; index += 1) {
    const code = runtimeEpoch.charCodeAt(index);
    if (code < 48 || code > 57 || (index === 0 && code === 48)) {
      throw new Error('Expo module runtime epoch must be a canonical positive decimal string.');
    }
  }
}

function requireMemberName(name: string, kind: string): void {
  if (name.length === 0) throw new Error(`Expo module ${kind} names cannot be empty.`);
}

function reportModuleLifecycleFailure(moduleName: string, eventName: string, error: Object): void {
  try {
    console.error(`Expo module '${moduleName}' failed during ${eventName}: ${String(error)}`);
  } catch (_) {}
}

function errorMessage(error: Object): string {
  try {
    return String(error);
  } catch (_) {
    return 'The ArkTS Expo module failed.';
  }
}

function disposeViewRegistrations(disposers: (() => void)[]): void {
  for (let index = disposers.length - 1; index >= 0; --index) {
    try {
      disposers[index]();
    } catch (error) {
      reportModuleLifecycleFailure('ExpoViewRegistry', 'dispose', error);
    }
  }

  disposers.length = 0;
}

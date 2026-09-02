import type { ExpoModuleContext } from './ExpoModule';
import {
  ExpoFunction0,
  ExpoFunction1,
  ExpoFunction2,
  ExpoFunction3,
  ExpoFunction4,
  ExpoFunction5,
  ExpoFunction6,
  ExpoFunction7,
  ExpoFunction8,
  ExpoFunction9,
  ExpoFunctionArityRange,
  ExpoFunctionSpec,
  ExpoOwnedAsyncFunction,
  ExpoOwnedAsyncFunctionBody,
  ExpoOwnedSyncFunction,
  ExpoOwnedSyncFunctionBody,
  ExpoValueConverter,
  ExpoValueType,
  invokeOwnedAsyncFunction,
  invokeOwnedSyncFunction,
  invokeOwnedSyncFunctionForAuthorObject,
  ownedFunctionArity,
} from './ExpoValueConverter';
import { ExpoModuleError } from './ExpoModuleError';
import { EXPO_SHARED_OBJECT_MARKER } from '../protocol/Protocol';
import { defineExpoRecordValue } from './ExpoRecord';

const MAX_COPY_VALUE_DEPTH: number = 64;
const MAX_SHARED_OBJECT_ID: number = Number.MAX_SAFE_INTEGER;

function isValidSharedObjectId(value: number): boolean {
  return Number.isSafeInteger(value) && value > 0 && value <= MAX_SHARED_OBJECT_ID;
}

export interface ExpoSharedObjectFunctionDescriptor {
  readonly name: string;
  readonly arity: number;
  readonly requiredArity: number;
  readonly async: boolean;
}

export interface ExpoSharedObjectPropertyDescriptor {
  readonly name: string;
  readonly writable: boolean;
}

export interface ExpoSharedObjectClassDescriptor {
  readonly name: string;
  readonly baseClassName: string;
  readonly nativeRefType: string;
  readonly constructible: boolean;
  readonly constructorArity: number;
  readonly constructorRequiredArity: number;
  readonly constants: ExpoSharedObjectConstantDescriptor[];
  readonly functions: ExpoSharedObjectFunctionDescriptor[];
  readonly staticFunctions: ExpoSharedObjectFunctionDescriptor[];
  readonly properties: ExpoSharedObjectPropertyDescriptor[];
  readonly events: string[];
}

export interface ExpoSharedObjectConstantDescriptor {
  readonly name: string;
}

type ExpoSharedObjectConstantGetter = () => ESObject | void;

interface ExpoSharedObjectConstantRegistration {
  readonly name: string;
  readonly getter: ExpoSharedObjectConstantGetter;
}

interface ExpoSharedObjectFunctionRegistration<ObjectType extends ExpoSharedObject> {
  readonly descriptor: ExpoSharedObjectFunctionDescriptor;
  readonly syncBody?: ExpoOwnedSyncFunction<ObjectType>;
  readonly asyncBody?: ExpoOwnedAsyncFunction<ObjectType>;
}

interface ExpoSharedObjectStaticFunctionRegistration {
  readonly descriptor: ExpoSharedObjectFunctionDescriptor;
  readonly syncBody?: ExpoOwnedSyncFunction<ExpoModuleContext>;
  readonly asyncBody?: ExpoOwnedAsyncFunction<ExpoModuleContext>;
}

type ExpoSharedObjectPropertyGetter<ObjectType extends ExpoSharedObject> = (object: ObjectType) => ESObject | void;
type ExpoSharedObjectPropertySetter<ObjectType extends ExpoSharedObject> = (object: ObjectType, value: ESObject) => void;

interface ExpoSharedObjectPropertyRegistration<ObjectType extends ExpoSharedObject> {
  readonly descriptor: ExpoSharedObjectPropertyDescriptor;
  readonly getter: ExpoSharedObjectPropertyGetter<ObjectType>;
  readonly setter?: ExpoSharedObjectPropertySetter<ObjectType>;
}

/** @internal Type-erased runtime surface for a typed author class definition. */
export interface ExpoSharedObjectClassRuntime {
  assertBinding(moduleName: string, className: string, nativeRefType: string): void;
  baseClassNameValue(): string;
  bindModule(context: ExpoModuleContext, moduleName: string, registry: ExpoSharedObjectRegistry): void;
  createFromBridge(args: ESObject[]): ExpoSharedObject;
  declaredEvents(): string[];
  descriptor(): ExpoSharedObjectClassDescriptor;
  declaredRefType(): string;
  getConstant(name: string): ESObject | void;
  getProperty(object: ExpoSharedObject, name: string): ESObject | void;
  invokeAsync(object: ExpoSharedObject, name: string, args: ESObject[]): Promise<ESObject | void>;
  invokeStaticAsync(name: string, args: ESObject[]): Promise<ESObject | void>;
  invokeStaticSync(name: string, args: ESObject[]): ESObject | void;
  invokeSync(object: ExpoSharedObject, name: string, args: ESObject[]): ESObject | void;
  moduleNameValue(): string;
  name(): string;
  notifyObserving(object: ExpoSharedObject, eventName: string, observing: boolean): void;
  toBridgeEventPayload(eventName: string, payload: ESObject): ESObject | void;
  refType(): string;
  setProperty(object: ExpoSharedObject, name: string, value: ESObject): void;
}

class ExpoSharedObjectBinding {
  readonly runtimeEpoch: string;
  readonly objectId: number;
  readonly moduleName: string;
  readonly className: string;
  readonly nativeRefType: string;
  readonly classLineage: ExpoSharedObjectClassIdentity[];
  readonly events: Set<string>;

  constructor(
    runtimeEpoch: string,
    objectId: number,
    moduleName: string,
    className: string,
    nativeRefType: string,
    classLineage: ExpoSharedObjectClassIdentity[],
    events: string[],
  ) {
    this.runtimeEpoch = runtimeEpoch;
    this.objectId = objectId;
    this.moduleName = moduleName;
    this.className = className;
    this.nativeRefType = nativeRefType;
    this.classLineage = classLineage;
    this.events = new Set<string>(events);
  }
}

class ExpoSharedObjectClassIdentity {
  readonly moduleName: string;
  readonly className: string;

  constructor(moduleName: string, className: string) {
    this.moduleName = moduleName;
    this.className = className;
  }
}

class ExpoSharedObjectMarker {
  runtimeEpoch: string;
  objectId: number;
  authorId: number;
  moduleName: string;
  className: string;
  nativeRefType: string;
  classLineage: ExpoSharedObjectClassIdentity[];

  constructor(
    runtimeEpoch: string,
    objectId: number,
    authorId: number,
    moduleName: string,
    className: string,
    nativeRefType: string,
    classLineage: ExpoSharedObjectClassIdentity[],
  ) {
    this.runtimeEpoch = runtimeEpoch;
    this.objectId = objectId;
    this.authorId = authorId;
    this.moduleName = moduleName;
    this.className = className;
    this.nativeRefType = nativeRefType;
    this.classLineage = classLineage;
  }
}

class ExpoSharedObjectWireValue {
  __expoHarmonySharedObject: ExpoSharedObjectMarker;

  constructor(marker: ExpoSharedObjectMarker) {
    this.__expoHarmonySharedObject = marker;
  }
}

/** ArkTS SharedObject whose identity and lifecycle are owned by Core. */
export abstract class ExpoSharedObject {
  readonly context: ExpoModuleContext;
  readonly appContext: ExpoModuleContext;
  private classDefinition?: ExpoSharedObjectClassRuntime = undefined;
  private binding?: ExpoSharedObjectBinding = undefined;
  private ownerRegistry?: ExpoSharedObjectRegistry = undefined;
  private pendingAuthorId: number = 0;
  private pendingTransportCount: number = 0;
  private willReleaseNotified: boolean = false;

  constructor(context: ExpoModuleContext) {
    this.context = context;
    this.appContext = context;
  }

  /** Called once after the JS wrapper is explicitly released or collected. */
  sharedObjectDidRelease(): void {}

  /** Called once immediately before Core retires the live JS wrapper. */
  sharedObjectWillRelease(): void {}

  /** Returns the native memory pressure reported to the JSI runtime. */
  getAdditionalMemoryPressure(): number {
    return 0;
  }

  /** Called when the first JS listener for an event is attached. */
  onStartListeningToEvent(_eventName: string): void {}

  /** Called when the final JS listener for an event is removed. */
  onStopListeningToEvent(_eventName: string): void {}

  protected sendEvent(eventName: string): void;
  protected sendEvent<Payload>(eventName: string, payload: Payload): void;
  protected sendEvent<Payload>(eventName: string, payload?: Payload): void {
    const binding = this.binding;
    if (binding === undefined) {
      throw new Error('An Expo SharedObject cannot send events before it has a JavaScript identity.');
    }
    if (!binding.events.has(eventName)) {
      throw new Error(`Expo SharedObject '${binding.moduleName}.${binding.className}' did not declare event '${eventName}'.`);
    }
    const value: ESObject | void = this.requireClassDefinition().toBridgeEventPayload(eventName, payload as ESObject);
    this.context.sendSharedObjectEvent(
      binding.runtimeEpoch,
      binding.objectId,
      binding.moduleName,
      binding.className,
      eventName,
      value === undefined ? [] : [value],
    );
  }

  /** @internal */
  attachClassDefinition(definition: ExpoSharedObjectClassRuntime): void {
    if (this.classDefinition !== undefined && this.classDefinition !== definition) {
      throw new Error('An Expo SharedObject instance cannot belong to two unrelated Expo classes.');
    }
    this.classDefinition = definition;
  }

  /** @internal */
  requireClassDefinition(): ExpoSharedObjectClassRuntime {
    if (this.classDefinition === undefined) {
      throw new Error('An ArkTS SharedObject returned to JavaScript must be created through its ExpoSharedObjectClassDefinition.');
    }
    return this.classDefinition;
  }

  /** @internal */
  currentBinding(): ExpoSharedObjectBinding | undefined {
    return this.binding;
  }

  /** @internal */
  bind(binding: ExpoSharedObjectBinding, registry: ExpoSharedObjectRegistry): void {
    if (this.binding !== undefined) {
      if (this.binding.runtimeEpoch === binding.runtimeEpoch && this.binding.objectId === binding.objectId) return;
      throw new Error('An Expo SharedObject cannot have two live JavaScript identities.');
    }
    this.context.assertRuntimeEpoch(binding.runtimeEpoch);
    const definition = this.requireClassDefinition();
    definition.assertBinding(binding.moduleName, binding.className, binding.nativeRefType);
    this.installBinding(binding, registry);
  }

  private installBinding(binding: ExpoSharedObjectBinding, registry: ExpoSharedObjectRegistry): void {
    this.binding = binding;
    this.ownerRegistry = registry;
    this.willReleaseNotified = false;
    this.pendingAuthorId = 0;
    this.pendingTransportCount = 0;
  }

  /** @internal */
  markStaged(authorId: number): void {
    if (this.pendingAuthorId !== 0 || this.pendingTransportCount !== 0) {
      throw new Error('An Expo SharedObject bridge identity is already staged.');
    }
    this.pendingAuthorId = authorId;
    this.pendingTransportCount = 1;
  }

  /** @internal Retains another in-flight marker for the same staged object. */
  retainStaged(authorId: number): void {
    if (this.pendingAuthorId !== authorId || this.pendingTransportCount <= 0) {
      throw new Error('An Expo SharedObject bridge identity is not staged.');
    }
    this.pendingTransportCount += 1;
  }

  /** @internal */
  stagedAuthorId(): number {
    return this.pendingAuthorId;
  }

  /** @internal */
  clearStaged(authorId: number): void {
    if (this.pendingAuthorId !== authorId) return;
    this.pendingAuthorId = 0;
    this.pendingTransportCount = 0;
  }

  /** @internal Releases one staged bridge attempt that never gained JS identity. */
  discardStaged(authorId: number): void {
    if (this.pendingAuthorId !== authorId) return;
    this.pendingTransportCount -= 1;
    if (this.pendingTransportCount > 0) return;
    this.releaseStaged(authorId);
  }

  /** @internal Releases the staged identity when its entire runtime scope is retired. */
  discardAllStaged(authorId: number): void {
    if (this.pendingAuthorId !== authorId) return;
    this.releaseStaged(authorId);
  }

  private releaseStaged(authorId: number): void {
    if (this.pendingAuthorId !== authorId) return;

    this.pendingAuthorId = 0;
    this.pendingTransportCount = 0;

    const definition = this.requireClassDefinition();
    this.notifyWillRelease(definition.moduleNameValue(), definition.name());

    try {
      this.sharedObjectDidRelease();
    } catch (error) {
      reportSharedObjectCallbackFailure(definition.moduleNameValue(), definition.name(), 'sharedObjectDidRelease', error);
    }
  }

  /** @internal */
  willRelease(runtimeEpoch: string, objectId: number): void {
    const binding = this.binding;
    if (binding === undefined || binding.runtimeEpoch !== runtimeEpoch || binding.objectId !== objectId) return;
    this.notifyWillRelease(binding.moduleName, binding.className);
  }

  /** @internal */
  release(runtimeEpoch: string, objectId: number): void {
    const binding = this.binding;
    if (binding === undefined || binding.runtimeEpoch !== runtimeEpoch || binding.objectId !== objectId) return;

    this.notifyWillRelease(binding.moduleName, binding.className);
    this.binding = undefined;
    this.ownerRegistry = undefined;

    try {
      this.sharedObjectDidRelease();
    } catch (error) {
      reportSharedObjectCallbackFailure(binding.moduleName, binding.className, 'sharedObjectDidRelease', error);
    }
  }

  /** @internal Validates the canonical identity before an author closure sees it. */
  assertValueContract(path: string, expectedModule?: string, expectedClass?: string, expectedNativeRefType?: string): ExpoSharedObject {
    const binding = this.binding;

    if (binding === undefined) {
      throw new ExpoModuleError('ERR_SHARED_OBJECT_RELEASED', `${path} received an Expo SharedObject that has already been released.`);
    }

    const registry = this.ownerRegistry;
    if (registry === undefined) {
      throw new ExpoModuleError('ERR_SHARED_OBJECT_IDENTITY', `${path} received an Expo SharedObject without a canonical runtime registry.`);
    }

    registry.assertValueContract(this, binding, path, expectedModule, expectedClass, expectedNativeRefType);

    return this;
  }

  private notifyWillRelease(moduleName: string, className: string): void {
    if (this.willReleaseNotified) return;
    this.willReleaseNotified = true;
    try {
      this.sharedObjectWillRelease();
    } catch (error) {
      reportSharedObjectCallbackFailure(moduleName, className, 'sharedObjectWillRelease', error);
    }
  }
}

/** Typed ArkTS value shared between Expo modules through a stable native tag. */
export abstract class ExpoSharedRef<T> extends ExpoSharedObject {
  readonly nativeRefType: string;
  readonly value: T;

  constructor(context: ExpoModuleContext, nativeRefType: string, value: T) {
    super(context);
    if (nativeRefType.length === 0 || nativeRefType === 'SharedObject') {
      throw new Error('ExpoSharedRef requires a non-empty stable nativeRefType.');
    }

    this.nativeRefType = nativeRefType;
    this.value = value;
  }
}

/** Standard reusable contracts for SharedObject values passed to ArkTS functions. */
export class ExpoSharedObjectTypes {
  /** Accepts any canonical ArkTS-authored non-SharedRef SharedObject. */
  static sharedObject<ObjectType extends ExpoSharedObject>(): ExpoValueType<ObjectType> {
    return sharedObjectValueType<ObjectType>('SharedObject', undefined, undefined, 'SharedObject');
  }

  static named<ObjectType extends ExpoSharedObject>(moduleName: string, className: string): ExpoValueType<ObjectType> {
    requireSharedMemberName(moduleName, 'module');
    requireSharedMemberName(className, 'class');
    const expected: string = `${moduleName}.${className}`;
    return sharedObjectValueType<ObjectType>(expected, moduleName, className, undefined);
  }

  static sharedRef<ObjectType extends ExpoSharedObject>(nativeRefType: string): ExpoValueType<ObjectType> {
    if (nativeRefType.length === 0 || nativeRefType === 'SharedObject') {
      throw new Error('Expo SharedRef value types require a stable nativeRefType.');
    }
    return sharedObjectValueType<ObjectType>(`SharedRef<'${nativeRefType}'>`, undefined, undefined, nativeRefType);
  }
}

/** ArkTS Class DSL and type-preserving SharedObject factory. */
export class ExpoSharedObjectClassDefinition<ObjectType extends ExpoSharedObject = ExpoSharedObject> {
  private readonly className: string;
  private baseClassName: string = 'SharedObject';
  private sharedRefType: string = 'SharedObject';
  private constructorArityValue: number = 0;
  private constructorRequiredArityValue: number = 0;
  private constructorBody?: ExpoOwnedSyncFunction<ExpoModuleContext> = undefined;
  private readonly functionValues: Map<string, ExpoSharedObjectFunctionRegistration<ObjectType>> = new Map<
    string,
    ExpoSharedObjectFunctionRegistration<ObjectType>
  >();
  private readonly staticFunctionValues: Map<string, ExpoSharedObjectStaticFunctionRegistration> = new Map<
    string,
    ExpoSharedObjectStaticFunctionRegistration
  >();
  private readonly propertyValues: Map<string, ExpoSharedObjectPropertyRegistration<ObjectType>> = new Map<
    string,
    ExpoSharedObjectPropertyRegistration<ObjectType>
  >();
  private readonly eventNames: Set<string> = new Set<string>();
  private readonly eventPayloadTypes: Map<string, ExpoValueType<ESObject>> = new Map<string, ExpoValueType<ESObject>>();
  private readonly constantValues: Map<string, ExpoSharedObjectConstantRegistration> = new Map<string, ExpoSharedObjectConstantRegistration>();
  private moduleContext?: ExpoModuleContext = undefined;
  private moduleName?: string = undefined;
  private registry?: ExpoSharedObjectRegistry = undefined;

  constructor(name: string) {
    requireSharedMemberName(name, 'class');
    this.className = name;
  }

  baseClass(name: string): ExpoSharedObjectClassDefinition<ObjectType> {
    requireSharedMemberName(name, 'base class');
    this.baseClassName = name;
    return this;
  }

  sharedRef(nativeRefType: string): ExpoSharedObjectClassDefinition<ObjectType> {
    if (nativeRefType.length === 0 || nativeRefType === 'SharedObject') {
      throw new Error(`Expo SharedRef class '${this.className}' requires a stable nativeRefType.`);
    }
    this.baseClassName = 'SharedRef';
    this.sharedRefType = nativeRefType;
    return this;
  }

  /** Returns the runtime type token for this class. */
  valueType(): ExpoValueType<ObjectType> {
    const expected: string = this.className;
    return new ExpoValueType<ObjectType>(
      expected,
      (value: ESObject, path: string): ObjectType => {
        const object: ExpoSharedObject = requireSharedObjectValue(value, path, expected);
        return object.assertValueContract(path, this.moduleNameValue(), this.className, this.refType()) as ObjectType;
      },
      (value: ObjectType, path: string): ESObject => {
        const object: ExpoSharedObject = requireSharedObjectValue(value as ESObject, path, expected);
        const binding = object.currentBinding();
        if (binding !== undefined) {
          object.assertValueContract(path, this.moduleNameValue(), this.className, this.refType());
          return object as ESObject;
        }
        if (object.context !== this.requireContext()) {
          throw new ExpoModuleError('ERR_SHARED_OBJECT_RUNTIME', `${path} returned ${expected} from another AppContext/runtime.`);
        }
        if (object.requireClassDefinition() !== this) {
          throw new ExpoModuleError('ERR_INVALID_SHARED_OBJECT_CLASS', `${path} expected ${expected}, received another Expo SharedObject class.`);
        }
        this.assertReturnRefType(object, path);
        return object as ESObject;
      },
    );
  }

  construct(body: ExpoFunction1<ExpoModuleContext, ObjectType>): ExpoSharedObjectClassDefinition<ObjectType>;
  construct<Body extends ExpoOwnedSyncFunctionBody<ExpoModuleContext>>(body: ExpoFunctionSpec<Body>): ExpoSharedObjectClassDefinition<ObjectType>;
  construct(body: ExpoOwnedSyncFunction<ExpoModuleContext>): ExpoSharedObjectClassDefinition<ObjectType> {
    const arity = ownedFunctionArity(body);
    this.constructorArityValue = arity.maximum;
    this.constructorRequiredArityValue = arity.required;
    this.constructorBody = body;
    return this;
  }

  constant<Value>(name: string, getter: ExpoFunction0<Value>): ExpoSharedObjectClassDefinition<ObjectType>;
  constant(name: string, value: ESObject): ExpoSharedObjectClassDefinition<ObjectType>;
  constant<Value>(name: string, valueOrGetter: ESObject | ExpoFunction0<Value>): ExpoSharedObjectClassDefinition<ObjectType> {
    requireSharedMemberName(name, 'constant');
    if (this.constantValues.has(name) || this.staticFunctionValues.has(name)) {
      throw new Error(`Expo SharedObject static member '${this.className}.${name}' was defined more than once.`);
    }
    const getter: ExpoSharedObjectConstantGetter =
      typeof valueOrGetter === 'function'
        ? (): ESObject | void =>
            ExpoValueConverter.toBridge(
              (valueOrGetter as ExpoFunction0<Value>)(),
              undefined,
              `Expo SharedObject constant '${this.qualifiedName()}.${name}'`,
            )
        : (): ESObject | void =>
            ExpoValueConverter.toBridge(valueOrGetter as ESObject, undefined, `Expo SharedObject constant '${this.qualifiedName()}.${name}'`);
    this.constantValues.set(name, { name, getter });
    return this;
  }

  typedConstant<Value>(name: string, type: ExpoValueType<Value>, getter: ExpoFunction0<Value>): ExpoSharedObjectClassDefinition<ObjectType> {
    requireSharedMemberName(name, 'constant');
    if (this.constantValues.has(name) || this.staticFunctionValues.has(name)) {
      throw new Error(`Expo SharedObject static member '${this.className}.${name}' was defined more than once.`);
    }
    this.constantValues.set(name, {
      name,
      getter: (): ESObject | void => ExpoValueConverter.toBridge(getter(), type, `Expo SharedObject constant '${this.qualifiedName()}.${name}'`),
    });
    return this;
  }

  syncFunction<Result>(name: string, body: ExpoFunction1<ObjectType, Result>): ExpoSharedObjectClassDefinition<ObjectType>;
  syncFunction<Body extends ExpoOwnedSyncFunctionBody<ObjectType>>(
    name: string,
    body: ExpoFunctionSpec<Body>,
  ): ExpoSharedObjectClassDefinition<ObjectType>;
  syncFunction(name: string, body: ExpoOwnedSyncFunction<ObjectType>): ExpoSharedObjectClassDefinition<ObjectType> {
    this.registerFunction(name, ownedFunctionArity(body), false, body, undefined);
    return this;
  }

  asyncFunction<Result>(name: string, body: ExpoFunction1<ObjectType, Promise<Result>>): ExpoSharedObjectClassDefinition<ObjectType>;
  asyncFunction<Body extends ExpoOwnedAsyncFunctionBody<ObjectType>>(
    name: string,
    body: ExpoFunctionSpec<Body>,
  ): ExpoSharedObjectClassDefinition<ObjectType>;
  asyncFunction(name: string, body: ExpoOwnedAsyncFunction<ObjectType>): ExpoSharedObjectClassDefinition<ObjectType> {
    this.registerFunction(name, ownedFunctionArity(body), true, undefined, body);
    return this;
  }

  staticSyncFunction<Result>(name: string, body: ExpoFunction1<ExpoModuleContext, Result>): ExpoSharedObjectClassDefinition<ObjectType>;
  staticSyncFunction<Body extends ExpoOwnedSyncFunctionBody<ExpoModuleContext>>(
    name: string,
    body: ExpoFunctionSpec<Body>,
  ): ExpoSharedObjectClassDefinition<ObjectType>;
  staticSyncFunction(name: string, body: ExpoOwnedSyncFunction<ExpoModuleContext>): ExpoSharedObjectClassDefinition<ObjectType> {
    this.registerStaticFunction(name, ownedFunctionArity(body), false, body, undefined);
    return this;
  }

  staticAsyncFunction<Result>(name: string, body: ExpoFunction1<ExpoModuleContext, Promise<Result>>): ExpoSharedObjectClassDefinition<ObjectType>;
  staticAsyncFunction<Body extends ExpoOwnedAsyncFunctionBody<ExpoModuleContext>>(
    name: string,
    body: ExpoFunctionSpec<Body>,
  ): ExpoSharedObjectClassDefinition<ObjectType>;
  staticAsyncFunction(name: string, body: ExpoOwnedAsyncFunction<ExpoModuleContext>): ExpoSharedObjectClassDefinition<ObjectType> {
    this.registerStaticFunction(name, ownedFunctionArity(body), true, undefined, body);
    return this;
  }

  property<Value>(name: string, getter: ExpoFunction1<ObjectType, Value>): ExpoSharedObjectClassDefinition<ObjectType>;
  property<Value>(
    name: string,
    type: ExpoValueType<Value>,
    getter: ExpoFunction1<ObjectType, Value>,
    setter?: ExpoFunction2<ObjectType, Value, void>,
  ): ExpoSharedObjectClassDefinition<ObjectType>;
  property<Value>(
    name: string,
    typeOrGetter: ExpoValueType<Value> | ExpoFunction1<ObjectType, Value>,
    getterOrSetter?: ExpoFunction1<ObjectType, Value> | ExpoFunction2<ObjectType, Value, void>,
    maybeSetter?: ExpoFunction2<ObjectType, Value, void>,
  ): ExpoSharedObjectClassDefinition<ObjectType> {
    requireSharedMemberName(name, 'property');
    if (this.propertyValues.has(name) || this.functionValues.has(name)) {
      throw new Error(`Expo SharedObject member '${this.className}.${name}' was defined more than once.`);
    }
    let type: ExpoValueType<Value> | undefined = undefined;
    let getter: ExpoFunction1<ObjectType, Value>;
    let setter: ExpoFunction2<ObjectType, Value, void> | undefined = undefined;
    if (typeOrGetter instanceof ExpoValueType) {
      type = typeOrGetter;
      getter = getterOrSetter as ExpoFunction1<ObjectType, Value>;
      setter = maybeSetter;
    } else {
      getter = typeOrGetter;
      setter = getterOrSetter as ExpoFunction2<ObjectType, Value, void> | undefined;
    }
    let bridgeSetter: ExpoSharedObjectPropertySetter<ObjectType> | undefined = undefined;
    if (setter !== undefined) {
      const propertySetter: ExpoFunction2<ObjectType, Value, void> = setter;
      bridgeSetter = (object: ObjectType, value: ESObject): void => {
        propertySetter(object, ExpoValueConverter.fromBridge<Value>(value, type, `Expo SharedObject property '${this.qualifiedName()}.${name}'`));
      };
    }
    this.propertyValues.set(name, {
      descriptor: { name, writable: setter !== undefined },
      getter: (object: ObjectType): ESObject | void =>
        ExpoValueConverter.toBridge(getter(object), type, `Expo SharedObject property '${this.qualifiedName()}.${name}'`),
      setter: bridgeSetter,
    });
    return this;
  }

  events(names: string[]): ExpoSharedObjectClassDefinition<ObjectType> {
    names.forEach((name: string): void => {
      requireSharedMemberName(name, 'event');
      this.eventNames.add(name);
    });
    return this;
  }

  /** Declares an event whose outbound payload is validated and encoded by Core. */
  event<Payload>(name: string, payloadType: ExpoValueType<Payload>): ExpoSharedObjectClassDefinition<ObjectType> {
    requireSharedMemberName(name, 'event');
    if (this.eventPayloadTypes.has(name)) {
      throw new Error(`Expo SharedObject event '${this.className}.${name}' already has a payload type.`);
    }
    this.eventNames.add(name);
    this.eventPayloadTypes.set(name, payloadType as ExpoValueType<ESObject>);
    return this;
  }

  /** @internal Constructs an author object from bridge arguments. */
  createFromBridge(args: ESObject[]): ObjectType {
    const context = this.requireContext();
    const body = this.constructorBody;

    if (body === undefined) {
      throw new Error(`Expo SharedObject class '${this.qualifiedName()}' is not constructible.`);
    }

    requireArityRange(`${this.qualifiedName()}.constructor`, this.constructorRequiredArityValue, this.constructorArityValue, args.length);

    const value: ESObject | void = invokeOwnedSyncFunctionForAuthorObject(
      context,
      body,
      args,
      `Expo SharedObject constructor '${this.qualifiedName()}'`,
    );

    if (!(value instanceof ExpoSharedObject)) {
      throw new Error(`Expo SharedObject constructor '${this.qualifiedName()}' did not return an ExpoSharedObject.`);
    }

    const object = value as ObjectType;

    return this.instance(object);
  }

  /** Associates an author-created instance with this class. */
  instance(object: ObjectType): ObjectType {
    const context = this.requireContext();

    if (object.context !== context) {
      throw new Error(`Expo SharedObject '${this.qualifiedName()}' was created with another module context.`);
    }

    this.assertReturnRefType(object, `Expo SharedObject '${this.qualifiedName()}'`);

    object.attachClassDefinition(this);

    return object;
  }

  private assertReturnRefType(object: ExpoSharedObject, path: string): void {
    const nativeRefType: string = this.refType();
    if (nativeRefType !== 'SharedObject') {
      if (!(object instanceof ExpoSharedRef) || object.nativeRefType !== nativeRefType) {
        throw new ExpoModuleError('ERR_INVALID_SHARED_REF_TYPE', `${path} expected SharedRef<'${nativeRefType}'>.`);
      }
    } else if (object instanceof ExpoSharedRef) {
      throw new ExpoModuleError('ERR_INVALID_SHARED_REF_TYPE', `${path} expected a SharedObject, received SharedRef<'${object.nativeRefType}'>.`);
    }
  }

  /** @internal */
  bindModule(context: ExpoModuleContext, moduleName: string, registry: ExpoSharedObjectRegistry): void {
    if (this.moduleContext !== undefined || this.moduleName !== undefined) {
      throw new Error(`Expo SharedObject class '${this.className}' cannot be registered twice.`);
    }

    this.moduleContext = context;
    this.moduleName = moduleName;
    this.registry = registry;
  }

  /** @internal */
  descriptor(): ExpoSharedObjectClassDescriptor {
    const constants: ExpoSharedObjectConstantDescriptor[] = [];

    this.constantValues.forEach((value: ExpoSharedObjectConstantRegistration): void => {
      constants.push({ name: value.name });
    });

    const functions: ExpoSharedObjectFunctionDescriptor[] = [];

    this.functionValues.forEach((value: ExpoSharedObjectFunctionRegistration<ObjectType>): void => {
      functions.push(value.descriptor);
    });

    const staticFunctions: ExpoSharedObjectFunctionDescriptor[] = [];

    this.staticFunctionValues.forEach((value: ExpoSharedObjectStaticFunctionRegistration): void => {
      staticFunctions.push(value.descriptor);
    });

    const properties: ExpoSharedObjectPropertyDescriptor[] = [];

    this.propertyValues.forEach((value: ExpoSharedObjectPropertyRegistration<ObjectType>): void => {
      properties.push(value.descriptor);
    });

    return {
      name: this.className,
      baseClassName: this.baseClassName,
      nativeRefType: this.sharedRefType,
      constructible: this.constructorBody !== undefined,
      constructorArity: this.constructorArityValue,
      constructorRequiredArity: this.constructorRequiredArityValue,
      constants,
      functions,
      staticFunctions,
      properties,
      events: Array.from(this.eventNames),
    };
  }

  /** @internal */
  getConstant(name: string): ESObject | void {
    const registration = this.constantValues.get(name);
    if (registration === undefined) {
      throw new Error(`Expo SharedObject class '${this.qualifiedName()}' does not expose constant '${name}'.`);
    }
    return registration.getter();
  }

  /** @internal */
  invokeSync(object: ExpoSharedObject, name: string, args: ESObject[]): ESObject | void {
    const registration = this.requireFunction(name, false, args.length);
    const body = registration.syncBody;

    if (body === undefined) throw new Error(`SharedObject sync function '${this.qualifiedName()}.${name}' has no body.`);

    return invokeOwnedSyncFunction(object as ObjectType, body, args, `Expo SharedObject '${this.qualifiedName()}.${name}'`);
  }

  /** @internal */
  async invokeAsync(object: ExpoSharedObject, name: string, args: ESObject[]): Promise<ESObject | void> {
    const registration = this.requireFunction(name, true, args.length);
    const body = registration.asyncBody;

    if (body === undefined) throw new Error(`SharedObject async function '${this.qualifiedName()}.${name}' has no body.`);

    return await invokeOwnedAsyncFunction(object as ObjectType, body, args, `Expo SharedObject '${this.qualifiedName()}.${name}'`);
  }

  /** @internal */
  invokeStaticSync(name: string, args: ESObject[]): ESObject | void {
    const registration = this.requireStaticFunction(name, false, args.length);
    const body = registration.syncBody;

    if (body === undefined) throw new Error(`SharedObject static sync function '${this.qualifiedName()}.${name}' has no body.`);

    return invokeOwnedSyncFunction(this.requireContext(), body, args, `Expo SharedObject static function '${this.qualifiedName()}.${name}'`);
  }

  /** @internal */
  async invokeStaticAsync(name: string, args: ESObject[]): Promise<ESObject | void> {
    const registration = this.requireStaticFunction(name, true, args.length);
    const body = registration.asyncBody;

    if (body === undefined) throw new Error(`SharedObject static async function '${this.qualifiedName()}.${name}' has no body.`);

    return await invokeOwnedAsyncFunction(this.requireContext(), body, args, `Expo SharedObject static function '${this.qualifiedName()}.${name}'`);
  }

  /** @internal */
  getProperty(object: ExpoSharedObject, name: string): ESObject | void {
    const property = this.requireProperty(name);
    return property.getter(object as ObjectType);
  }

  /** @internal */
  setProperty(object: ExpoSharedObject, name: string, value: ESObject): void {
    const property = this.requireProperty(name);

    if (property.setter === undefined) {
      throw new Error(`Expo SharedObject property '${this.qualifiedName()}.${name}' is read-only.`);
    }

    property.setter(object as ObjectType, value);
  }

  /** @internal */
  notifyObserving(object: ExpoSharedObject, eventName: string, observing: boolean): void {
    if (!this.eventNames.has(eventName)) {
      throw new Error(`Expo SharedObject '${this.qualifiedName()}' did not declare event '${eventName}'.`);
    }

    if (observing) object.onStartListeningToEvent(eventName);
    else object.onStopListeningToEvent(eventName);
  }

  /** @internal Keeps event conversion on the same path as returns and properties. */
  toBridgeEventPayload(eventName: string, payload: ESObject): ESObject | void {
    if (!this.eventNames.has(eventName)) {
      throw new Error(`Expo SharedObject '${this.qualifiedName()}' did not declare event '${eventName}'.`);
    }
    return ExpoValueConverter.toBridge(
      payload,
      this.eventPayloadTypes.get(eventName),
      `Expo SharedObject event '${this.qualifiedName()}.${eventName}' payload`,
    );
  }

  /** @internal */
  assertBinding(moduleName: string, className: string, nativeRefType: string): void {
    if (this.moduleName !== moduleName || this.className !== className || this.refType() !== nativeRefType) {
      throw new Error(`Expo SharedObject binding does not match '${this.qualifiedName()}'.`);
    }
  }

  /** @internal */
  declaredEvents(): string[] {
    return Array.from(this.eventNames);
  }

  /** @internal */
  name(): string {
    return this.className;
  }

  /** @internal */
  baseClassNameValue(): string {
    return this.baseClassName;
  }

  /** @internal */
  declaredRefType(): string {
    return this.sharedRefType;
  }

  /** @internal */
  moduleNameValue(): string {
    if (this.moduleName === undefined) {
      throw new Error(`Expo SharedObject class '${this.className}' is not attached to a module.`);
    }
    return this.moduleName;
  }

  /** @internal */
  refType(): string {
    if (this.registry === undefined || this.moduleName === undefined) {
      return this.sharedRefType;
    }
    return this.registry.resolveNativeRefType(this.moduleName, this.className);
  }

  /** @internal */
  qualifiedName(): string {
    return this.moduleName === undefined ? this.className : `${this.moduleName}.${this.className}`;
  }

  private registerFunction(
    name: string,
    arity: ExpoFunctionArityRange,
    async: boolean,
    syncBody?: ExpoOwnedSyncFunction<ObjectType>,
    asyncBody?: ExpoOwnedAsyncFunction<ObjectType>,
  ): void {
    requireSharedMemberName(name, 'function');
    if (this.functionValues.has(name) || this.propertyValues.has(name)) {
      throw new Error(`Expo SharedObject member '${this.className}.${name}' was defined more than once.`);
    }
    this.functionValues.set(name, {
      descriptor: { name, arity: arity.maximum, requiredArity: arity.required, async },
      syncBody,
      asyncBody,
    });
  }

  private registerStaticFunction(
    name: string,
    arity: ExpoFunctionArityRange,
    async: boolean,
    syncBody?: ExpoOwnedSyncFunction<ExpoModuleContext>,
    asyncBody?: ExpoOwnedAsyncFunction<ExpoModuleContext>,
  ): void {
    requireSharedMemberName(name, 'static function');
    if (this.staticFunctionValues.has(name) || this.constantValues.has(name)) {
      throw new Error(`Expo SharedObject static member '${this.className}.${name}' was defined more than once.`);
    }
    this.staticFunctionValues.set(name, {
      descriptor: { name, arity: arity.maximum, requiredArity: arity.required, async },
      syncBody,
      asyncBody,
    });
  }

  private requireFunction(name: string, async: boolean, receivedArity: number): ExpoSharedObjectFunctionRegistration<ObjectType> {
    const value = this.functionValues.get(name);
    if (value === undefined || value.descriptor.async !== async) {
      throw new Error(`Expo SharedObject '${this.qualifiedName()}' does not expose '${name}'.`);
    }
    requireArityRange(`${this.qualifiedName()}.${name}`, value.descriptor.requiredArity, value.descriptor.arity, receivedArity);
    return value;
  }

  private requireStaticFunction(name: string, async: boolean, receivedArity: number): ExpoSharedObjectStaticFunctionRegistration {
    const value = this.staticFunctionValues.get(name);
    if (value === undefined || value.descriptor.async !== async) {
      throw new Error(`Expo SharedObject '${this.qualifiedName()}' does not expose static function '${name}'.`);
    }
    requireArityRange(`${this.qualifiedName()}.${name}`, value.descriptor.requiredArity, value.descriptor.arity, receivedArity);
    return value;
  }

  private requireProperty(name: string): ExpoSharedObjectPropertyRegistration<ObjectType> {
    const value = this.propertyValues.get(name);
    if (value === undefined) {
      throw new Error(`Expo SharedObject '${this.qualifiedName()}' does not expose property '${name}'.`);
    }
    return value;
  }

  private requireContext(): ExpoModuleContext {
    if (this.moduleContext === undefined) {
      throw new Error(`Expo SharedObject class '${this.className}' is not attached to a module runtime.`);
    }
    return this.moduleContext;
  }
}

/** @internal Runtime-scoped identity and invocation owner. */
export class ExpoSharedObjectRegistry {
  private readonly runtimeEpoch: string;
  private readonly classes: Map<string, ExpoSharedObjectClassRuntime> = new Map<string, ExpoSharedObjectClassRuntime>();
  private readonly objects: Map<number, ExpoSharedObject> = new Map<number, ExpoSharedObject>();
  private readonly staged: Map<number, ExpoSharedObject> = new Map<number, ExpoSharedObject>();
  private readonly resolvedAuthors: Map<number, ExpoSharedObject> = new Map<number, ExpoSharedObject>();
  private nextAuthorId: number = 1;
  private valid: boolean = true;

  constructor(runtimeEpoch: string) {
    this.runtimeEpoch = runtimeEpoch;
  }

  registerClass(moduleName: string, definition: ExpoSharedObjectClassRuntime): void {
    const key = sharedClassKey(moduleName, definition.name());
    if (this.classes.has(key)) {
      throw new Error(`Expo SharedObject class '${moduleName}.${definition.name()}' was registered more than once.`);
    }
    this.classes.set(key, definition);
  }

  resolveNativeRefType(moduleName: string, className: string): string {
    const seen: Set<string> = new Set<string>();

    for (let depth = 0; depth < MAX_COPY_VALUE_DEPTH; depth += 1) {
      const key: string = sharedClassKey(moduleName, className);
      if (seen.has(key)) {
        throw new Error(`Expo SharedObject class '${key}' has a base-class cycle.`);
      }
      seen.add(key);

      const definition = this.requireClass(moduleName, className);
      const baseClassName: string = definition.baseClassNameValue();
      if (baseClassName === 'SharedObject') return 'SharedObject';
      if (baseClassName === 'SharedRef') {
        const nativeRefType: string = definition.declaredRefType();
        if (nativeRefType === 'SharedObject') {
          throw new Error(`Expo SharedRef class '${key}' does not declare a nativeRefType.`);
        }
        return nativeRefType;
      }

      const separator: number = baseClassName.indexOf('.');
      if (separator < 0) {
        className = baseClassName;
      } else {
        moduleName = baseClassName.slice(0, separator);
        className = baseClassName.slice(separator + 1);
      }
    }

    throw new Error('Expo SharedObject class inheritance exceeds the maximum depth.');
  }

  getConstant(moduleName: string, className: string, name: string): ESObject {
    const value: ESObject | void = this.requireClass(moduleName, className).getConstant(name);
    return this.encodeResult(value);
  }

  construct(objectId: number, moduleName: string, className: string, nativeRefType: string, args: ESObject[]): void {
    this.assertValid();

    if (!isValidSharedObjectId(objectId) || this.objects.has(objectId)) {
      throw new Error(`Expo SharedObject received invalid object id ${objectId}.`);
    }

    const definition = this.requireClass(moduleName, className);

    definition.assertBinding(moduleName, className, nativeRefType);

    const decoded: ESObject[] = this.decodeArguments(args);
    const object = definition.createFromBridge(decoded);

    object.bind(
      new ExpoSharedObjectBinding(
        this.runtimeEpoch,
        objectId,
        moduleName,
        className,
        nativeRefType,
        this.classLineage(moduleName, className),
        definition.declaredEvents(),
      ),
      this,
    );

    this.objects.set(objectId, object);
  }

  bindStaged(authorId: number, objectId: number, moduleName: string, className: string, nativeRefType: string): number {
    this.assertValid();

    if (!isValidSharedObjectId(authorId) || !isValidSharedObjectId(objectId)) {
      throw new Error('Expo SharedObject received an invalid staged identity.');
    }

    const resolved = this.resolvedAuthors.get(authorId);
    if (resolved !== undefined) {
      const binding = resolved.currentBinding();

      if (binding === undefined) {
        this.resolvedAuthors.delete(authorId);
        throw new Error(`Expo SharedObject staged identity ${authorId} was released.`);
      }

      resolved.requireClassDefinition().assertBinding(moduleName, className, nativeRefType);

      if (
        binding.runtimeEpoch !== this.runtimeEpoch ||
        binding.moduleName !== moduleName ||
        binding.className !== className ||
        binding.nativeRefType !== nativeRefType
      ) {
        throw new Error(`Expo SharedObject staged identity ${authorId} has mismatched metadata.`);
      }

      return binding.objectId;
    }

    if (this.objects.has(objectId)) {
      throw new Error('Expo SharedObject received an occupied native object id.');
    }

    const object = this.staged.get(authorId);

    if (object === undefined || object.stagedAuthorId() !== authorId) {
      throw new Error(`Expo SharedObject staged identity ${authorId} does not exist.`);
    }

    const definition = object.requireClassDefinition();

    definition.assertBinding(moduleName, className, nativeRefType);

    object.bind(
      new ExpoSharedObjectBinding(
        this.runtimeEpoch,
        objectId,
        moduleName,
        className,
        nativeRefType,
        this.classLineage(moduleName, className),
        definition.declaredEvents(),
      ),
      this,
    );

    object.clearStaged(authorId);
    this.staged.delete(authorId);
    this.objects.set(objectId, object);
    this.resolvedAuthors.set(authorId, object);

    return objectId;
  }

  discardStaged(authorIds: number[]): void {
    authorIds.forEach((authorId: number): void => {
      const object = this.staged.get(authorId);
      if (object !== undefined) object.discardStaged(authorId);
      if (object === undefined || object.stagedAuthorId() === 0) {
        this.staged.delete(authorId);
      }
    });
  }

  invokeSync(objectId: number, moduleName: string, className: string, functionName: string, args: ESObject[]): ESObject {
    const object = this.requireObject(objectId, moduleName, className);
    const definition = this.requireClass(moduleName, className);
    return this.encodeResult(definition.invokeSync(object, functionName, this.decodeArguments(args)));
  }

  async invokeAsync(objectId: number, moduleName: string, className: string, functionName: string, args: ESObject[]): Promise<ESObject> {
    const object = this.requireObject(objectId, moduleName, className);
    const definition = this.requireClass(moduleName, className);

    const result: ESObject | void = await definition.invokeAsync(object, functionName, this.decodeArguments(args));

    this.assertValid();

    return this.encodeResult(result);
  }

  invokeStaticSync(moduleName: string, className: string, functionName: string, args: ESObject[]): ESObject {
    const definition = this.requireClass(moduleName, className);
    return this.encodeResult(definition.invokeStaticSync(functionName, this.decodeArguments(args)));
  }

  async invokeStaticAsync(moduleName: string, className: string, functionName: string, args: ESObject[]): Promise<ESObject> {
    const definition = this.requireClass(moduleName, className);

    const result: ESObject | void = await definition.invokeStaticAsync(functionName, this.decodeArguments(args));

    this.assertValid();

    return this.encodeResult(result);
  }

  getProperty(objectId: number, moduleName: string, className: string, propertyName: string): ESObject {
    const object = this.requireObject(objectId, moduleName, className);
    return this.encodeResult(this.requireClass(moduleName, className).getProperty(object, propertyName));
  }

  setProperty(objectId: number, moduleName: string, className: string, propertyName: string, value: ESObject): void {
    const object = this.requireObject(objectId, moduleName, className);
    this.requireClass(moduleName, className).setProperty(object, propertyName, this.decodeValue(value, 0));
  }

  setObserving(objectId: number, moduleName: string, className: string, eventName: string, observing: boolean): void {
    const object = this.requireObject(objectId, moduleName, className);
    this.requireClass(moduleName, className).notifyObserving(object, eventName, observing);
  }

  willRelease(objectId: number): void {
    const object = this.objects.get(objectId);
    if (object !== undefined) object.willRelease(this.runtimeEpoch, objectId);
  }

  memoryPressure(objectId: number): number {
    const object = this.objects.get(objectId);
    if (object === undefined) {
      throw new Error(`Cannot read memory pressure for unknown Expo SharedObject ${objectId}.`);
    }
    const value = object.getAdditionalMemoryPressure();
    if (!Number.isInteger(value) || value < 0 || value > 9007199254740991) {
      throw new Error('Expo SharedObject memory pressure must be a non-negative safe integer.');
    }
    return value;
  }

  release(objectId: number): void {
    const object = this.objects.get(objectId);
    if (object === undefined) return;
    this.objects.delete(objectId);
    this.resolvedAuthors.forEach((resolved: ExpoSharedObject, authorId: number): void => {
      if (resolved === object) this.resolvedAuthors.delete(authorId);
    });
    object.release(this.runtimeEpoch, objectId);
  }

  invalidate(): void {
    if (!this.valid) return;
    this.valid = false;
    const objectIds = Array.from(this.objects.keys());
    objectIds.forEach((objectId: number): void => this.release(objectId));
    this.staged.forEach((object: ExpoSharedObject, authorId: number): void => {
      object.discardAllStaged(authorId);
    });
    this.staged.clear();
    this.resolvedAuthors.clear();
    this.classes.clear();
  }

  encodeResult(value: ESObject | void): ESObject {
    this.assertValid();
    const authorIds: number[] = [];

    try {
      return this.encodeValue(value, 0, authorIds);
    } catch (error) {
      this.discardStaged(authorIds);

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      if (error instanceof Error) throw new Error(error.message);
      throw new Error(String(error));
    }
  }

  encodeArguments(args: ESObject[]): ESObject[] {
    this.assertValid();
    const authorIds: number[] = [];

    try {
      return args.map((value: ESObject): ESObject => this.encodeValue(value, 0, authorIds));
    } catch (error) {
      this.discardStaged(authorIds);

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      if (error instanceof Error) throw new Error(error.message);
      throw new Error(String(error));
    }
  }

  /** @internal Rolls back staged identities when an encoded event was not published. */
  discardEncodedArguments(args: ESObject[]): void {
    const authorIds: number[] = [];
    args.forEach((value: ESObject): void => {
      this.collectEncodedAuthorIds(value, 0, authorIds);
    });
    this.discardStaged(authorIds);
  }

  decodeArguments(args: ESObject[]): ESObject[] {
    return args.map((value: ESObject): ESObject => this.decodeValue(value, 0));
  }

  private encodeValue(value: ESObject | void, depth: number, authorIds: number[]): ESObject {
    if (depth > MAX_COPY_VALUE_DEPTH) {
      throw new Error('Expo module return value exceeds the maximum nesting depth.');
    }

    if (value instanceof ExpoSharedObject) return this.encodeSharedObject(value, authorIds);
    if (value === null || value === undefined) return value;

    // Preserve TypedArrays across the private JSI/NAPI bridge.
    if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) return value;

    const kind = typeof value;

    if (kind === 'string' || kind === 'number' || kind === 'boolean') return value;

    if (Array.isArray(value)) {
      return value.map((item: ESObject): ESObject => this.encodeValue(item, depth + 1, authorIds));
    }

    if (kind !== 'object') {
      throw new Error(`Expo module returned unsupported value type '${kind}'.`);
    }

    const output: Record<string, ESObject> = {};

    Object.keys(value).forEach((key: string): void => {
      if (key === EXPO_SHARED_OBJECT_MARKER) {
        throw new Error('Plain objects cannot use the reserved Expo SharedObject marker key.');
      }

      defineExpoRecordValue(output, key, this.encodeValue(value[key], depth + 1, authorIds));
    });

    return output;
  }

  private encodeSharedObject(object: ExpoSharedObject, authorIds: number[]): ESObject {
    if (object.context.runtimeEpochValue() !== this.runtimeEpoch) {
      throw new Error('An Expo SharedObject cannot cross runtime epochs.');
    }

    const binding = object.currentBinding();

    if (binding !== undefined) {
      return new ExpoSharedObjectWireValue(
        new ExpoSharedObjectMarker(
          binding.runtimeEpoch,
          binding.objectId,
          0,
          binding.moduleName,
          binding.className,
          binding.nativeRefType,
          binding.classLineage,
        ),
      );
    }

    const definition = object.requireClassDefinition();
    let authorId = object.stagedAuthorId();

    if (authorId === 0) {
      if (this.nextAuthorId > MAX_SHARED_OBJECT_ID) {
        throw new ExpoModuleError('ERR_SHARED_OBJECT_ID_EXHAUSTED', 'The Expo SharedObject author identity space for this runtime was exhausted.');
      }
      authorId = this.nextAuthorId;
      this.nextAuthorId += 1;
      object.markStaged(authorId);
      this.staged.set(authorId, object);
    } else {
      object.retainStaged(authorId);
    }

    authorIds.push(authorId);

    return new ExpoSharedObjectWireValue(
      new ExpoSharedObjectMarker(
        this.runtimeEpoch,
        0,
        authorId,
        definition.moduleNameValue(),
        definition.name(),
        definition.refType(),
        this.classLineage(definition.moduleNameValue(), definition.name()),
      ),
    );
  }

  private decodeValue(value: ESObject, depth: number): ESObject {
    if (depth > MAX_COPY_VALUE_DEPTH) {
      throw new Error('Expo module argument exceeds the maximum nesting depth.');
    }

    if (value === null || value === undefined) return value;
    if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) return value;

    const kind = typeof value;

    if (kind === 'string' || kind === 'number' || kind === 'boolean') return value;

    if (Array.isArray(value)) {
      return value.map((item: ESObject): ESObject => this.decodeValue(item, depth + 1));
    }

    if (kind !== 'object') {
      throw new Error(`Expo module received unsupported value type '${kind}'.`);
    }

    const marker: ESObject = value[EXPO_SHARED_OBJECT_MARKER];

    if (marker !== undefined) return this.decodeSharedObject(marker);

    const output: Record<string, ESObject> = {};

    Object.keys(value).forEach((key: string): void => {
      defineExpoRecordValue(output, key, this.decodeValue(value[key], depth + 1));
    });

    return output;
  }

  private collectEncodedAuthorIds(value: ESObject, depth: number, ids: number[]): void {
    if (depth > MAX_COPY_VALUE_DEPTH || value === null || value === undefined) return;
    if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) return;

    if (Array.isArray(value)) {
      value.forEach((item: ESObject): void => {
        this.collectEncodedAuthorIds(item, depth + 1, ids);
      });
      return;
    }

    if (typeof value !== 'object') return;

    const marker: ESObject = value[EXPO_SHARED_OBJECT_MARKER];

    if (marker !== undefined) {
      const authorId: ESObject = marker['authorId'];

      if (typeof authorId === 'number' && Number.isSafeInteger(authorId) && authorId > 0) {
        ids.push(authorId);
      }

      return;
    }

    Object.keys(value).forEach((key: string): void => {
      this.collectEncodedAuthorIds(value[key], depth + 1, ids);
    });
  }

  private decodeSharedObject(marker: ESObject): ExpoSharedObject {
    const rawEpoch: ESObject = marker.runtimeEpoch;
    const rawObjectId: ESObject = marker.objectId;
    const rawAuthorId: ESObject = marker.authorId;
    const rawModule: ESObject = marker.moduleName;
    const rawClass: ESObject = marker.className;
    const rawRef: ESObject = marker.nativeRefType;
    const rawLineage: ESObject = marker.classLineage;

    if (
      typeof rawEpoch !== 'string' ||
      rawEpoch !== this.runtimeEpoch ||
      typeof rawObjectId !== 'number' ||
      !Number.isSafeInteger(rawObjectId) ||
      rawObjectId <= 0 ||
      typeof rawAuthorId !== 'number' ||
      rawAuthorId !== 0 ||
      typeof rawModule !== 'string' ||
      typeof rawClass !== 'string' ||
      rawClass.length === 0 ||
      typeof rawRef !== 'string' ||
      rawRef.length === 0 ||
      !Array.isArray(rawLineage)
    ) {
      throw new Error('Expo SharedObject argument belongs to another or invalid runtime identity.');
    }

    const objectId: number = rawObjectId;
    const moduleName: string = rawModule;
    const className: string = rawClass;
    const nativeRefType: string = rawRef;

    if (moduleName.length === 0) {
      throw new Error('Expo SharedObject argument has an empty module identity.');
    }

    const classLineage: ExpoSharedObjectClassIdentity[] = this.decodeClassLineage(rawLineage, moduleName, className);

    const existing = this.objects.get(objectId);

    if (existing !== undefined) {
      this.assertCanonicalBinding(existing, objectId, moduleName, className, nativeRefType, classLineage);
      return existing;
    }

    throw new ExpoModuleError('ERR_SHARED_OBJECT_IDENTITY', `Expo SharedObject ${objectId} was not created by this ArkTS runtime scope.`);
  }

  private assertCanonicalBinding(
    object: ExpoSharedObject,
    objectId: number,
    moduleName: string,
    className: string,
    nativeRefType: string,
    classLineage?: ExpoSharedObjectClassIdentity[],
  ): void {
    const binding = object.currentBinding();
    if (
      binding === undefined ||
      binding.runtimeEpoch !== this.runtimeEpoch ||
      binding.objectId !== objectId ||
      binding.moduleName !== moduleName ||
      binding.className !== className ||
      binding.nativeRefType !== nativeRefType ||
      (classLineage !== undefined && !sameClassLineage(binding.classLineage, classLineage))
    ) {
      throw new Error(`Expo SharedObject ${objectId} has mismatched canonical identity metadata.`);
    }
  }

  /** @internal Author-argument contract backed by the canonical runtime registry. */
  assertValueContract(
    object: ExpoSharedObject,
    binding: ExpoSharedObjectBinding,
    path: string,
    expectedModule?: string,
    expectedClass?: string,
    expectedNativeRefType?: string,
  ): void {
    this.assertValid();

    if (binding.runtimeEpoch !== this.runtimeEpoch) {
      throw new ExpoModuleError('ERR_SHARED_OBJECT_RUNTIME', `${path} received an Expo SharedObject from another runtime epoch.`);
    }

    const canonical: ExpoSharedObject | undefined = this.objects.get(binding.objectId);

    if (canonical !== object) {
      throw new ExpoModuleError(
        canonical === undefined ? 'ERR_SHARED_OBJECT_RELEASED' : 'ERR_SHARED_OBJECT_IDENTITY',
        canonical === undefined
          ? `${path} received an Expo SharedObject that has already been released.`
          : `${path} received a non-canonical Expo SharedObject identity.`,
      );
    }

    this.assertCanonicalBinding(object, binding.objectId, binding.moduleName, binding.className, binding.nativeRefType);

    if (expectedModule !== undefined && expectedClass !== undefined && !this.isClassAssignable(binding, expectedModule, expectedClass)) {
      throw new ExpoModuleError(
        'ERR_INVALID_SHARED_OBJECT_CLASS',
        `${path} expected ${expectedModule}.${expectedClass}, received ${binding.moduleName}.${binding.className}.`,
      );
    }

    if (expectedNativeRefType !== undefined && binding.nativeRefType !== expectedNativeRefType) {
      throw new ExpoModuleError(
        'ERR_INVALID_SHARED_REF_TYPE',
        `${path} expected SharedRef<'${expectedNativeRefType}'>, received '${binding.nativeRefType}'.`,
      );
    }
  }

  private requireObject(objectId: number, moduleName: string, className: string): ExpoSharedObject {
    this.assertValid();

    const object = this.objects.get(objectId);

    if (object === undefined) {
      throw new Error(`Expo SharedObject ${objectId} was released or belongs to another runtime.`);
    }

    const binding = object.currentBinding();

    if (
      binding === undefined ||
      binding.runtimeEpoch !== this.runtimeEpoch ||
      binding.moduleName !== moduleName ||
      !this.isClassAssignable(binding, moduleName, className)
    ) {
      throw new Error(`Expo SharedObject ${objectId} is not an instance of '${moduleName}.${className}'.`);
    }

    return object;
  }

  private isClassAssignable(binding: ExpoSharedObjectBinding, expectedModule: string, expectedClass: string): boolean {
    return binding.classLineage.some(
      (identity: ExpoSharedObjectClassIdentity): boolean => identity.moduleName === expectedModule && identity.className === expectedClass,
    );
  }

  private classLineage(actualModule: string, actualClass: string): ExpoSharedObjectClassIdentity[] {
    const lineage: ExpoSharedObjectClassIdentity[] = [];
    let moduleName = actualModule;
    let className = actualClass;

    for (let depth = 0; depth < MAX_COPY_VALUE_DEPTH; depth += 1) {
      lineage.push(new ExpoSharedObjectClassIdentity(moduleName, className));

      const definition = this.classes.get(sharedClassKey(moduleName, className));
      if (definition === undefined) return lineage;

      const descriptor = definition.descriptor();

      if (descriptor.baseClassName === 'SharedObject' || descriptor.baseClassName === 'SharedRef') {
        return lineage;
      }

      const separator = descriptor.baseClassName.indexOf('.');

      if (separator < 0) className = descriptor.baseClassName;
      else {
        moduleName = descriptor.baseClassName.slice(0, separator);
        className = descriptor.baseClassName.slice(separator + 1);
      }
    }

    return lineage;
  }

  private decodeClassLineage(value: ESObject[], actualModule: string, actualClass: string): ExpoSharedObjectClassIdentity[] {
    if (value.length === 0 || value.length > MAX_COPY_VALUE_DEPTH) {
      throw new Error('Expo SharedObject argument has invalid canonical class lineage.');
    }

    const lineage: ExpoSharedObjectClassIdentity[] = [];
    const seen: Set<string> = new Set<string>();

    value.forEach((item: ESObject, index: number): void => {
      if (item === null || typeof item !== 'object') {
        throw new Error('Expo SharedObject argument has invalid canonical class lineage.');
      }

      const moduleNameValue: ESObject = item.moduleName;
      const classNameValue: ESObject = item.className;

      if (typeof moduleNameValue !== 'string' || typeof classNameValue !== 'string' || classNameValue.length === 0) {
        throw new Error('Expo SharedObject argument has invalid canonical class lineage.');
      }
      if (moduleNameValue.length === 0) {
        throw new Error('Expo SharedObject argument has invalid canonical class lineage.');
      }
      if (index === 0 && (moduleNameValue !== actualModule || classNameValue !== actualClass)) {
        throw new Error('Expo SharedObject argument class lineage does not match its canonical class.');
      }
      const key: string = sharedClassKey(moduleNameValue, classNameValue);
      if (seen.has(key)) {
        throw new Error('Expo SharedObject argument class lineage contains a cycle.');
      }

      seen.add(key);
      lineage.push(new ExpoSharedObjectClassIdentity(moduleNameValue, classNameValue));
    });

    return lineage;
  }

  private requireClass(moduleName: string, className: string): ExpoSharedObjectClassRuntime {
    this.assertValid();
    const definition = this.classes.get(sharedClassKey(moduleName, className));
    if (definition === undefined) {
      throw new Error(`Cannot find ArkTS Expo SharedObject class '${moduleName}.${className}'.`);
    }
    return definition;
  }

  private assertValid(): void {
    if (!this.valid) throw new Error('The ArkTS Expo SharedObject registry has been invalidated.');
  }
}

function sameClassLineage(first: ExpoSharedObjectClassIdentity[], second: ExpoSharedObjectClassIdentity[]): boolean {
  if (first.length !== second.length) return false;
  for (let index = 0; index < first.length; index += 1) {
    if (first[index].moduleName !== second[index].moduleName || first[index].className !== second[index].className) return false;
  }
  return true;
}

function sharedObjectValueType<ObjectType extends ExpoSharedObject>(
  expected: string,
  expectedModule?: string,
  expectedClass?: string,
  expectedNativeRefType?: string,
): ExpoValueType<ObjectType> {
  return new ExpoValueType<ObjectType>(
    expected,
    (value: ESObject, path: string): ObjectType =>
      requireSharedObjectValue(value, path, expected).assertValueContract(path, expectedModule, expectedClass, expectedNativeRefType) as ObjectType,
    (value: ObjectType, path: string): ESObject => {
      const object: ExpoSharedObject = requireSharedObjectValue(value as ESObject, path, expected);
      if (object.currentBinding() !== undefined) {
        object.assertValueContract(path, expectedModule, expectedClass, expectedNativeRefType);
        return object as ESObject;
      }

      let definition: ExpoSharedObjectClassRuntime;
      try {
        definition = object.requireClassDefinition();
      } catch (_) {
        throw new ExpoModuleError('ERR_SHARED_OBJECT_IDENTITY', `${path} returned an Expo SharedObject without a registered class identity.`);
      }

      if (
        expectedModule !== undefined &&
        expectedClass !== undefined &&
        (definition.moduleNameValue() !== expectedModule || definition.name() !== expectedClass)
      ) {
        throw new ExpoModuleError(
          'ERR_INVALID_SHARED_OBJECT_CLASS',
          `${path} expected ${expectedModule}.${expectedClass}, received ${definition.moduleNameValue()}.${definition.name()}.`,
        );
      }

      if (expectedNativeRefType !== undefined && definition.refType() !== expectedNativeRefType) {
        throw new ExpoModuleError(
          'ERR_INVALID_SHARED_REF_TYPE',
          `${path} expected SharedRef<'${expectedNativeRefType}'>, received '${definition.refType()}'.`,
        );
      }

      return object as ESObject;
    },
  );
}

function requireSharedObjectValue(value: ESObject, path: string, expected: string): ExpoSharedObject {
  if (!(value instanceof ExpoSharedObject)) {
    throw new ExpoModuleError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected ${expected}, received ${ExpoValueConverter.actualType(value)}.`);
  }
  return value;
}

function sharedClassKey(moduleName: string, className: string): string {
  return `${moduleName}\n${className}`;
}

function requireSharedMemberName(name: string, kind: string): void {
  if (name.length === 0) throw new Error(`Expo SharedObject ${kind} names cannot be empty.`);
}

function requireArityRange(path: string, required: number, maximum: number, received: number): void {
  if (received >= required && received <= maximum) return;
  const expectation: string = required === maximum ? `${required}` : `${required} to ${maximum}`;
  throw new ExpoModuleError('ERR_INVALID_ARGS_NUMBER', `${path} expected ${expectation} arguments, received ${received}.`);
}

function reportSharedObjectCallbackFailure(moduleName: string, className: string, callbackName: string, error: Object): void {
  try {
    console.error(`Expo SharedObject '${moduleName}.${className}' failed during ${callbackName}: ${String(error)}`);
  } catch (_) {}
}

import type { Descriptor, RNComponentContext } from '@rnoh/react-native-openharmony';
import {
  EXPO_MODULE_NAME_PROP,
  EXPO_VIEW_REVISION_PROP,
  EXPO_VIEW_NAME_PROP,
  ExpoViewAdapter,
  ExpoViewAdapterRegistry,
  ExpoViewContentDelegate,
  ExpoViewContentContext,
  requireExpoViewSize,
} from './ExpoViewTypes';
import {
  ExpoFunction1,
  ExpoFunction2,
  ExpoFunctionArityRange,
  ExpoFunctionSpec,
  ExpoOwnedAsyncFunction,
  ExpoOwnedAsyncFunctionBody,
  ExpoValueConverter,
  ExpoValueType,
  invokeOwnedAsyncFunction,
  ownedFunctionArity,
} from '../modules/ExpoValueConverter';
import { ExpoModuleError } from '../modules/ExpoModuleError';

export type ExpoViewFactory<ViewType extends ExpoView> = (context: ExpoViewContext) => ViewType;
type ExpoViewPropSetter<ViewType extends ExpoView> = (view: ViewType, value: ESObject) => void;
export type ExpoViewLifecycleBody<ViewType extends ExpoView> = (view: ViewType) => void;
export type ExpoViewDidUpdatePropsBody<ViewType extends ExpoView> = (view: ViewType) => void;
export type ExpoViewPropGroupBody<ViewType extends ExpoView, Value> = (view: ViewType, index: number, value: Value) => void;

export interface ExpoViewPropDescriptor {
  readonly name: string;
}

export interface ExpoViewFunctionDescriptor {
  readonly name: string;
  readonly arity: number;
  readonly requiredArity: number;
  readonly async: boolean;
}

/** Copy-value metadata consumed by the common C++ Host adapter. */
export interface ExpoViewDescriptor {
  readonly name: string;
  readonly componentName: string;
  readonly prototypeName: string;
  readonly defaultView: boolean;
  readonly group: boolean;
  readonly props: ExpoViewPropDescriptor[];
  readonly events: string[];
  readonly functions: ExpoViewFunctionDescriptor[];
}

/** @internal Type-erased runtime surface for a typed author View definition. */
export interface ExpoViewDefinitionRuntime {
  bindModule(moduleName: string, defaultView: boolean, instanceId: number, runtimeEpoch: string): () => void;
  descriptor(): ExpoViewDescriptor;
}

interface ExpoViewPropRegistration<ViewType extends ExpoView> {
  readonly descriptor: ExpoViewPropDescriptor;
  readonly setter: ExpoViewPropSetter<ViewType>;
  readonly hasDefaultValue: boolean;
  readonly defaultValue: ESObject;
}

interface ExpoViewFunctionRegistration<ViewType extends ExpoView> {
  readonly descriptor: ExpoViewFunctionDescriptor;
  readonly asyncBody?: ExpoOwnedAsyncFunction<ViewType>;
}

/**
 * Mount-scoped capabilities available to an ArkTS-authored Expo View.
 * The context is invalidated after the view's destroy callback returns.
 */
export class ExpoViewContext implements ExpoViewContentDelegate {
  readonly rnComponentContext: RNComponentContext;
  readonly tag: number;
  readonly componentName: string;
  private readonly declaredEvents: Set<string>;
  private readonly eventPayloadTypes: Map<string, ExpoValueType<ESObject>>;
  private sizeState: ExpoViewSizeState = {};
  private valid: boolean = true;

  constructor(
    rnComponentContext: RNComponentContext,
    tag: number,
    componentName: string,
    declaredEvents: string[],
    eventPayloadTypes: Map<string, ExpoValueType<ESObject>>,
  ) {
    this.rnComponentContext = rnComponentContext;
    this.tag = tag;
    this.componentName = componentName;
    this.declaredEvents = new Set<string>(declaredEvents);
    this.eventPayloadTypes = new Map<string, ExpoValueType<ESObject>>(eventPayloadTypes);
  }

  emit(eventName: string): void;
  emit<Payload>(eventName: string, payload: Payload): void;
  emit<Payload>(eventName: string, payload?: Payload): void {
    this.assertValid();

    if (!this.declaredEvents.has(eventName)) {
      throw new Error(`Expo view '${this.componentName}' did not declare event '${eventName}'.`);
    }

    const value: ESObject | void = ExpoValueConverter.toBridge(
      payload as ESObject,
      this.eventPayloadTypes.get(eventName),
      `Expo view event '${this.componentName}.${eventName}' payload`,
    );

    if (value !== undefined && containsBinaryValue(value, new Set<ESObject>())) {
      throw new ExpoModuleError(
        'ERR_VIEW_EVENT_BINARY_UNSUPPORTED',
        `Expo view event '${this.componentName}.${eventName}' cannot transport ArrayBuffer or TypedArray values through RNOH emitComponentEvent.`,
      );
    }

    this.rnComponentContext.rnInstance.emitComponentEvent(this.tag, eventName, normalizeViewEventPayload(value));
  }

  setShadowNodeSize(width: number, height: number): void {
    this.assertValid();
    requireExpoViewSize(width, height, `Expo view '${this.componentName}' setShadowNodeSize`);
    this.sizeState.width = width;
    this.sizeState.height = height;

    this.rnComponentContext.descriptorRegistry.setState(this.tag, this.sizeState);
  }

  setStyleSize(width: number, height: number): void {
    this.assertValid();
    requireExpoViewSize(width, height, `Expo view '${this.componentName}' setStyleSize`);
    this.sizeState.styleWidth = width;
    this.sizeState.styleHeight = height;

    this.rnComponentContext.descriptorRegistry.setState(this.tag, this.sizeState);
  }

  /** Returns the Fabric-owned child count for a GroupView. */
  getChildCount(): number {
    this.assertValid();

    return this.childTags().length;
  }

  getChildTagAt(index: number): number {
    this.assertValid();
    const tags: number[] = this.childTags();

    if (!Number.isSafeInteger(index) || index < 0 || index >= tags.length) {
      throw new ExpoModuleError('ERR_VIEW_CHILD_INDEX', `Expo view '${this.componentName}' has no child at index ${index}.`);
    }

    return tags[index];
  }

  /** @internal */
  invalidate(): void {
    this.valid = false;
  }

  private assertValid(): void {
    if (!this.valid) {
      throw new Error(`Expo view '${this.componentName}' has been invalidated.`);
    }
  }

  private childTags(): number[] {
    const descriptor: Descriptor = this.rnComponentContext.descriptorRegistry.getDescriptor(this.tag);

    if (descriptor === undefined || descriptor === null) {
      throw new ExpoModuleError('ERR_VIEW_NOT_MOUNTED', `Expo view '${this.componentName}' is not present in the Fabric descriptor tree.`);
    }

    return descriptor.childrenTags.slice();
  }
}

function normalizeViewEventPayload(value: ESObject | void): ESObject {
  if (value === undefined || value === null) return {};

  if (typeof value === 'object' && !Array.isArray(value) && !(value instanceof ArrayBuffer) && !ArrayBuffer.isView(value)) {
    return value;
  }

  return { payload: value };
}

/** Public ArkTS author base class. View authors never implement C++ glue. */
export abstract class ExpoView {
  readonly context: ExpoViewContext;

  constructor(context: ExpoViewContext) {
    this.context = context;
  }

  protected sendEvent(eventName: string): void;
  protected sendEvent<Payload>(eventName: string, payload: Payload): void;
  protected sendEvent<Payload>(eventName: string, payload?: Payload): void {
    if (payload === undefined) {
      this.context.emit(eventName);
      return;
    }
    this.context.emit(eventName, payload);
  }
}

interface ExpoViewSizeState {
  width?: number;
  height?: number;
  styleWidth?: number;
  styleHeight?: number;
}

class MountedExpoView {
  readonly view: ExpoView;
  readonly context: ExpoViewContext;
  readonly previousProps: Map<string, ESObject> = new Map<string, ESObject>();
  initialized: boolean = false;
  destroyed: boolean = false;

  constructor(view: ExpoView, context: ExpoViewContext) {
    this.view = view;
    this.context = context;
  }
}

/** ArkTS-native View definition builder. */
export class ExpoViewDefinition<ViewType extends ExpoView = ExpoView> implements ExpoViewAdapter {
  readonly name: string;
  readonly content?: WrappedBuilder<[ExpoViewContentContext]>;
  private readonly factory: ExpoViewFactory<ViewType>;
  private readonly propValues: Map<string, ExpoViewPropRegistration<ViewType>> = new Map<string, ExpoViewPropRegistration<ViewType>>();
  private readonly functionValues: Map<string, ExpoViewFunctionRegistration<ViewType>> = new Map<string, ExpoViewFunctionRegistration<ViewType>>();
  private readonly eventNames: Set<string> = new Set<string>();
  private readonly eventPayloadTypes: Map<string, ExpoValueType<ESObject>> = new Map<string, ExpoValueType<ESObject>>();
  private groupValue: boolean = false;
  private runtimeEpochValue?: string = undefined;
  private componentNameValue?: string = undefined;
  private prototypeNameValue?: string = undefined;
  private readonly componentNamesValue: Set<string> = new Set<string>();
  private defaultViewValue: boolean = false;
  private createBody?: ExpoViewLifecycleBody<ViewType> = undefined;
  private updateBody?: ExpoViewDidUpdatePropsBody<ViewType> = undefined;
  private destroyBody?: ExpoViewLifecycleBody<ViewType> = undefined;

  constructor(name: string, factory: ExpoViewFactory<ViewType>, content?: WrappedBuilder<[ExpoViewContentContext]>) {
    requireViewMemberName(name, 'name');
    this.name = name;
    this.factory = factory;
    this.content = content;
  }

  get componentName(): string {
    if (this.componentNameValue === undefined) {
      throw new Error(`Expo view '${this.name}' is not bound to a module.`);
    }
    return this.componentNameValue;
  }

  get group(): boolean {
    return this.groupValue;
  }

  get runtimeEpoch(): string {
    if (this.runtimeEpochValue === undefined) {
      throw new Error(`Expo view '${this.name}' is not bound to a runtime.`);
    }
    return this.runtimeEpochValue;
  }

  prop<Value>(
    name: string,
    type: ExpoValueType<Value>,
    setter: ExpoFunction2<ViewType, Value, void>,
    defaultValue?: Value,
  ): ExpoViewDefinition<ViewType> {
    requireViewMemberName(name, 'prop');

    if (name === EXPO_MODULE_NAME_PROP || name === EXPO_VIEW_REVISION_PROP || name === EXPO_VIEW_NAME_PROP) {
      throw new Error(`Expo view prop '${name}' is reserved by Expo Modules Core.`);
    }
    if (this.propValues.has(name)) {
      throw new Error(`Expo view prop '${name}' was defined more than once.`);
    }

    this.propValues.set(name, {
      descriptor: { name },
      setter: (view: ViewType, value: ESObject): void => {
        setter(view, ExpoValueConverter.fromBridge<Value>(value, type, `Expo view prop '${this.componentName}.${name}'`));
      },
      hasDefaultValue: defaultValue !== undefined,
      defaultValue:
        defaultValue === undefined
          ? null
          : (ExpoValueConverter.toBridge(defaultValue, type, `Expo view prop '${this.name}.${name}' default value`) as ESObject),
    });

    return this;
  }

  /** Defines a family of props sharing one converter and indexed setter. */
  propGroup<Value>(
    names: string[],
    type: ExpoValueType<Value>,
    setter: ExpoViewPropGroupBody<ViewType, Value>,
    defaultValue?: Value,
  ): ExpoViewDefinition<ViewType> {
    if (names.length === 0) {
      throw new Error('Expo view prop group must contain at least one prop name.');
    }

    const uniqueNames: Set<string> = new Set<string>();
    names.forEach((name: string): void => {
      requireViewMemberName(name, 'prop');
      if (uniqueNames.has(name)) {
        throw new Error(`Expo view prop group contains duplicate prop '${name}'.`);
      }
      uniqueNames.add(name);
    });

    names.forEach((name: string, index: number): void => {
      this.prop(name, type, (view: ViewType, value: Value): void => setter(view, index, value), defaultValue);
    });

    return this;
  }

  events(names: string[]): ExpoViewDefinition<ViewType> {
    names.forEach((name: string): void => {
      requireViewMemberName(name, 'event');
      this.eventNames.add(name);
    });
    return this;
  }

  event<Payload>(name: string, payloadType: ExpoValueType<Payload>): ExpoViewDefinition<ViewType> {
    requireViewMemberName(name, 'event');
    if (this.eventPayloadTypes.has(name)) {
      throw new Error(`Expo view event '${this.name}.${name}' already has a payload type.`);
    }
    this.eventNames.add(name);
    this.eventPayloadTypes.set(name, payloadType as ExpoValueType<ESObject>);
    return this;
  }

  asyncFunction<Result>(name: string, body: ExpoFunction1<ViewType, Promise<Result>>): ExpoViewDefinition<ViewType>;
  asyncFunction<Body extends ExpoOwnedAsyncFunctionBody<ViewType>>(name: string, body: ExpoFunctionSpec<Body>): ExpoViewDefinition<ViewType>;
  asyncFunction(name: string, body: ExpoOwnedAsyncFunction<ViewType>): ExpoViewDefinition<ViewType> {
    this.registerFunction(name, ownedFunctionArity(body), body);
    return this;
  }

  groupView(value: boolean = true): ExpoViewDefinition<ViewType> {
    this.groupValue = value;
    return this;
  }

  onCreate(body: ExpoViewLifecycleBody<ViewType>): ExpoViewDefinition<ViewType> {
    this.createBody = body;
    return this;
  }

  onDidUpdateProps(body: ExpoViewDidUpdatePropsBody<ViewType>): ExpoViewDefinition<ViewType> {
    this.updateBody = body;
    return this;
  }

  onDestroy(body: ExpoViewLifecycleBody<ViewType>): ExpoViewDefinition<ViewType> {
    this.destroyBody = body;
    return this;
  }

  /** @internal Registers one runtime-scoped adapter for this RN instance. */
  bindModule(moduleName: string, defaultView: boolean, instanceId: number, runtimeEpoch: string): () => void {
    if (this.componentNameValue !== undefined) {
      throw new Error(`Expo view '${moduleName}.${this.name}' was bound more than once.`);
    }

    this.defaultViewValue = defaultView;
    this.runtimeEpochValue = runtimeEpoch;
    this.componentNameValue = `ViewManagerAdapter_${moduleName}_${this.name}`;
    this.prototypeNameValue = `${moduleName}_${this.name}`;
    this.componentNamesValue.add(this.componentNameValue);

    const aliases: string[] = [];
    if (defaultView) {
      const defaultComponentName = `ViewManagerAdapter_${moduleName}`;
      this.componentNamesValue.add(defaultComponentName);
      aliases.push(defaultComponentName);
    }

    return ExpoViewAdapterRegistry.registerForRuntime(instanceId, runtimeEpoch, this, aliases);
  }

  /** @internal Returns metadata only; author bodies never leave ArkTS. */
  descriptor(): ExpoViewDescriptor {
    if (this.prototypeNameValue === undefined) {
      throw new Error(`Expo view '${this.name}' is not bound to a module.`);
    }

    const functions: ExpoViewFunctionDescriptor[] = [];
    this.functionValues.forEach((registration: ExpoViewFunctionRegistration<ViewType>): void => {
      functions.push(registration.descriptor);
    });

    return {
      name: this.name,
      componentName: this.componentName,
      prototypeName: this.prototypeNameValue,
      defaultView: this.defaultViewValue,
      group: this.groupValue,
      props: Array.from(this.propValues.values()).map(
        (registration: ExpoViewPropRegistration<ViewType>): ExpoViewPropDescriptor => registration.descriptor,
      ),
      events: Array.from(this.eventNames),
      functions,
    };
  }

  create(rnComponentContext: RNComponentContext, tag: number, componentName: string): ESObject {
    if (!this.componentNamesValue.has(componentName)) {
      throw new Error(`Expo view '${this.componentName}' cannot create '${componentName}'.`);
    }

    const context = new ExpoViewContext(rnComponentContext, tag, componentName, Array.from(this.eventNames), this.eventPayloadTypes);
    let mounted: MountedExpoView | undefined = undefined;

    try {
      const view: ViewType = this.factory(context);
      mounted = new MountedExpoView(view, context);
      this.createBody?.(view);

      return mounted;
    } catch (error) {
      if (mounted !== undefined) {
        try {
          this.destroyBody?.(mounted.view as ViewType);
        } catch (cleanupError) {
          reportViewDefinitionCleanupFailure(this.componentName, 'create rollback', cleanupError);
        }
      }

      context.invalidate();

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      if (error instanceof Error) throw new Error(error.message);
      throw new Error(String(error));
    }
  }

  contentValue(value: ESObject): ESObject {
    return this.requireMounted(value).view;
  }

  createContentContext(value: ESObject): ExpoViewContentContext {
    const mounted: MountedExpoView = this.requireMounted(value);
    return new ExpoViewContentContext(mounted.context, mounted.view);
  }

  updateProps(value: ESObject, props: Record<string, ESObject>): void {
    const mounted: MountedExpoView = this.requireMounted(value);
    const nextPreviousProps: Map<string, ESObject> = new Map<string, ESObject>(mounted.previousProps);

    this.propValues.forEach((registration: ExpoViewPropRegistration<ViewType>, name: string): void => {
      const hasValue: boolean = Object.keys(props).includes(name);

      if (!hasValue) {
        if (mounted.previousProps.has(name)) {
          registration.setter(mounted.view as ViewType, registration.hasDefaultValue ? registration.defaultValue : null);
          nextPreviousProps.delete(name);
        } else if (!mounted.initialized && registration.hasDefaultValue) {
          registration.setter(mounted.view as ViewType, registration.defaultValue);
        }
        return;
      }

      const rawValue: ESObject = props[name];
      if (mounted.previousProps.has(name) && mounted.previousProps.get(name) === rawValue) return;

      const resolvedValue: ESObject = rawValue === null && registration.hasDefaultValue ? registration.defaultValue : rawValue;
      registration.setter(mounted.view as ViewType, resolvedValue);
      nextPreviousProps.set(name, rawValue);
    });

    this.updateBody?.(mounted.view as ViewType);
    mounted.previousProps.clear();
    nextPreviousProps.forEach((prop: ESObject, name: string): void => {
      mounted.previousProps.set(name, prop);
    });
    mounted.initialized = true;
  }

  async invokeAsync(value: ESObject, functionName: string, args: ESObject[]): Promise<ESObject | void> {
    const mounted: MountedExpoView = this.requireMounted(value);
    const registration: ExpoViewFunctionRegistration<ViewType> = this.requireFunction(functionName, args.length);
    const body: ExpoOwnedAsyncFunction<ViewType> | undefined = registration.asyncBody;

    if (body === undefined) {
      throw new Error(`Expo view async function '${this.componentName}.${functionName}' has no implementation.`);
    }

    const result: ESObject | void = await invokeOwnedAsyncFunction(
      mounted.view as ViewType,
      body,
      args,
      `Expo view function '${this.componentName}.${functionName}'`,
    );

    this.requireMounted(value);

    return result;
  }

  destroy(value: ESObject): void {
    const mounted = value as MountedExpoView;
    if (mounted.destroyed) return;

    mounted.destroyed = true;
    try {
      this.destroyBody?.(mounted.view as ViewType);
    } finally {
      mounted.context.invalidate();
      mounted.previousProps.clear();
    }
  }

  private registerFunction(name: string, arity: ExpoFunctionArityRange, asyncBody: ExpoOwnedAsyncFunction<ViewType>): void {
    requireViewMemberName(name, 'function');
    if (this.functionValues.has(name)) {
      throw new Error(`Expo view function '${name}' was defined more than once.`);
    }

    this.functionValues.set(name, {
      descriptor: { name, arity: arity.maximum, requiredArity: arity.required, async: true },
      asyncBody,
    });
  }

  private requireFunction(functionName: string, receivedArity: number): ExpoViewFunctionRegistration<ViewType> {
    const registration = this.functionValues.get(functionName);
    if (registration === undefined) {
      throw new Error(`Expo view '${this.componentName}' does not expose async function '${functionName}'.`);
    }

    if (receivedArity < registration.descriptor.requiredArity || receivedArity > registration.descriptor.arity) {
      const expectation: string =
        registration.descriptor.requiredArity === registration.descriptor.arity
          ? `${registration.descriptor.arity}`
          : `${registration.descriptor.requiredArity} to ${registration.descriptor.arity}`;
      throw new ExpoModuleError(
        'ERR_INVALID_ARGS_NUMBER',
        `Expo view function '${this.componentName}.${functionName}' expected ${expectation} arguments, received ${receivedArity}.`,
      );
    }

    return registration;
  }

  private requireMounted(value: ESObject): MountedExpoView {
    const mounted = value as MountedExpoView;
    if (mounted.destroyed) {
      throw new Error(`Expo view '${this.componentName}' is no longer mounted.`);
    }
    return mounted;
  }
}

function requireViewMemberName(name: string, kind: string): void {
  if (name.length === 0) throw new Error(`Expo view ${kind} cannot be empty.`);
}

function reportViewDefinitionCleanupFailure(componentName: string, step: string, error: Object): void {
  try {
    console.error(`Expo view '${componentName}' failed during ${step}: ${String(error)}`);
  } catch (_) {}
}

function containsBinaryValue(value: ESObject, seen: Set<ESObject>): boolean {
  if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) return true;
  if (value === null || typeof value !== 'object') return false;
  if (seen.has(value)) return false;
  seen.add(value);
  if (Array.isArray(value)) {
    return value.some((item: ESObject): boolean => containsBinaryValue(item, seen));
  }
  return Object.keys(value).some((key: string): boolean => containsBinaryValue(value[key], seen));
}

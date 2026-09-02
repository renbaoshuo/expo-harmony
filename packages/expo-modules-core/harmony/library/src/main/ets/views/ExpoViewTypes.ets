import type { RNComponentContext } from '@rnoh/react-native-openharmony';
import { EXPO_MODULES_CORE_VIEW_COMPONENT_NAME, EXPO_MODULE_NAME_PROP, EXPO_VIEW_REVISION_PROP, EXPO_VIEW_NAME_PROP } from '../protocol/Protocol';
export { EXPO_MODULES_CORE_VIEW_COMPONENT_NAME, EXPO_MODULE_NAME_PROP, EXPO_VIEW_REVISION_PROP, EXPO_VIEW_NAME_PROP } from '../protocol/Protocol';

export interface ExpoViewContentDelegate {
  readonly rnComponentContext: RNComponentContext;
  readonly tag: number;
  readonly componentName: string;
  emit(eventName: string, payload?: ESObject): void;
  setShadowNodeSize(width: number, height: number): void;
  setStyleSize(width: number, height: number): void;
}

export class ExpoViewContentContext {
  readonly rnComponentContext: RNComponentContext;
  readonly tag: number;
  readonly componentName: string;
  readonly nativeView: ESObject;
  private readonly delegate: ExpoViewContentDelegate;

  constructor(delegate: ExpoViewContentDelegate, nativeView: ESObject) {
    this.delegate = delegate;
    this.rnComponentContext = delegate.rnComponentContext;
    this.tag = delegate.tag;
    this.componentName = delegate.componentName;
    this.nativeView = nativeView;
  }

  emit(eventName: string, payload: ESObject = {}): void {
    this.delegate.emit(eventName, payload);
  }

  setShadowNodeSize(width: number, height: number): void {
    this.delegate.setShadowNodeSize(width, height);
  }

  setStyleSize(width: number, height: number): void {
    this.delegate.setStyleSize(width, height);
  }
}

/** @internal Runtime adapter produced by an ArkTS ExpoViewDefinition. */
export interface ExpoViewAdapter {
  readonly componentName: string;
  readonly runtimeEpoch?: string;
  readonly group?: boolean;
  readonly content?: WrappedBuilder<[ExpoViewContentContext]>;
  create(rnComponentContext: RNComponentContext, tag: number, componentName: string): ESObject;
  createContentContext(view: ESObject): ExpoViewContentContext;
  contentValue?(view: ESObject): ESObject;
  updateProps(view: ESObject, props: Record<string, ESObject>): void;
  receiveCommand?(view: ESObject, commandName: string, args: ESObject[]): void;
  invokeAsync?(view: ESObject, functionName: string, args: ESObject[]): Promise<ESObject | void>;
  destroy?(view: ESObject): void;
}

interface BoundExpoView {
  adapter: ExpoViewAdapter;
  componentName: string;
  view: ESObject;
  committedPropsRevision: number;
  propsFailure?: ExpoViewPropsFailure;
  propsWaiters: Set<ExpoViewPropsWaiter>;
}

interface ExpoViewPropsFailure {
  readonly revision?: number;
  readonly error: Error;
}

class ExpoViewPropsWaiter {
  readonly revision: number;
  private readonly resolveBody: () => void;
  private readonly rejectBody: (error: Error) => void;

  constructor(revision: number, resolve: () => void, reject: (error: Error) => void) {
    this.revision = revision;
    this.resolveBody = resolve;
    this.rejectBody = reject;
  }

  resolve(): void {
    this.resolveBody();
  }

  reject(error: Error): void {
    this.rejectBody(error);
  }
}

interface ScopedExpoViewAdapter {
  runtimeEpoch: string;
  adapter: ExpoViewAdapter;
}

/** Runtime-scoped registry for ArkUI adapters. */
export class ExpoViewAdapterRegistry {
  private static readonly scopedAdapters: Map<number, Map<string, ScopedExpoViewAdapter[]>> = new Map();
  private static readonly boundViewsByInstance: Map<number, Map<number, BoundExpoView>> = new Map();

  /** @internal Registers one ArkTS ModuleDefinition adapter for one RN instance. */
  static registerForRuntime(instanceId: number, runtimeEpoch: string, adapter: ExpoViewAdapter, aliases: string[] = []): () => void {
    const componentNames: string[] = [adapter.componentName, ...aliases];
    const uniqueNames: Set<string> = new Set<string>();
    componentNames.forEach((componentName: string): void => {
      requireExpoComponentName(componentName);

      if (uniqueNames.has(componentName)) {
        throw new Error(`Expo component '${componentName}' was registered twice as the same View.`);
      }

      uniqueNames.add(componentName);
    });

    if (runtimeEpoch.length === 0) throw new Error('Expo view runtime epoch cannot be empty.');

    let adapters = ExpoViewAdapterRegistry.scopedAdapters.get(instanceId);
    if (adapters === undefined) {
      adapters = new Map<string, ScopedExpoViewAdapter[]>();
      ExpoViewAdapterRegistry.scopedAdapters.set(instanceId, adapters);
    }

    componentNames.forEach((componentName: string): void => {
      const registrations = adapters?.get(componentName);
      if (registrations?.some((entry: ScopedExpoViewAdapter): boolean => entry.runtimeEpoch === runtimeEpoch)) {
        throw new Error(`Expo component '${componentName}' was registered twice for runtime ${runtimeEpoch}.`);
      }
    });

    const registration: ScopedExpoViewAdapter = { runtimeEpoch, adapter };
    componentNames.forEach((componentName: string): void => {
      let registrations = adapters?.get(componentName);
      if (registrations === undefined) {
        registrations = [];
        adapters?.set(componentName, registrations);
      }
      registrations.push(registration);
    });

    return (): void => {
      const current = ExpoViewAdapterRegistry.scopedAdapters.get(instanceId);
      componentNames.forEach((componentName: string): void => {
        const currentRegistrations = current?.get(componentName);
        if (currentRegistrations === undefined) return;
        const index = currentRegistrations.indexOf(registration);
        if (index < 0) return;

        currentRegistrations.splice(index, 1);
        if (currentRegistrations.length === 0) current?.delete(componentName);
      });
      if (current !== undefined && current.size === 0) {
        ExpoViewAdapterRegistry.scopedAdapters.delete(instanceId);
      }
    };
  }

  static require(instanceId: number, componentName: string): ExpoViewAdapter {
    const registrations = ExpoViewAdapterRegistry.scopedAdapters.get(instanceId)?.get(componentName);
    const adapter = registrations !== undefined && registrations.length > 0 ? registrations[registrations.length - 1].adapter : undefined;
    if (adapter === undefined) {
      throw new Error(`No ArkUI adapter is registered for '${componentName}' in RN instance ${instanceId}.`);
    }

    return adapter;
  }

  static names(): string[] {
    return [EXPO_MODULES_CORE_VIEW_COMPONENT_NAME];
  }

  static bind(instanceId: number, tag: number, componentName: string, adapter: ExpoViewAdapter, view: ESObject): void {
    let boundViews = ExpoViewAdapterRegistry.boundViewsByInstance.get(instanceId);
    if (boundViews === undefined) {
      boundViews = new Map();
      ExpoViewAdapterRegistry.boundViewsByInstance.set(instanceId, boundViews);
    }

    if (boundViews.has(tag)) {
      throw new Error(`Expo view tag ${tag} is already bound in RN instance ${instanceId}.`);
    }

    boundViews.set(tag, {
      adapter,
      componentName,
      view,
      committedPropsRevision: 0,
      propsFailure: undefined,
      propsWaiters: new Set<ExpoViewPropsWaiter>(),
    });
  }

  static markPropsCommitted(instanceId: number, tag: number, componentName: string, revision: number): void {
    if (!Number.isSafeInteger(revision) || revision <= 0) {
      throw new Error(`ERR_INVALID_VIEW_REVISION: Expo view tag ${tag} received invalid props revision ${revision}.`);
    }

    const bound = ExpoViewAdapterRegistry.requireBoundView(instanceId, tag, componentName);
    if (revision <= bound.committedPropsRevision) return;

    bound.committedPropsRevision = revision;
    if (bound.propsFailure !== undefined && (bound.propsFailure.revision === undefined || bound.propsFailure.revision <= revision)) {
      bound.propsFailure = undefined;
    }

    const ready: ExpoViewPropsWaiter[] = [];
    bound.propsWaiters.forEach((waiter: ExpoViewPropsWaiter): void => {
      if (waiter.revision <= revision) ready.push(waiter);
    });

    ready.forEach((waiter: ExpoViewPropsWaiter): void => {
      bound.propsWaiters.delete(waiter);
      waiter.resolve();
    });
  }

  static markPropsFailed(instanceId: number, tag: number, componentName: string, revision: number | undefined, error: Error): void {
    const bound = ExpoViewAdapterRegistry.requireBoundView(instanceId, tag, componentName);
    if (revision !== undefined && (!Number.isSafeInteger(revision) || revision <= 0)) {
      revision = undefined;
    }

    bound.propsFailure = { revision, error };

    const failed: ExpoViewPropsWaiter[] = [];
    bound.propsWaiters.forEach((waiter: ExpoViewPropsWaiter): void => {
      if (revision === undefined || waiter.revision <= revision) failed.push(waiter);
    });

    failed.forEach((waiter: ExpoViewPropsWaiter): void => {
      bound.propsWaiters.delete(waiter);
      waiter.reject(error);
    });
  }

  static destroyBoundView(instanceId: number, tag: number): boolean {
    const boundViews = ExpoViewAdapterRegistry.boundViewsByInstance.get(instanceId);
    if (boundViews === undefined) return false;

    const bound = boundViews.get(tag);
    if (bound === undefined) return false;

    // Detach before invoking adapter cleanup.
    boundViews.delete(tag);
    if (boundViews.size === 0) ExpoViewAdapterRegistry.boundViewsByInstance.delete(instanceId);
    ExpoViewAdapterRegistry.rejectPropsWaiters(bound, tag);

    try {
      bound.adapter.destroy?.(bound.view);
    } catch (error) {
      reportAdapterDestroyFailure(bound.adapter.componentName, tag, error);
    }

    return true;
  }

  static destroyInstance(instanceId: number): void {
    const boundViews = ExpoViewAdapterRegistry.boundViewsByInstance.get(instanceId);
    if (boundViews === undefined) return;

    // Detach the instance before invoking author cleanup.
    ExpoViewAdapterRegistry.boundViewsByInstance.delete(instanceId);
    const views = Array.from(boundViews.entries());
    boundViews.clear();

    for (let index = views.length - 1; index >= 0; --index) {
      const tag = views[index][0];
      const bound = views[index][1];
      ExpoViewAdapterRegistry.rejectPropsWaiters(bound, tag);
      try {
        bound.adapter.destroy?.(bound.view);
      } catch (error) {
        reportAdapterDestroyFailure(bound.adapter.componentName, tag, error);
      }
    }
  }

  static destroyRuntime(instanceId: number, runtimeEpoch: string): void {
    const boundViews = ExpoViewAdapterRegistry.boundViewsByInstance.get(instanceId);
    if (boundViews === undefined) return;

    const tags: number[] = [];
    boundViews.forEach((bound: BoundExpoView, tag: number): void => {
      if (bound.adapter.runtimeEpoch === runtimeEpoch) tags.push(tag);
    });

    for (let index = tags.length - 1; index >= 0; --index) {
      ExpoViewAdapterRegistry.destroyBoundView(instanceId, tags[index]);
    }
  }

  static async invokeAsync(
    instanceId: number,
    runtimeEpoch: string,
    tag: number,
    componentName: string,
    propsRevision: number,
    functionName: string,
    args: ESObject[],
  ): Promise<ESObject | void> {
    const bound = ExpoViewAdapterRegistry.requireBoundView(instanceId, tag, componentName);

    if (bound.adapter.runtimeEpoch !== undefined && bound.adapter.runtimeEpoch !== runtimeEpoch) {
      throw new Error(`ERR_VIEW_RUNTIME_MISMATCH: Expo view tag ${tag} belongs to runtime ${bound.adapter.runtimeEpoch}, not ${runtimeEpoch}.`);
    }

    if (bound.adapter.invokeAsync === undefined) {
      throw new Error(`ERR_UNKNOWN_VIEW_FUNCTION: '${componentName}' does not expose async view functions.`);
    }

    await ExpoViewAdapterRegistry.waitForProps(bound, propsRevision, tag);

    const current = ExpoViewAdapterRegistry.requireBoundView(instanceId, tag, componentName);
    if (current !== bound) {
      throw new Error(`ERR_VIEW_NOT_MOUNTED: Expo view tag ${tag} was replaced before invocation.`);
    }

    return await bound.adapter.invokeAsync(bound.view, functionName, args);
  }

  /** @internal Controlled AppContext lookup for an author-owned mounted View. */
  static findContent(instanceId: number, runtimeEpoch: string, tag: number, componentName?: string): ESObject | undefined {
    const bound = ExpoViewAdapterRegistry.boundViewsByInstance.get(instanceId)?.get(tag);
    if (bound === undefined || bound.adapter.runtimeEpoch !== runtimeEpoch) {
      return undefined;
    }
    if (componentName !== undefined && bound.componentName !== componentName) {
      return undefined;
    }

    if (bound.adapter.contentValue === undefined) {
      return undefined;
    }

    return bound.adapter.contentValue(bound.view);
  }

  static dispatchCommand(instanceId: number, tag: number, componentName: string, commandName: string, args: ESObject[]): void {
    const bound = ExpoViewAdapterRegistry.requireBoundView(instanceId, tag, componentName);

    if (bound.adapter.receiveCommand === undefined) {
      throw new Error(`ERR_UNKNOWN_VIEW_COMMAND: '${componentName}' does not expose view commands.`);
    }

    bound.adapter.receiveCommand(bound.view, commandName, args);
  }

  private static requireBoundView(instanceId: number, tag: number, componentName: string): BoundExpoView {
    const bound = ExpoViewAdapterRegistry.boundViewsByInstance.get(instanceId)?.get(tag);
    if (bound === undefined) {
      throw new Error(`ERR_VIEW_NOT_MOUNTED: Expo view tag ${tag} is not mounted in RN instance ${instanceId}.`);
    }

    if (bound.componentName !== componentName) {
      throw new Error(`ERR_VIEW_COMPONENT_MISMATCH: Expo view tag ${tag} belongs to '${bound.componentName}', not '${componentName}'.`);
    }

    return bound;
  }

  private static async waitForProps(bound: BoundExpoView, revision: number, tag: number): Promise<void> {
    if (!Number.isSafeInteger(revision) || revision <= 0) {
      throw new Error(`ERR_INVALID_VIEW_REVISION: Expo view tag ${tag} received invalid props revision ${revision}.`);
    }

    if (bound.committedPropsRevision >= revision) return;

    if (bound.propsFailure !== undefined && (bound.propsFailure.revision === undefined || revision <= bound.propsFailure.revision)) {
      throw bound.propsFailure.error;
    }

    await new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
      bound.propsWaiters.add(new ExpoViewPropsWaiter(revision, resolve, reject));
    });
  }

  private static rejectPropsWaiters(bound: BoundExpoView, tag: number): void {
    bound.propsWaiters.forEach((waiter: ExpoViewPropsWaiter): void => {
      waiter.reject(new Error(`ERR_VIEW_NOT_MOUNTED: Expo view tag ${tag} was unmounted before its props committed.`));
    });

    bound.propsWaiters.clear();
  }
}

export function requireExpoViewSize(width: number, height: number, operation: string): void {
  if (typeof width !== 'number' || typeof height !== 'number' || !Number.isFinite(width) || !Number.isFinite(height) || width < 0 || height < 0) {
    throw new Error(`${operation} requires finite, non-negative dimensions; received ${width} x ${height}.`);
  }
}

function requireExpoComponentName(componentName: string): void {
  if (!componentName.startsWith('ViewManagerAdapter_')) {
    throw new Error(`Expo component '${componentName}' must use the ViewManagerAdapter_ prefix.`);
  }
}

function reportAdapterDestroyFailure(componentName: string, tag: number, error: Object): void {
  let message = 'unknown error';
  try {
    message = String(error);
  } catch (_) {}

  try {
    console.error(`Expo View adapter '${componentName}' failed to destroy tag ${tag}: ${message}`);
  } catch (_) {}
}

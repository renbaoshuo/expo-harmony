import type { RNComponentContext } from '@rnoh/react-native-openharmony';

export class ExpoViewContentContext {
  readonly rnComponentContext: RNComponentContext;
  readonly tag: number;
  readonly componentName: string;
  readonly nativeView: ESObject;
  private sizeState: ExpoViewSizeState = {};

  constructor(rnComponentContext: RNComponentContext, tag: number, componentName: string, nativeView: ESObject) {
    this.rnComponentContext = rnComponentContext;
    this.tag = tag;
    this.componentName = componentName;
    this.nativeView = nativeView;
  }

  emit(eventName: string, payload: ESObject = {}): void {
    this.rnComponentContext.rnInstance.emitComponentEvent(this.tag, eventName, payload);
  }

  setShadowNodeSize(width: number, height: number): void {
    this.sizeState.width = width;
    this.sizeState.height = height;
    this.rnComponentContext.descriptorRegistry.setState(this.tag, this.sizeState);
  }

  setStyleSize(width: number, height: number): void {
    this.sizeState.styleWidth = width;
    this.sizeState.styleHeight = height;
    this.rnComponentContext.descriptorRegistry.setState(this.tag, this.sizeState);
  }
}

interface ExpoViewSizeState {
  width?: number;
  height?: number;
  styleWidth?: number;
  styleHeight?: number;
}

export interface ExpoViewAdapter {
  readonly componentName: string;
  readonly group?: boolean;
  readonly content?: WrappedBuilder<[ExpoViewContentContext]>;
  create(rnComponentContext: RNComponentContext, tag: number, componentName: string): ESObject;
  updateProps(view: ESObject, props: Record<string, ESObject>): void;
  receiveCommand?(view: ESObject, commandName: string, args: ESObject[]): void;
  destroy?(view: ESObject): void;
}

interface BoundExpoView {
  adapter: ExpoViewAdapter;
  view: ESObject;
}

/**
 * Static ArkUI adapter registry. Autolinking-generated ArkTS imports call
 * register() before RNOH asks ExpoModulesCorePackage for wrapped builders.
 */
export class ExpoViewAdapterRegistry {
  private static readonly adapters: Map<string, ExpoViewAdapter> = new Map();
  private static readonly boundViewsByInstance: Map<number, Map<number, BoundExpoView>> = new Map();

  static register(adapter: ExpoViewAdapter): () => void {
    if (!adapter.componentName.startsWith('ViewManagerAdapter_')) {
      throw new Error(`Expo component '${adapter.componentName}' must use the ViewManagerAdapter_ prefix.`);
    }
    if (ExpoViewAdapterRegistry.adapters.has(adapter.componentName)) {
      throw new Error(`Expo component '${adapter.componentName}' was registered twice.`);
    }
    ExpoViewAdapterRegistry.adapters.set(adapter.componentName, adapter);
    return (): void => {
      if (ExpoViewAdapterRegistry.adapters.get(adapter.componentName) === adapter) {
        ExpoViewAdapterRegistry.adapters.delete(adapter.componentName);
      }
    };
  }

  static require(componentName: string): ExpoViewAdapter {
    const adapter = ExpoViewAdapterRegistry.adapters.get(componentName);
    if (adapter === undefined) {
      throw new Error(`No ArkUI adapter is registered for '${componentName}'.`);
    }
    return adapter;
  }

  static names(): string[] {
    return Array.from(ExpoViewAdapterRegistry.adapters.keys());
  }

  static bind(instanceId: number, tag: number, adapter: ExpoViewAdapter, view: ESObject): void {
    let boundViews = ExpoViewAdapterRegistry.boundViewsByInstance.get(instanceId);
    if (boundViews === undefined) {
      boundViews = new Map();
      ExpoViewAdapterRegistry.boundViewsByInstance.set(instanceId, boundViews);
    }
    if (boundViews.has(tag)) {
      throw new Error(`Expo view tag ${tag} is already bound in RN instance ${instanceId}.`);
    }
    boundViews.set(tag, { adapter, view });
  }

  static unbind(instanceId: number, tag: number): void {
    const boundViews = ExpoViewAdapterRegistry.boundViewsByInstance.get(instanceId);
    if (boundViews === undefined) return;
    boundViews.delete(tag);
    if (boundViews.size === 0) ExpoViewAdapterRegistry.boundViewsByInstance.delete(instanceId);
  }

  static dispatchCommand(instanceId: number, tag: number, commandName: string, args: ESObject[]): void {
    const bound = ExpoViewAdapterRegistry.boundViewsByInstance.get(instanceId)?.get(tag);
    if (bound === undefined) return;
    bound.adapter.receiveCommand?.(bound.view, commandName, args);
  }
}

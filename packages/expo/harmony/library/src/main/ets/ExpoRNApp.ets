/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoReactRootViewFactory } from './ExpoReactRootViewFactory';
import { ExpoReactHost } from './ExpoReactHost';
import { JSBundleProvider, RNApp, RNInstance, RNOHCoreContext, RNOHError } from '@rnoh/react-native-openharmony';
import type { RNInstanceConfig } from '@rnoh/react-native-openharmony/src/main/ets/RNApp';
import type { WrappedCustomRNComponentBuilder } from '@rnoh/react-native-openharmony/src/main/ets/RNOH';
import {
  ReactNativeRuntime,
  ReactRuntimeListener,
  ExpoModuleError,
  ReactRootViewBuilder,
  ReactRootViewContext,
  ReactActivityHandler,
} from '@expo-harmony/expo-modules-core';

interface ExpoUnmanagedRNInstanceConfig {
  rnInstance: RNInstance;
}

class ExpoRootGestureModifier implements GestureModifier {
  private handlers: ReactActivityHandler[];
  private context: ReactRootViewContext;
  constructor(handlers: ReactActivityHandler[], context: ReactRootViewContext) {
    this.handlers = handlers;
    this.context = context;
  }
  applyGesture(event: UIGestureEvent): void {
    event.clearGestures();
    this.handlers.forEach((handler: ReactActivityHandler): void => handler.applyRootViewGestures?.(this.context, event));
  }
}

export type ExpoRNInstanceReplacement = (reason: string) => Promise<RNInstance>;
@Builder
export function buildExpoDefaultRoot(context: ReactRootViewContext): void {
  if (context.ready) {
    RNApp({
      rnInstanceConfig: context.instanceConfig,
      appKey: context.appKey,
      initialProps: context.initialProps,
      jsBundleProvider: context.jsBundleProvider,
      wrappedCustomRNComponentBuilder: context.wrappedCustomRNComponentBuilder,
      onSetUp: context.onSetUp,
    });
  }
}

@Component
struct ExpoReactRootView {
  @Require public builder!: ReactRootViewBuilder;
  @Require public context!: ReactRootViewContext;
  @Prop public ready: boolean = false;
  public handlers: ReactActivityHandler[] = [];
  private readonly rootToken: Object = new Object();

  aboutToAppear(): void {
    this.handlers.forEach((handler: ReactActivityHandler): void => handler.onRootViewMounted?.(this.context, this.getUIContext(), this.rootToken));
  }

  aboutToDisappear(): void {
    this.handlers.forEach((handler: ReactActivityHandler): void => handler.onRootViewUnmounted?.(this.context, this.rootToken));
  }

  build(): void {
    // Keep this literal at the call site so ArkUI tracks ready changes.
    this.builder.builder({
      owner: this.context.owner,
      core: this.context.core,
      host: this.context.host,
      instanceConfig: this.context.instanceConfig,
      appKey: this.context.appKey,
      initialProps: this.context.initialProps,
      jsBundleProvider: this.context.jsBundleProvider,
      wrappedCustomRNComponentBuilder: this.context.wrappedCustomRNComponentBuilder,
      onSetUp: this.context.onSetUp,
      ready: this.ready,
      isCustomRoot: this.context.isCustomRoot,
      defaultRoot: this.context.defaultRoot,
    });
  }
}
class AppRootViewContext implements ReactRootViewContext {
  readonly owner: Object;
  readonly core: RNOHCoreContext;
  readonly host: ExpoReactHost;
  readonly instanceConfig: RNInstanceConfig;
  readonly appKey: string;
  readonly initialProps: Record<string, string>;
  readonly jsBundleProvider: JSBundleProvider | undefined;
  readonly wrappedCustomRNComponentBuilder: WrappedCustomRNComponentBuilder | undefined;
  readonly onSetUp: (instance: RNInstance) => Promise<void> | void;
  readonly ready: boolean;
  readonly isCustomRoot: boolean | undefined;
  readonly defaultRoot: WrappedBuilder<[ReactRootViewContext]>;

  constructor(
    owner: Object,
    core: RNOHCoreContext,
    host: ExpoReactHost,
    instanceConfig: RNInstanceConfig,
    appKey: string,
    initialProps: Record<string, string>,
    jsBundleProvider: JSBundleProvider | undefined,
    wrappedCustomRNComponentBuilder: WrappedCustomRNComponentBuilder | undefined,
    ready: boolean,
    isCustomRoot: boolean | undefined,
    defaultRoot: WrappedBuilder<[ReactRootViewContext]>,
  ) {
    this.owner = owner;
    this.core = core;
    this.host = host;
    this.instanceConfig = instanceConfig;
    this.appKey = appKey;
    this.initialProps = initialProps;
    this.jsBundleProvider = jsBundleProvider;
    this.wrappedCustomRNComponentBuilder = wrappedCustomRNComponentBuilder;
    this.onSetUp = (): void => {};
    this.ready = ready;
    this.isCustomRoot = isCustomRoot;
    this.defaultRoot = defaultRoot;
  }
}
@Component
export struct ExpoRNApp {
  @Require public rnInstanceConfig: RNInstanceConfig;
  @Require public appKey: string = '';
  @Require public reactHost: ExpoReactHost;
  public initialProps: Record<string, string> = {};
  public jsBundleProvider: JSBundleProvider | undefined = undefined;
  public wrappedCustomRNComponentBuilder: WrappedCustomRNComponentBuilder | undefined = undefined;
  public rootViewBuilder: ReactRootViewBuilder | undefined = undefined;
  public onDelayLoadError: ((error: Object) => void) | undefined = undefined;
  public onSetUp: (rnInstance: RNInstance) => Promise<void> | void = (): void => {};
  public replaceRNInstance: ExpoRNInstanceReplacement | undefined = undefined;
  @StorageLink('RNOHCoreContext') private core?: RNOHCoreContext = undefined;
  @State private generation: number = 0;
  @State private rootPrepared: boolean = false;
  @State private ready: boolean = false;
  private instance: RNInstance | undefined = undefined;
  private runtime: ReactNativeRuntime | undefined = undefined;
  private unregister: (() => void) | undefined = undefined;
  private mounted: boolean = false;
  private preparationSerial: number = 0;
  private selectedRoot: ReactRootViewBuilder | undefined = undefined;
  private activityHandlers: ReactActivityHandler[] = [];

  aboutToAppear(): void {
    this.mounted = true;
    this.prepareRoot();
  }

  private async prepareRoot(): Promise<void> {
    const serial = ++this.preparationSerial;
    if (this.core === undefined) {
      this.reportDelayError(new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'The RNOH context is not available.') as Object);
      return;
    }

    const context: ReactRootViewContext = this.rootContext(false);

    try {
      const handlers: ReactActivityHandler[] = this.reactHost.activityHandlers
        .map((registration) => registration.create(context.core.uiAbilityContext))
        .sort((left, right) => (right.priority ?? 0) - (left.priority ?? 0));
      this.activityHandlers = handlers;
      this.selectedRoot = this.rootViewBuilder ?? ExpoReactRootViewFactory.create(handlers, context);
      this.rootPrepared = true;

      const delay = ExpoReactRootViewFactory.getDelayLoadAppHandler(handlers, context);
      if (delay !== undefined) await delay;
      if (!this.mounted || serial !== this.preparationSerial) return;

      const runtime = this.reactHost.createRuntime(context.core, this.rnInstanceConfig, this.jsBundleProvider, this.replaceRNInstance);
      this.runtime = runtime;
      const listener: ReactRuntimeListener = {
        prepare: async (instance: RNInstance): Promise<void> => {
          if (this.mounted && serial === this.preparationSerial) await this.onSetUp(instance);
        },
        changed: (instance: RNInstance | undefined): void => {
          if (!this.mounted || serial !== this.preparationSerial) return;
          this.instance = instance;
          this.ready = instance !== undefined;
          this.generation += 1;
        },
        failed: (error: Error): void => {
          if (this.mounted && serial === this.preparationSerial) this.reportDelayError(error as Object);
        },
      };

      this.unregister = runtime.subscribe(listener);
      await runtime.start().catch((): void => {});
    } catch (error) {
      if (this.mounted && serial === this.preparationSerial) this.reportDelayError(error as Object);
    }
  }

  private reportDelayError(error: Object): void {
    const callback = this.onDelayLoadError;
    if (callback !== undefined) callback(error);
    else if (this.core !== undefined) {
      this.core.reportRNOHError(
        new RNOHError({
          whatHappened: 'Unable to prepare the Expo React root.',
          howCanItBeFixed: [],
          extraData: error,
        }),
      );
    } else {
      console.error(`Unable to prepare the Expo React root: ${String(error)}`);
    }
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.preparationSerial += 1;
    this.rootPrepared = false;
    this.ready = false;

    this.unregister?.();
    this.unregister = undefined;
    this.runtime = undefined;
    this.instance = undefined;
  }

  private rootContext(ready: boolean): ReactRootViewContext {
    if (this.core === undefined) throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'The RNOH context is not available.');
    return new AppRootViewContext(
      this,
      this.core,
      this.reactHost,
      this.instanceConfig(),
      this.appKey,
      this.initialProps,
      this.runtime?.bundle ?? this.jsBundleProvider,
      this.wrappedCustomRNComponentBuilder,
      ready,
      this.selectedRoot !== undefined,
      wrapBuilder(buildExpoDefaultRoot),
    );
  }

  private instanceConfig(): RNInstanceConfig {
    if (this.instance !== undefined) {
      const config: ExpoUnmanagedRNInstanceConfig = { rnInstance: this.instance };
      return config;
    }
    return this.rnInstanceConfig;
  }

  @Builder
  private renderRoot(): void {
    if (this.selectedRoot !== undefined) {
      ExpoReactRootView({ builder: this.selectedRoot, context: this.rootContext(this.ready), ready: this.ready, handlers: this.activityHandlers });
    } else {
      ExpoReactRootView({
        builder: wrapBuilder(buildExpoDefaultRoot),
        context: this.rootContext(this.ready),
        ready: this.ready,
        handlers: this.activityHandlers,
      });
    }
  }

  build(): void {
    Stack() {
      if (this.rootPrepared && this.core !== undefined) {
        Stack() {
          ForEach(
            [this.generation],
            (_generation: number): void => this.renderRoot(),
            (generation: number): string => `${generation}`,
          )
        }
        .width('100%')
        .height('100%')
        .gestureModifier(new ExpoRootGestureModifier(this.activityHandlers, this.rootContext(this.ready)))
        .onKeyEvent((event: KeyEvent): void => {
          for (const handler of this.activityHandlers) {
            if (handler.onRootViewKeyEvent?.(this.rootContext(this.ready), event)) {
              event.stopPropagation();
              return;
            }
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

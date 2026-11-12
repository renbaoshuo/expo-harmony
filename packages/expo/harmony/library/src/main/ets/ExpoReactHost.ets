/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoReactHostDelegate } from './ExpoReactHostDelegate';
import {
  AppLoaderProvider,
  ExpoModuleError,
  ExpoReloadRegistry,
  HeadlessAppLoaderDelegate,
  ReactActivityHandlerRegistration,
  ReactRuntimeContext,
  ReactNativeRuntime,
  RnohReactRuntime,
  RnohReactRuntimeOptions,
  RNHeadlessAppLoader,
  RnohContextLifecycle,
  observeRnohDestroy,
} from '@expo-harmony/expo-modules-core';
import { bundleManager, common } from '@kit.AbilityKit';
import { JSBundleProvider, MetroJSBundleProvider, RNInstance, RNInstanceOptions, RNOHCoreContext } from '@rnoh/react-native-openharmony';
import { ExpoJSBundleProvider, ExpoResourceBundle } from './ExpoJSBundleProvider';
import { withDeveloperSupport } from './ExpoRNInstanceOptions';
import type { RNInstanceConfig } from '@rnoh/react-native-openharmony/src/main/ets/RNApp';
import type { ExpoHarmonyHostProvider } from './ExpoModulesPackage';

export interface ExpoReactHostOptions {
  bundlePath: string;
  workerScriptUrl: string;
  provider: ExpoHarmonyHostProvider;
  createRNInstanceOptions: (headless: boolean) => RNInstanceOptions;
}

interface SuppliedRuntime {
  rnInstance?: RNInstance;
}

interface HostRuntime {
  core: RNOHCoreContext;
  family: Object;
  ready: Promise<void>;
  cleanup?: () => void;
  destroyed: boolean;
  released: boolean;
  ui: boolean;
}

export class ExpoReactHost {
  private static readonly hosts: Map<string, ExpoReactHost> = new Map();
  private static readonly abilities: Set<common.UIAbilityContext> = new Set();
  private readonly options: ExpoReactHostOptions;
  private readonly delegate: ExpoReactHostDelegate;
  private owner?: string;
  private readonly runtimes = new Set<RNInstance>();
  private readonly managed = new WeakMap<RNOHCoreContext, ReactNativeRuntime>();
  private readonly owners = new WeakMap<RNInstance, ReactNativeRuntime>();
  private readonly records = new WeakMap<RNInstance, HostRuntime>();
  private readonly families = new WeakMap<Object, Object>();
  private debug: boolean = false;
  private readonly loader: RNHeadlessAppLoader;

  constructor(options: ExpoReactHostOptions) {
    if (options.bundlePath.length === 0 || options.workerScriptUrl.length === 0) {
      throw new ExpoModuleError('ERR_REACT_HOST_CONFIG', 'A React host requires its application bundle path and worker script.');
    }

    this.options = options;
    this.delegate = new ExpoReactHostDelegate(options.provider.reactNativeHostHandlers, options.provider.runtimeBindings);
    this.loader = new RNHeadlessAppLoader(
      new HostLoaderDelegate(
        options.workerScriptUrl,
        (): boolean => this.isAvailable(),
        (): ReactNativeRuntime | undefined => {
          for (const instance of this.runtimes) {
            const runtime = this.owners.get(instance);
            if (runtime !== undefined) return runtime;
          }
          return undefined;
        },
        (context: common.UIAbilityContext): boolean => ExpoReactHost.hasOtherOwner(context),
        (core: RNOHCoreContext, context: common.Context): ReactNativeRuntime =>
          this.runtime(core, this.createRNInstanceOptions(true), (): JSBundleProvider => this.createJSBundleProvider(context, this.debug), false),
        (context: common.UIAbilityContext): void => this.options.provider.hostState.beginAbility(context, {}),
        (context: common.UIAbilityContext): void => this.options.provider.hostState.finishAbility(context),
      ),
    );
  }

  initialize(context: common.Context): void {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const owner = info.name;
    const existing = ExpoReactHost.hosts.get(owner);
    if (existing !== undefined && existing !== this) {
      throw new ExpoModuleError('ERR_REACT_HOST_CONFIG', `A React host is already registered for '${owner}'.`);
    }
    if (existing === this) return;

    this.debug = info.appInfo.debug;
    this.delegate.initialize(context, this, this.debug);
    this.debug = this.delegate.useDeveloperSupport(this.debug);
    AppLoaderProvider.registerLoader(AppLoaderProvider.reactNative, this.loader);
    ExpoReactHost.hosts.set(owner, this);
    this.owner = owner;
  }

  static get(owner: string): ExpoReactHost | undefined {
    return ExpoReactHost.hosts.get(owner);
  }

  static attachAbility(context: common.UIAbilityContext): void {
    ExpoReactHost.abilities.add(context);
  }

  static detachAbility(context: common.UIAbilityContext): void {
    ExpoReactHost.abilities.delete(context);
  }

  static hasOtherOwner(context: common.UIAbilityContext): boolean {
    for (const ability of ExpoReactHost.abilities) {
      if (ability !== context) return true;
    }
    for (const host of ExpoReactHost.hosts.values()) {
      if (host.loader.active) return true;
    }

    return false;
  }

  isAvailable(): boolean {
    return this.owner !== undefined;
  }

  createRNInstanceOptions(headless: boolean = false): RNInstanceOptions {
    const options = this.options.createRNInstanceOptions(headless);
    return withDeveloperSupport(options, this.delegate.useDeveloperSupport(options.enableDebugger ?? this.debug));
  }

  createJSBundleProvider(context: common.Context, debug: boolean = false): JSBundleProvider {
    const embedded = this.createEmbeddedJSBundleProvider(context);
    const development = this.delegate.useDeveloperSupport(debug);
    const fallback: JSBundleProvider = development ? new MetroJSBundleProvider() : embedded;

    return new ExpoJSBundleProvider(context, fallback, this.delegate, development);
  }

  createEmbeddedJSBundleProvider(context: common.Context): JSBundleProvider {
    return new ExpoResourceBundle(context, this.options.bundlePath);
  }

  hasEmbeddedJSBundle(context: common.Context): boolean {
    try {
      const path = this.options.bundlePath;
      const separator = path.lastIndexOf('/');
      const directory = separator < 0 ? '' : path.slice(0, separator);
      return context.resourceManager.getRawFileListSync(directory).includes(path.slice(separator + 1));
    } catch (_error) {
      return false;
    }
  }

  createRuntime(
    core: RNOHCoreContext,
    config: RNInstanceConfig,
    bundle?: JSBundleProvider,
    replace?: (reason: string) => Promise<RNInstance>,
  ): ReactNativeRuntime {
    const supplied = config as SuppliedRuntime;
    if (supplied.rnInstance !== undefined) {
      const existing = this.owners.get(supplied.rnInstance);
      if (existing !== undefined) {
        if (existing.instance !== supplied.rnInstance)
          throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'The supplied instance has already been replaced or destroyed.');
        if (existing.core !== core) throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'A root cannot bind an instance from another coordinator.');
        return existing;
      }

      return this.runtime(core, supplied.rnInstance, bundle === undefined ? undefined : (): JSBundleProvider => bundle, true, replace);
    }
    if (replace !== undefined)
      throw new ExpoModuleError('ERR_RELOAD_HOST_REPLACEMENT', 'replaceRNInstance requires an unmanaged rnInstance configuration.');

    let runtime = this.managed.get(core);
    if (runtime === undefined) {
      runtime = this.runtime(
        core,
        config as RNInstanceOptions,
        (): JSBundleProvider => bundle ?? this.createJSBundleProvider(core.uiAbilityContext, this.debug),
        true,
      );
      this.managed.set(core, runtime);
    }

    return runtime;
  }

  private runtime(
    core: RNOHCoreContext,
    source: RNInstanceOptions | RNInstance,
    bundle: (() => JSBundleProvider) | undefined,
    ui: boolean,
    replace?: (reason: string) => Promise<RNInstance>,
  ): ReactNativeRuntime {
    const external = typeof (source as RNInstance).getId === 'function';
    const runtime = new RnohReactRuntime(
      core,
      new HostRuntimeOptions(
        external
          ? undefined
          : (): RNInstanceOptions => {
              const options = source as RNInstanceOptions;
              // Resolve after the launcher's selection gate, on every reload as well.
              return withDeveloperSupport(options, this.delegate.useDeveloperSupport(options.enableDebugger ?? this.debug));
            },
        external ? (source as RNInstance) : undefined,
        replace,
        bundle,
        async (instance: RNInstance): Promise<void> => {
          this.owners.set(instance, runtime);
          await this.prepareRuntime(instance, core, runtime, ui);
        },
      ),
    );
    if (external) this.owners.set(source as RNInstance, runtime);

    return runtime;
  }

  async prepareRuntime(instance: RNInstance, core: RNOHCoreContext, owner: Object, ui: boolean = owner !== this): Promise<void> {
    let record = this.records.get(instance);
    if (record !== undefined && (record.core !== core || record.destroyed)) {
      throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'The React instance belongs to another or destroyed RNOH context.');
    }

    if (record === undefined) record = this.prepareInstance(instance, core, owner, ui);
    else this.families.set(owner, record.family);
    if (ui) record.ui = true;

    try {
      await record.ready;
      if (record.destroyed) throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'The React instance was destroyed while preparing its host.');
      if (record.ui) this.runtimes.add(instance);
    } catch (error) {
      throw new ExpoModuleError('ERR_REACT_HOST_BIND', 'Unable to prepare the React runtime.', error as Object);
    }
  }

  private prepareInstance(instance: RNInstance, core: RNOHCoreContext, owner: Object, ui: boolean): HostRuntime {
    let family = this.families.get(owner);
    if (family === undefined) {
      family = new Object();
      this.families.set(owner, family);
    }
    const record: HostRuntime = { core, family, ready: Promise.resolve(), destroyed: false, released: false, ui };
    const lifetime = RnohContextLifecycle.install(core);
    const runtime = this.owners.get(instance);
    const context: ReactRuntimeContext = {
      instance,
      host: this,
      core,
      owner: family,
      isHeadless: !ui,
      getJSBundleProvider: (): JSBundleProvider | undefined => {
        const currentOwner = this.owners.get(instance);
        return !record.destroyed && currentOwner?.instance === instance ? currentOwner.sourceBundle : undefined;
      },
      reload: (reason: string): Promise<void> => {
        if (runtime !== undefined) return runtime.reload(reason);
        if (record.destroyed) throw new ExpoModuleError('ERR_RELOAD_UNAVAILABLE', 'The React instance was destroyed.');
        return ExpoReloadRegistry.require(instance.getId())(reason);
      },
      suspend: (): Promise<void> => {
        if (runtime === undefined) {
          throw new ExpoModuleError('ERR_REACT_HOST_OWNER', 'No React runtime owns this instance.');
        }
        return runtime.suspend();
      },
    };
    const destroyed = observeRnohDestroy(instance, (): void => {
      record.destroyed = true;
      this.runtimes.delete(instance);
    });
    const released = lifetime.observeDestroy(instance, (): void => {
      record.released = true;
      record.cleanup?.();
      record.cleanup = undefined;
      destroyed();
    });

    this.records.set(instance, record);
    record.ready = Promise.resolve().then(async (): Promise<void> => {
      try {
        if (record.destroyed) throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'Cannot bind a destroyed React instance.');
        const cleanup = await this.delegate.prepare(context);
        if (record.released) cleanup();
        else record.cleanup = cleanup;
      } catch (error) {
        destroyed();
        released();
        if (this.records.get(instance) === record) this.records.delete(instance);
        throw new ExpoModuleError('ERR_REACT_HOST_BIND', 'Unable to bind the React runtime.', error as Object);
      }
    });

    return record;
  }

  get activityHandlers(): ReactActivityHandlerRegistration[] {
    return this.options.provider.reactActivityHandlers;
  }

  async load(context: common.Context): Promise<void> {
    if (this.owner === undefined) throw new ExpoModuleError('ERR_REACT_HOST_CONFIG', 'Initialize the Expo React host before loading an application.');

    this.loader.loadApp(context, { appScopeKey: this.owner });
    await this.loader.waitForApp(this.owner);
  }

  unload(): Promise<void> {
    return this.owner === undefined ? Promise.resolve() : this.loader.invalidateAppAsync(this.owner);
  }
}

class HostLoaderDelegate implements HeadlessAppLoaderDelegate {
  readonly workerScriptUrl: string;
  private readonly available: () => boolean;
  private readonly runtime: () => ReactNativeRuntime | undefined;
  private readonly otherOwner: (context: common.UIAbilityContext) => boolean;
  private readonly create: (core: RNOHCoreContext, context: common.Context) => ReactNativeRuntime;
  private readonly beginAbility: (context: common.UIAbilityContext) => void;
  private readonly finishAbility: (context: common.UIAbilityContext) => void;

  constructor(
    workerScriptUrl: string,
    available: () => boolean,
    runtime: () => ReactNativeRuntime | undefined,
    otherOwner: (context: common.UIAbilityContext) => boolean,
    create: (core: RNOHCoreContext, context: common.Context) => ReactNativeRuntime,
    beginAbility: (context: common.UIAbilityContext) => void,
    finishAbility: (context: common.UIAbilityContext) => void,
  ) {
    this.workerScriptUrl = workerScriptUrl;
    this.available = available;
    this.runtime = runtime;
    this.otherOwner = otherOwner;
    this.create = create;
    this.beginAbility = beginAbility;
    this.finishAbility = finishAbility;
  }

  isAvailable(): boolean {
    return this.available();
  }

  hasOtherOwner(context: common.UIAbilityContext): boolean {
    return this.otherOwner(context);
  }

  getRuntime(): ReactNativeRuntime | undefined {
    return this.runtime();
  }

  createRuntime(core: RNOHCoreContext, context: common.Context): ReactNativeRuntime {
    return this.create(core, context);
  }

  begin(context: common.UIAbilityContext): void {
    this.beginAbility(context);
  }

  end(context: common.UIAbilityContext): void {
    this.finishAbility(context);
  }
}

class HostRuntimeOptions implements RnohReactRuntimeOptions {
  options?: RNInstanceOptions | (() => RNInstanceOptions);
  instance?: RNInstance;
  replace?: (reason: string) => Promise<RNInstance>;
  bundle?: (() => JSBundleProvider) | undefined;
  private readonly prepareCallback: (instance: RNInstance) => Promise<void>;

  constructor(
    options: RNInstanceOptions | (() => RNInstanceOptions) | undefined,
    instance: RNInstance | undefined,
    replace: ((reason: string) => Promise<RNInstance>) | undefined,
    bundle: (() => JSBundleProvider) | undefined,
    prepare: (instance: RNInstance) => Promise<void>,
  ) {
    this.options = options;
    this.instance = instance;
    this.replace = replace;
    this.bundle = bundle;
    this.prepareCallback = prepare;
  }

  prepare(instance: RNInstance): Promise<void> {
    return this.prepareCallback(instance);
  }
}

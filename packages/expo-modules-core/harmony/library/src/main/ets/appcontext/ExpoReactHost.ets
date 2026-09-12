import { bundleManager, common } from '@kit.AbilityKit';
import {
  JSBundleProvider,
  MetroJSBundleProvider,
  RNInstance,
  RNInstanceOptions,
  RNInstancesCoordinator,
  ResourceJSBundleProvider,
  StandardRNOHLogger,
} from '@rnoh/react-native-openharmony';
import type { ExpoHarmonyHostState } from './HarmonyHostLifecycle';
import { ExpoModuleError } from '../modules/ExpoModuleError';

export interface ExpoReactHostOptions {
  bundlePath: string;
  workerScriptUrl: string;
  hostState: ExpoHarmonyHostState;
  createRNInstanceOptions: (headless: boolean) => RNInstanceOptions;
}

class ExpoResourceBundle extends ResourceJSBundleProvider {
  private readonly resources: common.Context;
  private readonly resource: string;

  constructor(context: common.Context, path: string) {
    super(context.resourceManager, path);
    this.resources = context;
    this.resource = path;
  }

  override async getBundle(): Promise<ArrayBuffer> {
    const bytes = await this.resources.resourceManager.getRawFileContent(this.resource);
    return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  }
}

export class ExpoReactHost {
  private static readonly hosts: Map<string, ExpoReactHost> = new Map();
  private static readonly abilities: Set<common.UIAbilityContext> = new Set();
  private readonly options: ExpoReactHostOptions;
  private resources?: common.Context;
  private debug: boolean = false;
  private coordinator?: RNInstancesCoordinator;
  private instance?: RNInstance;
  private pending?: Promise<void>;

  constructor(options: ExpoReactHostOptions) {
    if (options.bundlePath.length === 0 || options.workerScriptUrl.length === 0) {
      throw new ExpoModuleError('ERR_REACT_HOST_CONFIG', 'A React host requires its application bundle path and worker script.');
    }

    this.options = options;
  }

  initialize(context: common.Context): void {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const owner = info.name;
    const existing = ExpoReactHost.hosts.get(owner);
    if (existing !== undefined && existing !== this) {
      throw new ExpoModuleError('ERR_REACT_HOST_CONFIG', `A React host is already registered for '${owner}'.`);
    }

    this.resources = context;
    this.debug = info.appInfo.debug;
    ExpoReactHost.hosts.set(owner, this);
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
      if (host.coordinator !== undefined) return true;
    }

    return false;
  }

  isAvailable(): boolean {
    if (this.resources === undefined) return false;
    if (this.debug) return true;

    try {
      const path = this.options.bundlePath;
      const separator = path.lastIndexOf('/');
      const directory = separator < 0 ? '' : path.slice(0, separator);
      return this.resources.resourceManager.getRawFileListSync(directory).includes(path.slice(separator + 1));
    } catch (_error) {
      return false;
    }
  }

  createRNInstanceOptions(headless: boolean = false): RNInstanceOptions {
    return this.options.createRNInstanceOptions(headless);
  }

  createJSBundleProvider(context: common.Context, debug: boolean = false): JSBundleProvider {
    return debug ? new MetroJSBundleProvider() : new ExpoResourceBundle(context, this.options.bundlePath);
  }

  async load(context: common.Context): Promise<void> {
    while (this.pending !== undefined) await this.pending;
    if (this.instance !== undefined) return;
    if (!this.isAvailable()) throw new ExpoModuleError('ERR_REACT_HOST_BUNDLE', 'The application bundle is not available for background execution.');

    const pending = this.start(context);

    this.pending = pending;
    try {
      await pending;
    } finally {
      if (this.pending === pending) this.pending = undefined;
    }
  }

  async unload(): Promise<void> {
    while (this.pending !== undefined) await this.pending;
    const coordinator = this.coordinator;
    const instance = this.instance;
    if (coordinator === undefined || instance === undefined) return;

    const pending = this.stop(coordinator, instance);

    this.pending = pending;
    try {
      await pending;
    } finally {
      if (this.pending === pending) this.pending = undefined;
    }
  }

  private async stop(coordinator: RNInstancesCoordinator, instance: RNInstance): Promise<void> {
    const core = coordinator.getRNOHCoreContext();

    this.instance = undefined;
    try {
      await core.destroyAndUnregisterRNInstance(instance);
    } finally {
      this.options.hostState.finishAbility(core.uiAbilityContext);
      this.destroyCoordinator(coordinator);
      this.coordinator = undefined;
    }

    console.info(`Expo background React runtime released: ${instance.getId()}`);
  }

  private async start(context: common.Context): Promise<void> {
    const native: ESObject = context;
    if (native.extensionAbilityInfo === undefined) {
      throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'Background execution requires an ExtensionAbility context.');
    }

    // RNOH 0.84 reads UIAbility metadata even without a surface. Keep the native
    // ExtensionContext and expose its own metadata under the expected property.
    native.abilityInfo = native.extensionAbilityInfo;
    const ability = native as common.UIAbilityContext;
    const client: ESObject = AppStorage.get('jsPackagerClient');
    let coordinator: RNInstancesCoordinator;

    try {
      coordinator = RNInstancesCoordinator.create(
        {
          uiAbilityContext: ability,
          logger: new StandardRNOHLogger(),
          rnohWorkerScriptUrl: this.options.workerScriptUrl,
          defaultBackPressHandler: (): void => {},
        },
        { disableCleaningRNInstances: ExpoReactHost.hasOtherOwner(ability) },
      );
      this.coordinator = coordinator;
      coordinator.onBackground();
    } finally {
      // RNOH stores the Metro client globally even for a headless coordinator.
      if (client === undefined) AppStorage.delete('jsPackagerClient');
      else AppStorage.setOrCreate('jsPackagerClient', client);
    }

    const core = coordinator.getRNOHCoreContext();
    let instance: RNInstance | undefined;

    // RNOH 0.84 eagerly awaits window insets even for a surface-free runtime.
    // Its initial zero insets are the correct value when no window exists.
    const insets: ESObject = core.safeAreaInsetsProvider;
    insets.ready = insets.ready.catch((error: ESObject): void => {
      if (error?.code !== 1300002)
        throw new ExpoModuleError('ERR_REACT_HOST_INSETS', 'Unable to initialize background display insets.', error as Object);
    });

    this.options.hostState.beginAbility(ability, {});
    try {
      instance = await core.createAndRegisterRNInstance(this.createRNInstanceOptions(true));
      coordinator.onBackground();
      await instance.runJSBundle(this.createJSBundleProvider(context, this.debug));
      this.instance = instance;
      console.info(`Expo background React runtime loaded: ${instance.getId()}`);
    } catch (error) {
      if (instance !== undefined) await core.destroyAndUnregisterRNInstance(instance);
      this.options.hostState.finishAbility(ability);
      this.destroyCoordinator(coordinator);
      this.coordinator = undefined;

      throw new ExpoModuleError('ERR_REACT_HOST_LOAD', 'Unable to load the application for background execution.', error as Object);
    }
  }

  private destroyCoordinator(coordinator: RNInstancesCoordinator): void {
    const client: ESObject = AppStorage.get('jsPackagerClient');

    // onDestroy otherwise destroys whichever coordinator last published a client.
    AppStorage.delete('jsPackagerClient');
    try {
      coordinator.onDestroy();
    } finally {
      if (client !== undefined) AppStorage.setOrCreate('jsPackagerClient', client);
    }
  }
}

import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNInstance, RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { ExpoPlatformServiceError, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import type bundleManager from '@ohos.bundle.bundleManager';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import type common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';

const SERVICE_NAME: string = 'ExpoSystemUIService';
const ROOT_BACKGROUND_METADATA: string = 'expo.harmony.rootViewBackgroundColor';
const INTERFACE_STYLE_METADATA: string = 'expo.harmony.userInterfaceStyle';
const PREFERENCES_NAME: string = 'expo_ui_preferences';
const PREFERENCE_KEY: string = 'expoRootBackgroundColor';
const LIGHT_WINDOW_BACKGROUND: string = '#FFFFFFFF';
const DARK_WINDOW_BACKGROUND: string = '#FF000000';
const abilityStates: WeakMap<Object, AbilitySystemUIState> = new WeakMap<Object, AbilitySystemUIState>();
let registered: boolean = false;

export class ExpoSystemUILifecycle {
  static async onRNInstanceSetUp(context: common.UIAbilityContext, rnInstance: RNInstance): Promise<void> {
    const state = getAbilityState(context);

    try {
      state.applyInterfaceStyle();
    } catch (error) {
      console.warn(`Unable to apply the Expo System UI interface style during setup: ${String(error)}`);
    }

    let target: window.Window;
    try {
      target = await rnInstance.getRNWindow();
    } catch (error) {
      console.warn(`Unable to locate the React Native window during Expo System UI setup: ${String(error)}`);
      return;
    }

    try {
      await state.initializeWindow(target, false, (): boolean => true);
    } catch (error) {
      console.warn(`Unable to initialize the Expo System UI window: ${String(error)}`);
    }
  }

  static applyInterfaceStyle(
    context: common.UIAbilityContext,
    userInterfaceStyle: string,
    automaticColorMode?: ConfigurationConstant.ColorMode,
  ): void {
    if (userInterfaceStyle === 'dark') {
      context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (userInterfaceStyle === 'light') {
      context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else if (userInterfaceStyle === 'automatic') {
      context.setColorMode(resolvedSystemColorMode(automaticColorMode ?? context.config.colorMode));
    }
  }
}

class SystemUIConfiguration {
  backgroundColor: string | null = null;
  userInterfaceStyle: string = 'light';
}

class ParsedBackgroundColor {
  windowColor: string;
  exposedColor: string;

  constructor(windowColor: string, exposedColor: string) {
    this.windowColor = windowColor;
    this.exposedColor = exposedColor;
  }
}

class WindowBackgroundState {
  color: ParsedBackgroundColor;
  followsSystem: boolean;

  constructor(color: ParsedBackgroundColor, followsSystem: boolean) {
    this.color = color;
    this.followsSystem = followsSystem;
  }
}

class AbilitySystemUIState {
  private readonly context: common.UIAbilityContext;
  private readonly configuredBackground: ParsedBackgroundColor | null;
  private readonly userInterfaceStyle: string;
  private resolvedMode: ConfigurationConstant.ColorMode;
  private readonly backgrounds: Map<number, WindowBackgroundState> = new Map();
  private readonly preferencesStore: Promise<preferences.Preferences | null>;
  private readonly storageReady: Promise<void>;
  private persistedBackground: ParsedBackgroundColor | null = null;

  constructor(context: common.UIAbilityContext) {
    this.context = context;

    const config = readConfiguration(context);
    const background = config.backgroundColor === null ? null : parseManifestColor(config.backgroundColor);

    if (config.backgroundColor !== null && background === null) {
      console.warn('Harmony application metadata contains an invalid expo-system-ui background color.');
    }

    this.configuredBackground = background;
    this.userInterfaceStyle = config.userInterfaceStyle;
    this.resolvedMode = resolvedSystemColorMode(context.config.colorMode);

    this.preferencesStore = preferences.getPreferences(context, { name: PREFERENCES_NAME }).catch((error: Object): preferences.Preferences | null => {
      console.warn(`Unable to open Expo System UI preferences: ${String(error)}`);
      return null;
    });

    this.storageReady = this.loadPersistedBackground();
  }

  applyInterfaceStyle(): void {
    ExpoSystemUILifecycle.applyInterfaceStyle(this.context, this.userInterfaceStyle, this.resolvedMode);
  }

  tryApplyInterfaceStyle(moduleContext: UITurboModuleContext): void {
    try {
      this.applyInterfaceStyle();
    } catch (error) {
      // The eager ExpoModulesCore TurboModule may be created before ArkUI has
      // loaded the page. The generated host hook and foreground lifecycle are
      // authoritative retries after the page exists.
      moduleContext.logger.warn(`Unable to apply the configured Expo System UI interface style yet: ${String(error)}`);
    }
  }

  usesAutomaticInterfaceStyle(): boolean {
    return this.userInterfaceStyle === 'automatic';
  }

  updateSystemColorMode(colorMode: ConfigurationConstant.ColorMode | undefined): void {
    if (colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK || colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      this.resolvedMode = colorMode;
    }
  }

  async initializeWindow(target: window.Window, refreshSystem: boolean, canApply: () => boolean): Promise<void> {
    await this.storageReady;

    if (!canApply()) return;

    const id = inspectWindowId(target);
    let background = this.backgrounds.get(id);

    if (background === undefined) {
      if (this.persistedBackground !== null) {
        background = new WindowBackgroundState(this.persistedBackground, false);
      } else if (this.configuredBackground !== null) {
        background = new WindowBackgroundState(this.configuredBackground, false);
      } else {
        background = new WindowBackgroundState(this.systemBackgroundColor(), true);
      }

      this.backgrounds.clear();
      this.backgrounds.set(id, background);
    } else if (refreshSystem && background.followsSystem) {
      background.color = this.systemBackgroundColor();
    }

    if (!canApply()) return;

    applyWindowColor(target, background.color.windowColor);
  }

  async setBackgroundColor(target: window.Window, color: ParsedBackgroundColor | null, canApply: () => boolean): Promise<void> {
    await this.storageReady;

    if (!canApply()) return;

    const id = inspectWindowId(target);

    if (color === null) {
      await this.removePersistedBackground();

      if (!canApply()) return;

      const fallback = this.systemBackgroundColor();

      applyWindowColor(target, fallback.windowColor);

      this.backgrounds.clear();
      this.backgrounds.set(id, new WindowBackgroundState(fallback, true));
      return;
    }

    await this.persistBackground(color);

    if (!canApply()) return;

    applyWindowColor(target, color.windowColor);

    this.backgrounds.clear();
    this.backgrounds.set(id, new WindowBackgroundState(color, false));
  }

  getBackgroundColor(target: window.Window): ParsedBackgroundColor | null {
    const background = this.backgrounds.get(inspectWindowId(target));
    return background === undefined ? null : background.color;
  }

  private async loadPersistedBackground(): Promise<void> {
    const store = await this.preferencesStore;

    if (store === null) return;

    try {
      if (!(await store.has(PREFERENCE_KEY))) return;

      const value = await store.get(PREFERENCE_KEY, '');

      if (typeof value === 'string') {
        this.persistedBackground = parseManifestColor(value);
      }
    } catch (error) {
      console.warn(`Unable to read Expo System UI preferences: ${String(error)}`);
    }
  }

  private async persistBackground(color: ParsedBackgroundColor): Promise<void> {
    this.persistedBackground = color;

    const store = await this.preferencesStore;
    if (store === null) return;

    try {
      await store.put(PREFERENCE_KEY, color.windowColor);
      await store.flush();
    } catch (error) {
      console.warn(`Unable to persist the Expo System UI background: ${String(error)}`);
    }
  }

  private async removePersistedBackground(): Promise<void> {
    this.persistedBackground = null;

    const store = await this.preferencesStore;
    if (store === null) return;

    try {
      await store.delete(PREFERENCE_KEY);
      await store.flush();
    } catch (error) {
      console.warn(`Unable to clear the Expo System UI background preference: ${String(error)}`);
    }
  }

  private systemBackgroundColor(): ParsedBackgroundColor {
    if (this.userInterfaceStyle === 'dark') {
      return parseKnownWindowColor(DARK_WINDOW_BACKGROUND);
    }
    if (this.userInterfaceStyle === 'light') {
      return parseKnownWindowColor(LIGHT_WINDOW_BACKGROUND);
    }

    return this.resolvedMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      ? parseKnownWindowColor(DARK_WINDOW_BACKGROUND)
      : parseKnownWindowColor(LIGHT_WINDOW_BACKGROUND);
  }
}

class ExpoSystemUIService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;
  private readonly state: AbilitySystemUIState;
  private readonly unsubscribers: Array<() => void> = [];
  private mutation: Promise<void> = Promise.resolve();
  private destroyed: boolean = false;

  constructor(context: UITurboModuleContext) {
    this.context = context;
    this.state = getAbilityState(context.uiAbilityContext);

    this.state.tryApplyInterfaceStyle(context);

    this.mutation = this.initializeCurrentWindow(false).catch((error: Object): void => {
      context.logger.warn(`Unable to initialize the Expo System UI window yet: ${String(error)}`);
    });

    this.unsubscribers.push(
      context.rnInstance.subscribeToLifecycleEvents('FOREGROUND', () => {
        this.state.tryApplyInterfaceStyle(context);
        this.scheduleWindowInitialization(true);
      }),
    );

    if (this.state.usesAutomaticInterfaceStyle()) {
      this.unsubscribers.push(
        context.rnInstance.subscribeToLifecycleEvents('CONFIGURATION_UPDATE', (config) => {
          this.state.updateSystemColorMode(config.colorMode);
          this.scheduleWindowInitialization(true);
        }),
      );
    }

    this.unsubscribers.push(
      context.rnInstance.subscribeToLifecycleEvents('WINDOW_SIZE_CHANGE', () => {
        this.scheduleWindowInitialization(true);
      }),
    );
  }

  onDestroy(): void {
    this.destroy();
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (method === 'setBackgroundColorAsync') {
      const value: ESObject = args.length > 0 ? args[0] : null;

      await this.serialize(async (): Promise<void> => {
        await this.setBackgroundColor(value);
      });

      return null;
    }

    if (method === 'getBackgroundColorAsync') {
      await this.mutation.catch((): void => {});

      const target = await this.currentWindow();
      const color = this.state.getBackgroundColor(target);

      return color === null ? null : color.exposedColor;
    }

    if (method === 'destroy') {
      this.destroy();
      return null;
    }

    throw new ExpoPlatformServiceError('ERR_SYSTEM_UI_UNKNOWN_METHOD', `Unknown ExpoSystemUI Harmony method '${method}'.`);
  }

  invokeSync(method: string, _: ESObject[]): ESObject {
    if (method === 'destroy') {
      this.destroy();
      return null;
    }

    throw new ExpoPlatformServiceError('ERR_SYSTEM_UI_ASYNC_METHOD', `ExpoSystemUI Harmony method '${method}' is asynchronous.`);
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;

    this.unsubscribers.forEach((unsubscribe) => unsubscribe());
    this.unsubscribers.length = 0;
  }

  private async serialize(operation: () => Promise<void>): Promise<void> {
    const next = this.mutation.catch((): void => {}).then(operation);
    this.mutation = next;

    await next;
  }

  private scheduleWindowInitialization(refreshSystem: boolean): void {
    if (this.destroyed) return;

    this.serialize(async (): Promise<void> => {
      await this.initializeCurrentWindow(refreshSystem);
    }).catch((error: Object): void => {
      this.context.logger.warn(`Unable to refresh the Expo System UI window: ${String(error)}`);
    });
  }

  private async initializeCurrentWindow(refreshSystem: boolean): Promise<void> {
    if (this.destroyed) return;

    const target = await this.currentWindow();

    if (this.destroyed) return;

    await this.state.initializeWindow(target, refreshSystem, (): boolean => !this.destroyed);
  }

  private async setBackgroundColor(value: ESObject): Promise<void> {
    if (
      value !== null &&
      value !== undefined &&
      (typeof value !== 'number' || !Number.isInteger(value) || value < -2147483648 || value > 4294967295)
    ) {
      throw new ExpoPlatformServiceError('ERR_SYSTEM_UI_COLOR', 'ExpoSystemUI expected a processed 32-bit React Native color or null.');
    }

    const target = await this.currentWindow();

    if (this.destroyed) return;

    const color = value === null || value === undefined ? null : parseProcessedColor(value);

    await this.state.setBackgroundColor(target, color, (): boolean => !this.destroyed);
  }

  private async currentWindow(): Promise<window.Window> {
    try {
      return await this.context.rnInstance.getRNWindow();
    } catch (error) {
      throw new ExpoPlatformServiceError('ERR_SYSTEM_UI_WINDOW', `Unable to locate the current React Native window: ${String(error)}`);
    }
  }
}

function getAbilityState(context: common.UIAbilityContext): AbilitySystemUIState {
  const state = abilityStates.get(context);
  if (state !== undefined) return state;

  const created = new AbilitySystemUIState(context);
  abilityStates.set(context, created);

  return created;
}

function inspectWindowId(target: window.Window): number {
  try {
    return target.getWindowProperties().id;
  } catch (error) {
    throw new ExpoPlatformServiceError('ERR_SYSTEM_UI_WINDOW', `Unable to inspect the current React Native window: ${String(error)}`);
  }
}

function applyWindowColor(target: window.Window, color: string): void {
  try {
    target.setWindowBackgroundColor(color);
  } catch (error) {
    throw new ExpoPlatformServiceError('ERR_SYSTEM_UI_WINDOW', `Unable to update the current React Native window background: ${String(error)}`);
  }
}

function parseKnownWindowColor(value: string): ParsedBackgroundColor {
  return new ParsedBackgroundColor(value, `#${value.slice(3).toLowerCase()}`);
}

function parseProcessedColor(value: number): ParsedBackgroundColor {
  const unsigned = value < 0 ? value + 4294967296 : value;
  const argb = unsigned.toString(16).padStart(8, '0').toUpperCase();
  return new ParsedBackgroundColor(`#${argb}`, `#${argb.slice(2).toLowerCase()}`);
}

function parseManifestColor(value: string): ParsedBackgroundColor | null {
  if (!/^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i.test(value)) return null;

  const hex = value.slice(1).toUpperCase();
  const argb = hex.length === 6 ? `FF${hex}` : hex;

  return new ParsedBackgroundColor(`#${argb}`, `#${argb.slice(2).toLowerCase()}`);
}

function resolvedSystemColorMode(colorMode: ConfigurationConstant.ColorMode | undefined): ConfigurationConstant.ColorMode {
  return colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
}

function readConfiguration(context: common.UIAbilityContext): SystemUIConfiguration {
  const config = new SystemUIConfiguration();

  try {
    // UIAbilityContext already exposes metadata for the current HAP module;
    // avoid a synchronous BundleManager query during TurboModule creation.
    applyMetadata(config, context.currentHapModuleInfo.metadata);
  } catch (error) {
    console.warn(`Unable to read Expo System UI module metadata: ${String(error)}`);
  }

  if (config.userInterfaceStyle !== 'light' && config.userInterfaceStyle !== 'dark' && config.userInterfaceStyle !== 'automatic') {
    console.warn(`Ignoring invalid Expo System UI interface style '${config.userInterfaceStyle}'.`);
    config.userInterfaceStyle = 'light';
  }

  return config;
}

function applyMetadata(config: SystemUIConfiguration, metadata: Array<bundleManager.Metadata>): void {
  metadata.forEach((entry) => {
    if (entry.name === ROOT_BACKGROUND_METADATA) config.backgroundColor = entry.value;
    if (entry.name === INTERFACE_STYLE_METADATA) config.userInterfaceStyle = entry.value;
  });
}

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new ExpoSystemUIService(context),
  });

  registered = true;
}

export class ExpoSystemUIPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    super(context);
    registerService();
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-system-ui';
  }
}

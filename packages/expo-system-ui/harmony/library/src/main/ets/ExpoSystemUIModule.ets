import type bundleManager from '@ohos.bundle.bundleManager';
import deviceInfo from '@ohos.deviceInfo';
import { AbilityConstant, Configuration, ConfigurationConstant, EnvironmentCallback, common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';
import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';

const ROOT_BACKGROUND_METADATA: string = 'expo.harmony.rootViewBackgroundColor';
const INTERFACE_STYLE_METADATA: string = 'expo.harmony.userInterfaceStyle';
const PREFERENCES_NAME: string = 'expo_ui_preferences';
const PREFERENCE_KEY: string = 'expoRootBackgroundColor';
const LIGHT_WINDOW_BACKGROUND: string = '#FFFFFFFF';
const DARK_WINDOW_BACKGROUND: string = '#FF000000';
const UI_ABILITY_COLOR_MODE_API: number = 18;

type InterfaceStyle = 'light' | 'dark' | 'automatic';

class ExpoSystemUIError extends ExpoModuleError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoSystemUIError';
  }
}

class SystemUIConfiguration {
  backgroundColor: string | null = null;
  userInterfaceStyle: InterfaceStyle = 'light';
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

class SystemUIEnvironmentCallback extends EnvironmentCallback {
  private readonly state: AbilitySystemUIState;

  constructor(state: AbilitySystemUIState) {
    super();
    this.state = state;
  }

  override onConfigurationUpdated(config: Configuration): void {
    this.state.onConfigurationUpdated(config.colorMode);
  }

  override onMemoryLevel(_level: AbilityConstant.MemoryLevel): void {}
}

class AbilitySystemUIState {
  private readonly context: common.UIAbilityContext;
  private readonly configured: ParsedBackgroundColor | null;
  private readonly style: InterfaceStyle;
  private mode: ConfigurationConstant.ColorMode;
  private readonly backgrounds: Map<number, WindowBackgroundState> = new Map<number, WindowBackgroundState>();
  private readonly windows: Map<number, window.Window> = new Map<number, window.Window>();
  private readonly store: Promise<preferences.Preferences | null>;
  private readonly ready: Promise<void>;
  private persisted: ParsedBackgroundColor | null = null;
  private mutation: Promise<void> = Promise.resolve();
  private subscription: number = -1;
  private owners: number = 0;
  private destroyed: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;

    const config: SystemUIConfiguration = readConfiguration(context);
    const background: ParsedBackgroundColor | null = config.backgroundColor === null ? null : parseManifestColor(config.backgroundColor);

    if (config.backgroundColor !== null && background === null) {
      console.warn('Harmony application metadata contains an invalid expo-system-ui background color.');
    }

    this.configured = background;
    this.style = config.userInterfaceStyle;
    this.mode = resolvedSystemColorMode(context);

    this.store = preferences.getPreferences(context, { name: PREFERENCES_NAME }).catch((error: Object): preferences.Preferences | null => {
      console.warn(`Unable to open Expo System UI preferences: ${String(error)}`);
      return null;
    });
    this.ready = this.loadPersistedBackground();

    this.registerEnvironmentCallback();
  }

  applyInterfaceStyle(): void {
    this.assertActive();

    let mode: ConfigurationConstant.ColorMode;
    if (this.style === 'dark') {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (this.style === 'light') {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    }

    if (deviceInfo.sdkApiVersion >= UI_ABILITY_COLOR_MODE_API) this.context.setColorMode(mode);
    else this.context.getApplicationContext().setColorMode(mode);
  }

  retain(): void {
    this.assertActive();
    this.owners += 1;
  }

  release(): boolean {
    if (this.destroyed) return true;

    if (this.owners > 0) this.owners -= 1;
    if (this.owners > 0) return false;

    this.destroy();
    return true;
  }

  onConfigurationUpdated(_colorMode: ConfigurationConstant.ColorMode | undefined): void {
    if (this.destroyed || this.style !== 'automatic') return;

    this.mode = resolvedSystemColorMode(this.context);

    Array.from(this.windows.values()).forEach((target: window.Window): void => {
      this.initializeWindow(target, true, (): boolean => !this.destroyed).catch((error: Object): void => {
        if (!this.destroyed) {
          console.warn(`Unable to refresh the Expo System UI window after a configuration change: ${String(error)}`);
        }
      });
    });
  }

  async initializeWindowFrom(resolve: () => Promise<window.Window>, refresh: boolean, canApply: () => boolean): Promise<void> {
    await this.serialize(async (): Promise<void> => {
      const target: window.Window = await resolve();
      await this.applyWindowState(target, refresh, canApply);
    });
  }

  async initializeWindow(target: window.Window, refresh: boolean, canApply: () => boolean): Promise<void> {
    await this.serialize(async (): Promise<void> => {
      await this.applyWindowState(target, refresh, canApply);
    });
  }

  private async applyWindowState(target: window.Window, refresh: boolean, canApply: () => boolean): Promise<void> {
    await this.ready;

    this.assertActive();
    if (!canApply()) return;

    const id: number = inspectWindowId(target);
    let background: WindowBackgroundState | undefined = this.backgrounds.get(id);

    if (background === undefined) {
      if (this.persisted !== null) {
        background = new WindowBackgroundState(this.persisted, false);
      } else if (this.configured !== null) {
        background = new WindowBackgroundState(this.configured, false);
      } else {
        background = new WindowBackgroundState(this.systemBackgroundColor(), true);
      }
    } else if (refresh && background.followsSystem) {
      background.color = this.systemBackgroundColor();
    }

    if (!canApply()) return;

    applyWindowColor(target, background.color.windowColor);

    this.windows.set(id, target);
    this.backgrounds.set(id, background);
  }

  async setBackgroundColor(target: window.Window, color: ParsedBackgroundColor | null, canApply: () => boolean): Promise<void> {
    await this.serialize(async (): Promise<void> => {
      await this.ready;

      this.assertActive();
      if (!canApply()) return;

      const id: number = inspectWindowId(target);

      if (color === null) {
        const fallback: ParsedBackgroundColor = this.systemBackgroundColor();

        applyWindowColor(target, fallback.windowColor);
        await this.removePersistedBackground();

        if (!canApply()) return;

        this.windows.set(id, target);
        this.backgrounds.set(id, new WindowBackgroundState(fallback, true));

        return;
      }

      applyWindowColor(target, color.windowColor);
      await this.persistBackground(color);

      if (!canApply()) return;

      this.windows.set(id, target);
      this.backgrounds.set(id, new WindowBackgroundState(color, false));
    });
  }

  async getBackgroundColor(target: window.Window, canRead: () => boolean): Promise<string | null> {
    await this.mutation.catch((): void => {});

    this.assertActive();
    if (!canRead()) return null;

    const background: WindowBackgroundState | undefined = this.backgrounds.get(inspectWindowId(target));

    return background === undefined ? null : background.color.exposedColor;
  }

  forgetWindow(): void {
    this.windows.clear();
    this.backgrounds.clear();
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.owners = 0;
    this.windows.clear();
    this.backgrounds.clear();

    if (this.subscription >= 0) {
      const id: number = this.subscription;
      this.subscription = -1;

      this.context
        .getApplicationContext()
        .off('environment', id)
        .catch((error: Object): void => {
          console.warn(`Unable to release the Expo System UI environment callback: ${String(error)}`);
        });
    }
  }

  private registerEnvironmentCallback(): void {
    try {
      this.subscription = this.context.getApplicationContext().on('environment', new SystemUIEnvironmentCallback(this));
    } catch (error) {
      console.warn(`Unable to observe Expo System UI configuration changes: ${String(error)}`);
    }
  }

  private async serialize(operation: () => Promise<void>): Promise<void> {
    this.assertActive();

    const next: Promise<void> = this.mutation.catch((): void => {}).then(operation);
    this.mutation = next;

    await next;
  }

  private async loadPersistedBackground(): Promise<void> {
    const store: preferences.Preferences | null = await this.store;
    if (store === null || this.destroyed) return;

    try {
      if (!(await store.has(PREFERENCE_KEY))) return;

      const value: preferences.ValueType = await store.get(PREFERENCE_KEY, '');

      if (typeof value === 'string') this.persisted = parseManifestColor(value);
    } catch (error) {
      console.warn(`Unable to read Expo System UI preferences: ${String(error)}`);
    }
  }

  private async persistBackground(color: ParsedBackgroundColor): Promise<void> {
    this.persisted = color;

    const store: preferences.Preferences | null = await this.store;
    if (store === null || this.destroyed) return;

    try {
      await store.put(PREFERENCE_KEY, color.windowColor);
      await store.flush();
    } catch (error) {
      console.warn(`Unable to persist the Expo System UI background: ${String(error)}`);
    }
  }

  private async removePersistedBackground(): Promise<void> {
    this.persisted = null;

    const store: preferences.Preferences | null = await this.store;
    if (store === null || this.destroyed) return;

    try {
      await store.delete(PREFERENCE_KEY);
      await store.flush();
    } catch (error) {
      console.warn(`Unable to clear the Expo System UI background preference: ${String(error)}`);
    }
  }

  private systemBackgroundColor(): ParsedBackgroundColor {
    if (this.style === 'dark') return parseKnownWindowColor(DARK_WINDOW_BACKGROUND);
    if (this.style === 'light') return parseKnownWindowColor(LIGHT_WINDOW_BACKGROUND);
    return this.mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      ? parseKnownWindowColor(DARK_WINDOW_BACKGROUND)
      : parseKnownWindowColor(LIGHT_WINDOW_BACKGROUND);
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoSystemUIError('ERR_SYSTEM_UI_DESTROYED', 'ExpoSystemUI cannot access a UIAbility that has already been destroyed.');
    }
  }
}

const abilityStates: WeakMap<common.UIAbilityContext, AbilitySystemUIState> = new WeakMap<common.UIAbilityContext, AbilitySystemUIState>();

function stateForAbility(context: common.UIAbilityContext): AbilitySystemUIState {
  let state: AbilitySystemUIState | undefined = abilityStates.get(context);
  if (state === undefined) {
    state = new AbilitySystemUIState(context);
    abilityStates.set(context, state);
  }

  return state;
}

export function attachSystemUIRoot(context: common.UIAbilityContext): () => void {
  const state: AbilitySystemUIState = stateForAbility(context);
  let attached: boolean = true;
  state.retain();

  try {
    state.applyInterfaceStyle();
  } catch (error) {
    console.warn(`Unable to apply the pre-JavaScript Expo System UI interface style: ${String(error)}`);
  }

  state
    .initializeWindowFrom(
      (): Promise<window.Window> => window.getLastWindow(context),
      false,
      (): boolean => attached,
    )
    .catch((error: Object): void => {
      if (attached) {
        console.warn(`Unable to apply the pre-JavaScript Expo System UI window background: ${String(error)}`);
      }
    });

  return (): void => {
    if (!attached) return;

    attached = false;
    if (state.release()) abilityStates.delete(context);
  };
}

export class ExpoSystemUIModule extends ExpoModule {
  private readonly state: AbilitySystemUIState;
  private released: boolean = false;
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.state = stateForAbility(context.uiAbilityContext);
    this.state.retain();
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoSystemUI')
      .asyncFunction(
        'setBackgroundColorAsync',
        ExpoFunction.typed1(ExpoValueTypes.number().nullable(), async (color: number | null): Promise<void> => {
          this.assertActive();
          if (color !== null) requireProcessedColor(color);

          const target: window.Window = await this.currentWindow();

          const parsed: ParsedBackgroundColor | null = color === null ? null : parseProcessedColor(color);

          await this.state.setBackgroundColor(target, parsed, (): boolean => this.isActive());
          this.assertActive();
        }),
      )
      .asyncFunction('getBackgroundColorAsync', async (): Promise<string | null> => {
        this.assertActive();

        const target: window.Window = await this.currentWindow();
        const color: string | null = await this.state.getBackgroundColor(target, (): boolean => this.isActive());
        this.assertActive();

        return color;
      })
      .onCreate((): void => this.initialize())
      .onForeground((): void => this.refresh())
      .onWindowStageSetup((stage: window.WindowStage): void => {
        this.scheduleWindowStage(stage);
      })
      .onWindowStageWillDestroy((): void => this.state.forgetWindow())
      .onAbilityDestroy((): void => this.destroyAbility())
      .onDestroy((): void => this.destroyRuntime());
  }

  private initialize(): void {
    this.tryApplyInterfaceStyle();
    this.scheduleCurrentWindow(false);
  }

  private refresh(): void {
    if (!this.isActive()) return;

    this.tryApplyInterfaceStyle();
    this.scheduleCurrentWindow(true);
  }

  private tryApplyInterfaceStyle(): void {
    if (!this.isActive()) return;

    try {
      this.state.applyInterfaceStyle();
    } catch (error) {
      this.context.logger.warn(`Unable to apply the Expo System UI interface style: ${String(error)}`);
    }
  }

  private scheduleCurrentWindow(refresh: boolean): void {
    if (!this.isActive()) return;

    this.state
      .initializeWindowFrom(
        (): Promise<window.Window> => this.currentWindow(),
        refresh,
        (): boolean => this.isActive(),
      )
      .catch((error: Object): void => this.reportInitializationFailure(error));
  }

  private scheduleWindowStage(stage: window.WindowStage): void {
    if (!this.isActive()) return;

    this.tryApplyInterfaceStyle();

    this.state
      .initializeWindowFrom(
        (): Promise<window.Window> => stage.getMainWindow(),
        true,
        (): boolean => this.isActive(),
      )
      .catch((error: Object): void => this.reportInitializationFailure(error));
  }

  private reportInitializationFailure(error: Object): void {
    if (this.isActive()) {
      this.context.logger.warn(`Unable to initialize the Expo System UI window: ${String(error)}`);
    }
  }

  private async currentWindow(): Promise<window.Window> {
    this.assertActive();

    try {
      return await this.context.getReactNativeWindow();
    } catch (error) {
      throw new ExpoSystemUIError('ERR_SYSTEM_UI_WINDOW', `Unable to locate the current React Native window: ${String(error)}`);
    }
  }

  private destroyAbility(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.released = true;

    this.state.destroy();
    abilityStates.delete(this.context.uiAbilityContext);
  }

  private destroyRuntime(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    if (this.released) return;

    this.released = true;
    if (this.state.release()) abilityStates.delete(this.context.uiAbilityContext);
  }

  private isActive(): boolean {
    return !this.destroyed && this.context.isValid;
  }

  private assertActive(): void {
    if (!this.isActive()) {
      throw new ExpoSystemUIError('ERR_SYSTEM_UI_DESTROYED', 'ExpoSystemUI cannot run after its Expo runtime has been invalidated.');
    }
  }
}

function inspectWindowId(target: window.Window): number {
  try {
    return target.getWindowProperties().id;
  } catch (error) {
    throw new ExpoSystemUIError('ERR_SYSTEM_UI_WINDOW', `Unable to inspect the current application window: ${String(error)}`);
  }
}

function applyWindowColor(target: window.Window, color: string): void {
  try {
    target.setWindowBackgroundColor(color);
  } catch (error) {
    throw new ExpoSystemUIError('ERR_SYSTEM_UI_WINDOW', `Unable to update the current application window background: ${String(error)}`);
  }
}

function requireProcessedColor(value: number): void {
  if (!Number.isFinite(value) || !Number.isInteger(value) || value < -2147483648 || value > 4294967295) {
    throw new ExpoSystemUIError('ERR_SYSTEM_UI_COLOR', 'ExpoSystemUI expected a processed 32-bit React Native color or null.');
  }
}

function parseKnownWindowColor(value: string): ParsedBackgroundColor {
  return new ParsedBackgroundColor(value, `#${value.slice(3).toLowerCase()}`);
}

function parseProcessedColor(value: number): ParsedBackgroundColor {
  const unsigned: number = value < 0 ? value + 4294967296 : value;
  const argb: string = unsigned.toString(16).padStart(8, '0').toUpperCase();
  return new ParsedBackgroundColor(`#${argb}`, `#${argb.slice(2).toLowerCase()}`);
}

function parseManifestColor(value: string): ParsedBackgroundColor | null {
  if (!/^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i.test(value)) return null;

  const hex: string = value.slice(1).toUpperCase();
  const argb: string = hex.length === 6 ? `FF${hex}` : hex;

  return new ParsedBackgroundColor(`#${argb}`, `#${argb.slice(2).toLowerCase()}`);
}

function resolvedSystemColorMode(context: common.UIAbilityContext): ConfigurationConstant.ColorMode {
  const mode: number = context.resourceManager.getConfigurationSync().colorMode;
  return mode === 0 ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
}

function readConfiguration(context: common.UIAbilityContext): SystemUIConfiguration {
  const config = new SystemUIConfiguration();

  try {
    applyMetadata(config, context.currentHapModuleInfo.metadata);
  } catch (error) {
    console.warn(`Unable to read Expo System UI module metadata: ${String(error)}`);
  }

  return config;
}

function applyMetadata(config: SystemUIConfiguration, metadata: Array<bundleManager.Metadata>): void {
  metadata.forEach((entry: bundleManager.Metadata): void => {
    if (entry.name === ROOT_BACKGROUND_METADATA) config.backgroundColor = entry.value;
    if (entry.name !== INTERFACE_STYLE_METADATA) return;

    if (entry.value === 'light' || entry.value === 'dark' || entry.value === 'automatic') {
      config.userInterfaceStyle = entry.value;
      return;
    }

    console.warn(`Ignoring invalid Expo System UI interface style '${entry.value}'.`);
  });
}

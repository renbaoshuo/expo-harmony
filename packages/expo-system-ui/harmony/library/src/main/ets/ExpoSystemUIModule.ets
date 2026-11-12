/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type bundleManager from '@ohos.bundle.bundleManager';
import deviceInfo from '@ohos.deviceInfo';
import { Configuration, ConfigurationConstant, common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import {
  ExpoAbilityLifecycleSubscriber,
  ExpoFunction,
  ExpoModule,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';

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
  argb: string;
  rgb: string;

  constructor(argb: string, rgb: string) {
    this.argb = argb;
    this.rgb = rgb;
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
  private readonly configured: ParsedBackgroundColor | null;
  private readonly style: InterfaceStyle;
  private mode: ConfigurationConstant.ColorMode;
  private readonly backgrounds: Map<number, WindowBackgroundState> = new Map<number, WindowBackgroundState>();
  private readonly windows: Map<number, window.Window> = new Map<number, window.Window>();
  private readonly store: Promise<preferences.Preferences | null>;
  private readonly ready: Promise<void>;
  private persisted: ParsedBackgroundColor | null = null;
  private mutation: Promise<void> = Promise.resolve();
  private generation: number = 0;
  private available: boolean = false;
  private windowReady: Promise<void> = Promise.resolve();
  private resolveWindowReady: (() => void) | null = null;
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

    this.store = Promise.resolve()
      .then((): Promise<preferences.Preferences> => preferences.getPreferences(context, { name: PREFERENCES_NAME }))
      .catch((error: Object): preferences.Preferences | null => {
        console.warn(`Unable to open Expo System UI preferences: ${String(error)}`);

        return null;
      });
    this.ready = this.loadPersistedBackground();
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

    try {
      if (deviceInfo.sdkApiVersion >= UI_ABILITY_COLOR_MODE_API) this.context.setColorMode(mode);
      else this.context.getApplicationContext().setColorMode(mode);
    } catch (error) {
      throw new ExpoSystemUIError('ERR_SYSTEM_UI_STYLE', `Unable to update the application interface style: ${String(error)}`);
    }

    // setColorMode can replace the resource manager; read the current instance.
    this.mode = resolvedSystemColorMode(this.context);
  }

  onConfigurationUpdated(mode: ConfigurationConstant.ColorMode | undefined): void {
    if (this.destroyed || this.style !== 'automatic') return;

    this.mode =
      mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK || mode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        ? mode
        : resolvedSystemColorMode(this.context);

    Array.from(this.windows.values()).forEach((target: window.Window): void => {
      this.initializeWindow(target, true, (): boolean => !this.destroyed).catch((error: Object): void => {
        if (!this.destroyed) {
          console.warn(`Unable to refresh the Expo System UI window after a configuration change: ${String(error)}`);
        }
      });
    });
  }

  async initializeWindowFrom(resolve: () => Promise<window.Window>, refresh: boolean, valid: () => boolean): Promise<void> {
    const generation = this.generation;

    await this.serialize(async (): Promise<void> => {
      if (generation !== this.generation || !valid()) return;

      const target: window.Window = await resolve();

      await this.applyWindowState(target, refresh, (): boolean => generation === this.generation && valid());
    });
  }

  async initializeWindow(target: window.Window, refresh: boolean, valid: () => boolean): Promise<void> {
    await this.initializeWindowFrom(async (): Promise<window.Window> => target, refresh, valid);
  }

  private async applyWindowState(target: window.Window, refresh: boolean, valid: () => boolean): Promise<void> {
    await this.ready;

    this.assertActive();
    if (!valid()) return;

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
      background = new WindowBackgroundState(this.systemBackgroundColor(), true);
    }

    if (!valid()) return;

    applyWindowColor(target, background.color.argb);

    this.windows.set(id, target);
    this.backgrounds.set(id, background);
  }

  async setBackgroundColor(target: window.Window, color: ParsedBackgroundColor | null, valid: () => boolean): Promise<void> {
    await this.serialize(async (): Promise<void> => {
      await this.ready;

      this.assertActive();
      requireCurrentWindow(valid);

      const id: number = inspectWindowId(target);
      const background = new WindowBackgroundState(color ?? this.systemBackgroundColor(), color === null);

      applyWindowColor(target, background.color.argb);
      this.windows.set(id, target);
      this.backgrounds.set(id, background);

      if (color === null) await this.removePersistedBackground();
      else await this.persistBackground(color);
      requireCurrentWindow(valid);
    });
  }

  async getBackgroundColor(target: window.Window, valid: () => boolean): Promise<string | null> {
    await this.mutation.catch((): void => {});

    this.assertActive();
    requireCurrentWindow(valid);

    const background: WindowBackgroundState | undefined = this.backgrounds.get(inspectWindowId(target));

    return background === undefined ? null : background.color.rgb;
  }

  beginWindow(): void {
    this.forgetWindow();

    this.available = true;
    this.windowReady = new Promise<void>((resolve): void => {
      this.resolveWindowReady = resolve;
    });
  }

  markWindowReady(): void {
    this.resolveWindowReady?.();
    this.resolveWindowReady = null;
  }

  async waitForWindowReady(runtimeDestroyed: Promise<void>): Promise<void> {
    this.assertActive();

    if (this.resolveWindowReady !== null) {
      await Promise.race([this.windowReady, runtimeDestroyed]);
    }
  }

  captureWindowGuard(): () => boolean {
    const generation = this.generation;
    return (): boolean => !this.destroyed && this.available && generation === this.generation;
  }

  forgetWindow(): void {
    this.generation += 1;
    this.available = false;

    // Release calls waiting on the old stage so they can reject instead of hanging.
    this.markWindowReady();
    this.windows.clear();
    this.backgrounds.clear();
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.forgetWindow();
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
      await store.put(PREFERENCE_KEY, color.argb);
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

const states: WeakMap<common.UIAbilityContext, AbilitySystemUIState> = new WeakMap<common.UIAbilityContext, AbilitySystemUIState>();

function stateForAbility(context: common.UIAbilityContext): AbilitySystemUIState {
  const state = states.get(context);
  if (state === undefined) {
    throw new ExpoSystemUIError(
      'ERR_SYSTEM_UI_ABILITY_NOT_INITIALIZED',
      'Expo System UI requires the autolinked Ability lifecycle subscriber. Use ExpoRNAbility or forward native lifecycle callbacks.',
    );
  }

  return state;
}

export class ExpoSystemUILifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  private readonly state: AbilitySystemUIState;
  private stage?: window.WindowStage;
  private ready: boolean = false;
  private destroyed: boolean = false;

  constructor(context: common.UIAbilityContext) {
    super(context);
    this.state = new AbilitySystemUIState(context);
    states.set(context, this.state);
  }

  override onWindowStageCreate(stage: window.WindowStage): void {
    this.stage = stage;
    this.ready = false;
    this.state.beginWindow();
  }

  override onWindowStageRestore(stage: window.WindowStage): void {
    this.onWindowStageCreate(stage);
  }

  override async onWindowStageReady(stage: window.WindowStage): Promise<void> {
    if (this.destroyed || this.stage !== stage) return;

    this.ready = true;

    try {
      this.state.applyInterfaceStyle();
    } catch (error) {
      console.warn(`Unable to apply Expo System UI interface style: ${String(error)}`);
    }

    const initialization = this.state.initializeWindowFrom(
      (): Promise<window.Window> => stage.getMainWindow(),
      true,
      (): boolean => !this.destroyed && this.stage === stage,
    );
    this.state.markWindowReady();
    await initialization;
  }

  override onForeground(): void {
    const stage = this.stage;
    if (stage === undefined || !this.ready) return;

    this.onWindowStageReady(stage).catch((error: Object): void => {
      if (!this.destroyed && this.stage === stage) console.warn(`Unable to refresh Expo System UI: ${String(error)}`);
    });
  }

  override onConfigurationUpdate(configuration: Configuration): void {
    this.state.onConfigurationUpdated(configuration.colorMode);
  }

  override onWindowStageWillDestroy(): void {
    this.stage = undefined;
    this.ready = false;
    this.state.forgetWindow();
  }

  override onWindowStageDestroy(): void {
    this.onWindowStageWillDestroy();
  }

  override onDestroy(): void {
    this.destroyed = true;
    this.stage = undefined;

    this.state.destroy();
    states.delete(this.context);
  }
}

export class ExpoSystemUIModule extends ExpoModule {
  private destroyed: boolean = false;
  private resolveRuntimeDestroyed: (() => void) | null = null;
  private readonly runtimeDestroyed: Promise<void> = new Promise<void>((resolve): void => {
    this.resolveRuntimeDestroyed = resolve;
  });

  private get state(): AbilitySystemUIState {
    if (this.context.isHeadless) throw new ExpoSystemUIError('ERR_SYSTEM_UI_WINDOW', 'SystemUI requires a UIAbility window.');

    return stateForAbility(this.context.uiAbilityContext);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoSystemUI')
      .asyncFunction(
        'setBackgroundColorAsync',
        ExpoFunction.typed1(ExpoValueTypes.number().nullable(), async (color: number | null): Promise<void> => {
          this.assertActive();
          if (color !== null) requireProcessedColor(color);

          const state = this.state;
          const valid = this.captureWindowGuard(state);
          const target: window.Window = await this.currentWindow(state, valid);

          const parsed: ParsedBackgroundColor | null = color === null ? null : parseProcessedColor(color);

          await state.setBackgroundColor(target, parsed, valid);

          this.assertActive();
        }),
      )
      .asyncFunction('getBackgroundColorAsync', async (): Promise<string | null> => {
        this.assertActive();

        const state = this.state;
        const valid = this.captureWindowGuard(state);
        const target: window.Window = await this.currentWindow(state, valid);

        const color: string | null = await state.getBackgroundColor(target, valid);
        this.assertActive();

        return color;
      })
      .onDestroy((): void => {
        this.destroyed = true;
        this.resolveRuntimeDestroyed?.();
        this.resolveRuntimeDestroyed = null;
      });
  }

  private captureWindowGuard(state: AbilitySystemUIState): () => boolean {
    const valid = state.captureWindowGuard();
    return (): boolean => {
      this.assertActive();
      return valid();
    };
  }

  private async currentWindow(state: AbilitySystemUIState, valid: () => boolean): Promise<window.Window> {
    // RNOH can return the main window while its page is still loading.
    await state.waitForWindowReady(this.runtimeDestroyed);
    requireCurrentWindow(valid);

    try {
      return await this.context.getReactNativeWindow();
    } catch (error) {
      this.assertActive();
      throw new ExpoSystemUIError('ERR_SYSTEM_UI_WINDOW', `Unable to locate the current React Native window: ${String(error)}`);
    }
  }

  private assertActive(): void {
    if (this.destroyed || !this.context.isValid) {
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

function requireCurrentWindow(valid: () => boolean): void {
  if (!valid()) {
    throw new ExpoSystemUIError('ERR_SYSTEM_UI_WINDOW', 'The React Native window was removed or replaced before the SystemUI operation completed.');
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

  return mode === resourceManager.ColorMode.DARK ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
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

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
  ReactRuntimeAppearance,
  ReactRuntimeBinding,
  ReactRuntimeContext,
  parseExpoColor,
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
  readonly argb: string;

  constructor(argb: string) {
    this.argb = argb;
  }

  get rgb(): string {
    return `#${this.argb.slice(3).toLowerCase()}`;
  }
}

class RuntimeAppearance {
  readonly runtimeId: number;
  readonly style?: InterfaceStyle;
  background: ParsedBackgroundColor | null = null;

  constructor(runtimeId: number, config: ReactRuntimeAppearance) {
    this.runtimeId = runtimeId;
    this.style = config.userInterfaceStyle;

    if (config.backgroundColor === undefined) return;

    try {
      this.background = formatArgb(parseExpoColor(config.backgroundColor));
    } catch (_) {
      console.warn('Ignoring an invalid Expo project background color.');
    }
  }
}

class WindowBackgroundState {
  readonly target: window.Window;
  color: ParsedBackgroundColor;
  followsSystem: boolean;
  private listener?: (event: window.WindowEventType) => void;

  constructor(target: window.Window, color: ParsedBackgroundColor, followsSystem: boolean) {
    this.target = target;
    this.color = color;
    this.followsSystem = followsSystem;
  }

  apply(color: ParsedBackgroundColor, followsSystem: boolean): void {
    applyWindowColor(this.target, color.argb);

    this.color = color;
    this.followsSystem = followsSystem;
  }

  observeDestruction(onDestroy: () => void): void {
    if (!canIUse('SystemCapability.Window.SessionManager')) return;

    const listener = (event: window.WindowEventType): void => {
      if (event === window.WindowEventType.WINDOW_DESTROYED) onDestroy();
    };

    try {
      this.target.on('windowEvent', listener);
      this.listener = listener;
    } catch (error) {
      console.warn(`Unable to observe Expo System UI window destruction: ${String(error)}`);
    }
  }

  close(): void {
    const listener = this.listener;
    if (listener === undefined) return;

    this.listener = undefined;

    try {
      this.target.off('windowEvent', listener);
    } catch (_) {
      // The native window can be destroyed before cleanup reaches ArkTS.
    }
  }
}

class AbilitySystemUIState {
  private readonly context: common.UIAbilityContext;
  private readonly configured: ParsedBackgroundColor | null;
  private readonly style: InterfaceStyle;
  private appliedStyle?: InterfaceStyle;
  private appearance?: RuntimeAppearance;
  private readyStage?: window.WindowStage;
  private mode: ConfigurationConstant.ColorMode;
  private readonly windows: Map<number, WindowBackgroundState> = new Map<number, WindowBackgroundState>();
  private readonly store: Promise<preferences.Preferences | null>;
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
  }

  private applyInterfaceStyle(style: InterfaceStyle): void {
    this.assertActive();
    if (this.appliedStyle === style) return;

    let mode: ConfigurationConstant.ColorMode;
    if (style === 'dark') {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (style === 'light') {
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

    this.appliedStyle = style;
    // Inherited mode uses the resource manager returned after setColorMode.
    this.mode = mode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET ? resolvedSystemColorMode(this.context) : mode;
  }

  onConfigurationUpdated(reported?: ConfigurationConstant.ColorMode): void {
    if (this.destroyed) return;

    const mode = reported === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ||
      reported === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ? reported : resolvedSystemColorMode(this.context);
    if (mode === this.mode) return;

    const generation = this.generation;
    this.mode = mode;

    this.serialize(async (): Promise<void> => {
      if (this.destroyed || generation !== this.generation) return;

      const color = this.systemBackgroundColor();
      this.windows.forEach((background: WindowBackgroundState): void => {
        if (!background.followsSystem || background.color.argb === color.argb) return;

        try {
          background.apply(color, true);
        } catch (error) {
          console.warn(`Unable to refresh the Expo System UI window after a configuration change: ${String(error)}`);
        }
      });
    }).catch((error: Object): void => {
      if (!this.destroyed) console.warn(`Unable to refresh Expo System UI: ${String(error)}`);
    });
  }

  async initializeWindow(stage: window.WindowStage): Promise<void> {
    this.readyStage = stage;
    await this.applyWindowAppearance(stage);
  }

  async bindRuntimeAppearance(appearance: RuntimeAppearance): Promise<() => void> {
    this.appearance = appearance;
    await this.refreshWindowAppearance();

    return (): void => {
      if (this.destroyed || this.appearance !== appearance) return;

      this.appearance = undefined;
      this.refreshWindowAppearance();
    };
  }

  private async refreshWindowAppearance(): Promise<void> {
    if (this.readyStage === undefined) return;

    try {
      await this.applyWindowAppearance(this.readyStage);
    } catch (error) {
      if (!this.destroyed) console.warn(`Unable to restore or apply Expo runtime appearance: ${String(error)}`);
    }
  }

  private async applyWindowAppearance(stage: window.WindowStage): Promise<void> {
    const valid = this.captureWindowGuard();
    const appearance = this.appearance;

    await this.serialize(async (): Promise<void> => {
      if (!valid() || appearance !== this.appearance) return;

      const color = appearance === undefined
        ? (await this.loadPersistedBackground()) ?? this.configured
        : appearance.background;

      if (!valid() || appearance !== this.appearance) return;

      const win = stage.getMainWindowSync();
      const style = deviceInfo.sdkApiVersion >= UI_ABILITY_COLOR_MODE_API ? appearance?.style ?? this.style : this.style;

      try {
        this.applyInterfaceStyle(style);
      } catch (error) {
        console.warn(`Unable to apply Expo System UI interface style: ${String(error)}`);
      }

      const mainId = this.applyBackground(win, color);
      const applied = color ?? this.systemBackgroundColor();

      // RNOH can host its surface in a previously styled subwindow.
      this.windows.forEach((background: WindowBackgroundState, id: number): void => {
        if (id === mainId) return;

        try {
          background.apply(applied, color === null);
        } catch (error) {
          console.warn(`Unable to restore an Expo System UI window after a runtime change: ${String(error)}`);
        }
      });
    });
  }

  async setBackgroundColor(target: window.Window, color: ParsedBackgroundColor | null, valid: () => boolean): Promise<void> {
    await this.serialize(async (): Promise<void> => {
      this.assertActive();
      requireCurrentWindow(valid);

      this.applyBackground(target, color);

      if (this.appearance !== undefined) this.appearance.background = color;
      else await this.persistBackground(color);

      requireCurrentWindow(valid);
    });
  }

  async getBackgroundColor(target: window.Window, valid: () => boolean): Promise<string | null> {
    await this.mutation.catch((): void => {});

    this.assertActive();
    requireCurrentWindow(valid);

    const background: WindowBackgroundState | undefined = this.windows.get(inspectWindowId(target));

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

  captureWindowGuard(runtimeId?: number): () => boolean {
    const generation = this.generation;
    const appearance = this.appearance;

    return (): boolean => !this.destroyed && this.available && generation === this.generation &&
      (runtimeId === undefined || (this.appearance === appearance && (appearance === undefined || appearance.runtimeId === runtimeId)));
  }

  forgetWindow(): void {
    this.generation += 1;
    this.available = false;
    this.readyStage = undefined;
    this.appliedStyle = undefined;

    // Release calls waiting on the old stage so they can reject instead of hanging.
    this.markWindowReady();
    this.windows.forEach((state: WindowBackgroundState): void => state.close());
    this.windows.clear();
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.appearance = undefined;
    this.forgetWindow();
  }

  private async serialize(operation: () => Promise<void>): Promise<void> {
    this.assertActive();

    const next: Promise<void> = this.mutation.catch((): void => {}).then(operation);
    this.mutation = next;

    await next;
  }

  private applyBackground(win: window.Window, color: ParsedBackgroundColor | null): number {
    const id = inspectWindowId(win);
    const applied = color ?? this.systemBackgroundColor();
    const current = this.windows.get(id);

    if (current !== undefined) {
      current.apply(applied, color === null);
      return id;
    }

    applyWindowColor(win, applied.argb);

    const background = new WindowBackgroundState(win, applied, color === null);
    this.windows.set(id, background);
    background.observeDestruction((): void => {
      if (this.windows.get(id) !== background) return;

      this.windows.delete(id);
      background.close();
    });

    return id;
  }

  private async loadPersistedBackground(): Promise<ParsedBackgroundColor | null> {
    const store: preferences.Preferences | null = await this.store;
    if (store === null || this.destroyed) return null;

    try {
      const value: preferences.ValueType = await store.get(PREFERENCE_KEY, '');

      return typeof value === 'string' ? parseManifestColor(value) : null;
    } catch (error) {
      console.warn(`Unable to read Expo System UI preferences: ${String(error)}`);
      return null;
    }
  }

  private async persistBackground(color: ParsedBackgroundColor | null): Promise<void> {
    const store: preferences.Preferences | null = await this.store;
    if (store === null || this.destroyed) return;

    try {
      if (color === null) await store.delete(PREFERENCE_KEY);
      else await store.put(PREFERENCE_KEY, color.argb);
      await store.flush();
    } catch (error) {
      console.warn(`Unable to persist the Expo System UI background: ${String(error)}`);
    }
  }

  private systemBackgroundColor(): ParsedBackgroundColor {
    return new ParsedBackgroundColor(
      this.mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? DARK_WINDOW_BACKGROUND : LIGHT_WINDOW_BACKGROUND,
    );
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
    if (this.destroyed || this.stage !== stage || this.ready) return;

    this.ready = true;

    const ready = this.state.initializeWindow(stage);
    this.state.markWindowReady();
    await ready;
  }

  override onForeground(): void {
    if (this.ready) this.state.onConfigurationUpdated();
  }

  override onConfigurationUpdate(configuration: Configuration): void {
    this.state.onConfigurationUpdated(configuration.colorMode);
  }

  override onWindowStageWillDestroy(stage?: window.WindowStage): void {
    if (stage !== undefined && this.stage !== stage) return;

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

export class ExpoSystemUIRuntimeBinding implements ReactRuntimeBinding {
  constructor(_context: common.Context) {}

  async bind(runtime: ReactRuntimeContext): Promise<(() => void) | void> {
    const config = runtime.appearance;
    if (runtime.isHeadless || config === undefined) return;

    const state = states.get(runtime.core.uiAbilityContext);
    if (state === undefined) return;

    return await state.bindRuntimeAppearance(new RuntimeAppearance(runtime.instance.getId(), config));
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
          const parsed = color === null ? null : parseProcessedColor(color);

          const state = this.state;
          const valid = this.captureWindowGuard(state);
          const target: window.Window = await this.currentWindow(state, valid);

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
    const valid = state.captureWindowGuard(this.context.runtimeId);

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

function parseProcessedColor(value: number): ParsedBackgroundColor {
  try {
    return formatArgb(parseExpoColor(value));
  } catch (_) {
    throw new ExpoSystemUIError('ERR_SYSTEM_UI_COLOR', 'ExpoSystemUI expected a processed 32-bit React Native color or null.');
  }
}

function formatArgb(color: number): ParsedBackgroundColor {
  return new ParsedBackgroundColor(`#${color.toString(16).padStart(8, '0').toUpperCase()}`);
}

function parseManifestColor(value: string): ParsedBackgroundColor | null {
  if (!/^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i.test(value)) return null;

  const hex: string = value.slice(1).toUpperCase();
  const argb: string = hex.length === 6 ? `FF${hex}` : hex;

  return new ParsedBackgroundColor(`#${argb}`);
}

function resolvedSystemColorMode(context: common.UIAbilityContext): ConfigurationConstant.ColorMode {
  try {
    const mode = context.resourceManager.getConfigurationSync().colorMode;

    if (mode === resourceManager.ColorMode.DARK) return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    if (mode === resourceManager.ColorMode.LIGHT) return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  } catch (error) {
    console.warn(`Unable to read the Expo System UI resource configuration: ${String(error)}`);
  }

  return context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
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

import type bundleManager from '@ohos.bundle.bundleManager';
import type common from '@ohos.app.ability.common';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  ExpoAbilityLifecycleSubscriber,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';

const VISIBILITY_EVENT_NAME: string = 'ExpoNavigationBar.didChange';
const BACKGROUND_METADATA: string = 'expo.harmony.navigationBar.backgroundColor';
const BUTTON_STYLE_METADATA: string = 'expo.harmony.navigationBar.barStyle';
const POSITION_METADATA: string = 'expo.harmony.navigationBar.position';
const VISIBILITY_METADATA: string = 'expo.harmony.navigationBar.visibility';
// Harmony has no Android-style system UI bitmask. Preserve the Android hide-navigation bit
// so consumers that only inspect that flag keep working across platforms.
const ANDROID_HIDE_NAVIGATION_FLAG: number = 2;
const CONFIG_BACKGROUND: string = 'backgroundColor';
const CONFIG_BUTTON_STYLE: string = 'buttonStyle';
const CONFIG_POSITION: string = 'position';
const CONFIG_VISIBILITY: string = 'visibility';

type NavigationBarButtonStyle = 'light' | 'dark';
type NavigationBarPosition = 'relative' | 'absolute';
type NavigationBarVisibility = 'visible' | 'hidden';

const BUTTON_STYLE_TYPE = ExpoValueTypes.enumerable<NavigationBarButtonStyle>('navigation bar button style', {
  light: 'light',
  dark: 'dark',
});
const POSITION_TYPE = ExpoValueTypes.enumerable<NavigationBarPosition>('navigation bar position', {
  relative: 'relative',
  absolute: 'absolute',
});
const VISIBILITY_TYPE = ExpoValueTypes.enumerable<NavigationBarVisibility>('navigation bar visibility', {
  visible: 'visible',
  hidden: 'hidden',
});

class ExpoNavigationBarError extends ExpoModuleError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoNavigationBarError';
  }
}

class NavigationBarConfiguration {
  backgroundColor: string | null = null;
  buttonStyle: NavigationBarButtonStyle | null = null;
  position: NavigationBarPosition | null = null;
  visibility: NavigationBarVisibility | null = null;
}

class NavigationBarVisibilityEvent {
  visibility: NavigationBarVisibility;
  rawVisibility: number;

  constructor(visibility: NavigationBarVisibility) {
    this.visibility = visibility;
    this.rawVisibility = visibility === 'hidden' ? ANDROID_HIDE_NAVIGATION_FLAG : 0;
  }
}

type NavigationBarListener = (event: NavigationBarVisibilityEvent) => void;

class AbilityNavigationBarState {
  private readonly config: NavigationBarConfiguration;
  private stage?: window.WindowStage;
  private generation: number = 0;
  private destroyed: boolean = false;
  private configuredId: number | null = null;
  private readonly applied: Set<string> = new Set();
  private queue: Promise<void> = Promise.resolve();
  private readonly listeners: Set<NavigationBarListener> = new Set();
  private observed?: window.Window;
  private last: NavigationBarVisibility | null = null;
  private readonly listener = (options: window.AvoidAreaOptions): void => {
    if (options.type === window.AvoidAreaType.TYPE_SYSTEM || options.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      this.publishVisibility(options.type === window.AvoidAreaType.TYPE_SYSTEM);
    }
  };

  constructor(context: common.UIAbilityContext) {
    this.config = readConfiguration(context);
  }

  setStage(stage: window.WindowStage): void {
    this.clearWindow();
    this.stage = stage;
  }

  clearWindow(): void {
    this.generation += 1;
    this.stage = undefined;
    this.configuredId = null;
    this.applied.clear();
    this.detachWindow();
  }

  destroy(): void {
    this.destroyed = true;
    this.clearWindow();
    this.listeners.clear();
  }

  async prepare(): Promise<void> {
    await this.useWindow(async (): Promise<void> => {});
  }

  refresh(): void {
    if (this.destroyed || this.stage === undefined) return;
    this.prepare().catch((error: Object): void => {
      if (!this.destroyed && this.stage !== undefined) console.warn(`Unable to initialize Expo NavigationBar: ${String(error)}`);
    });
  }

  addListener(listener: NavigationBarListener): void {
    this.listeners.add(listener);
    this.refresh();
  }

  removeListener(listener: NavigationBarListener): void {
    this.listeners.delete(listener);
    if (this.listeners.size === 0) this.detachWindow();
  }

  async useWindow<T>(operation: (target: window.Window) => Promise<T>, active: () => boolean = (): boolean => true, key?: string): Promise<T> {
    const stage = this.stage;
    const generation = this.generation;
    const assertCurrent = (): void => {
      if (this.destroyed || !active())
        throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_DESTROYED', 'The Expo NavigationBar owner has been destroyed.');
      if (stage === undefined || this.stage !== stage || this.generation !== generation) {
        throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_WINDOW', 'The Expo NavigationBar window is no longer available.');
      }
    };

    const next = this.queue
      .catch((): void => {})
      .then(async (): Promise<T> => {
        assertCurrent();

        const target = await (stage as window.WindowStage).getMainWindow();
        assertCurrent();

        await this.prepareWindow(target, assertCurrent);
        assertCurrent();

        const result = await operation(target);
        assertCurrent();
        if (key !== undefined) this.applied.add(key);

        return result;
      });

    this.queue = next.then(
      (): void => {},
      (): void => {},
    );

    return await next;
  }

  private async prepareWindow(target: window.Window, assertCurrent: () => void): Promise<void> {
    const id = target.getWindowProperties().id;
    if (this.configuredId !== id) {
      this.configuredId = id;
      this.applied.clear();
    }

    const config = this.config;
    const position = config.position;
    const color = config.backgroundColor;
    const style = config.buttonStyle;
    const visibility = config.visibility;

    if (position !== null)
      await this.applyOption(CONFIG_POSITION, (): Promise<void> => target.setWindowLayoutFullScreen(position === 'absolute'), assertCurrent);
    if (color !== null)
      await this.applyOption(
        CONFIG_BACKGROUND,
        (): Promise<void> => target.setWindowSystemBarProperties({ navigationBarColor: color }),
        assertCurrent,
      );
    if (style !== null) await this.applyOption(CONFIG_BUTTON_STYLE, (): Promise<void> => applyButtonStyle(target, style), assertCurrent);
    if (visibility !== null)
      await this.applyOption(CONFIG_VISIBILITY, (): Promise<void> => setNavigationBarVisibility(target, visibility === 'visible'), assertCurrent);
    assertCurrent();

    if (this.listeners.size > 0 && this.observed !== target) {
      this.detachWindow();
      target.on('avoidAreaChange', this.listener);
      this.observed = target;
      this.last = inspectVisibility(target);
    }
  }

  private async applyOption(key: string, operation: () => Promise<void>, assertCurrent: () => void): Promise<void> {
    assertCurrent();
    if (this.applied.has(key)) return;

    try {
      await operation();
    } catch (error) {
      assertCurrent();
      console.warn(`Unable to apply Expo NavigationBar startup ${key}: ${String(error)}`);

      return;
    }

    assertCurrent();
    this.applied.add(key);
  }

  private detachWindow(): void {
    if (this.observed !== undefined) {
      try {
        this.observed.off('avoidAreaChange', this.listener);
      } catch (error) {
        console.warn(`Unable to detach Expo NavigationBar observer: ${String(error)}`);
      }
    }
    this.observed = undefined;
    this.last = null;
  }

  private publishVisibility(force: boolean): void {
    if (this.destroyed || this.observed === undefined) return;
    try {
      const visibility = inspectVisibility(this.observed);
      if (!force && this.last === visibility) return;

      this.last = visibility;

      const event = new NavigationBarVisibilityEvent(visibility);

      this.listeners.forEach((listener: NavigationBarListener): void => {
        try {
          listener(event);
        } catch (error) {
          console.warn(`Unable to deliver Expo NavigationBar visibility: ${String(error)}`);
        }
      });
    } catch (error) {
      console.warn(`Unable to inspect Expo NavigationBar visibility: ${String(error)}`);
    }
  }
}

const abilityStates: WeakMap<common.UIAbilityContext, AbilityNavigationBarState> = new WeakMap();

export class ExpoNavigationBarLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  private readonly state: AbilityNavigationBarState;
  private ready: boolean = false;

  constructor(context: common.UIAbilityContext) {
    super(context);
    this.state = new AbilityNavigationBarState(context);
    abilityStates.set(context, this.state);
  }

  override onWindowStageCreate(stage: window.WindowStage): void {
    this.ready = false;
    this.state.setStage(stage);
  }
  override onWindowStageRestore(stage: window.WindowStage): void {
    this.onWindowStageCreate(stage);
  }
  override async onWindowStageSetup(): Promise<void> {
    this.ready = true;
    await this.state.prepare();
  }
  override onForeground(): void {
    if (this.ready) this.state.refresh();
  }
  override onWindowStageWillDestroy(): void {
    this.state.clearWindow();
  }
  override onWindowStageDestroy(): void {
    this.state.clearWindow();
  }
  override onDestroy(): void {
    this.state.destroy();
    abilityStates.delete(this.context);
  }
}

export class ExpoNavigationBarModule extends ExpoModule {
  private readonly state?: AbilityNavigationBarState;
  private destroyed: boolean = false;
  private observing: boolean = false;
  private readonly onVisibility = (event: NavigationBarVisibilityEvent): void => {
    if (this.observing && this.isActive()) this.sendEvent(VISIBILITY_EVENT_NAME, event);
  };

  constructor(context: ExpoModuleContext) {
    super(context);

    const state = abilityStates.get(context.uiAbilityContext);
    if (state === undefined && !context.isHeadless)
      throw new ExpoNavigationBarError(
        'ERR_NAVIGATION_BAR_ABILITY_NOT_INITIALIZED',
        'Expo NavigationBar requires its autolinked Ability lifecycle subscriber.',
      );

    this.state = state;
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoNavigationBar')
      .events([VISIBILITY_EVENT_NAME])
      .asyncFunction(
        'setBackgroundColorAsync',
        ExpoFunction.typed1(ExpoValueTypes.number(), async (color: number): Promise<void> => {
          const value = requireProcessedColor(color);
          await this.useWindow(async (target: window.Window): Promise<void> => {
            await target.setWindowSystemBarProperties({ navigationBarColor: value });
          }, CONFIG_BACKGROUND);
        }),
      )
      .asyncFunction(
        'getBackgroundColorAsync',
        async (): Promise<string> =>
          this.useWindow(
            async (target: window.Window): Promise<string> => exposeWindowColor(target.getWindowSystemBarProperties().navigationBarColor),
          ),
      )
      .asyncFunction(
        'setButtonStyleAsync',
        ExpoFunction.typed1(BUTTON_STYLE_TYPE, async (style: NavigationBarButtonStyle): Promise<void> => {
          await this.useWindow(async (target: window.Window): Promise<void> => {
            await applyButtonStyle(target, style);
          }, CONFIG_BUTTON_STYLE);
        }),
      )
      .asyncFunction(
        'getButtonStyleAsync',
        async (): Promise<NavigationBarButtonStyle> =>
          this.useWindow(
            async (target: window.Window): Promise<NavigationBarButtonStyle> => inspectButtonStyle(target.getWindowSystemBarProperties()),
          ),
      )
      .asyncFunction(
        'setVisibilityAsync',
        ExpoFunction.typed1(VISIBILITY_TYPE, async (visibility: NavigationBarVisibility): Promise<void> => {
          await this.useWindow(async (target: window.Window): Promise<void> => {
            try {
              await setNavigationBarVisibility(target, visibility === 'visible');
            } catch (error) {
              throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_VISIBILITY', `Unable to set Harmony navigation bar visibility: ${String(error)}`);
            }
          }, CONFIG_VISIBILITY);
        }),
      )
      .asyncFunction(
        'getVisibilityAsync',
        async (): Promise<NavigationBarVisibility> =>
          this.useWindow(async (target: window.Window): Promise<NavigationBarVisibility> => inspectVisibility(target)),
      )
      .asyncFunction(
        'setPositionAsync',
        ExpoFunction.typed1(POSITION_TYPE, async (position: NavigationBarPosition): Promise<void> => {
          await this.useWindow(async (target: window.Window): Promise<void> => {
            await target.setWindowLayoutFullScreen(position === 'absolute');
          }, CONFIG_POSITION);
        }),
      )
      .asyncFunction(
        'getPositionAsync',
        async (): Promise<NavigationBarPosition> =>
          this.useWindow(
            async (target: window.Window): Promise<NavigationBarPosition> =>
              target.getWindowProperties().isLayoutFullScreen ? 'absolute' : 'relative',
          ),
      )
      .onStartObserving(VISIBILITY_EVENT_NAME, (): void => {
        if (!this.isActive() || this.observing) return;

        this.observing = true;
        this.state?.addListener(this.onVisibility);
      })
      .onStopObserving(VISIBILITY_EVENT_NAME, (): void => this.stopObserving())
      .onPrepareForReload(async (): Promise<void> => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private async useWindow<T>(operation: (target: window.Window) => Promise<T>, key?: string): Promise<T> {
    if (this.state === undefined) throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_WINDOW', 'NavigationBar requires a UIAbility window.');

    return await this.state.useWindow(operation, (): boolean => this.isActive(), key);
  }

  private isActive(): boolean {
    return !this.destroyed && this.context.isValid;
  }
  private stopObserving(): void {
    this.observing = false;
    this.state?.removeListener(this.onVisibility);
  }
  private destroy(): void {
    this.destroyed = true;
    this.stopObserving();
  }
}

async function applyButtonStyle(target: window.Window, style: NavigationBarButtonStyle): Promise<void> {
  await target.setWindowSystemBarProperties({
    navigationBarContentColor: style === 'light' ? '#FFFFFFFF' : '#FF000000',
  });
}

async function setNavigationBarVisibility(target: window.Window, visible: boolean): Promise<void> {
  await target.setSpecificSystemBarEnabled('navigation', visible, false);

  try {
    await target.setSpecificSystemBarEnabled('navigationIndicator', visible, false);
  } catch (error) {
    if (!isCapabilityUnsupported(error)) {
      throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_VISIBILITY', `Unable to update the Harmony navigation indicator: ${String(error)}`);
    }
    // Three-button-only devices may not expose a separate gesture indicator.
  }
}

function inspectVisibility(target: window.Window): NavigationBarVisibility {
  const system: window.AvoidArea = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
  if (hasNavigationEdge(system)) return 'visible';

  try {
    const indicator: window.AvoidArea = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    if (hasAnyEdge(indicator)) return 'visible';
  } catch (error) {
    if (!isCapabilityUnsupported(error)) {
      throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_VISIBILITY', `Unable to inspect the Harmony navigation indicator: ${String(error)}`);
    }
  }

  return 'hidden';
}

function hasNavigationEdge(area: window.AvoidArea): boolean {
  return area.visible && (area.leftRect.width > 0 || area.rightRect.width > 0 || area.bottomRect.height > 0);
}

function hasAnyEdge(area: window.AvoidArea): boolean {
  return area.visible && (area.leftRect.width > 0 || area.topRect.height > 0 || area.rightRect.width > 0 || area.bottomRect.height > 0);
}

function isCapabilityUnsupported(error: Object): boolean {
  const value = error as BusinessError;
  return value.code === 801;
}

function inspectButtonStyle(props: window.SystemBarProperties): NavigationBarButtonStyle {
  if (typeof props.navigationBarContentColor === 'string') {
    return isLightColor(props.navigationBarContentColor) ? 'light' : 'dark';
  }

  if (typeof props.isNavigationBarLightIcon === 'boolean') {
    return props.isNavigationBarLightIcon ? 'light' : 'dark';
  }

  throw new ExpoNavigationBarError(
    'ERR_NAVIGATION_BAR_BUTTON_STYLE_UNAVAILABLE',
    'HarmonyOS did not expose the current navigation bar content color.',
  );
}

function isLightColor(value: string): boolean {
  const match: RegExpMatchArray | null = value.match(/^#(?:[0-9a-f]{2})?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);
  if (match === null) {
    throw new ExpoNavigationBarError(
      'ERR_NAVIGATION_BAR_BUTTON_STYLE_UNAVAILABLE',
      `HarmonyOS returned an unsupported navigation bar color '${value}'.`,
    );
  }

  const red: number = parseInt(match[1], 16);
  const green: number = parseInt(match[2], 16);
  const blue: number = parseInt(match[3], 16);

  return red * 299 + green * 587 + blue * 114 >= 128000;
}

function requireProcessedColor(value: number): string {
  if (!Number.isInteger(value) || value < -2147483648 || value > 4294967295) {
    throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_COLOR', 'Expo NavigationBar expected a processed 32-bit React Native color.');
  }

  const unsigned: number = value < 0 ? value + 4294967296 : value;

  return `#${unsigned.toString(16).padStart(8, '0').toUpperCase()}`;
}

function exposeWindowColor(value: string | undefined): string {
  if (typeof value !== 'string') {
    throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_COLOR_UNAVAILABLE', 'HarmonyOS did not expose the current navigation bar background color.');
  }

  const argb: RegExpMatchArray | null = value.match(/^#([0-9a-f]{8})$/i);
  if (argb !== null) {
    return `#${argb[1].slice(2)}${argb[1].slice(0, 2)}`.toLowerCase();
  }

  if (/^#[0-9a-f]{6}$/i.test(value)) return value.toLowerCase();

  throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_COLOR_UNAVAILABLE', `HarmonyOS returned an unsupported navigation bar color '${value}'.`);
}

function readConfiguration(context: common.UIAbilityContext): NavigationBarConfiguration {
  const config = new NavigationBarConfiguration();

  try {
    applyMetadata(config, context.currentHapModuleInfo.metadata);
  } catch (error) {
    console.warn(`Unable to read the Expo NavigationBar module metadata: ${String(error)}`);
  }

  return config;
}

function applyMetadata(config: NavigationBarConfiguration, metadata: Array<bundleManager.Metadata>): void {
  metadata.forEach((entry: bundleManager.Metadata): void => {
    if (entry.name === BACKGROUND_METADATA) {
      if (/^#[0-9a-f]{8}$/i.test(entry.value)) config.backgroundColor = entry.value;
      else console.warn(`Ignoring invalid ${BACKGROUND_METADATA} metadata value '${entry.value}'.`);
    }

    if (entry.name === BUTTON_STYLE_METADATA) {
      if (entry.value === 'light' || entry.value === 'dark') config.buttonStyle = entry.value;
      else console.warn(`Ignoring invalid ${BUTTON_STYLE_METADATA} metadata value '${entry.value}'.`);
    }

    if (entry.name === POSITION_METADATA) {
      if (entry.value === 'relative' || entry.value === 'absolute') config.position = entry.value;
      else console.warn(`Ignoring invalid ${POSITION_METADATA} metadata value '${entry.value}'.`);
    }

    if (entry.name === VISIBILITY_METADATA) {
      if (entry.value === 'visible' || entry.value === 'hidden') config.visibility = entry.value;
      else console.warn(`Ignoring invalid ${VISIBILITY_METADATA} metadata value '${entry.value}'.`);
    }
  });
}

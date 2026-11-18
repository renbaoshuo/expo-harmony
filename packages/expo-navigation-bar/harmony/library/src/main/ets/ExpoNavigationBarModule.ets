/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { bundleManager, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
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
const STYLE_METADATA: string = 'expo.harmony.navigationBar.style';
const HIDDEN_METADATA: string = 'expo.harmony.navigationBar.hidden';
const ANDROID_HIDE_NAVIGATION_FLAG: number = 2;
const WINDOW_MANAGER_CAPABILITY = 'SystemCapability.WindowManager.WindowManager.Core';
const WINDOW_SESSION_CAPABILITY = 'SystemCapability.Window.SessionManager';
const TWO_IN_ONE_DEVICE_TYPE = '2in1';
const CAPABILITY_UNSUPPORTED = 801;
const CONFIG_STYLE: string = 'style';
const CONFIG_HIDDEN: string = 'hidden';

type NavigationBarStyle = 'light' | 'dark';
type NavigationBarVisibility = 'visible' | 'hidden';

const STYLE_VALUES: Record<string, NavigationBarStyle> = {
  'light': 'light',
  'dark': 'dark',
};
const STYLE_TYPE = ExpoValueTypes.enumerable<NavigationBarStyle>('navigation bar style', STYLE_VALUES);

class ExpoNavigationBarError extends ExpoModuleError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoNavigationBarError';
  }
}

class NavigationBarConfiguration {
  style: NavigationBarStyle | null = null;
  hidden: boolean | null = null;
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
  readonly startup: NavigationBarConfiguration;
  private style: NavigationBarStyle | null;
  private hidden: boolean | null;
  private target?: window.Window;
  private generation: number = 0;
  private destroyed: boolean = false;
  private readonly applied: Set<string> = new Set();
  private queue: Promise<void> = Promise.resolve();
  private readonly listeners: Set<NavigationBarListener> = new Set();
  private observer?: (options: window.AvoidAreaOptions) => void;
  private last: NavigationBarVisibility | null = null;

  constructor(context: common.UIAbilityContext) {
    this.startup = readConfiguration(context);
    this.style = this.startup.style;
    this.hidden = this.startup.hidden;
  }

  async setWindow(target: window.Window): Promise<void> {
    if (this.target !== target) {
      this.clearWindow();
      this.target = target;
    }

    await this.prepare();
  }

  clearWindow(): void {
    this.generation += 1;
    this.detachWindow();
    this.target = undefined;
    this.applied.clear();
  }

  destroy(): void {
    this.destroyed = true;
    this.clearWindow();
    this.listeners.clear();
  }

  private async prepare(): Promise<void> {
    await this.useWindow(async (target: window.Window, check: () => void): Promise<void> => {
      await this.prepareWindow(target, check);

      this.publishVisibility(target, false);
    });
  }

  refresh(): void {
    if (this.destroyed || this.target === undefined) return;

    const generation = this.generation;

    this.prepare().catch((error: Object): void => {
      if (!this.destroyed && this.generation === generation) console.warn(`Unable to initialize Expo NavigationBar: ${String(error)}`);
    });
  }

  addListener(listener: NavigationBarListener): void {
    this.listeners.add(listener);
    this.refresh();
  }

  removeListener(listener: NavigationBarListener): void {
    this.listeners.delete(listener);
    if (this.listeners.size === 0) {
      this.detachWindow();
      this.last = null;
    }
  }

  async setStyle(style: NavigationBarStyle, active: () => boolean): Promise<void> {
    await this.useWindow(async (target: window.Window, check: () => void): Promise<void> => {
      await applyStyle(target, style);
      check();

      this.style = style;
      this.applied.add(CONFIG_STYLE);
    }, active);
  }

  async setHidden(hidden: boolean, active: () => boolean): Promise<void> {
    await this.useWindow(async (target: window.Window, check: () => void): Promise<void> => {
      await setNavigationBarVisibility(target, !hidden);
      check();

      this.hidden = hidden;
      this.applied.add(CONFIG_HIDDEN);
    }, active);
  }

  async useWindow<T>(
    operation: (target: window.Window, check: () => void) => Promise<T>,
    active: () => boolean = (): boolean => true,
  ): Promise<T> {
    const win = this.target;
    const generation = this.generation;

    const check = (): void => {
      if (this.destroyed || !active()) {
        throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_DESTROYED', 'The Expo NavigationBar owner has been destroyed.');
      }
      if (win === undefined || this.generation !== generation) {
        throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_WINDOW', 'The Expo NavigationBar window is no longer available.');
      }
    };

    const next = this.queue
      .then(async (): Promise<T> => {
        check();

        const result = await operation(win as window.Window, check);
        check();

        return result;
      });

    this.queue = next.then(
      (): void => {},
      (): void => {},
    );

    return await next;
  }

  private async prepareWindow(target: window.Window, check: () => void): Promise<void> {
    const style = this.style;
    const hidden = this.hidden;

    if (style !== null && supportsNavigationBarChanges(WINDOW_MANAGER_CAPABILITY)) {
      await this.applyOption(CONFIG_STYLE, (): Promise<void> => applyStyle(target, style), check);
    }
    if (hidden !== null && supportsNavigationBarChanges(WINDOW_SESSION_CAPABILITY)) {
      await this.applyOption(CONFIG_HIDDEN, (): Promise<void> => setNavigationBarVisibility(target, !hidden), check);
    }

    check();

    if (this.listeners.size === 0 || this.observer !== undefined || !canIUse(WINDOW_MANAGER_CAPABILITY)) return;

    const observer = (options: window.AvoidAreaOptions): void => {
      if (this.observer !== observer) return;
      if (options.type === window.AvoidAreaType.TYPE_SYSTEM || options.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        this.publishVisibility(target);
      }
    };

    try {
      target.on('avoidAreaChange', observer);
      this.observer = observer;
    } catch (error) {
      console.warn(`Unable to initialize Expo NavigationBar visibility observation: ${String(error)}`);
    }
  }

  private async applyOption(key: string, operation: () => Promise<void>, check: () => void): Promise<void> {
    check();
    if (this.applied.has(key)) return;

    try {
      await operation();
    } catch (error) {
      check();

      console.warn(`Unable to apply Expo NavigationBar startup ${key}: ${String(error)}`);

      return;
    }

    check();
    this.applied.add(key);
  }

  private detachWindow(): void {
    const observer = this.observer;
    this.observer = undefined;
    if (this.target !== undefined && observer !== undefined) {
      try {
        this.target.off('avoidAreaChange', observer);
      } catch (error) {
        console.warn(`Unable to detach Expo NavigationBar observer: ${String(error)}`);
      }
    }
  }

  private publishVisibility(target: window.Window, notifyInitial: boolean = true): void {
    if (this.observer === undefined) return;

    try {
      const value = inspectVisibility(target);
      const previous = this.last;

      this.last = value;
      if (previous === value || (previous === null && !notifyInitial)) return;

      const event = new NavigationBarVisibilityEvent(value);
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

const states: WeakMap<common.UIAbilityContext, AbilityNavigationBarState> = new WeakMap();

export class ExpoNavigationBarLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  private readonly state: AbilityNavigationBarState;

  constructor(context: common.UIAbilityContext) {
    super(context);
    this.state = new AbilityNavigationBarState(context);
    states.set(context, this.state);
  }

  override onWindowStageCreate(): void {
    this.state.clearWindow();
  }

  override onWindowStageRestore(): void {
    this.state.clearWindow();
  }

  override async onWindowSetup(target: window.Window): Promise<void> {
    await this.state.setWindow(target);
  }

  override onForeground(): void {
    this.state.refresh();
  }

  override onWindowStageWillDestroy(): void {
    this.state.clearWindow();
  }

  override onWindowStageDestroy(): void {
    this.state.clearWindow();
  }

  override onDestroy(): void {
    this.state.destroy();
    if (states.get(this.context) === this.state) states.delete(this.context);
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

    if (context.isHeadless) return;

    this.state = states.get(context.uiAbilityContext);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoNavigationBar')
      .constant('initialStyle', (): NavigationBarStyle | null => this.state?.startup.style ?? null)
      .constant('initialHidden', (): boolean | null => this.state?.startup.hidden ?? null)
      .events([VISIBILITY_EVENT_NAME])
      .asyncFunction(
        'setStyle',
        ExpoFunction.typed1(STYLE_TYPE, async (style: NavigationBarStyle): Promise<void> => {
          await this.requireState().setStyle(style, (): boolean => this.isActive());
        }),
      )
      .asyncFunction(
        'setHidden',
        ExpoFunction.typed1(ExpoValueTypes.boolean(), async (hidden: boolean): Promise<void> => {
          await this.requireState().setHidden(hidden, (): boolean => this.isActive());
        }),
      )
      .asyncFunction(
        'getVisibilityAsync',
        async (): Promise<NavigationBarVisibility> => this.requireState().useWindow(
          async (target: window.Window): Promise<NavigationBarVisibility> => inspectVisibility(target),
          (): boolean => this.isActive(),
        ),
      )
      .onStartObserving(VISIBILITY_EVENT_NAME, (): void => {
        if (this.state === undefined || !this.isActive() || this.observing) return;

        this.observing = true;
        this.state.addListener(this.onVisibility);
      })
      .onStopObserving(VISIBILITY_EVENT_NAME, (): void => this.stopObserving())
      .onPrepareForReload(async (): Promise<void> => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private requireState(): AbilityNavigationBarState {
    if (this.state === undefined) {
      const message = this.context.isHeadless
        ? 'NavigationBar requires a UIAbility window.'
        : 'NavigationBar requires its autolinked UIAbility lifecycle subscriber.';
      throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_WINDOW', message);
    }

    return this.state;
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

async function applyStyle(target: window.Window, style: NavigationBarStyle): Promise<void> {
  if (!supportsNavigationBarChanges(WINDOW_MANAGER_CAPABILITY)) {
    throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_STYLE', 'This HarmonyOS device does not support navigation bar styling.');
  }

  try {
    await target.setWindowSystemBarProperties({
      navigationBarContentColor: style === 'light' ? '#FFFFFFFF' : '#FF000000',
    });
  } catch (error) {
    throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_STYLE', `Unable to update the Harmony navigation bar style: ${String(error)}`);
  }
}

async function setNavigationBarVisibility(target: window.Window, visible: boolean): Promise<void> {
  if (!supportsNavigationBarChanges(WINDOW_SESSION_CAPABILITY)) {
    throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_VISIBILITY', 'This HarmonyOS device does not support changing navigation bar visibility.');
  }

  try {
    await target.setSpecificSystemBarEnabled('navigationIndicator', visible);
  } catch (error) {
    throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_VISIBILITY', `Unable to update the Harmony navigation indicator: ${String(error)}`);
  }
}

function inspectVisibility(target: window.Window): NavigationBarVisibility {
  if (!canIUse(WINDOW_MANAGER_CAPABILITY)) return 'hidden';

  try {
    const indicator = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    if (hasNavigationEdge(indicator) || (indicator.visible && hasArea(indicator.topRect))) return 'visible';
  } catch (error) {
    if ((error as BusinessError).code !== CAPABILITY_UNSUPPORTED) {
      throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_VISIBILITY', `Unable to inspect the Harmony navigation indicator: ${String(error)}`);
    }
  }

  // Some releases report three-button navigation in the system area.
  try {
    const system = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    return hasNavigationEdge(system) ? 'visible' : 'hidden';
  } catch (error) {
    throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_VISIBILITY', `Unable to inspect the Harmony system bar area: ${String(error)}`);
  }
}

function hasNavigationEdge(area: window.AvoidArea): boolean {
  return area.visible && (hasArea(area.leftRect) || hasArea(area.rightRect) || hasArea(area.bottomRect));
}

function hasArea(rect: window.Rect): boolean {
  return rect.width > 0 && rect.height > 0;
}

function supportsNavigationBarChanges(capability: string): boolean {
  return deviceInfo.deviceType !== TWO_IN_ONE_DEVICE_TYPE && canIUse(capability);
}

function readConfiguration(context: common.UIAbilityContext): NavigationBarConfiguration {
  const config = new NavigationBarConfiguration();

  try {
    applyMetadata(config, context.currentHapModuleInfo.metadata ?? []);
  } catch (error) {
    console.warn(`Unable to read the Expo NavigationBar module metadata: ${String(error)}`);
  }

  return config;
}

function applyMetadata(config: NavigationBarConfiguration, metadata: Array<bundleManager.Metadata>): void {
  metadata.forEach((entry: bundleManager.Metadata): void => {
    if (entry.name === STYLE_METADATA) {
      if (entry.value === 'light' || entry.value === 'dark') config.style = entry.value;
      else console.warn(`Ignoring invalid ${STYLE_METADATA} metadata value '${entry.value}'.`);
    }

    if (entry.name === HIDDEN_METADATA) {
      if (entry.value === 'true' || entry.value === 'false') config.hidden = entry.value === 'true';
      else console.warn(`Ignoring invalid ${HIDDEN_METADATA} metadata value '${entry.value}'.`);
    }
  });
}

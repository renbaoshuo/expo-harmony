import type bundleManager from '@ohos.bundle.bundleManager';
import type common from '@ohos.app.ability.common';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';

const VISIBILITY_EVENT_NAME: string = 'ExpoNavigationBar.didChange';
// Keep these keys aligned with METADATA in plugin/withNavigationBar.js.
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

export class ExpoNavigationBarModule extends ExpoModule {
  private readonly config: NavigationBarConfiguration;
  private readonly listener: (options: window.AvoidAreaOptions) => void;
  private observed: window.Window | null = null;
  private observedId: number | null = null;
  private configuredId: number | null = null;
  private readonly applied: Set<string> = new Set<string>();
  private last: NavigationBarVisibility | null = null;
  private queue: Promise<void> = Promise.resolve();
  private observing: boolean = false;
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);

    this.config = readConfiguration(context.uiAbilityContext);
    this.listener = (options: window.AvoidAreaOptions): void => {
      if (options.type === window.AvoidAreaType.TYPE_SYSTEM || options.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        this.publishObservedVisibility(options.type === window.AvoidAreaType.TYPE_SYSTEM);
      }
    };
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoNavigationBar')
      .events([VISIBILITY_EVENT_NAME])
      .asyncFunction(
        'setBackgroundColorAsync',
        ExpoFunction.typed1(ExpoValueTypes.number(), async (color: number): Promise<void> => {
          const value: string = requireProcessedColor(color);

          await this.serialize(async (): Promise<void> => {
            const target = await this.prepareCurrentWindow();

            if (!this.destroyed) {
              await target.setWindowSystemBarProperties({ navigationBarColor: value });
              this.applied.add(CONFIG_BACKGROUND);
            }
          });
        }),
      )
      .asyncFunction('getBackgroundColorAsync', async (): Promise<string> => {
        await this.waitForMutations();
        const target = await this.prepareCurrentWindow();

        return exposeWindowColor(target.getWindowSystemBarProperties().navigationBarColor);
      })
      .asyncFunction(
        'setButtonStyleAsync',
        ExpoFunction.typed1(BUTTON_STYLE_TYPE, async (style: NavigationBarButtonStyle): Promise<void> => {
          await this.serialize(async (): Promise<void> => {
            const target = await this.prepareCurrentWindow();

            if (!this.destroyed) {
              await applyButtonStyle(target, style);
              this.applied.add(CONFIG_BUTTON_STYLE);
            }
          });
        }),
      )
      .asyncFunction('getButtonStyleAsync', async (): Promise<NavigationBarButtonStyle> => {
        await this.waitForMutations();
        const target = await this.prepareCurrentWindow();

        return inspectButtonStyle(target.getWindowSystemBarProperties());
      })
      .asyncFunction(
        'setVisibilityAsync',
        ExpoFunction.typed1(VISIBILITY_TYPE, async (visibility: NavigationBarVisibility): Promise<void> => {
          await this.setVisibility(visibility);
        }),
      )
      .asyncFunction('getVisibilityAsync', async (): Promise<NavigationBarVisibility> => {
        await this.waitForMutations();
        const target = await this.prepareCurrentWindow();

        return inspectVisibility(target);
      })
      .asyncFunction(
        'setPositionAsync',
        ExpoFunction.typed1(POSITION_TYPE, async (position: NavigationBarPosition): Promise<void> => {
          await this.serialize(async (): Promise<void> => {
            const target = await this.prepareCurrentWindow();

            if (!this.destroyed) {
              await target.setWindowLayoutFullScreen(position === 'absolute');
              this.applied.add(CONFIG_POSITION);
            }
          });
        }),
      )
      .asyncFunction('getPositionAsync', async (): Promise<NavigationBarPosition> => {
        await this.waitForMutations();
        const target = await this.prepareCurrentWindow();

        return target.getWindowProperties().isLayoutFullScreen ? 'absolute' : 'relative';
      })
      .onCreate((): void => this.initializeCurrentWindow())
      .onForeground((): void => this.scheduleWindowRefresh())
      .onWindowStageSetup((stage: window.WindowStage): void => {
        this.scheduleWindowStage(stage);
      })
      .onWindowStageWillDestroy((): void => this.handleWindowStageWillDestroy())
      .onStartObserving(VISIBILITY_EVENT_NAME, (): void => this.startObserving())
      .onStopObserving(VISIBILITY_EVENT_NAME, (): void => this.stopObserving())
      .onAbilityDestroy((): void => this.destroy())
      .onPrepareForReload(async (): Promise<void> => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private startObserving(): void {
    if (this.destroyed || this.observing) return;

    this.observing = true;
    this.scheduleWindowRefresh();
  }

  private stopObserving(): void {
    if (!this.observing) return;

    this.observing = false;
    this.detachObservedWindow();
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.observing = false;
    this.detachObservedWindow();
  }

  private handleWindowStageWillDestroy(): void {
    this.configuredId = null;
    this.applied.clear();
    this.detachObservedWindow();
  }

  private async setVisibility(visibility: NavigationBarVisibility): Promise<void> {
    await this.serialize(async (): Promise<void> => {
      const target = await this.prepareCurrentWindow();
      if (this.destroyed) return;

      try {
        await setNavigationBarVisibility(target, visibility === 'visible');
      } catch (error) {
        throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_VISIBILITY', `Unable to set the Harmony navigation bar visibility: ${String(error)}`);
      }

      this.applied.add(CONFIG_VISIBILITY);
    });
  }

  private scheduleWindowRefresh(): void {
    if (this.destroyed) return;

    this.serialize(async (): Promise<void> => {
      await this.prepareCurrentWindow();
    }).catch((error: Object): void => {
      if (!this.destroyed) {
        this.context.logger.warn(`Unable to initialize the Expo NavigationBar window: ${String(error)}`);
      }
    });
  }

  /** Starts the Harmony window lookup before the eager runtime bind returns. */
  private initializeCurrentWindow(): void {
    if (this.destroyed) return;

    const pending: Promise<void> = this.prepareCurrentWindow()
      .then((): void => {})
      .catch((error: Object): void => {
        if (!this.destroyed) {
          this.context.logger.warn(`Unable to initialize the Expo NavigationBar window: ${String(error)}`);
        }
      });

    this.queue = pending;
  }

  private scheduleWindowStage(stage: window.WindowStage): void {
    if (this.destroyed) return;

    this.serialize(async (): Promise<void> => {
      const target: window.Window = await stage.getMainWindow();

      await this.prepareWindow(target);
    }).catch((error: Object): void => {
      if (!this.destroyed) {
        this.context.logger.warn(`Unable to initialize the Expo NavigationBar window stage: ${String(error)}`);
      }
    });
  }

  private async serialize(task: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.queue.catch((): void => {}).then(task);
    this.queue = next;
    await next;
  }

  private async waitForMutations(): Promise<void> {
    await this.queue.catch((): void => {});
    this.assertActive();
  }

  private async prepareCurrentWindow(): Promise<window.Window> {
    this.assertActive();

    let target: window.Window;
    try {
      target = await this.context.getReactNativeWindow();
    } catch (error) {
      throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_WINDOW', `Unable to locate the current application window: ${String(error)}`);
    }

    await this.prepareWindow(target);

    return target;
  }

  private async prepareWindow(target: window.Window): Promise<void> {
    this.assertActive();

    const id: number = target.getWindowProperties().id;
    if (this.configuredId !== id) {
      this.configuredId = id;
      this.applied.clear();
    }

    await this.applyConfiguration(target);

    if (this.observing && (this.observed !== target || this.observedId !== id)) {
      this.detachObservedWindow();
      target.on('avoidAreaChange', this.listener);
      this.observed = target;
      this.observedId = id;

      try {
        this.last = inspectVisibility(target);
      } catch (error) {
        this.context.logger.warn(`Unable to inspect the Harmony navigation bar visibility: ${String(error)}`);
      }
    }
  }

  private async applyConfiguration(target: window.Window): Promise<void> {
    const config: NavigationBarConfiguration = this.config;
    const position: NavigationBarPosition | null = config.position;
    if (position !== null && !this.applied.has(CONFIG_POSITION)) {
      if (
        await this.bestEffort(
          (): Promise<void> => target.setWindowLayoutFullScreen(position === 'absolute'),
          'apply the Expo NavigationBar startup position',
        )
      ) {
        this.applied.add(CONFIG_POSITION);
      }
    }

    const color: string | null = config.backgroundColor;
    if (color !== null && !this.applied.has(CONFIG_BACKGROUND)) {
      if (
        await this.bestEffort(
          (): Promise<void> => target.setWindowSystemBarProperties({ navigationBarColor: color }),
          'apply the Expo NavigationBar startup background color',
        )
      ) {
        this.applied.add(CONFIG_BACKGROUND);
      }
    }

    const style: NavigationBarButtonStyle | null = config.buttonStyle;
    if (style !== null && !this.applied.has(CONFIG_BUTTON_STYLE)) {
      if (await this.bestEffort((): Promise<void> => applyButtonStyle(target, style), 'apply the Expo NavigationBar startup button style')) {
        this.applied.add(CONFIG_BUTTON_STYLE);
      }
    }

    const visibility: NavigationBarVisibility | null = config.visibility;
    if (visibility !== null && !this.applied.has(CONFIG_VISIBILITY)) {
      if (
        await this.bestEffort(
          (): Promise<void> => setNavigationBarVisibility(target, visibility === 'visible'),
          'apply the Expo NavigationBar startup visibility',
        )
      ) {
        this.applied.add(CONFIG_VISIBILITY);
      }
    }
  }

  private async bestEffort(operation: () => Promise<void>, description: string): Promise<boolean> {
    try {
      await operation();
      return true;
    } catch (error) {
      this.context.logger.warn(`Unable to ${description}: ${String(error)}`);
      return false;
    }
  }

  private detachObservedWindow(): void {
    if (this.observed !== null) {
      try {
        this.observed.off('avoidAreaChange', this.listener);
      } catch (error) {
        if (!this.destroyed) {
          this.context.logger.warn(`Unable to detach the Expo NavigationBar observer: ${String(error)}`);
        }
      }
    }

    this.observed = null;
    this.observedId = null;
    this.last = null;
  }

  private publishObservedVisibility(force: boolean = false): void {
    if (this.destroyed || !this.observing || this.observed === null) return;

    try {
      const visibility: NavigationBarVisibility = inspectVisibility(this.observed);
      this.emitVisibility(visibility, force);
    } catch (error) {
      this.context.logger.warn(`Unable to inspect the Harmony navigation bar visibility: ${String(error)}`);
    }
  }

  private emitVisibility(visibility: NavigationBarVisibility, force: boolean = false): void {
    if (!this.observing || (!force && visibility === this.last)) return;

    this.last = visibility;
    this.sendEvent(VISIBILITY_EVENT_NAME, new NavigationBarVisibilityEvent(visibility));
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_DESTROYED', 'The Expo NavigationBar Harmony module has already been destroyed.');
    }
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

export function applyNavigationBarStartupConfiguration(context: common.UIAbilityContext): void {
  const config: NavigationBarConfiguration = readConfiguration(context);

  window
    .getLastWindow(context)
    .then(async (target: window.Window): Promise<void> => {
      const operations: Array<() => Promise<void>> = [];
      if (config.position !== null) {
        const position: NavigationBarPosition = config.position;
        operations.push((): Promise<void> => target.setWindowLayoutFullScreen(position === 'absolute'));
      }
      if (config.backgroundColor !== null) {
        const color: string = config.backgroundColor;
        operations.push((): Promise<void> => target.setWindowSystemBarProperties({ navigationBarColor: color }));
      }
      if (config.buttonStyle !== null) {
        const style: NavigationBarButtonStyle = config.buttonStyle;
        operations.push((): Promise<void> => applyButtonStyle(target, style));
      }
      if (config.visibility !== null) {
        const visibility: NavigationBarVisibility = config.visibility;
        operations.push((): Promise<void> => setNavigationBarVisibility(target, visibility === 'visible'));
      }

      for (let index: number = 0; index < operations.length; index += 1) {
        try {
          await operations[index]();
        } catch (error) {
          console.warn(`Unable to apply an Expo NavigationBar startup option: ${String(error)}`);
        }
      }
    })
    .catch((error: Object): void => {
      console.warn(`Unable to locate the Expo NavigationBar startup window: ${String(error)}`);
    });
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

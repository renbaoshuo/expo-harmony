import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNInstance, RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { ExpoPlatformServiceError, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import type bundleManager from '@ohos.bundle.bundleManager';
import type common from '@ohos.app.ability.common';
import { window } from '@kit.ArkUI';

const SERVICE_NAME: string = 'ExpoNavigationBarService';
const VISIBILITY_EVENT_NAME: string = 'ExpoNavigationBar.didChange';
// Keep these keys aligned with METADATA in plugin/withNavigationBar.js.
const BACKGROUND_METADATA: string = 'expo.harmony.navigationBar.backgroundColor';
const BUTTON_STYLE_METADATA: string = 'expo.harmony.navigationBar.barStyle';
const POSITION_METADATA: string = 'expo.harmony.navigationBar.position';
const VISIBILITY_METADATA: string = 'expo.harmony.navigationBar.visibility';
// Harmony has no Android-style system UI bitmask. Preserve the Android hide-navigation bit
// so consumers that only inspect that flag keep working across platforms.
const ANDROID_HIDE_NAVIGATION_FLAG: number = 2;
const VISIBILITY_RECONCILE_WINDOW_MS: number = 1000;
let registered: boolean = false;

type NavigationBarButtonStyle = 'light' | 'dark';
type NavigationBarPosition = 'relative' | 'absolute';
type NavigationBarVisibility = 'visible' | 'hidden';

class ExpoNavigationBarError extends ExpoPlatformServiceError {
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

export class ExpoNavigationBarLifecycle {
  static async onRNInstanceSetUp(context: common.UIAbilityContext, rnInstance: RNInstance): Promise<void> {
    let target: window.Window;
    try {
      target = await rnInstance.getRNWindow();
    } catch (error) {
      console.warn(`Unable to locate the React Native window during Expo NavigationBar setup: ${String(error)}`);
      return;
    }

    await applyConfiguration(target, readConfiguration(context));
  }
}

class ExpoNavigationBarService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;
  private readonly subscriptions: Array<() => void> = [];
  private readonly areaListener: (options: window.AvoidAreaOptions) => void;
  private observed: window.Window | null = null;
  private observedId: number | null = null;
  private last: NavigationBarVisibility | null = null;
  private requested: NavigationBarVisibility | null = null;
  private requestedUntil: number = 0;
  private queue: Promise<void> = Promise.resolve();
  private destroyed: boolean = false;

  constructor(context: UITurboModuleContext) {
    this.context = context;
    this.areaListener = (options: window.AvoidAreaOptions): void => {
      if (options.type === window.AvoidAreaType.TYPE_SYSTEM || options.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        this.publishObservedVisibility();
      }
    };

    this.queue = this.attachCurrentWindow().catch((error: Object): void => {
      context.logger.warn(`Unable to observe the Expo NavigationBar window yet: ${String(error)}`);
    });

    this.subscriptions.push(
      context.rnInstance.subscribeToLifecycleEvents('FOREGROUND', () => {
        this.scheduleWindowAttachment();
      }),
      context.rnInstance.subscribeToLifecycleEvents('WINDOW_SIZE_CHANGE', () => {
        this.scheduleWindowAttachment();
      }),
    );
  }

  onDestroy(): void {
    this.destroy();
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (method === 'destroy') {
      this.destroy();
      return null;
    }

    if (this.destroyed) {
      throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_DESTROYED', 'The Expo NavigationBar Harmony service has already been destroyed.');
    }

    if (method === 'setBackgroundColorAsync') {
      const color = requireProcessedColor(args[0]);

      await this.serialize(async (): Promise<void> => {
        const target = await this.currentWindow();

        if (this.destroyed) return;

        await target.setWindowSystemBarProperties({ navigationBarColor: color });
      });

      return null;
    }

    if (method === 'getBackgroundColorAsync') {
      await this.queue.catch((): void => {});

      const target = await this.currentWindow();
      const props = target.getWindowSystemBarProperties();

      return exposeWindowColor(props.navigationBarColor);
    }

    if (method === 'setButtonStyleAsync') {
      const style = requireButtonStyle(args[0]);

      await this.serialize(async (): Promise<void> => {
        const target = await this.currentWindow();

        if (this.destroyed) return;

        await applyButtonStyle(target, style);
      });

      return null;
    }

    if (method === 'getButtonStyleAsync') {
      await this.queue.catch((): void => {});

      const target = await this.currentWindow();
      const props = target.getWindowSystemBarProperties();

      return inspectButtonStyle(props);
    }

    if (method === 'setVisibilityAsync') {
      const visibility = requireVisibility(args[0]);

      await this.serialize(async (): Promise<void> => {
        const target = await this.currentWindow();

        if (this.destroyed) return;

        const previous = this.requested;
        const previousUntil = this.requestedUntil;

        this.requested = visibility;
        this.requestedUntil = 0;

        try {
          await setNavigationBarVisibility(target, visibility === 'visible');
        } catch (error) {
          this.requested = previous;
          this.requestedUntil = previousUntil;

          throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_VISIBILITY', `Unable to set the Harmony navigation bar visibility: ${String(error)}`);
        }

        if (this.destroyed) return;

        // Avoid-area state can trail a successful system-bar mutation by a frame. Keep the
        // requested value only during a bounded reconciliation window so an immediate getter
        // observes the completed setter without permanently masking later system changes.
        this.requestedUntil = Date.now() + VISIBILITY_RECONCILE_WINDOW_MS;
        this.emitVisibility(visibility);
      });

      return null;
    }

    if (method === 'getVisibilityAsync') {
      await this.queue.catch((): void => {});

      const target = await this.currentWindow();
      const visibility = inspectVisibility(target);

      if (this.requested === null) return visibility;

      if (visibility === this.requested || Date.now() >= this.requestedUntil) {
        this.requested = null;
        this.requestedUntil = 0;

        return visibility;
      }

      return this.requested;
    }

    if (method === 'setPositionAsync') {
      const position = requirePosition(args[0]);

      await this.serialize(async (): Promise<void> => {
        const target = await this.currentWindow();

        if (this.destroyed) return;

        await target.setWindowLayoutFullScreen(position === 'absolute');
      });

      return null;
    }

    if (method === 'getPositionAsync') {
      await this.queue.catch((): void => {});

      const target = await this.currentWindow();

      return target.getWindowProperties().isLayoutFullScreen ? 'absolute' : 'relative';
    }

    throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_UNKNOWN_METHOD', `Unknown Expo NavigationBar Harmony method '${method}'.`);
  }

  invokeSync(method: string, _: ESObject[]): ESObject {
    if (method === 'destroy') {
      this.destroy();
      return null;
    }

    throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_ASYNC_METHOD', `Expo NavigationBar Harmony method '${method}' is asynchronous.`);
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;

    this.subscriptions.forEach((unsubscribe) => unsubscribe());
    this.subscriptions.length = 0;
    this.detachObservedWindow();
  }

  private async serialize(task: () => Promise<void>): Promise<void> {
    const next = this.queue.catch((): void => {}).then(task);
    this.queue = next;

    await next;
  }

  private scheduleWindowAttachment(): void {
    if (this.destroyed) return;

    this.serialize(async (): Promise<void> => {
      await this.attachCurrentWindow();
    }).catch((error: Object): void => {
      this.context.logger.warn(`Unable to refresh the Expo NavigationBar window observer: ${String(error)}`);
    });
  }

  private async attachCurrentWindow(): Promise<void> {
    if (this.destroyed) return;

    const target = await this.currentWindow();

    if (this.destroyed) return;

    const id = target.getWindowProperties().id;

    if (this.observed !== target || this.observedId !== id) {
      this.detachObservedWindow();

      target.on('avoidAreaChange', this.areaListener);
      this.observed = target;
      this.observedId = id;
    }

    this.publishObservedVisibility();
  }

  private detachObservedWindow(): void {
    if (this.observed !== null) {
      try {
        this.observed.off('avoidAreaChange', this.areaListener);
      } catch (_) {}
    }

    this.observed = null;
    this.observedId = null;
    this.last = null;
    this.requested = null;
    this.requestedUntil = 0;
  }

  private publishObservedVisibility(): void {
    if (this.destroyed || this.observed === null) return;

    try {
      const visibility = inspectVisibility(this.observed);

      if (this.requested !== null) {
        const pending = this.requestedUntil === 0;
        const settling = visibility !== this.requested && Date.now() < this.requestedUntil;

        if (pending || settling) return;

        this.requested = null;
        this.requestedUntil = 0;
      }

      this.emitVisibility(visibility);
    } catch (error) {
      this.context.logger.warn(`Unable to inspect the Harmony navigation bar visibility: ${String(error)}`);
    }
  }

  private emitVisibility(visibility: NavigationBarVisibility): void {
    if (visibility === this.last) return;

    this.last = visibility;

    this.context.rnInstance.emitDeviceEvent(VISIBILITY_EVENT_NAME, {
      visibility,
      rawVisibility: visibility === 'hidden' ? ANDROID_HIDE_NAVIGATION_FLAG : 0,
    });
  }

  private async currentWindow(): Promise<window.Window> {
    try {
      return await this.context.rnInstance.getRNWindow();
    } catch (error) {
      throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_WINDOW', `Unable to locate the current React Native window: ${String(error)}`);
    }
  }
}

async function applyConfiguration(target: window.Window, config: NavigationBarConfiguration): Promise<void> {
  if (config.position !== null) {
    try {
      await target.setWindowLayoutFullScreen(config.position === 'absolute');
    } catch (error) {
      console.warn(`Unable to apply the Expo NavigationBar startup position: ${String(error)}`);
    }
  }

  if (config.backgroundColor !== null) {
    try {
      await target.setWindowSystemBarProperties({ navigationBarColor: config.backgroundColor });
    } catch (error) {
      console.warn(`Unable to apply the Expo NavigationBar startup background color: ${String(error)}`);
    }
  }

  if (config.buttonStyle !== null) {
    try {
      await applyButtonStyle(target, config.buttonStyle);
    } catch (error) {
      console.warn(`Unable to apply the Expo NavigationBar startup button style: ${String(error)}`);
    }
  }

  if (config.visibility !== null) {
    try {
      await setNavigationBarVisibility(target, config.visibility === 'visible');
    } catch (error) {
      console.warn(`Unable to apply the Expo NavigationBar startup visibility: ${String(error)}`);
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
  } catch (_) {
    // Some three-button-only devices do not expose a separate gesture indicator.
  }
}

function inspectVisibility(target: window.Window): NavigationBarVisibility {
  const system = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
  if (system.visible && system.bottomRect.height > 0) return 'visible';

  try {
    const indicator = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    if (indicator.visible && indicator.bottomRect.height > 0) return 'visible';
  } catch (_) {}

  return 'hidden';
}

function inspectButtonStyle(props: window.SystemBarProperties): NavigationBarButtonStyle {
  if (typeof props.navigationBarContentColor === 'string') {
    return isLightColor(props.navigationBarContentColor) ? 'light' : 'dark';
  }

  if (typeof props.isNavigationBarLightIcon === 'boolean') {
    return props.isNavigationBarLightIcon ? 'light' : 'dark';
  }

  return 'light';
}

function isLightColor(value: string): boolean {
  const match = value.match(/^#(?:[0-9a-f]{2})?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);
  if (match === null) return true;

  const red = parseInt(match[1], 16);
  const green = parseInt(match[2], 16);
  const blue = parseInt(match[3], 16);

  return red * 299 + green * 587 + blue * 114 >= 128000;
}

function requireProcessedColor(value: ESObject): string {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < -2147483648 || value > 4294967295) {
    throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_COLOR', 'Expo NavigationBar expected a processed 32-bit React Native color.');
  }

  const unsigned = value < 0 ? value + 4294967296 : value;

  return `#${unsigned.toString(16).padStart(8, '0').toUpperCase()}`;
}

function exposeWindowColor(value: string | undefined): string {
  if (typeof value !== 'string') return '#00000000';

  const argb = value.match(/^#([0-9a-f]{8})$/i);
  if (argb !== null) {
    return `#${argb[1].slice(2)}${argb[1].slice(0, 2)}`.toLowerCase();
  }

  return /^#[0-9a-f]{6}$/i.test(value) ? value.toLowerCase() : '#00000000';
}

function requireButtonStyle(value: ESObject): NavigationBarButtonStyle {
  if (value === 'light' || value === 'dark') return value;

  throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_STYLE', `Invalid navigation bar button style '${String(value)}'.`);
}

function requireVisibility(value: ESObject): NavigationBarVisibility {
  if (value === 'visible' || value === 'hidden') return value;

  throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_VISIBILITY', `Invalid navigation bar visibility '${String(value)}'.`);
}

function requirePosition(value: ESObject): NavigationBarPosition {
  if (value === 'relative' || value === 'absolute') return value;

  throw new ExpoNavigationBarError('ERR_NAVIGATION_BAR_POSITION', `Invalid navigation bar position '${String(value)}'.`);
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
  metadata.forEach((entry) => {
    if (entry.name === BACKGROUND_METADATA && /^#[0-9a-f]{8}$/i.test(entry.value)) {
      config.backgroundColor = entry.value;
    }
    if (entry.name === BUTTON_STYLE_METADATA && (entry.value === 'light' || entry.value === 'dark')) {
      config.buttonStyle = entry.value;
    }
    if (entry.name === POSITION_METADATA && (entry.value === 'relative' || entry.value === 'absolute')) {
      config.position = entry.value;
    }
    if (entry.name === VISIBILITY_METADATA && (entry.value === 'visible' || entry.value === 'hidden')) {
      config.visibility = entry.value;
    }
  });
}

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new ExpoNavigationBarService(context),
  });

  registered = true;
}

export class ExpoNavigationBarPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    super(context);
    registerService();
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-navigation-bar';
  }
}

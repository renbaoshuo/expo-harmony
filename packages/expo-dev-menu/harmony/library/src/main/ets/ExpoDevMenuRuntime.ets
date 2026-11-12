/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { UIContext, window } from '@kit.ArkUI';
import type { common } from '@kit.AbilityKit';
import { KeyCode } from '@kit.InputKit';
import { url } from '@kit.ArkTS';
import type { DevMenuHostDelegate, DevMenuManagerProtocol, DevMenuUIResponderExtensionProtocol } from '@expo-harmony/expo-dev-menu-interface';
import { ExpoModuleError, ReactRuntimeBinding, ReactRuntimeContext } from '@expo-harmony/expo-modules-core';
import type { RNOHCoreContext } from '@rnoh/react-native-openharmony';
import { DevMenuCallback, DevMenuDialogItem, REGISTERED_CALLBACK_EVENT } from './DevMenuTypes';
import { DevMenuDialogModel, DevMenuScreen, ExpoDevMenuPresenter } from './ExpoDevMenuDialog';
import { DevMenuPreferences, DevMenuPreference } from './DevMenuPreferences';
import { DevMenuFab } from './DevMenuFab';
import { DevMenuAppInfo, DevMenuAppInfoProvider, readDevMenuAppInfo } from './DevMenuAppInfo';
import { DevMenuSourceMap } from './DevMenuSourceMap';

const RNOH_MENU_ITEM_EVENT: 'DID_PRESS_MENU_ITEM' = 'DID_PRESS_MENU_ITEM';
const OPEN_EXPO_MENU_ITEM: string = 'Open Expo development menu';
const RELOAD_REASON: string = 'Reload from Expo Dev Menu';
const HMR_CLIENT: string = 'HMRClient';
const TOGGLE_INSPECTOR_EVENT: string = 'toggleElementInspector';
const RELOAD_DEBOUNCE_MS: number = 500;
const RELOAD_TIMEOUT_MS: number = 5000;

class RnohMenuItemEvent {
  readonly title: string;

  constructor(title: string) {
    this.title = title;
  }
}

export class ExpoDevMenuRuntime implements DevMenuManagerProtocol, DevMenuUIResponderExtensionProtocol {
  private static readonly runtimes: Map<number, ExpoDevMenuRuntime> = new Map<number, ExpoDevMenuRuntime>();
  private static readonly delegates: Map<number, DevMenuHostDelegate> = new Map<number, DevMenuHostDelegate>();
  private static readonly appInfoProviders: Map<number, DevMenuAppInfoProvider> = new Map<number, DevMenuAppInfoProvider>();
  private static readonly bridges: WeakMap<RNOHCoreContext, ExpoDevMenuRnohBridge> = new WeakMap<RNOHCoreContext, ExpoDevMenuRnohBridge>();

  private readonly runtime: ReactRuntimeContext;
  private readonly presenter: ExpoDevMenuPresenter;
  readonly preferences: DevMenuPreferences;
  private readonly fab: DevMenuFab;
  private readonly cleanup: (() => void)[] = [];
  private ui?: UIContext;
  private desiredUI?: UIContext;
  private readonly roots: Map<Object, UIContext> = new Map<Object, UIContext>();
  private windowGeneration: number = 0;
  private windowUpdateComplete: boolean = false;
  private windowCleanup?: () => void;
  private windowName?: string;
  private windowActive: boolean = false;
  private foreground: boolean = true;
  private bundleReady: boolean = false;
  // RNOH initializes each Metro HMR client with isEnabled=true.
  private fastRefreshEnabled: boolean = true;
  private launchPending: boolean = true;
  private showsAtLaunch: boolean;
  private lastReloadAt: number = Date.now();
  private reloading: boolean = false;
  private reloadTimer?: number;
  private keyboardVisible: boolean = false;
  private callbacks: DevMenuCallback[] = [];
  private callbacksByName: Map<string, DevMenuCallback> = new Map<string, DevMenuCallback>();
  private openGeneration: number = 0;
  private opening?: Promise<boolean> = undefined;
  private active: boolean = true;
  private delegate: DevMenuHostDelegate | null = null;
  private screen: string | null = null;

  private constructor(runtime: ReactRuntimeContext) {
    this.runtime = runtime;
    this.preferences = new DevMenuPreferences(runtime.core.uiAbilityContext);
    this.showsAtLaunch = this.getShowsAtLaunch();
    this.fab = new DevMenuFab(this.preferences, (): void => {
      this.openMenu();
    });
    this.presenter = new ExpoDevMenuPresenter(
      (): void => this.refreshFab(),
      (error: Error): void => this.reportActionError(error),
    );
    this.delegate = ExpoDevMenuRuntime.delegates.get(runtime.instance.getId()) ?? null;
  }

  static registerAppInfoProvider(id: number, provider: DevMenuAppInfoProvider): () => void {
    if (ExpoDevMenuRuntime.appInfoProviders.has(id))
      throw new ExpoModuleError('ERR_DEV_MENU_DELEGATE', `RN runtime ${id} already has an app info provider.`);
    ExpoDevMenuRuntime.appInfoProviders.set(id, provider);

    let registered = true;

    return (): void => {
      if (!registered) return;
      registered = false;
      if (ExpoDevMenuRuntime.appInfoProviders.get(id) === provider) ExpoDevMenuRuntime.appInfoProviders.delete(id);
    };
  }

  private start(): void {
    this.foreground = this.runtime.core.getUIAbilityState() === 'FOREGROUND';

    this.cleanup.push(
      this.preferences.subscribe((): void => {
        if (!this.active) return;

        try {
          const showsAtLaunch = this.getShowsAtLaunch();
          if (showsAtLaunch && !this.showsAtLaunch) this.launchPending = true;
          this.showsAtLaunch = showsAtLaunch;
          this.syncFastRefresh();
          this.presenter.update(this.menuItems());
          this.refreshFab();
          this.maybeShowAtLaunch();
        } catch (error) {
          this.reportActionError(error instanceof Error ? error : new Error(String(error)));
        }
      }),
    );
    this.cleanup.push(
      this.runtime.instance.subscribeToLifecycleEvents('JS_BUNDLE_EXECUTION_FINISH', (event): void => {
        // Split bundles can finish before the initial app bundle on a shared instance.
        const source = this.runtime.instance.getInitialBundleUrl();
        if (source === undefined || event.jsBundleUrl !== source || this.runtime.instance.getBundleExecutionStatus(source) !== 'DONE') return;
        this.bundleReady = true;
        this.lastReloadAt = Date.now();

        try {
          this.syncFastRefresh();
          this.presenter.update(this.menuItems());
          this.maybeShowAtLaunch();
          this.refreshFab();
        } catch (error) {
          this.reportActionError(error instanceof Error ? error : new Error(String(error)));
        }
      }),
    );
    this.cleanup.push(
      this.runtime.instance.subscribeToLifecycleEvents('BACKGROUND', (): void => {
        this.foreground = false;
        this.refreshFab();
        this.close().catch((error: Error): void => this.reportActionError(error));
      }),
    );
    this.cleanup.push(
      this.runtime.instance.subscribeToLifecycleEvents('FOREGROUND', (): void => {
        this.foreground = true;
        this.refreshFab();
        this.maybeShowAtLaunch();
      }),
    );
    this.cleanup.push(
      this.runtime.instance.subscribeToLifecycleEvents('CONFIGURATION_UPDATE', (): void => {
        try {
          this.presenter.updateConfiguration();
          this.fab.updateConfiguration();
        } catch (error) {
          this.reportActionError(error instanceof Error ? error : new Error(String(error)));
        }
      }),
    );

    const source = this.runtime.instance.getInitialBundleUrl();
    this.bundleReady = source !== undefined && this.runtime.instance.getBundleExecutionStatus(source) === 'DONE';

    this.restoreFastRefresh();
  }

  mountRoot(owner: Object, ui: UIContext): void {
    if (!this.active) return;
    this.roots.delete(owner);
    this.roots.set(owner, ui);
    this.updateWindow(ui).catch((error: Error): void => this.reportActionError(error));
  }

  unmountRoot(owner: Object): void {
    this.roots.delete(owner);
    let last: UIContext | undefined;
    this.roots.forEach((ui: UIContext): void => {
      last = ui;
    });
    this.updateWindow(last).catch((error: Error): void => this.reportActionError(error));
  }

  private async updateWindow(ui: UIContext | undefined): Promise<void> {
    if (!this.active || (this.windowUpdateComplete && this.ui === ui && this.desiredUI === ui)) return;
    this.desiredUI = ui;
    // Keep failed transitions retryable, including failures while dismissing the old window.
    // A registered, non-owning runtime is valid; windowActive alone cannot detect completion.
    this.windowUpdateComplete = false;

    const generation = ++this.windowGeneration;
    this.ui = undefined;
    this.refreshFab();
    await this.close();
    if (!this.active || generation !== this.windowGeneration) return;

    const bridge = ExpoDevMenuRuntime.bridges.get(this.runtime.core);
    if (this.windowName !== undefined) await bridge?.unmountWindow(this, this.windowName);
    if (!this.active || generation !== this.windowGeneration) return;
    this.windowName = undefined;
    if (ui === undefined) {
      this.windowUpdateComplete = true;
      return;
    }

    const name = ui.getWindowName();
    if (name === undefined) throw new ExpoModuleError('ERR_DEV_MENU_WINDOW', 'The mounted root has no native window.');
    this.ui = ui;
    this.windowName = name;
    await bridge?.mountWindow(this, name);
    if (this.active && generation === this.windowGeneration) this.windowUpdateComplete = true;
  }

  /** Called only by the core's window coordinator. It never waits for runtime.open(). */
  async deactivateWindow(): Promise<void> {
    this.windowActive = false;
    ++this.openGeneration;
    this.refreshFab();
    try {
      this.windowCleanup?.();
    } catch (error) {
      this.reportActionError(error instanceof Error ? error : new Error(String(error)));
    }
    this.windowCleanup = undefined;
    try {
      this.fab.dispose();
    } catch (error) {
      this.reportActionError(error instanceof Error ? error : new Error(String(error)));
    }
    this.keyboardVisible = false;
    await this.presenter.close();
  }

  activateWindow(): void {
    const ui = this.ui;
    if (!this.active || ui === undefined) return;

    const name = ui.getWindowName();
    if (name === undefined) throw new ExpoModuleError('ERR_DEV_MENU_WINDOW', 'The mounted root has no native window.');

    const nativeWindow = window.findWindow(name);
    try {
      const keyboard = nativeWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
      this.keyboardVisible = keyboard.bottomRect.height > 0;
    } catch (error) {
      this.reportActionError(error instanceof Error ? error : new Error(String(error)));
    }
    const keyboardChanged = (height: number): void => {
      this.keyboardVisible = height > 0;
      this.refreshFab();
    };
    nativeWindow.on('keyboardHeightChange', keyboardChanged);
    this.windowCleanup = (): void => nativeWindow.off('keyboardHeightChange', keyboardChanged);
    try {
      this.fab.attach(ui);
    } catch (error) {
      this.reportActionError(error instanceof Error ? error : new Error(String(error)));
    }
    this.windowActive = true;
    this.refreshFab();
    this.maybeShowAtLaunch();
  }

  get hasMountedWindow(): boolean {
    return this.active && this.ui !== undefined;
  }
  get canPresentMenu(): boolean {
    return this.hasMountedWindow && this.bundleReady && this.foreground;
  }
  get isWindowOwner(): boolean {
    return this.active && this.windowActive;
  }

  private maybeShowAtLaunch(): void {
    if (!this.active || !this.windowActive || !this.foreground || !this.bundleReady || this.ui === undefined || !this.launchPending) return;
    this.launchPending = false;
    if (!this.getShowsAtLaunch() && this.preferences.get(DevMenuPreference.OnboardingFinished)) return;
    if (this.isVisible || this.opening !== undefined) return;
    this.showAtLaunch().catch((error: Error): void => this.reportActionError(error));
  }

  private async showAtLaunch(): Promise<void> {
    let opened = false;
    try {
      opened = await this.open();
      if (opened && this.active) await this.setShowsAtLaunch(false);
    } finally {
      // An interrupted window claim or failed native sheet should be retryable at the next eligible lifecycle event.
      if (!opened && this.active && (this.getShowsAtLaunch() || !this.preferences.get(DevMenuPreference.OnboardingFinished))) {
        this.launchPending = true;
      }
    }
  }

  getShowsAtLaunch(): boolean {
    return this.preferences.get(DevMenuPreference.ShowsAtLaunch);
  }

  async setShowsAtLaunch(enabled: boolean): Promise<void> {
    this.assertActive();
    this.launchPending = enabled;
    await this.preferences.set(DevMenuPreference.ShowsAtLaunch, enabled);
    this.maybeShowAtLaunch();
  }

  async reload(): Promise<void> {
    if (!this.active || !this.bundleReady) return;

    const now = Date.now();
    if (this.reloading || now - this.lastReloadAt < RELOAD_DEBOUNCE_MS) {
      this.lastReloadAt = now;
      return;
    }
    this.lastReloadAt = now;
    this.reloading = true;

    const timer = setTimeout((): void => {
      this.reloadTimer = undefined;
      this.reloading = false;
    }, RELOAD_TIMEOUT_MS);
    this.reloadTimer = timer;

    try {
      await this.runtime.reload(RELOAD_REASON);
    } catch (error) {
      if (this.reloadTimer === timer) {
        clearTimeout(timer);
        this.reloadTimer = undefined;
        this.reloading = false;
      }
      throw new ExpoModuleError(
        error instanceof ExpoModuleError ? error.code : 'ERR_DEV_MENU_RELOAD',
        error instanceof Error ? error.message : String(error),
        error as Object,
      );
    }
  }

  private refreshFab(): void {
    try {
      this.fab.setVisible(
        this.active &&
          this.windowActive &&
          this.ui !== undefined &&
          this.foreground &&
          this.bundleReady &&
          !this.keyboardVisible &&
          this.preferences.get(DevMenuPreference.ShowFab) &&
          this.preferences.get(DevMenuPreference.OnboardingFinished),
        this.isVisible || this.opening !== undefined,
      );
    } catch (error) {
      // A stale native overlay must not prevent showing or releasing the sheet.
      this.reportActionError(error instanceof Error ? error : new Error(String(error)));
    }
  }

  EXDevMenu_handleKeyCommand(event: KeyEvent): void {
    if (this.handleKeyEvent(event)) event.stopPropagation();
  }

  handleKeyEvent(event: KeyEvent): boolean {
    if (
      !this.active ||
      !this.windowActive ||
      !this.foreground ||
      !this.bundleReady ||
      this.keyboardVisible ||
      event.type !== KeyType.Up ||
      !this.preferences.get(DevMenuPreference.KeyCommands)
    )
      return false;
    // Modified commands avoid treating text entry as Android's bare R/P/I commands.
    // Root events bubble after the focused native/RN input has handled them.
    if (!event.getModifierKeyState?.(['Ctrl']) && event.metaKey !== 1) return false;
    if (event.getModifierKeyState?.(['Alt']) || event.getModifierKeyState?.(['Shift'])) return false;
    if (event.keyCode === KeyCode.KEYCODE_D) return this.toggleMenu();

    let action: (() => void | Promise<void>) | undefined;
    if (event.keyCode === KeyCode.KEYCODE_R) action = (): Promise<void> => this.reload();
    else if (event.keyCode === KeyCode.KEYCODE_I) action = (): void => this.toggleInspector();
    else if (event.keyCode === KeyCode.KEYCODE_P) action = (): void => this.togglePerformanceMonitor();
    if (action === undefined) return false;

    try {
      Promise.resolve(action()).catch((error: Error): void => this.reportActionError(error));
      this.closeMenu();
    } catch (error) {
      this.reportActionError(error instanceof Error ? error : new Error(String(error)));
    }

    return true;
  }

  static registerHostDelegate(id: number, delegate: DevMenuHostDelegate): () => void {
    if (ExpoDevMenuRuntime.delegates.has(id)) {
      throw new ExpoModuleError('ERR_DEV_MENU_DELEGATE', `RN runtime ${id} already has a Dev Menu host delegate.`);
    }
    ExpoDevMenuRuntime.delegates.set(id, delegate);
    try {
      ExpoDevMenuRuntime.find(id)?.setDelegate(delegate);
    } catch (error) {
      ExpoDevMenuRuntime.delegates.delete(id);
      throw new ExpoModuleError(
        error instanceof ExpoModuleError ? error.code : 'ERR_DEV_MENU_RUNTIME',
        error instanceof Error ? error.message : String(error),
        error as Object,
      );
    }

    let registered = true;

    return (): void => {
      if (!registered) return;
      registered = false;
      if (ExpoDevMenuRuntime.delegates.get(id) !== delegate) return;
      ExpoDevMenuRuntime.delegates.delete(id);
      ExpoDevMenuRuntime.find(id)?.setDelegate(null);
    };
  }

  private setDelegate(delegate: DevMenuHostDelegate | null): void {
    const previous = this.delegate;
    this.delegate = delegate;
    try {
      if (this.active) this.presenter.update(this.menuItems());
    } catch (error) {
      if (delegate === null) {
        // Presenter failures must not reattach a host that has already been disposed.
        this.closeMenu();
        this.reportActionError(error instanceof Error ? error : new Error(String(error)));
        return;
      }
      this.delegate = previous;
      throw new ExpoModuleError(
        error instanceof ExpoModuleError ? error.code : 'ERR_DEV_MENU_RUNTIME',
        error instanceof Error ? error.message : String(error),
        error as Object,
      );
    }
  }

  get isVisible(): boolean {
    return this.presenter.isVisible;
  }
  get currentScreen(): string | null {
    return this.presenter.currentScreen ?? this.screen;
  }
  get canNavigateHome(): boolean {
    return this.delegate?.devMenuNavigateHome !== undefined;
  }
  get shouldShowReactNativeDevMenu(): boolean {
    return this.delegate?.devMenuShouldShowReactNativeDevMenu?.() ?? true;
  }

  openMenu(screen: string | null = null): boolean {
    if (!this.canPresentMenu || this.isVisible || this.opening !== undefined) return false;
    this.open(screen).catch((error: Error): void => this.reportActionError(error));
    return true;
  }

  closeMenu(): boolean {
    if (!this.active || (!this.isVisible && this.opening === undefined)) return false;
    this.close().catch((error: Error): void => this.reportActionError(error));
    return true;
  }

  hideMenu(): boolean {
    return this.closeMenu();
  }

  toggleMenu(): boolean {
    return this.isVisible || this.opening !== undefined ? this.closeMenu() : this.openMenu();
  }

  async navigateHome(): Promise<void> {
    const delegate = this.delegate;
    if (!this.active || delegate?.devMenuNavigateHome === undefined) return;
    await this.close();
    if (this.canPresentMenu && this.isWindowOwner && this.delegate === delegate) delegate.devMenuNavigateHome?.();
  }

  togglePerformanceMonitor(): void {
    if (!this.active) return;

    const delegate = this.delegate;
    if (delegate?.devMenuTogglePerformanceMonitor !== undefined) {
      delegate.devMenuTogglePerformanceMonitor();
    } else {
      this.runtime.core.devToolsController.togglePerfMonitor();
    }
  }

  toggleInspector(): void {
    if (!this.active) return;

    const delegate = this.delegate;
    if (delegate?.devMenuToggleElementInspector !== undefined) {
      delegate.devMenuToggleElementInspector();
    } else {
      // RNOH broadcasts this event to all instances when called through the core controller.
      this.runtime.instance.emitDeviceEvent(TOGGLE_INSPECTOR_EVENT, {});
    }
  }

  private get hasMetroBundle(): boolean {
    if (!this.active || !this.bundleReady) return false;

    const source = this.runtime.instance.getInitialBundleUrl();
    if (source === undefined) return false;

    try {
      const provider = this.runtime.getJSBundleProvider?.();
      if (provider?.getHotReloadConfig() == null) return false;

      const bundle = new url.URL(source);

      return (bundle.protocol === 'http:' || bundle.protocol === 'https:') && bundle.params.get('dev') !== 'false';
    } catch (_error) {
      return false;
    }
  }

  private syncFastRefresh(): void {
    if (!this.hasMetroBundle) return;

    const enabled = this.preferences.getFastRefreshEnabled();
    if (enabled === this.fastRefreshEnabled) return;

    // RNOH's DevSettings setter is a no-op; use RN's HMR client.
    this.runtime.instance.callRNFunction(HMR_CLIENT, enabled ? 'enable' : 'disable', []);
    this.fastRefreshEnabled = enabled;
  }

  private restoreFastRefresh(): void {
    try {
      this.syncFastRefresh();
    } catch (error) {
      this.reportActionError(error instanceof Error ? error : new Error(String(error)));
    }
  }

  reportActionError(error: Error): void {
    this.runtime.core.logger.warn(`Expo Dev Menu action failed: ${error.message}`);
  }

  static attach(runtime: ReactRuntimeContext): () => void {
    const id = runtime.instance.getId();
    if (ExpoDevMenuRuntime.runtimes.has(id)) {
      throw new ExpoModuleError('ERR_DEV_MENU_RUNTIME', `Expo Dev Menu is already attached to RN runtime ${id}.`);
    }

    const attached = new ExpoDevMenuRuntime(runtime);
    let bridge = ExpoDevMenuRuntime.bridges.get(runtime.core);

    try {
      if (bridge === undefined) {
        bridge = new ExpoDevMenuRnohBridge(runtime.core);
        ExpoDevMenuRuntime.bridges.set(runtime.core, bridge);
      }
      bridge.attach(attached);
      ExpoDevMenuRuntime.runtimes.set(id, attached);
      attached.start();
    } catch (error) {
      bridge?.detach(attached);
      ExpoDevMenuRuntime.runtimes.delete(id);
      attached.dispose();
      throw new ExpoModuleError(
        error instanceof ExpoModuleError ? error.code : 'ERR_DEV_MENU_RUNTIME',
        error instanceof Error ? error.message : String(error),
        error as Object,
      );
    }

    return (): void => {
      try {
        bridge?.detach(attached);
      } finally {
        if (ExpoDevMenuRuntime.runtimes.get(id) === attached) ExpoDevMenuRuntime.runtimes.delete(id);
        attached.dispose();
      }
    };
  }

  static require(id: number): ExpoDevMenuRuntime {
    const runtime = ExpoDevMenuRuntime.find(id);
    if (runtime === undefined || !runtime.active) {
      throw new ExpoModuleError('ERR_DEV_MENU_RUNTIME', `Expo Dev Menu cannot find the active RN runtime ${id}.`);
    }
    return runtime;
  }

  static find(id: number): ExpoDevMenuRuntime | undefined {
    const runtime = ExpoDevMenuRuntime.runtimes.get(id);
    return runtime !== undefined && runtime.active ? runtime : undefined;
  }

  async open(screen: string | null = null): Promise<boolean> {
    this.assertActive();
    if (!this.canPresentMenu || this.isVisible || this.opening !== undefined) return false;
    this.screen = screen;

    const generation = ++this.openGeneration;
    const pending = this.openNow(generation);
    this.opening = pending;
    this.refreshFab();
    try {
      return await pending;
    } finally {
      if (this.opening === pending) this.opening = undefined;
      this.refreshFab();
    }
  }

  async close(): Promise<void> {
    ++this.openGeneration;

    const opening = this.opening;
    if (opening !== undefined) {
      try {
        await opening;
      } catch (_error) {
        /* The caller of open owns this rejection. */
      }
    }
    await this.presenter.close();
  }

  private async openNow(generation: number): Promise<boolean> {
    if (!this.active || !this.bundleReady || !this.foreground) return false;
    if (generation !== this.openGeneration) return false;

    const ui = this.ui;
    if (ui === undefined) return false;

    const bridge = ExpoDevMenuRuntime.bridges.get(this.runtime.core);
    if (this.windowName === undefined || bridge === undefined || !(await bridge.claimWindow(this, this.windowName))) return false;
    if (!this.active || !this.bundleReady || !this.foreground || this.ui !== ui) return false;
    if (generation !== this.openGeneration) return false;

    const app = this.readAppInfo();
    const model = new DevMenuDialogModel(
      app,
      new DevMenuSourceMap(this.runtime.core.uiAbilityContext.resourceManager),
      this.menuItems(),
      this.preferences,
      async (): Promise<void> => this.close(),
      (error: Error): void => this.reportActionError(error),
      (event: KeyEvent): boolean => this.handleKeyEvent(event),
      (): void => {
        if (this.active && this.preferences.get(DevMenuPreference.TouchGesture)) this.toggleMenu();
      },
    );
    if (this.screen === DevMenuScreen.Settings) model.screen = DevMenuScreen.Settings;
    else if (this.screen === DevMenuScreen.SourceMap) model.run((): Promise<void> => model.showSources());
    if (!this.active) {
      model.dispose();
      return false;
    }
    if (generation !== this.openGeneration) {
      model.dispose();
      return false;
    }
    const presented = await this.presenter.open(ui, model);

    return presented && this.active && generation === this.openGeneration;
  }

  updateCallbacks(callbacks: DevMenuCallback[]): void {
    this.assertActive();
    this.callbacks = callbacks.slice();
    this.callbacksByName = new Map<string, DevMenuCallback>();
    callbacks.forEach((callback: DevMenuCallback): void => {
      this.callbacksByName.set(callback.name, callback);
    });
    this.presenter.update(this.menuItems());
  }

  private menuItems(): DevMenuDialogItem[] {
    const connected = this.bundleReady;
    const inspector = connected && (this.delegate?.devMenuToggleElementInspector !== undefined || this.runtime.core.isDebugModeEnabled);
    const performance = connected && (this.delegate?.devMenuTogglePerformanceMonitor !== undefined || this.runtime.core.isDebugModeEnabled);
    const items: DevMenuDialogItem[] = [
      new DevMenuDialogItem(
        'reload',
        'Reload',
        'Reload the current JavaScript bundle',
        true,
        async (): Promise<void> => {
          await this.reload();
        },
        connected,
      ),
      new DevMenuDialogItem(
        'inspector',
        'Toggle element inspector',
        'Inspect React Native views on screen',
        true,
        (): void => {
          this.toggleInspector();
        },
        inspector,
      ),
      new DevMenuDialogItem(
        'devtools',
        'Open React Native DevTools',
        'Requires a loaded development bundle from Metro',
        true,
        (): void => {
          this.runtime.core.devToolsController.openDebugger();
        },
        this.hasMetroBundle,
      ),
      new DevMenuDialogItem(
        'performance',
        'Toggle performance monitor',
        'Show or hide the RNOH performance overlay',
        true,
        (): void => {
          this.togglePerformanceMonitor();
        },
        performance,
      ),
    ];

    if (this.shouldShowReactNativeDevMenu) {
      items.push(
        new DevMenuDialogItem('rnoh-menu', 'Open React Native dev menu', 'Open the RNOH developer menu', false, async (): Promise<void> => {
          await this.close();

          if (this.canPresentMenu && this.isWindowOwner) this.runtime.core.devMenu.show();
        }),
      );
    }

    items.push(
      new DevMenuDialogItem(
        'fast-refresh',
        'Fast Refresh',
        'Requires a loaded development bundle from Metro',
        false,
        async (): Promise<void> => {
          if (!this.hasMetroBundle) return;

          await this.preferences.setFastRefreshEnabled(!this.fastRefreshEnabled);

          // Retry a failed RN call even when the saved preference is unchanged.
          this.syncFastRefresh();
          this.presenter.update(this.menuItems());
        },
        this.hasMetroBundle,
        this.fastRefreshEnabled,
      ),
    );

    if (this.canNavigateHome) {
      items.push(
        new DevMenuDialogItem('home', 'Go home', 'Return to the host home screen', false, async (): Promise<void> => {
          await this.navigateHome();
        }),
      );
    }

    this.callbacks.forEach((callback: DevMenuCallback, index: number): void => {
      items.push(
        new DevMenuDialogItem(`custom-${index}-${callback.name}`, callback.name, 'Custom development action', callback.shouldCollapse, (): void =>
          this.emitCallback(callback.name),
        ),
      );
    });

    return items;
  }

  private emitCallback(name: string): void {
    if (!this.active || !this.callbacksByName.has(name)) return;
    this.runtime.instance.emitDeviceEvent(REGISTERED_CALLBACK_EVENT, name);
  }

  private readAppInfo(): DevMenuAppInfo {
    try {
      return readDevMenuAppInfo(
        this.runtime.core,
        this.runtime.instance.getInitialBundleUrl() ?? '',
        ExpoDevMenuRuntime.appInfoProviders.get(this.runtime.instance.getId()),
      );
    } catch (error) {
      this.runtime.core.logger.warn(`Unable to read application information for Expo Dev Menu: ${String(error)}`);
      const info = new DevMenuAppInfo();
      info.hostUrl = this.runtime.instance.getInitialBundleUrl() ?? '';
      return info;
    }
  }

  private assertActive(): void {
    if (!this.active) throw new ExpoModuleError('ERR_DEV_MENU_RUNTIME', 'The Expo Dev Menu runtime has already been destroyed.');
  }

  private dispose(): void {
    if (!this.active) return;
    this.active = false;
    if (this.reloadTimer !== undefined) clearTimeout(this.reloadTimer);
    this.reloadTimer = undefined;
    ++this.windowGeneration;
    this.roots.clear();
    this.ui = undefined;
    ++this.openGeneration;
    this.callbacks = [];
    this.callbacksByName.clear();
    this.delegate = null;
    try {
      this.windowCleanup?.();
    } catch (error) {
      this.reportActionError(error instanceof Error ? error : new Error(String(error)));
    }
    this.windowCleanup = undefined;
    this.cleanup.splice(0).forEach((cleanup: () => void): void => {
      try {
        cleanup();
      } catch (error) {
        this.reportActionError(error instanceof Error ? error : new Error(String(error)));
      }
    });
    try {
      this.preferences.dispose();
    } catch (error) {
      this.reportActionError(error instanceof Error ? error : new Error(String(error)));
    }
    try {
      this.fab.dispose();
    } catch (error) {
      this.reportActionError(error instanceof Error ? error : new Error(String(error)));
    }
    this.presenter.dispose();
  }
}

class ExpoDevMenuRnohBridge {
  private readonly core: RNOHCoreContext;
  private runtimes: ExpoDevMenuRuntime[] = [];
  private unsubscribe?: () => void = undefined;
  private readonly windows: Map<string, DevMenuWindowGroup> = new Map<string, DevMenuWindowGroup>();
  private lastWindow?: string;

  constructor(core: RNOHCoreContext) {
    this.core = core;
    core.devMenu.addMenuItem(OPEN_EXPO_MENU_ITEM);
  }

  attach(runtime: ExpoDevMenuRuntime): void {
    if (this.runtimes.length === 0) {
      this.unsubscribe = this.core.devToolsController.eventEmitter.subscribe(RNOH_MENU_ITEM_EVENT, (item: RnohMenuItemEvent): void =>
        this.onMenuItem(item),
      );
    }
    this.runtimes.push(runtime);
  }

  detach(runtime: ExpoDevMenuRuntime): void {
    this.runtimes = this.runtimes.filter((candidate: ExpoDevMenuRuntime): boolean => candidate !== runtime);
    this.windows.forEach((_group: DevMenuWindowGroup, name: string): void => {
      this.unmountWindow(runtime, name).catch((error: Error): void => runtime.reportActionError(error));
    });
    if (this.runtimes.length === 0) {
      const unsubscribe = this.unsubscribe;
      this.unsubscribe = undefined;
      unsubscribe?.();
    }
  }

  async mountWindow(runtime: ExpoDevMenuRuntime, name: string): Promise<void> {
    let group = this.windows.get(name);
    if (group === undefined) {
      group = new DevMenuWindowGroup();
      this.windows.set(name, group);
    }
    group.runtimes = group.runtimes.filter((candidate: ExpoDevMenuRuntime): boolean => candidate !== runtime);
    group.runtimes.push(runtime);
    await this.claimWindow(runtime, name);
  }

  async unmountWindow(runtime: ExpoDevMenuRuntime, name: string): Promise<void> {
    const group = this.windows.get(name);
    // A failed dismissal has already removed membership but still owns native resources.
    // Allow a later root update/disposal to retry that cleanup.
    if (group === undefined || (!group.runtimes.includes(runtime) && group.owner !== runtime && group.desired !== runtime)) return;
    group.runtimes = group.runtimes.filter((candidate: ExpoDevMenuRuntime): boolean => candidate !== runtime);
    if (group.owner !== runtime && group.desired !== runtime && group.runtimes.length > 0) return;

    const next = group.runtimes[group.runtimes.length - 1];
    if (next !== undefined) await this.claimWindow(next, name);
    else {
      group.desired = undefined;

      const pending = group.pending
        .catch((): boolean => false)
        .then(async (): Promise<boolean> => {
          if (group.desired !== undefined || group.runtimes.length > 0) return false;
          await group.owner?.deactivateWindow();
          group.owner = undefined;
          if (group.runtimes.length === 0 && this.windows.get(name) === group) this.windows.delete(name);
          return true;
        });
      group.pending = pending;
      await pending;
    }
  }

  claimWindow(runtime: ExpoDevMenuRuntime, name: string): Promise<boolean> {
    const group = this.windows.get(name);
    if (group === undefined || !group.runtimes.includes(runtime)) return Promise.resolve(false);
    group.desired = runtime;

    const pending = group.pending
      .catch((): boolean => false)
      .then(async (): Promise<boolean> => {
        if (group.desired !== runtime || !group.runtimes.includes(runtime) || !runtime.hasMountedWindow) return false;
        if (group.owner === runtime && runtime.isWindowOwner) {
          this.lastWindow = name;
          return true;
        }

        const previous = group.owner;
        await previous?.deactivateWindow();
        group.owner = undefined;
        if (group.desired !== runtime || !group.runtimes.includes(runtime) || !runtime.hasMountedWindow) return false;
        try {
          runtime.activateWindow();
        } catch (error) {
          await runtime.deactivateWindow();
          throw new ExpoModuleError(
            error instanceof ExpoModuleError ? error.code : 'ERR_DEV_MENU_RUNTIME',
            error instanceof Error ? error.message : String(error),
            error as Object,
          );
        }
        group.owner = runtime;
        this.lastWindow = name;

        return true;
      });
    group.pending = pending;

    return pending;
  }

  private onMenuItem(item: RnohMenuItemEvent): void {
    if (item.title !== OPEN_EXPO_MENU_ITEM) return;
    this.openFirstAvailableRuntime().catch((error: Error): void => {
      this.core.logger.warn(`Unable to open Expo Dev Menu from the RNOH menu: ${error.message}`);
    });
  }

  private async openFirstAvailableRuntime(): Promise<void> {
    let failure: Error | undefined = undefined;
    const candidates: ExpoDevMenuRuntime[] = [];
    const recent = this.lastWindow === undefined ? undefined : this.windows.get(this.lastWindow)?.availableRuntime();
    if (recent !== undefined) candidates.push(recent);
    this.windows.forEach((group: DevMenuWindowGroup): void => {
      const candidate = group.availableRuntime();
      if (candidate !== undefined && candidate !== recent) candidates.push(candidate);
    });

    for (const runtime of candidates) {
      try {
        if (runtime.isVisible || (await runtime.open())) return;
      } catch (error) {
        failure = error instanceof Error ? error : new Error(String(error));
      }
    }
    throw new ExpoModuleError(
      failure instanceof ExpoModuleError ? failure.code : 'ERR_DEV_MENU_RUNTIME',
      failure?.message ?? 'Expo Dev Menu cannot find a runtime with an available window.',
      failure,
    );
  }
}

/** Serializes native dismissal and ownership transfer for one actual window. */
class DevMenuWindowGroup {
  runtimes: ExpoDevMenuRuntime[] = [];
  owner?: ExpoDevMenuRuntime;
  desired?: ExpoDevMenuRuntime;
  pending: Promise<boolean> = Promise.resolve(true);
  availableRuntime(): ExpoDevMenuRuntime | undefined {
    if (this.owner?.canPresentMenu) return this.owner;
    return this.runtimes
      .slice()
      .reverse()
      .find((runtime: ExpoDevMenuRuntime): boolean => runtime.canPresentMenu);
  }
}

export class ExpoDevMenuRuntimeBinding implements ReactRuntimeBinding {
  constructor(_context: common.Context) {}

  bind(context: ReactRuntimeContext): (() => void) | void {
    if (!context.core.isDebugModeEnabled || context.isHeadless) return;
    return ExpoDevMenuRuntime.attach(context);
  }
}

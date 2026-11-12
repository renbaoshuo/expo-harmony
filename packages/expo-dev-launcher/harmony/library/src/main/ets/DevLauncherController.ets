/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { scanBarcode, scanCore } from '@kit.ScanKit';
import { bundleManager } from '@kit.AbilityKit';
import type { common } from '@kit.AbilityKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import { pasteboard } from '@kit.BasicServicesKit';
import type { JSBundleProvider } from '@rnoh/react-native-openharmony';
import { FileJSBundleProvider } from '@rnoh/react-native-openharmony';
import { Manifest } from '@expo-harmony/expo-manifests';
import { DevMenuAppMetadata, DevMenuPreference, DevMenuPreferences } from '@expo-harmony/expo-dev-menu';
import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { UpdatesControllerRegistry, UpdatesDevLauncherInterface, UpdatesInterfaceCallbacks } from '@expo-harmony/expo-updates-interface';
import { DevLauncherManifestLoader, LaunchSelection } from './DevLauncherManifestLoader';
import {
  DEFAULT_LAUNCH_URL_METADATA, EMBEDDED_BUNDLE_METADATA, DevLauncherError, displayError,
  hasEnabledFlag, isLauncherHomeLink, resolveDevelopmentURL,
} from './DevLauncherProtocol';
import { DevServerDiscovery, DiscoveredServer } from './DevServerDiscovery';
import { RecentApp, RecentApps } from './RecentApps';
import { sendRuntimeError } from './DevLauncherRemoteLogs';

const SCAN_CAPABILITY = 'SystemCapability.Multimedia.Scan.ScanBarcode';
const SCANNER_CANCELLED_ERROR_CODE = 1000500002;

export class DevLauncherViewState {
  readonly loading: boolean;
  readonly progress: number;
  readonly error?: string;
  readonly recent: RecentApp[];
  readonly servers: DiscoveredServer[];
  readonly searching: boolean;
  readonly discoveryError?: string;
  readonly hasEmbeddedBundle: boolean;
  readonly canRetry: boolean;
  readonly settings: Record<string, boolean>;
  readonly filterBySlug: string;

  constructor(
    loading: boolean, progress: number, error: string | undefined, recent: RecentApp[], servers: DiscoveredServer[],
    searching: boolean = false, discoveryError: string | undefined = undefined, hasEmbeddedBundle: boolean = false,
    canRetry: boolean = false, settings: Record<string, boolean> = {}, filterBySlug: string = '',
  ) {
    this.loading = loading;
    this.progress = progress;
    this.error = error;
    this.recent = recent;
    this.servers = servers;
    this.searching = searching;
    this.discoveryError = discoveryError;
    this.hasEmbeddedBundle = hasEmbeddedBundle;
    this.canRetry = canRetry;
    this.settings = settings;
    this.filterBySlug = filterBySlug;
  }
}

type StateListener = (state: DevLauncherViewState) => void;

class LaunchRequest {
  readonly url?: string;
  readonly link?: string;

  constructor(url?: string, link?: string) {
    this.url = url;
    this.link = link;
  }
}

interface RuntimeRegistration {
  id: number;
  selection?: LaunchSelection;
  suspend: () => Promise<void>;
  reload: (reason: string) => Promise<void>;
}

export class DevLauncherController {
  private static readonly controllers = new Map<string, DevLauncherController>();

  static get(context: common.ApplicationContext): DevLauncherController {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    let controller = DevLauncherController.controllers.get(info.name);
    if (controller === undefined) {
      controller = new DevLauncherController(context, info.name);
      DevLauncherController.controllers.set(info.name, controller);
    }
    return controller;
  }

  private selectionReady: Promise<void>;
  private resolveReady?: () => void;
  private homeTransition?: Promise<void>;
  private readonly history: RecentApps;
  private readonly preferences: DevMenuPreferences;
  private readonly listeners = new Set<StateListener>();
  private ability?: common.UIAbilityContext;
  private discovery?: DevServerDiscovery;
  private detachDiscovery?: () => void;
  private updatesCallbacks?: UpdatesInterfaceCallbacks;
  private provider?: JSBundleProvider;
  private selection?: LaunchSelection;
  private selectedRequest?: LaunchRequest;
  private active = false;
  private foregrounded = false;
  private loadingRequest?: LaunchRequest;
  private loadPromise?: Promise<void>;
  private manifestLoad?: Promise<LaunchSelection>;
  private progress = 0;
  private error?: string;
  private recoveryChecked = false;
  private recoveredFailure = false;
  private recent: RecentApp[] = [];
  private servers: DiscoveredServer[] = [];
  private loadSerial = 0;
  private settledInitialSelection = false;
  private initialSelectionStarted = false;
  private pendingRequest?: LaunchRequest;
  private failedRequest?: LaunchRequest;
  private embeddedProvider?: JSBundleProvider;
  private runtime?: RuntimeRegistration;
  private runtimeOwner?: RuntimeRegistration;
  private pendingReloadReason?: string;
  private readonly context: common.ApplicationContext;
  private readonly bundleName: string;

  private constructor(context: common.ApplicationContext, bundleName: string) {
    this.context = context;
    this.bundleName = bundleName;
    this.history = new RecentApps(context);
    this.preferences = new DevMenuPreferences(context);
    this.preferences.subscribe((): void => this.publish());
    this.recent = this.history.all();
    this.selectionReady = new Promise<void>((resolve: () => void): void => {
      this.resolveReady = resolve;
    });
  }

  get enabled(): boolean {
    return this.active;
  }
  get ready(): Promise<void> {
    return this.selectionReady;
  }
  get selectedProvider(): JSBundleProvider | undefined {
    return this.provider;
  }
  get useDeveloperSupport(): boolean | undefined {
    return this.active ? (this.selection?.useDeveloperSupport ?? true) : undefined;
  }
  get manifestString(): string | null {
    return this.selection?.manifest === undefined ? null : JSON.stringify(this.selection.manifest);
  }
  get manifestURL(): string | null {
    return this.selection?.manifestURL ?? null;
  }
  private get loading(): boolean {
    return this.loadingRequest !== undefined;
  }

  setEmbeddedProvider(provider: JSBundleProvider | undefined): void {
    this.embeddedProvider = provider;
    this.publish();
  }

  registerRuntime(id: number, suspend: () => Promise<void>, reload: (reason: string) => Promise<void>): () => void {
    const runtime: RuntimeRegistration = { id, selection: this.selection, suspend, reload };
    this.runtime = runtime;
    // The owner remains available while the previous instance is being replaced.
    this.runtimeOwner = runtime;
    const reason = this.pendingReloadReason;
    if (reason !== undefined) {
      this.pendingReloadReason = undefined;
      this.requestReload(reason);
    }

    return (): void => {
      if (this.runtime === runtime) this.runtime = undefined;
    };
  }

  private metadata(name: string): string | undefined {
    return this.ability?.currentHapModuleInfo.metadata?.find((entry): boolean => entry.name === name)?.value;
  }

  private hasEmbeddedBundle(): boolean {
    return this.metadata(EMBEDDED_BUNDLE_METADATA) === 'true' && this.embeddedProvider !== undefined;
  }

  getDevMenuAppInfo(): DevMenuAppMetadata {
    const result = new DevMenuAppMetadata();
    const selection = this.selection;
    if (selection === undefined) return result;
    if (selection.provider instanceof FileJSBundleProvider) result.localBundlePath = selection.provider.getURL();
    if (selection.manifest === undefined) return result;
    try {
      const manifest = Manifest.fromManifestJson(selection.manifest);
      result.appName = manifest.getName() ?? undefined;
      result.appVersion = manifest.getVersion() ?? undefined;
      const config = manifest.getExpoClientConfigRootObject();
      const runtimeVersion: ESObject = selection.manifest.runtimeVersion ?? config?.runtimeVersion;
      if (typeof runtimeVersion === 'string') result.runtimeVersion = runtimeVersion;
      if (typeof config?.sdkVersion === 'string') result.sdkVersion = config.sdkVersion;
    } catch (error) {
      console.warn(`Unable to read optional Dev Menu manifest information: ${String(error)}`);
    }

    return result;
  }

  activate(debug: boolean): void {
    this.active = debug;
    if (!debug) {
      this.discovery?.stop();
      return;
    }
    UpdatesControllerRegistry.requestDevelopmentLauncherInitialization(this.bundleName);
    if (!this.recoveryChecked) {
      this.recoveryChecked = true;
      const failure = this.history.takeFailure();
      if (failure !== undefined) {
        this.recoveredFailure = true;
        this.error = `The previous runtime failed. Choose a project to try again.\n${failure}`;
        this.publish();
      }
    }
    if (this.foregrounded) this.discovery?.start();
  }

  attachAbility(ability: common.UIAbilityContext): void {
    if (this.ability === ability) return;
    this.detachAbility();
    this.ability = ability;
    this.discovery = new DevServerDiscovery(ability);
    this.detachDiscovery = this.discovery.subscribe((servers: DiscoveredServer[]): void => {
      this.servers = servers;
      this.publish();
    });
    if (this.active && this.foregrounded) this.discovery.start();
  }

  detachAbility(ability?: common.UIAbilityContext): void {
    if (ability !== undefined && this.ability !== ability) return;
    this.pendingRequest ??= this.loadingRequest;
    this.loadSerial += 1;
    this.loadingRequest = undefined;
    this.progress = 0;
    this.runtime = undefined;
    this.runtimeOwner = undefined;
    this.pendingReloadReason = undefined;
    this.foregrounded = false;
    this.discovery?.stop();
    this.detachDiscovery?.();
    this.detachDiscovery = undefined;
    this.discovery = undefined;
    this.ability = undefined;
    this.servers = [];
    this.publish();
  }

  foreground(ability: common.UIAbilityContext): void {
    if (this.ability !== ability || this.foregrounded) return;
    this.foregrounded = true;
    if (this.active) this.discovery?.start();
  }

  background(ability: common.UIAbilityContext): void {
    if (this.ability !== ability || !this.foregrounded) return;
    this.foregrounded = false;
    this.discovery?.stop();
  }

  connectUpdates(): void {
    const updates = UpdatesControllerRegistry.controller as UpdatesDevLauncherInterface | undefined;
    if (updates !== undefined && typeof updates.fetchUpdateWithConfiguration === 'function') {
      if (this.updatesCallbacks === undefined) {
        this.updatesCallbacks = new UpdatesRelaunchCallbacks((): void => {
          const request = this.selectedRequest;
          if (request?.url === undefined || this.runtime?.selection !== this.selection
            || this.loading || this.homeTransition !== undefined) return;

          // An Updates relaunch selects again so the server can provide a newer update.
          this.loadRequest(request).catch((): void => {});
        });
      }
      updates.updatesInterfaceCallbacks = this.updatesCallbacks;
    }
  }

  startInitialSelection(): void {
    if (!this.active || this.loading) return;

    const pending = this.pendingRequest;
    if (pending !== undefined) {
      this.pendingRequest = undefined;
      this.loadRequest(pending).catch((): void => {});
      return;
    }
    if (this.initialSelectionStarted || this.settledInitialSelection || this.recoveredFailure) return;
    this.initialSelectionStarted = true;
    this.launchInitialSelection().catch((): void => {});
  }

  private async launchInitialSelection(): Promise<void> {
    const recent = this.preferences.get(DevMenuPreference.TryToLaunchLastBundle) ? this.recent[0] : undefined;
    if (recent !== undefined) {
      const serial = this.loadSerial + 1;
      try {
        await this.load(recent.url);
        return;
      } catch (_) {}
      if (this.loadSerial !== serial) return;
    }
    // A newer link or a return-home action supersedes the startup fallback.
    if (this.selection !== undefined || this.pendingRequest !== undefined || this.loading) return;

    const fallback = this.metadata(DEFAULT_LAUNCH_URL_METADATA);
    if (fallback !== undefined && fallback.length > 0) await this.load(fallback);
  }

  receiveLink(value: string): void {
    let request = new LaunchRequest(value);
    if (isLauncherHomeLink(value)) {
      const fallback = this.metadata(DEFAULT_LAUNCH_URL_METADATA);
      if (fallback === undefined || fallback.length === 0) {
        this.initialSelectionStarted = true;
        const suspend = this.runtimeOwner?.suspend;
        if (this.settledInitialSelection) {
          this.showLauncher(suspend ?? (async (): Promise<void> => {})).catch((): void => {});
        } else {
          ++this.loadSerial;
          this.pendingRequest = undefined;
          this.loadingRequest = undefined;
          this.progress = 0;
          this.error = undefined;
          this.failedRequest = undefined;
          this.publish();
        }
        return;
      }
      request = new LaunchRequest(fallback, value);
    }
    if (this.active) this.loadRequest(request).catch((): void => {});
    else this.pendingRequest = request;
  }

  subscribe(listener: StateListener): () => void {
    this.listeners.add(listener);
    listener(this.state());

    return (): void => {
      this.listeners.delete(listener);
    };
  }

  async showLauncherForRuntime(id: number): Promise<void> {
    const runtime = this.runtime;
    if (runtime?.id !== id || runtime.selection !== this.selection) return;
    await this.showLauncher(runtime.suspend);
  }

  async showLauncher(suspend: () => Promise<void>): Promise<void> {
    if (!this.active || !this.settledInitialSelection) return;
    if (this.homeTransition !== undefined) return await this.homeTransition;

    const pending = this.returnToLauncher(suspend);
    this.homeTransition = pending;
    try {
      await pending;
    } finally {
      if (this.homeTransition === pending) this.homeTransition = undefined;
    }
  }

  private async returnToLauncher(suspend: () => Promise<void>): Promise<void> {
    const serial = ++this.loadSerial;
    this.loadingRequest = undefined;
    this.pendingRequest = undefined;
    this.pendingReloadReason = undefined;
    this.progress = 0;
    this.error = undefined;
    this.failedRequest = undefined;

    try {
      if (this.selection !== undefined) {
        await suspend();
        if (serial !== this.loadSerial) return;
        // A queued reload may still need the current selection to complete before
        // suspend can run. Install the new gate only after that queue has drained.
        this.selectionReady = new Promise<void>((resolve: () => void): void => {
          this.resolveReady = resolve;
        });
      }
      this.selection = undefined;
      this.selectedRequest = undefined;
      this.provider = undefined;
      if (this.manifestLoad === undefined) this.resetUpdates();
      this.publish();
    } catch (error) {
      if (serial !== this.loadSerial) return;
      this.error = displayError(error as Object);
      this.publish();
      throw new DevLauncherError(
        error instanceof DevLauncherError || error instanceof ExpoModuleError ? error.code : 'ERR_DEV_LAUNCHER_RUNTIME',
        displayError(error as Object),
      );
    }
  }

  async load(value: string): Promise<void> {
    await this.loadRequest(new LaunchRequest(value));
  }

  async loadEmbeddedBundle(): Promise<void> {
    await this.loadRequest(new LaunchRequest());
  }

  private async loadRequest(request: LaunchRequest): Promise<void> {
    if (this.homeTransition !== undefined) await this.homeTransition;
    if (!this.active) throw new DevLauncherError('ERR_DEV_LAUNCHER_UNAVAILABLE', 'Expo Dev Launcher is available only in debug builds.');
    if (this.loading) {
      this.pendingRequest = request;
      return await this.loadPromise;
    }

    const serial = ++this.loadSerial;
    this.loadingRequest = request;
    const pending = Promise.resolve().then((): Promise<void> => this.loadSelection(request, serial));
    this.loadPromise = pending;
    try {
      await pending;
    } finally {
      if (this.loadPromise === pending) this.loadPromise = undefined;
    }
  }

  private takePendingRequest(): LaunchRequest | undefined {
    const request = this.pendingRequest;
    if (request !== undefined) {
      this.pendingRequest = undefined;
      this.loadingRequest = undefined;
    }

    return request;
  }

  private async loadSelection(request: LaunchRequest, serial: number): Promise<void> {
    if (serial !== this.loadSerial) return;

    const value = request.url;
    try {
      const url = value === undefined ? undefined : resolveDevelopmentURL(value);
      this.progress = 0;
      this.error = undefined;
      this.publish();
      this.connectUpdates();

      // A previous request may still be finishing after Home or ability teardown.
      // Let it finish before resetting or starting another Updates selection.
      if (this.manifestLoad !== undefined) {
        await this.manifestLoad.catch((): void => {});
        if (serial !== this.loadSerial) return;
      }
      let selection: LaunchSelection;
      if (url === undefined) {
        if (!this.hasEmbeddedBundle() || this.embeddedProvider === undefined) {
          throw new DevLauncherError('ERR_DEV_LAUNCHER_EMBEDDED_BUNDLE', 'Embedded bundle loading requires embeddedBundle: true and a bundle supplied by the application host.');
        }
        selection = new LaunchSelection(this.embeddedProvider, undefined, undefined, 'Embedded bundle', false);
      } else {
        const pending = new DevLauncherManifestLoader(this.context, []).load(url, (progress: number): void => {
          if (serial !== this.loadSerial) return;
          this.progress = progress;
          this.publish();
        });
        this.manifestLoad = pending;
        try {
          selection = await pending;
        } finally {
          this.manifestLoad = undefined;
          if (serial !== this.loadSerial && this.selection === undefined) this.resetUpdates();
        }
      }
      if (serial !== this.loadSerial) return;

      const pending = this.takePendingRequest();
      if (pending !== undefined) {
        // Let the next load own its error; this load's serial is now obsolete.
        return this.loadRequest(pending);
      }
      try {
        if (url !== undefined) {
          await this.applyMenuURLPreferences(value!, url, request.link);
          if (serial === this.loadSerial && this.pendingRequest === undefined) {
            await this.history.remember(url, selection.name);
            this.recent = this.history.all();
          }
        }
      } catch (error) {
        console.warn(`Unable to save Expo Dev Launcher history: ${String(error)}`);
      }
      if (serial !== this.loadSerial) return;

      const queued = this.takePendingRequest();
      if (queued !== undefined) {
        return this.loadRequest(queued);
      }
      if (selection.activateUpdate !== undefined) selection.activateUpdate();
      else if (url === undefined || selection.useDeveloperSupport) this.resetUpdates();
      this.selection = selection;
      this.selectedRequest = request;
      this.recoveredFailure = false;
      this.history.clearFailure();
      this.provider = selection.provider;
      this.loadingRequest = undefined;
      this.progress = 1;
      this.error = undefined;
      this.failedRequest = undefined;
      this.publish();

      const first = !this.settledInitialSelection;
      this.resolveReady?.();
      this.resolveReady = undefined;
      if (first) {
        this.settledInitialSelection = true;
      } else {
        const reason = `Opened ${selection.name} from Expo Dev Launcher.`;
        this.requestReload(reason);
      }
    } catch (error) {
      if (serial !== this.loadSerial) return;

      const pending = this.takePendingRequest();
      if (pending !== undefined) {
        return this.loadRequest(pending);
      }
      this.loadingRequest = undefined;
      this.progress = 0;
      this.error = displayError(error as Object);
      this.failedRequest = request;
      this.publish();
      throw new DevLauncherError(
        error instanceof DevLauncherError || error instanceof ExpoModuleError ? error.code : 'ERR_DEV_LAUNCHER_RUNTIME',
        displayError(error as Object),
      );
    }
  }

  private async requestReload(reason: string): Promise<void> {
    const owner = this.runtimeOwner;
    if (owner === undefined) {
      this.pendingReloadReason = reason;
      return;
    }

    const selection = this.selection;
    try {
      await owner.reload(reason);
    } catch (error) {
      if (this.runtimeOwner !== owner || this.selection !== selection || this.homeTransition !== undefined || this.loading) return;
      this.failedRequest = this.selectedRequest;
      this.error = displayError(error as Object);
      this.publish();
    }
  }

  private resetUpdates(): void {
    const updates = UpdatesControllerRegistry.controller as UpdatesDevLauncherInterface | undefined;
    if (typeof updates?.fetchUpdateWithConfiguration === 'function') updates.reset();
  }

  private async applyMenuURLPreferences(original: string, target: string, link?: string): Promise<void> {
    const flag = (name: string): boolean => hasEnabledFlag(original, name) || (link !== undefined && hasEnabledFlag(link, name));
    const changes = new Map<DevMenuPreference, boolean>();
    if (flag('disableOnboarding') || hasEnabledFlag(target, 'disableOnboarding') || flag('disableAutoLaunch')) {
      changes.set(DevMenuPreference.OnboardingFinished, true);
    }
    if (flag('disableFab')) changes.set(DevMenuPreference.ShowFab, false);
    if (flag('disableAutoLaunch')) changes.set(DevMenuPreference.ShowsAtLaunch, false);
    for (const entry of changes) {
      try {
        await this.preferences.set(entry[0], entry[1]);
      } catch (error) {
        console.warn(`Unable to persist Dev Menu preference ${entry[0]}: ${displayError(error as Object)}`);
      }
    }
  }

  async setPreference(key: DevMenuPreference, value: boolean): Promise<void> {
    try {
      await this.preferences.set(key, value);
    } catch (error) {
      this.error = displayError(error as Object);
      this.publish();
    }
  }

  refreshServers(): void {
    if (this.active && this.foregrounded) this.discovery?.restart();
  }

  async setDiscoveryFilter(value: string): Promise<void> {
    try {
      await this.discovery?.setFilterBySlug(value);
    } catch (error) {
      this.error = displayError(error as Object);
      this.publish();
    }
  }

  async retry(): Promise<void> {
    if (this.failedRequest !== undefined) await this.loadRequest(this.failedRequest);
  }

  async copyError(): Promise<void> {
    if (this.error === undefined) return;
    try {
      const url = this.failedRequest?.url;
      const text = url === undefined ? this.error : `${url}\n${this.error}`;
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
    } catch (error) {
      this.error = `Unable to copy error details. ${displayError(error as Object)}`;
      this.publish();
    }
  }

  async scan(): Promise<void> {
    const ability = this.ability;
    try {
      if (ability === undefined) throw new DevLauncherError('ERR_DEV_LAUNCHER_ABILITY', 'No foreground UIAbility is available for QR scanning.');;
      if (!canIUse(SCAN_CAPABILITY))
        throw new DevLauncherError('ERR_DEV_LAUNCHER_SCANNER_UNAVAILABLE', 'QR scanning is not supported on this device.');

      const result = await scanBarcode.startScanForResult(ability, { scanTypes: [scanCore.ScanType.QR_CODE] });
      if (this.ability !== ability) return;
      if (result.originalValue.length === 0) throw new DevLauncherError('ERR_DEV_LAUNCHER_INVALID_QR', 'The QR code is empty.');
      await this.load(result.originalValue);
    } catch (error) {
      if (this.ability !== ability) return;
      if (error !== null && typeof error === 'object' && (error as BusinessError).code === SCANNER_CANCELLED_ERROR_CODE) return;

      const code = error instanceof DevLauncherError ? error.code : 'ERR_DEV_LAUNCHER_SCANNER';
      const message = error instanceof DevLauncherError ? error.message : `The QR scanner could not complete. ${String(error)}`;
      this.error = message;
      this.publish();

      throw new DevLauncherError(code, message);
    }
  }

  async clearHistory(): Promise<void> {
    await this.history.clear();
    this.recent = [];
    this.publish();
  }

  reportReactError(id: number, error: Error): void {
    if (!this.active || this.runtime?.id !== id || this.runtime.selection !== this.selection || this.selection === undefined) return;
    this.history.rememberFailure(error);
    if (this.selection?.useDeveloperSupport && this.provider !== undefined) sendRuntimeError(this.provider.getURL(), error);
    if (this.loading) return;
    this.failedRequest = this.selectedRequest;
    this.error = error.message;
    this.publish();
  }

  private state(): DevLauncherViewState {
    return new DevLauncherViewState(
      this.loading, this.progress, this.error, this.recent.slice(), this.servers.slice(),
      this.discovery?.searching ?? false, this.discovery?.error, this.hasEmbeddedBundle(),
      this.failedRequest !== undefined, this.preferences.snapshot(), this.discovery?.filterBySlug ?? '',
    );
  }

  private publish(): void {
    const state = this.state();
    this.listeners.forEach((listener: StateListener): void => listener(state));
  }
}

class UpdatesRelaunchCallbacks implements UpdatesInterfaceCallbacks {
  private readonly reload: () => void;

  constructor(reload: () => void) {
    this.reload = reload;
  }

  onRequestRelaunch(): void {
    this.reload();
  }
}

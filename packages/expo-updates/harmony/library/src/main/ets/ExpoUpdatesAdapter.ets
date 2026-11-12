/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import {
  UpdatesInterface,
  UpdatesDevLauncherInterface,
  UpdatesDevLauncherCallback,
  UpdatesDevLauncherResult,
  UpdatesInterfaceCallbacks,
  UpdatesStateChangeListener,
  UpdatesStateChangeSubscription,
  UpdatesNativeInterfaceStateContext,
} from '@expo-harmony/expo-updates-interface';
import { UpdatesController } from './UpdatesController';
import { UpdatesDevLauncherController } from './UpdatesDevLauncherController';
import { IUpdatesController } from './IUpdatesController';
import type { UpdatesConfiguration } from './UpdatesConfiguration';
import { normalizeHeaders } from './UpdatesProtocol';

export class ExpoUpdatesAdapter implements UpdatesInterface {
  private readonly context: common.ApplicationContext;

  constructor(context: common.ApplicationContext) {
    this.context = context;
  }

  get controller(): IUpdatesController {
    return UpdatesController.get(this.context);
  }
  get isEnabled(): boolean {
    return this.controller.enabled;
  }
  get isUsingNativeDebug(): boolean {
    return this.controller.configuration.debug;
  }
  protected get publicConfiguration(): UpdatesConfiguration | undefined {
    const controller = this.controller;
    return controller.enabled ? controller.configuration : undefined;
  }
  get runtimeVersion(): string | null {
    return this.publicConfiguration?.runtime || null;
  }
  get updateUrl(): string | null {
    return this.publicConfiguration?.url || null;
  }
  get requestHeaders(): Record<string, string> | null {
    const configuration = this.publicConfiguration;
    return configuration === undefined ? null : normalizeHeaders(configuration.headers);
  }
  get launchedUpdateId(): string | null {
    return this.controller.launched?.id ?? null;
  }
  get embeddedUpdateId(): string | null {
    return this.controller.embedded?.id ?? null;
  }
  get launchAssetPath(): string | null {
    return this.controller.path;
  }
  subscribeToUpdatesStateChanges(listener: UpdatesStateChangeListener): UpdatesStateChangeSubscription {
    const controller = this.controller;
    if (!controller.active)
      return new CallbackSubscription(
        (): void => {},
        (): UpdatesNativeInterfaceStateContext | null => null,
      );

    const subscription = controller.state.subscribe((event: Record<string, ESObject>): void => {
      if (this.controller === controller && controller.active) listener.updatesStateDidChange(event);
    });
    controller.ready.then((): void => {
      if (this.controller !== controller) subscription.remove();
    });

    return new CallbackSubscription(
      (): void => subscription.remove(),
      (): UpdatesNativeInterfaceStateContext | null => {
        if (this.controller !== controller || !controller.active) return null;
        const value = subscription.getContext();
        return {
          isUpdateAvailable: value.isUpdateAvailable,
          isUpdatePending: value.isUpdatePending,
          isChecking: value.isChecking,
          isDownloading: value.isDownloading,
          isRestarting: value.isRestarting,
          restartCount: value.restartCount,
          sequenceNumber: value.sequenceNumber,
          downloadProgress: value.downloadProgress,
          latestManifest: value.latestManifest ?? null,
          downloadedManifest: value.downloadedManifest ?? null,
          rollback: value.rollback ? { commitTime: new Date(value.rollback.commitTime) } : null,
          checkError: value.checkError ?? null,
          downloadError: value.downloadError ?? null,
          lastCheckForUpdateTime: value.lastCheckForUpdateTimeString ? new Date(value.lastCheckForUpdateTimeString) : null,
          downloadStartTime: value.downloadStartTime == null ? null : new Date(value.downloadStartTime),
          downloadFinishTime: value.downloadFinishTime == null ? null : new Date(value.downloadFinishTime),
        };
      },
    );
  }
}

class CallbackSubscription implements UpdatesStateChangeSubscription {
  private readonly onRemove: () => void;
  private readonly onContext: () => UpdatesNativeInterfaceStateContext | null;

  constructor(onRemove: () => void, onContext: () => UpdatesNativeInterfaceStateContext | null) {
    this.onRemove = onRemove;
    this.onContext = onContext;
  }

  remove(): void {
    this.onRemove();
  }

  getContext(): UpdatesNativeInterfaceStateContext | null {
    return this.onContext();
  }
}

export class ExpoUpdatesDevLauncherAdapter extends ExpoUpdatesAdapter implements UpdatesDevLauncherInterface {
  private callbacks?: WeakRef<UpdatesInterfaceCallbacks>;

  private readonly development: UpdatesDevLauncherController;

  constructor(context: common.ApplicationContext, development: UpdatesDevLauncherController) {
    super(context);
    this.development = development;
  }

  override get controller(): UpdatesDevLauncherController {
    return this.development;
  }

  get configuredUpdateUrl(): string | null {
    return this.controller.configuredUpdateUrl;
  }

  protected override get publicConfiguration(): UpdatesConfiguration | undefined {
    const configuration = this.controller.configuration;
    return configuration.enabled ? configuration : undefined;
  }

  get updatesInterfaceCallbacks(): UpdatesInterfaceCallbacks | undefined {
    return this.callbacks?.deref();
  }
  set updatesInterfaceCallbacks(value: UpdatesInterfaceCallbacks | undefined) {
    this.callbacks = value === undefined ? undefined : new WeakRef(value);
    this.controller.developmentReload = value === undefined ? undefined : (): void => this.callbacks?.deref()?.onRequestRelaunch();
  }

  reset(): void {
    this.controller.reset();
  }

  isValidUpdatesConfiguration(value: Record<string, ESObject>): boolean {
    try {
      this.controller.configurationFor(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  fetchUpdateWithConfiguration(value: Record<string, ESObject>, callback: UpdatesDevLauncherCallback, deferActivation: boolean = false): void {
    this.controller
      .loadDevelopment(
        value,
        (manifest: Record<string, ESObject>): boolean => callback.onManifestLoaded(manifest),
        (successful: number, failed: number, total: number): void => callback.onProgress(successful, failed, total),
        deferActivation,
      )
      .then(
        (update: UpdatesDevLauncherResult | null): void => callback.onSuccess(update),
        (error: Error): void => callback.onFailure(error),
      )
      .catch((error: Error): void => console.error(`Development update callback failed: ${String(error)}`));
  }
}

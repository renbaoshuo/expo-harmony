/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export interface UpdatesStateChangeSubscription {
  remove(): void;
  getContext(): UpdatesNativeInterfaceStateContext | null;
}

export interface UpdatesStateChangeListener {
  updatesStateDidChange(event: Record<string, ESObject>): void;
}

export interface UpdatesInterface {
  readonly isEnabled: boolean;
  readonly runtimeVersion: string | null;
  readonly updateUrl: string | null;
  readonly requestHeaders: Record<string, string> | null;
  readonly launchedUpdateId: string | null;
  readonly embeddedUpdateId: string | null;
  readonly launchAssetPath: string | null;
  subscribeToUpdatesStateChanges(listener: UpdatesStateChangeListener): UpdatesStateChangeSubscription;
}

export interface UpdatesDevLauncherResult {
  manifest: Record<string, ESObject>;
  launchAssetPath: string;
  /** Commits a deferred update once. Reset or another activation invalidates it. */
  activate?: () => void;
}

export interface UpdatesDevLauncherCallback {
  onFailure(error: Error | null): void;
  onSuccess(update: UpdatesDevLauncherResult | null): void;
  onProgress(successful: number, failed: number, total: number): void;
  onManifestLoaded(manifest: Record<string, ESObject>): boolean;
}

export interface UpdatesInterfaceCallbacks {
  onRequestRelaunch(): void;
}

export interface UpdatesDevLauncherInterface extends UpdatesInterface {
  /** URL packaged with the app. Implementations can omit this if unavailable. */
  readonly configuredUpdateUrl?: string | null;
  updatesInterfaceCallbacks?: UpdatesInterfaceCallbacks;
  reset(): void;
  /** By default the update is selected before onSuccess. Pass true to defer selection to result.activate. */
  fetchUpdateWithConfiguration(
    configuration: Record<string, ESObject>,
    callback: UpdatesDevLauncherCallback,
    deferActivation?: boolean,
  ): void;
  isValidUpdatesConfiguration(configuration: Record<string, ESObject>): boolean;
}

export interface UpdatesNativeInterfaceStateContext {
  readonly isUpdateAvailable: boolean;
  readonly isUpdatePending: boolean;
  readonly isChecking: boolean;
  readonly isDownloading: boolean;
  readonly isRestarting: boolean;
  readonly restartCount: number;
  readonly latestManifest: Record<string, ESObject> | null;
  readonly downloadedManifest: Record<string, ESObject> | null;
  readonly rollback: UpdatesRollback | null;
  readonly checkError: Record<string, string> | null;
  readonly downloadError: Record<string, string> | null;
  readonly downloadProgress: number;
  readonly lastCheckForUpdateTime: Date | null;
  readonly sequenceNumber: number;
  readonly downloadStartTime: Date | null;
  readonly downloadFinishTime: Date | null;
}

export interface UpdatesRollback {
  readonly commitTime: Date;
}

export class UpdatesControllerRegistry {
  private static controllerRef?: WeakRef<UpdatesInterface>;
  private static readonly developmentLauncherRequests = new Set<string>();

  static get controller(): UpdatesInterface | undefined {
    const controller = UpdatesControllerRegistry.controllerRef?.deref();
    if (!controller) UpdatesControllerRegistry.controllerRef = undefined;
    return controller;
  }

  static set controller(value: UpdatesInterface | undefined) {
    UpdatesControllerRegistry.controllerRef = value === undefined ? undefined : new WeakRef(value);
  }

  static requestDevelopmentLauncherInitialization(bundleName: string): void {
    UpdatesControllerRegistry.developmentLauncherRequests.add(bundleName);
  }

  static isDevelopmentLauncherInitializationRequested(bundleName: string): boolean {
    return UpdatesControllerRegistry.developmentLauncherRequests.has(bundleName);
  }

  static completeDevelopmentLauncherInitialization(bundleName: string): void {
    UpdatesControllerRegistry.developmentLauncherRequests.delete(bundleName);
  }
}

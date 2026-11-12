/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type common from '@ohos.app.ability.common';
import { UpdatesConfiguration } from './UpdatesConfiguration';
import { UpdatesDownloader } from './UpdatesDownloader';
import { UpdatesState } from './UpdatesState';
import { UpdatesStorage } from './UpdatesStorage';
import { RemoteLoader } from './loader/RemoteLoader';
import { clientIdentity, prepareClientIdentity } from './UpdatesClientIdentity';
import { ExpoUpdatesError, Headers, Json, UpdateRecord } from './UpdatesProtocol';

import { IUpdatesController } from './IUpdatesController';
import { UpdatesLogReader } from './logging/UpdatesLogReader';
import { SelectionPolicyFactory } from './selectionpolicy/SelectionPolicyFactory';
import { UpdatesDatabaseLauncher } from './launcher/UpdatesDatabaseLauncher';
import { localAssetFiles } from './UpdatesAssetPaths';

interface DevelopmentUpdate {
  manifest: Json;
  launchAssetPath: string;
  activate?: () => void;
}

export class UpdatesDevLauncherController implements IUpdatesController {
  readonly state = new UpdatesState();
  readonly ready: Promise<void> = Promise.resolve();
  readonly enabled = true;
  readonly active = false;
  private config: UpdatesConfiguration;
  private readonly storage: UpdatesStorage;
  private readonly downloader: UpdatesDownloader;
  private readonly loader: RemoteLoader;
  private opened = false;
  private current?: UpdateRecord;
  private selectionGeneration = 0;
  developmentReload?: () => void;

  constructor(
    private readonly context: common.ApplicationContext,
    private readonly original: UpdatesConfiguration,
    readonly configuredUpdateUrl: string | null = original.url || null,
  ) {
    this.config = original;
    this.storage = new UpdatesStorage(context);
    this.downloader = new UpdatesDownloader(this.storage, context);
    this.loader = new RemoteLoader(this.storage, this.downloader, clientIdentity(context));
  }

  get configuration(): UpdatesConfiguration { return this.config; }
  get launched(): UpdateRecord | undefined { return this.current; }
  get embedded(): UpdateRecord | undefined { return undefined; }
  get path(): string | null { return this.current?.assets.find(asset => asset.launch)?.path ?? null; }

  start(): void {}

  constants(_id?: number): Json {
    const update = this.current;
    return {
      isEnabled: true,
      isEmergencyLaunch: false,
      emergencyLaunchReason: null,
      launchDuration: null,
      isEmbeddedLaunch: false,
      isUsingEmbeddedAssets: false,
      runtimeVersion: this.config.runtime || '1',
      checkAutomatically: this.config.check,
      channel: this.config.headers['expo-channel-name'] ?? '',
      shouldDeferToNativeForAPIMethodAvailabilityInDevelopment: true,
      updateId: update?.id,
      commitTime: update?.time,
      manifest: update?.manifest,
      localAssets: localAssetFiles(update),
      domAssetBaseUrl: update?.domAssets?.baseUrl ?? null,
      initialContext: this.state.context,
    };
  }

  attach(_id: number, _reload: (reason: string) => Promise<void>, _owner: Object): () => void { return () => {}; }
  loaded(_id: number): void {}
  contentAppeared(_id: number): void {}
  hasAsset(_id: number, path: string): boolean {
    return this.current?.assets.some(asset => asset.path === path) === true || [...this.current?.domAssets?.files.values() ?? []].includes(path);
  }
  onReactInstanceException(_id: number, _error: Error): void {}

  async reload(_id: number, _reload: (reason: string) => Promise<void>): Promise<void> {
    this.developmentReload?.();
  }

  async checkForUpdateAsync(): Promise<Json> {
    throw new ExpoUpdatesError('ERR_UPDATES_DEV_CLIENT', 'Updates.checkForUpdateAsync() is not supported in development builds.');
  }

  async fetchUpdateAsync(): Promise<Json> {
    throw new ExpoUpdatesError('ERR_UPDATES_DEV_CLIENT', 'Updates.fetchUpdateAsync() is not supported in development builds.');
  }

  async extra(): Promise<Headers> {
    throw new ExpoUpdatesError('ERR_UPDATES_DEV_CLIENT', 'Updates.getExtraParamsAsync() is not supported in development builds.');
  }

  async setExtra(_key: string, _value: string | null): Promise<void> {
    throw new ExpoUpdatesError('ERR_UPDATES_DEV_CLIENT', 'Updates.setExtraParamAsync() is not supported in development builds.');
  }

  override(_value: Json | null): void {
    throw new ExpoUpdatesError('ERR_UPDATES_DEV_CLIENT', 'Updates.setUpdateURLAndRequestHeadersOverride() is not supported in development builds.');
  }

  overrideHeaders(_headers: Headers | null): void {
    throw new ExpoUpdatesError('ERR_UPDATES_DEV_CLIENT', 'Updates.setUpdateRequestHeadersOverride() is not supported in development builds.');
  }


  logs(age: number): Promise<Json[]> { return new UpdatesLogReader(this.context).read(age); }

  clearLogs(): Promise<void> { return new UpdatesLogReader(this.context).clear(); }

  reset(): void {
    ++this.selectionGeneration;
    this.current = undefined;
    this.config = this.original;
  }

  configurationFor(value: Json): UpdatesConfiguration {
    const dynamic = { ...value };
    if (dynamic.url === undefined && typeof dynamic.updateUrl === 'string') dynamic.url = dynamic.updateUrl;
    const configuration = new UpdatesConfiguration({ ...this.original.raw, ...dynamic, useEmbeddedUpdate: false }, false);
    if (!configuration.enabled) throw new ExpoUpdatesError('ERR_UPDATES_CONFIGURATION', 'A development update requires an enabled configuration, URL, and runtime version.');

    return configuration;
  }

  async loadDevelopment(value: Json, accepted: (manifest: Json) => boolean,
    progress: (successful: number, failed: number, total: number) => void, deferActivation = false): Promise<DevelopmentUpdate | null> {
    const configuration = this.configurationFor(value);
    return this.state.queue({ run: () => this.fetch(configuration, accepted, progress, deferActivation) });
  }

  private async fetch(configuration: UpdatesConfiguration, accepted: (manifest: Json) => boolean,
    progress: (successful: number, failed: number, total: number) => void, deferActivation: boolean): Promise<DevelopmentUpdate | null> {
    const generation = this.selectionGeneration;
    try {
      await prepareClientIdentity(this.context);
      if (!this.opened) {
        await this.storage.open();
        this.opened = true;
      }
      const response = await this.loader.response(configuration);
      if (response.directive || !response.update || !accepted(response.update.manifest)) return null;

      const candidate = response.update;
      const headers = await this.loader.assetHeaders(configuration, undefined, undefined, candidate);
      const loaded = await this.loader.load(candidate, configuration, undefined, headers, () => {},
        candidate.status === 'development' ? 'development' : 'ready', progress);
      const policy = SelectionPolicyFactory.singleUpdate(loaded.id, SelectionPolicyFactory.development(configuration.runtime, configuration.url, configuration.headers));
      const launcher = new UpdatesDatabaseLauncher(this.storage, this.downloader, policy, () => undefined);
      const update = await launcher.launch(configuration, async () => headers);
      const path = update?.assets.find(asset => asset.launch)?.path;
      if (!update || !path) throw new ExpoUpdatesError('ERR_UPDATES_ASSET', 'The development update has no launch asset.');

      const activate = (): void => {
        if (generation !== this.selectionGeneration) {
          throw new ExpoUpdatesError('ERR_UPDATES_DEV_CLIENT', 'The development update selection was superseded.');
        }
        ++this.selectionGeneration;
        const previous = this.current;
        this.current = update;
        this.config = configuration;
        void this.state.queue({
          run: async (): Promise<void> => {
            const updates = await this.storage.updates();
            const obsolete = policy.toDelete(updates, update);
            await this.storage.delete(obsolete.filter(record => record.id !== previous?.id && record.id !== this.current?.id));
          },
        }).catch(error => this.storage.logger.log(`Unable to reap development updates: ${String(error)}`, 'Unknown', 'warn'));
      };
      const result = { manifest: update.manifest, launchAssetPath: path };
      if (deferActivation) return { ...result, activate };
      activate();

      return result;
    } catch (error) {
      throw new ExpoUpdatesError(error instanceof ExpoUpdatesError ? error.code : 'ERR_UPDATES_DEV_CLIENT',
        String(error), error instanceof Error ? error : undefined);
    }
  }
}

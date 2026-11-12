/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type common from '@ohos.app.ability.common';
import { IUpdatesController } from './IUpdatesController';
import { UpdatesConfiguration } from './UpdatesConfiguration';
import { UpdatesState } from './UpdatesState';
import { UpdatesLogReader } from './logging/UpdatesLogReader';
import { UpdatesLogger } from './logging/UpdatesLogger';
import { ExpoUpdatesError, Headers, Json, UpdateRecord } from './UpdatesProtocol';

export class DisabledUpdatesController implements IUpdatesController {
  readonly enabled = false;
  readonly active = false;
  readonly ready = Promise.resolve();
  readonly state = new UpdatesState();
  readonly path = null;
  readonly embedded = undefined;
  readonly launched: UpdateRecord | undefined = undefined;
  private started = false;
  private duration: number | null = null;

  constructor(private readonly context: common.ApplicationContext, readonly configuration: UpdatesConfiguration,
    private readonly failure?: Error) {
    if (failure) new UpdatesLogger(context).error(failure.message, failure, 'InitializationError');
  }

  start(): void {
    if (this.started) return;
    this.started = true;
    this.duration = 0;
  }

  constants(_id?: number): Json {
    return {
      isEnabled: false, isEmergencyLaunch: this.failure !== undefined, emergencyLaunchReason: this.failure?.message ?? null,
      launchDuration: this.duration, isEmbeddedLaunch: false, isUsingEmbeddedAssets: true,
      runtimeVersion: '', checkAutomatically: 'NEVER', channel: '', shouldDeferToNativeForAPIMethodAvailabilityInDevelopment: false,
      updateId: this.launched?.id, commitTime: this.launched?.time, manifest: this.launched?.manifest,
      localAssets: {}, domAssetBaseUrl: null, initialContext: this.state.context,
    };
  }

  attach(_id: number, _reload: (reason: string) => Promise<void>, _owner: Object): () => void { return (): void => {}; }
  loaded(_id: number): void {}
  contentAppeared(_id: number): void {}
  hasAsset(_id: number, _path: string): boolean { return false; }
  onReactInstanceException(_id: number, _error: Error): void {}

  async reload(_id: number, reload: (reason: string) => Promise<void>): Promise<void> {
    try {
      await reload('Expo Updates reload');
    } catch (error) {
      throw new ExpoUpdatesError('ERR_UPDATES_RELOAD', `Unable to restart the React runtime: ${String(error)}`, error as Error);
    }
  }

  async checkForUpdateAsync(): Promise<Json> {
    throw new ExpoUpdatesError('ERR_UPDATES_DISABLED', 'Updates.checkForUpdateAsync() is not supported when expo-updates is not enabled.');
  }

  async fetchUpdateAsync(): Promise<Json> {
    throw new ExpoUpdatesError('ERR_UPDATES_DISABLED', 'Updates.fetchUpdateAsync() is not supported when expo-updates is not enabled.');
  }

  async extra(): Promise<Headers> {
    throw new ExpoUpdatesError('ERR_UPDATES_DISABLED', 'Updates.getExtraParamsAsync() is not supported when expo-updates is not enabled.');
  }

  async setExtra(_key: string, _value: string | null): Promise<void> {
    throw new ExpoUpdatesError('ERR_UPDATES_DISABLED', 'Updates.setExtraParamAsync() is not supported when expo-updates is not enabled.');
  }

  override(_value: Json | null): void {
    throw new ExpoUpdatesError('ERR_UPDATES_DISABLED', 'Updates.setUpdateURLAndRequestHeadersOverride() is not supported when expo-updates is not enabled.');
  }

  overrideHeaders(_headers: Headers | null): void {
    throw new ExpoUpdatesError('ERR_UPDATES_DISABLED', 'Updates.setUpdateRequestHeadersOverride() is not supported when expo-updates is not enabled.');
  }


  logs(age: number): Promise<Json[]> { return new UpdatesLogReader(this.context).read(age); }

  clearLogs(): Promise<void> { return new UpdatesLogReader(this.context).clear(); }
}

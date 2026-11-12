/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import connection from '@ohos.net.connection';
import { ExpoUpdatesError, Json, UpdateRecord } from '../UpdatesProtocol';
import { UpdatesStateEvent } from '../UpdatesStateEvent';
import { UpdatesProcedureHost } from '../procedures/UpdatesProcedureHost';

export interface LoaderTaskDelegate {
  readonly state: string;
  process(event: UpdatesStateEvent): void;
  launched(update: UpdateRecord | undefined, error?: Error): void;
}

interface RemoteResult { result: Json; update: UpdateRecord; }

export class LoaderTask {
  private started = false;
  private running = false;

  constructor(private readonly host: UpdatesProcedureHost, private readonly select: () => Promise<UpdateRecord | undefined>) {}

  get isRunning(): boolean { return this.running; }

  private async shouldCheck(): Promise<boolean> {
    const check = this.host.configuration.check;
    if (check === 'ALWAYS') return true;
    if (check !== 'WIFI_ONLY') return false;

    try {
      const network = await connection.getDefaultNet();
      return (await connection.getNetCapabilities(network)).bearerTypes.includes(connection.NetBearType.BEARER_WIFI);
    } catch (error) {
      this.host.storage.logger.log(`Unable to determine the network connection: ${String(error)}`, 'Unknown', 'warn');
      return false;
    }
  }

  async start(delegate: LoaderTaskDelegate): Promise<void> {
    if (this.started) throw new ExpoUpdatesError('ERR_UPDATES_STARTUP', 'The startup loader task can only run once.');

    this.started = true;
    this.running = true;
    const started = Date.now();
    let remote: Promise<RemoteResult> | undefined;
    let timer: number | undefined;

    try {
      const check = await this.shouldCheck();
      let cached: UpdateRecord | undefined;
      let failure: Error | undefined;

      try {
        await this.host.loadEmbedded();
        await this.host.storage.integrity(this.host.embedded?.id);
        cached = await this.select();
      } catch (error) {
        failure = error as Error;
        this.host.storage.logger.error(`Unable to load a cached update: ${String(error)}`, failure, 'UpdateFailedToLoad');
      }

      let selected = cached;
      if (check) {
        remote = this.fetch(delegate, cached);
        this.host.remote(remote.then(value => value.result));
        // A remote error must not prevent an already validated cached update from launching.
        const candidate = remote.then(value => value.update).catch((error: Error) => { failure = error; return cached; });
        if (cached) {
          const remaining = Math.max(0, this.host.configuration.wait - (Date.now() - started));
          selected = remaining === 0 ? cached : await Promise.race([
            candidate,
            new Promise<UpdateRecord>(resolve => { timer = setTimeout(() => resolve(cached!), remaining); }),
          ]);
        } else {
          selected = await candidate;
        }
      }

      if (!selected) throw new ExpoUpdatesError('ERR_UPDATES_LAUNCH', 'No compatible update is available to launch.', failure);

      selected.accessed = Date.now();
      await this.host.storage.markAccessed(selected.id, selected.accessed);
      await this.host.storage.markFinished(selected.id);
      delegate.launched(selected);
    } catch (error) {
      this.host.storage.logger.error(`Emergency launch: ${String(error)}`, error as Error, 'UpdateFailedToLoad');
      delegate.launched(undefined, error as Error);
    } finally {
      if (timer !== undefined) clearTimeout(timer);
      if (remote) await remote.catch(() => undefined);
      this.running = false;
    }
  }

  private async fetch(delegate: LoaderTaskDelegate, launched?: UpdateRecord): Promise<RemoteResult> {
    delegate.process({ type: 'check' });

    try {
      const host = this.host;
      const configuration = host.configuration;
      const embedded = host.embedded;
      const { response, result } = await host.loader.check(configuration, host.policy, launched, embedded);
      if (result.isAvailable) delegate.process({ type: 'checkCompleteWithUpdate', manifest: result.manifest });
      else if (result.isRollBackToEmbedded) delegate.process({ type: 'checkCompleteWithRollback', commitTime: result.time });
      else delegate.process({ type: 'checkCompleteUnavailable' });
      if (result.isAvailable || result.isRollBackToEmbedded) delegate.process({ type: 'download' });

      const value = await host.loader.fetch(response, result, configuration, launched, embedded,
        progress => delegate.process({ type: 'downloadProgress', progress }));
      const update = await this.select();
      if (!update) throw new ExpoUpdatesError('ERR_UPDATES_LAUNCH', 'The remote result has no launchable update.');
      if (value.isRollBackToEmbedded) delegate.process({ type: 'downloadCompleteWithRollback', commitTime: result.time });
      else if (value.isNew) delegate.process({ type: 'downloadCompleteWithUpdate', manifest: value.manifest });
      else if (delegate.state === 'downloading') delegate.process({ type: 'downloadComplete' });

      return { result: value, update };
    } catch (error) {
      if (delegate.state === 'checking') delegate.process({ type: 'checkError', errorMessage: error instanceof Error ? error.message : String(error) });
      else {
        if (delegate.state === 'idle') delegate.process({ type: 'download' });
        delegate.process({ type: 'downloadError', errorMessage: error instanceof Error ? error.message : String(error) });
      }
      this.host.storage.logger.error(String(error), error as Error, 'UpdateFailedToLoad');
      throw new ExpoUpdatesError(error instanceof ExpoUpdatesError ? error.code : 'ERR_UPDATES_FETCH', `Unable to fetch startup update: ${String(error)}`, error as Error);
    }
  }
}

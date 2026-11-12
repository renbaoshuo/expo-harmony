/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

/// <reference path="../UpdatesNative.d.ts" />

import type common from '@ohos.app.ability.common';
import { crash } from 'libexpo_updates.so';
import { UpdatesConfiguration } from '../UpdatesConfiguration';
import { UpdatesDownloader } from '../UpdatesDownloader';
import { UpdatesStorage } from '../UpdatesStorage';
import { UpdatesState } from '../UpdatesState';
import { clientIdentity } from '../UpdatesClientIdentity';
import { EmbeddedLoader } from '../loader/EmbeddedLoader';
import { RemoteLoader } from '../loader/RemoteLoader';
import { LoaderTask } from '../loader/LoaderTask';
import { UpdatesDatabaseLauncher } from '../launcher/UpdatesDatabaseLauncher';
import { UpdatesSelectionPolicy } from '../selectionpolicy/UpdatesSelectionPolicy';
import { UpdatesErrorRecovery } from '../errorrecovery/UpdatesErrorRecovery';
import { RemoteLoadStatus } from '../errorrecovery/ErrorRecoveryHandler';
import { ExpoUpdatesError, Headers, Json, UpdateRecord } from '../UpdatesProtocol';
import { ProcedureContext, StateMachineProcedure } from './StateMachineProcedure';
import { UpdatesProcedureHost } from './UpdatesProcedureHost';
import { FetchUpdateProcedure } from './FetchUpdateProcedure';
import { RelaunchProcedure } from './RelaunchProcedure';

const recoveryWindow = 10000;

export interface StartupDelegate {
  readonly configuration: UpdatesConfiguration;
  readonly policy: UpdatesSelectionPolicy;
  readonly initialized: boolean;
  launched(): void;
}

export class StartupProcedure implements StateMachineProcedure<void>, UpdatesProcedureHost {
  readonly loader: RemoteLoader;
  private readonly downloader: UpdatesDownloader;
  private readonly embeddedLoader: EmbeddedLoader;
  private readonly recovery: UpdatesErrorRecovery;
  private readonly task: LoaderTask;
  private selected?: UpdateRecord;
  private bundled?: UpdateRecord;
  private failure?: string;
  private elapsed: number | null = null;
  private started = 0;
  private pending?: Promise<Json>;
  private remoteStatus = RemoteLoadStatus.IDLE;

  constructor(context: common.ApplicationContext, readonly storage: UpdatesStorage,
    private readonly state: UpdatesState, private readonly delegate: StartupDelegate) {
    this.downloader = new UpdatesDownloader(storage, context);
    this.embeddedLoader = new EmbeddedLoader(context, storage, this.downloader, delegate.configuration);
    this.loader = new RemoteLoader(storage, this.downloader, clientIdentity(context));
    this.task = new LoaderTask(this, () => this.select());
    this.recovery = new UpdatesErrorRecovery(recoveryWindow, storage, {
      enabled: () => true, initialized: () => delegate.initialized, launched: () => this.launched,
      scope: () => this.configuration.scope,
      status: () => this.remoteStatus, checkAllowed: () => this.configuration.check !== 'NEVER',
      download: () => this.download(true),
      restart: (id, reason) => this.relaunch(id, reason, false), reap: () => this.reap(),
    });
  }

  get configuration(): UpdatesConfiguration { return this.delegate.configuration; }
  get policy(): UpdatesSelectionPolicy { return this.delegate.policy; }
  get launched(): UpdateRecord | undefined { return this.selected; }
  get embedded(): UpdateRecord | undefined { return this.bundled; }
  get emergency(): string | undefined { return this.failure; }
  get duration(): number | null { return this.elapsed; }

  begin(): void { this.started = Date.now(); }

  async run(context: ProcedureContext): Promise<void> {
    context.process({ type: 'startStartup' });

    try {
      await this.task.start({
        process: event => context.process(event),
        get state() { return context.state; },
        launched: (update, error) => {
          this.selected = update ?? this.embedded;
          this.failure = error === undefined ? undefined : String(error);
          this.elapsed = Date.now() - this.started;
          this.delegate.launched();
        },
      });
    } finally {
      // LoaderTask finishes only after remote work, even when the launch deadline has expired.
      context.process({ type: 'endStartup' });
    }
  }

  async loadEmbedded(): Promise<void> {
    try {
      this.bundled = await this.embeddedLoader.load(this.configuration);
    } catch (error) {
      this.storage.logger.error(`Unable to load the embedded update: ${String(error)}`, error as Error, 'UpdateFailedToLoad');
    }
  }

  private async select(): Promise<UpdateRecord | undefined> {
    await this.loadEmbedded();
    const launcher = new UpdatesDatabaseLauncher(this.storage, this.downloader, this.policy, () => this.embedded);
    return launcher.launch(this.configuration, update => this.assetHeaders(update));
  }

  private assetHeaders(update?: UpdateRecord): Promise<Headers> {
    return this.loader.assetHeaders(this.configuration, this.launched, this.embedded, update);
  }

  update(id: number): UpdateRecord | undefined { return this.recovery.update(id); }

  download(waitForExisting: boolean = false): Promise<Json> {
    if (waitForExisting && this.pending !== undefined) return this.pending;
    return this.state.queue(new FetchUpdateProcedure(this));
  }

  remote(remote: Promise<Json>): void {
    this.pending = remote;
    this.remoteStatus = RemoteLoadStatus.NEW_UPDATE_LOADING;
    const finish = (status: RemoteLoadStatus): void => {
      if (this.pending !== remote) return;

      this.remoteStatus = status;
      this.pending = undefined;
      this.recovery.remoteChanged(status);
      this.reap();
    };
    remote.then(result => finish(result.isNew || result.isRollBackToEmbedded ? RemoteLoadStatus.NEW_UPDATE_LOADED : RemoteLoadStatus.IDLE),
      () => finish(RemoteLoadStatus.IDLE));
  }

  attach(id: number, reload: (reason: string) => Promise<void>, owner: Object): () => void {
    if (this.recovery.runtime(id) !== undefined) throw new ExpoUpdatesError('ERR_UPDATES_RUNTIME', `React runtime ${id} is already attached.`);
    return this.recovery.attach(id, reload, owner);
  }

  loaded(id: number): void {
    this.recovery.loaded(id);
  }

  contentAppeared(id: number): void {
    this.recovery.contentAppeared(id);
  }

  reap(): void {
    if (this.task.isRunning || this.pending || this.state.context.isDownloading) return;
    if (!this.delegate.initialized || !this.launched) return;
    this.state.queue({ run: async () => {
      const update = this.launched;
      if (!update || this.pending || this.state.context.isDownloading) return;

      const active = this.recovery.activeIds();
      const updates = await this.storage.updates(update.scope);
      const filters = await this.storage.metadata(update.scope, 'filters');
      await this.storage.delete(this.policy.toDelete(updates, update, filters).filter(value => !active.has(value.id)));
    } }).catch((error: Error) => this.storage.logger.log(`Unable to reap updates: ${String(error)}`, 'Unknown', 'warn'));
  }

  onReactInstanceException(id: number, error: Error): void {
    const runtime = this.recovery.runtime(id);
    if (runtime === undefined) return;

    this.recovery.recover(id, error).catch((failure: Error): void => {
      if (this.recovery.runtime(id) !== runtime) return;
      try { this.storage.logger.error(failure.message, failure, 'Unknown'); }
      finally { crash(failure.stack ?? failure.message); }
    });
  }

  async reload(id: number, reload: (reason: string) => Promise<void>): Promise<void> {
    this.recovery.setReload(id, reload);

    return this.relaunch(id, 'Expo Updates reload');
  }

  private relaunch(id: number, reason: string, reap: boolean = true): Promise<void> {
    const runtime = this.recovery.runtime(id);
    return this.state.queue(new RelaunchProcedure({
      select: async () => {
        if (!runtime || this.recovery.runtime(id) !== runtime) throw new ExpoUpdatesError('ERR_UPDATES_RELOAD', 'The React runtime has no reload route.');
        return this.select();
      },
      launch: async update => {
        if (this.recovery.runtime(id) !== runtime) throw new ExpoUpdatesError('ERR_UPDATES_RELOAD', 'The React runtime was destroyed during update selection.');

        const previous = this.launched;
        this.selected = update;

        try { await runtime!.reload(reason); }
        catch (error) {
          this.selected = previous;
          throw new ExpoUpdatesError(error instanceof ExpoUpdatesError ? error.code : 'ERR_UPDATES_RELOAD', String(error), error as Error);
        }
        if (reap) this.reap();
      },
    }));
  }

}

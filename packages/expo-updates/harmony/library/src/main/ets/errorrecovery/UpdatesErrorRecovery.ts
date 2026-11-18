/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoUpdatesError, UpdateRecord } from '../UpdatesProtocol';
import { UpdatesStorage } from '../UpdatesStorage';
import { ErrorRecoveryHandler, RemoteLoadStatus } from './ErrorRecoveryHandler';

interface RecoveryRuntime {
  reload: (reason: string) => Promise<void>;
  appeared: boolean;
  loaded: boolean;
  monitoring: boolean;
  update?: UpdateRecord;
  timer?: number;
  handler: ErrorRecoveryHandler;
}

export interface RecoveryDelegate {
  enabled(): boolean;
  initialized(): boolean;
  scope(): string;
  launched(): UpdateRecord | undefined;
  status(): RemoteLoadStatus;
  checkAllowed(): boolean;
  download(): Promise<unknown>;
  restart(id: number, reason: string): Promise<void>;
  reap(): void;
}

export class UpdatesErrorRecovery {
  private readonly runtimes = new Map<number, RecoveryRuntime>();
  private readonly handlers = new WeakMap<Object, ErrorRecoveryHandler>();

  constructor(private readonly windowMs: number, private readonly storage: UpdatesStorage, private readonly delegate: RecoveryDelegate) {}

  attach(id: number, reload: (reason: string) => Promise<void>, owner: Object): () => void {
    const handler = new ErrorRecoveryHandler(this.handlers.get(owner));
    this.handlers.set(owner, handler);
    const runtime: RecoveryRuntime = { reload, appeared: false, loaded: false, monitoring: true, update: this.delegate.launched(), handler };
    this.runtimes.set(id, runtime);
    handler.attach({
      status: () => this.delegate.status(), checkAllowed: () => this.delegate.checkAllowed(),
      loadRemote: () => { this.delegate.download().catch(() => {}); },
      successfulCount: () => runtime.update?.successful ?? 0,
      markFailed: () => {
        const update = runtime.update;
        if (update !== undefined) {
          update.failed++;
          this.storage.incrementFailed(update.id).catch((error: Error) => this.storage.logger.log(`Unable to record failed launch: ${String(error)}`, 'Unknown', 'warn', update.id));
        }
      },
      markSuccessful: () => {
        const update = runtime.update;
        if (update !== undefined && this.delegate.initialized()) {
          update.successful++;
          this.storage.incrementSuccessful(update.id).catch((error: Error) => this.storage.logger.log(`Unable to record successful launch: ${String(error)}`, 'Unknown', 'warn', update.id));
          this.storage.logger.log(`Update ${update.id} launched successfully.`, 'None', 'info', update.id);
          this.delegate.reap();
        }
      },
      relaunch: async () => {
        if (this.runtimes.get(id) !== runtime) return;
        await this.delegate.restart(id, 'Expo Updates error recovery');
      },
      log: (message, error) => this.storage.logger.log(message, error === undefined ? 'None' : 'JSRuntimeError', error === undefined ? 'info' : 'error', runtime.update?.id, undefined, error),
    });

    return (): void => {
      if (runtime.timer !== undefined) clearTimeout(runtime.timer);
      if (this.runtimes.get(id) !== runtime) return;

      this.runtimes.delete(id);
      handler.detach();
    };
  }

  update(id: number): UpdateRecord | undefined { return this.runtimes.get(id)?.update; }

  runtime(id: number): { reload: (reason: string) => Promise<void> } | undefined {
    const runtime = this.runtimes.get(id);
    return runtime;
  }

  activeIds(): Set<string> {
    return new Set([...this.runtimes.values()].flatMap(value => value.update ? [value.update.id] : []));
  }

  hasLoaded(id: number): boolean { return this.runtimes.get(id)?.loaded === true; }

  setReload(id: number, reload: (reason: string) => Promise<void>): void {
    const runtime = this.runtimes.get(id);
    if (runtime !== undefined) runtime.reload = reload;
  }

  loaded(id: number): void {
    const runtime = this.runtimes.get(id);
    if (runtime === undefined) return;

    runtime.update = this.delegate.launched();
    runtime.loaded = true;
  }

  contentAppeared(id: number): void {
    const runtime = this.runtimes.get(id);
    if (runtime === undefined || runtime.appeared || !this.delegate.enabled()) return;

    runtime.appeared = true;
    runtime.handler.contentAppeared();
    runtime.timer = setTimeout(() => { runtime.monitoring = false; }, this.windowMs);
  }

  remoteChanged(status: RemoteLoadStatus): void {
    for (const runtime of this.runtimes.values()) runtime.handler.remoteChanged(status);
  }

  async recover(id: number, error: Error): Promise<void> {
    const runtime = this.runtimes.get(id);
    if (runtime === undefined || !this.delegate.enabled() || !this.delegate.initialized()) return;
    if (!runtime.monitoring && !runtime.handler.isRunning) throw new ExpoUpdatesError('ERR_UPDATES_RECOVERY', error.message, error);

    const saved = this.storage.setMetadata(this.delegate.scope(), 'fatal', error.message).catch((failure: Error) => {
      this.storage.logger.log(`Unable to persist runtime error: ${String(failure)}`, 'Unknown', 'warn');
    });

    let recovered = false;
    try {
      await runtime.handler.recover(error);
      recovered = true;
    } finally {
      if (!recovered) await saved;
    }
  }
}

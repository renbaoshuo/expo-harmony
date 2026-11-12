/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import type { RNInstance } from '@rnoh/react-native-openharmony';
import { ExpoModuleError } from '../modules/ExpoModuleError';
import { ReactNativeRuntime, ReactRuntimeListener } from '../interfaces/ReactNativeRuntime';
import { RnohHeadlessContext } from '../appcontext/RnohHeadlessContext';
import { observeRnohDestroy } from '../appcontext/RnohDestroyAdapter';
import { waitForRnohBundle } from '../appcontext/RnohBundle';
import { HeadlessAppLoader, HeadlessAppLoaderDelegate, HeadlessAppLoaderParams } from './HeadlessAppLoader';

interface AppRecord {
  owner: RNHeadlessAppLoader;
  instance?: RNInstance;
  started: boolean;
  destroyed: boolean;
  failure?: Error;
  ready: Promise<void>;
  callbacks: ((success: boolean) => void)[];
  detach?: () => void;
  closing?: Promise<void>;
}

export class RNHeadlessAppLoader implements HeadlessAppLoader {
  private static readonly records = new Map<string, AppRecord>();
  private context?: RnohHeadlessContext;
  private instance?: RNInstance;
  private runtime?: ReactNativeRuntime;
  private unsubscribe?: () => void;
  private begun = false;
  private loaded = false;
  private borrowed = false;
  private get restarting(): boolean {
    return this.runtime?.isReloading ?? false;
  }
  private loading?: Promise<void>;
  private tail: Promise<void> = Promise.resolve();

  private readonly delegate: HeadlessAppLoaderDelegate;
  constructor(delegate: HeadlessAppLoaderDelegate) {
    this.delegate = delegate;
  }

  isAvailable(): boolean {
    return this.delegate.isAvailable();
  }

  get active(): boolean {
    return this.context !== undefined || this.borrowed;
  }

  isRunning(scope: string): boolean {
    const record = RNHeadlessAppLoader.records.get(scope);
    return (
      record !== undefined &&
      !record.owner.restarting &&
      record.started &&
      !record.destroyed &&
      record.failure === undefined &&
      record.closing === undefined
    );
  }

  loadApp(context: common.Context, params: HeadlessAppLoaderParams, alreadyRunning?: () => void, callback?: (success: boolean) => void): void {
    const scope = params?.appScopeKey;
    if (typeof scope !== 'string') throw new ExpoModuleError('ERR_REACT_HOST_SCOPE', 'Params must include an appScopeKey.');

    let record = RNHeadlessAppLoader.records.get(scope);
    if (record !== undefined) {
      if (record.failure !== undefined)
        throw new ExpoModuleError('ERR_REACT_HOST_LOAD', 'Invalidate the failed app scope before retrying its load.', record.failure);
      if (record.closing !== undefined || (record.destroyed && !record.owner.restarting)) {
        throw new ExpoModuleError('ERR_REACT_HOST_SCOPE', 'Invalidate the released app scope before loading it again.');
      }
      if (this.isRunning(scope)) alreadyRunning?.();
      else if (callback !== undefined) record.callbacks.push(callback);

      return;
    }

    record = { owner: this, started: false, destroyed: false, ready: Promise.resolve(), callbacks: callback === undefined ? [] : [callback] };
    RNHeadlessAppLoader.records.set(scope, record);
    const pending = this.loading ?? this.enqueue((): Promise<void> => this.start(context));
    record.ready = pending;
    this.track(pending);
    if (this.instance !== undefined) this.bind(this.instance);
    const current = record;
    pending.catch((error: Error): void => {
      current.failure = error;
      this.notify(current, false);
      if (this.context === undefined && this.instance === undefined) this.remove(scope, current);
    });
  }

  waitForApp(scope: string): Promise<void> {
    const record = RNHeadlessAppLoader.records.get(scope);
    if (record === undefined || record.closing !== undefined || (record.destroyed && !record.owner.restarting)) {
      return Promise.reject(new ExpoModuleError('ERR_REACT_HOST_SCOPE', 'The requested app scope is not available.'));
    }
    return record.owner.runtime?.ready ?? record.ready;
  }

  invalidateApp(scope: string): boolean {
    if (!RNHeadlessAppLoader.records.has(scope)) return false;
    this.invalidateAppAsync(scope).catch((error: Error): void => console.error(`Unable to invalidate the background app: ${String(error)}`));
    return true;
  }

  invalidateAppAsync(scope: string): Promise<void> {
    const record = RNHeadlessAppLoader.records.get(scope);
    if (record === undefined) return Promise.resolve();
    if (record.closing !== undefined) return record.closing;

    const closing = record.owner.enqueue(async (): Promise<void> => {
      const others = Array.from(RNHeadlessAppLoader.records.values()).some((value) => value !== record && value.owner === record.owner);

      if (!others) await record.owner.stop();
      record.owner.remove(scope, record);
    });

    record.closing = closing;
    closing.catch((): void => {
      if (record.closing === closing) record.closing = undefined;
    });

    return closing;
  }

  unload(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      await this.stop();
      for (const item of RNHeadlessAppLoader.records) {
        const scope = item[0];
        const record = item[1];
        if (record.owner === this) this.remove(scope, record);
      }
    });
  }

  private remove(scope: string, record: AppRecord): void {
    if (RNHeadlessAppLoader.records.get(scope) !== record) return;

    record.detach?.();
    RNHeadlessAppLoader.records.delete(scope);
    this.notify(record, false);
  }

  private notify(record: AppRecord, success: boolean): void {
    for (const callback of record.callbacks.splice(0)) {
      try {
        callback(success);
      } catch (error) {
        console.error(`Background app initialization callback failed: ${String(error)}`);
      }
    }
  }

  private bind(instance: RNInstance): void {
    for (const item of RNHeadlessAppLoader.records) {
      const scope = item[0];
      const record = item[1];
      if (record.owner !== this || (record.instance === instance && !record.destroyed)) continue;

      record.detach?.();
      record.instance = instance;
      record.failure = undefined;
      record.started = false;
      record.destroyed = false;
      record.detach = observeRnohDestroy(instance, (): void => {
        record.started = false;
        record.destroyed = true;
        this.loaded = false;
      });

      waitForRnohBundle(instance).then(
        (): void => {
          if (record.instance !== instance || record.destroyed || record.closing !== undefined || RNHeadlessAppLoader.records.get(scope) !== record) return;

          record.started = true;
          this.notify(record, true);
        },
        (): void => {
          if (record.instance === instance && RNHeadlessAppLoader.records.get(scope) === record) this.notify(record, false);
        },
      );
    }
  }

  private track(pending: Promise<void>): void {
    this.loading = pending;
    const settled = (): void => {
      if (this.loading === pending) this.loading = undefined;
    };
    pending.then(settled, settled);
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const pending = this.tail.then(operation);
    this.tail = pending.catch((): void => {});
    return pending;
  }

  private async start(context: common.Context): Promise<void> {
    if (this.loaded && this.instance !== undefined) {
      this.bind(this.instance);
      return;
    }
    if (this.instance !== undefined) await this.stop();

    const existing = this.context === undefined ? this.delegate.getRuntime() : undefined;
    if (existing !== undefined) {
      this.borrowed = true;
      this.observe(existing);
      try {
        await existing.start();
        this.loaded = true;
      } catch (error) {
        await this.stop();
        throw new ExpoModuleError('ERR_REACT_HOST_LOAD', 'The application runtime could not finish loading.', error as Object);
      }
      return;
    }

    const runtime =
      this.context ??
      new RnohHeadlessContext(context, this.delegate.workerScriptUrl, (ability: common.UIAbilityContext): boolean =>
        this.delegate.hasOtherOwner(ability),
      );
    this.context = runtime;
    const core = runtime.coordinator.getRNOHCoreContext();

    try {
      await runtime.ready;

      if (!this.begun) {
        this.begun = true;
        this.delegate.begin(runtime.ability);
      }
      if (this.runtime === undefined) this.observe(this.delegate.createRuntime(core, context));
      runtime.coordinator.onBackground();
      await this.runtime!.start();
      this.loaded = true;
      console.info(`Expo background React runtime loaded: ${this.instance?.getId()}`);
    } catch (error) {
      try {
        await this.stop();
      } catch (failure) {
        console.error(`Unable to release a failed background runtime: ${String(failure)}`);
      }
      throw new ExpoModuleError('ERR_REACT_HOST_LOAD', 'Unable to load the application for background execution.', error as Object);
    }
  }

  private observe(runtime: ReactNativeRuntime): void {
    this.runtime = runtime;
    const observer: ReactRuntimeListener = {
      prepare: async (instance: RNInstance): Promise<void> => {
        this.instance = instance;
        this.bind(instance);
      },
      changed: (instance: RNInstance | undefined): void => {
        this.instance = instance;
        this.loaded = instance !== undefined;

        if (instance !== undefined) this.bind(instance);
        else {
          for (const record of RNHeadlessAppLoader.records.values()) {
            if (record.owner !== this) continue;

            record.detach?.();
            record.detach = undefined;
            record.instance = undefined;
            record.started = false;
          }
        }
      },
      failed: (error: Error): void => console.error(`Background runtime operation failed: ${String(error)}`),
    };
    this.unsubscribe = runtime.subscribe(observer);
  }

  private async stop(): Promise<void> {
    this.loaded = false;
    if (this.borrowed) {
      this.unsubscribe?.();
      this.unsubscribe = undefined;
      this.runtime = undefined;
      this.instance = undefined;
      this.borrowed = false;
      return;
    }
    const context = this.context;
    if (context === undefined) return;

    const instance = this.instance;
    await this.runtime?.destroy();
    await context.destroy();
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    this.runtime = undefined;
    this.instance = undefined;

    try {
      if (this.begun) this.delegate.end(context.ability);
    } finally {
      this.begun = false;
      try {
        context.close();
      } finally {
        this.context = undefined;
      }
    }
    if (instance !== undefined) console.info(`Expo background React runtime released: ${instance.getId()}`);
  }
}

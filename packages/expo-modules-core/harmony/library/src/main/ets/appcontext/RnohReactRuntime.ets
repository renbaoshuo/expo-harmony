/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { JSBundleProvider, JsBundle, RNInstance, RNInstanceOptions, RNOHCoreContext } from '@rnoh/react-native-openharmony';
import { ExpoModuleError } from '../modules/ExpoModuleError';
import { ReactNativeRuntime, ReactRuntimeListener } from '../interfaces/ReactNativeRuntime';
import { ExpoReloadRegistry } from './ExpoReloadRegistry';
import { RnohContextLifecycle } from './RnohContextLifecycle';
import { hasLoadedRnohBundle, installRnohBundleBarrier, waitForRnohBundle } from './RnohBundle';

export interface RnohReactRuntimeOptions {
  options?: RNInstanceOptions | (() => RNInstanceOptions);
  instance?: RNInstance;
  replace?: (reason: string) => Promise<RNInstance>;
  bundle?: () => JSBundleProvider;
  prepare(instance: RNInstance): Promise<void>;
}

interface Listener {
  observer: ReactRuntimeListener;
  instance?: RNInstance;
  preparation?: Promise<void>;
}

// RNApp needs a provider URL to display an already loaded unmanaged instance.
class LoadedBundle extends JSBundleProvider {
  private readonly instance: RNInstance;
  constructor(instance: RNInstance) {
    super();
    this.instance = instance;
  }
  getURL(): string {
    return this.instance.getInitialBundleUrl() ?? '';
  }
  getAppKeys(): string[] {
    return [];
  }
  async getBundle(): Promise<JsBundle> {
    throw new ExpoModuleError('ERR_REACT_HOST_BUNDLE', 'The root cannot load a bundle on behalf of its runtime owner.');
  }
}

export class RnohReactRuntime implements ReactNativeRuntime {
  private readonly lifetime: RnohContextLifecycle;
  private readonly listeners = new Set<Listener>();
  private current?: RNInstance;
  private provider?: JSBundleProvider;
  private sourceProvider?: JSBundleProvider;
  private loaded = false;
  private closing = false;
  private replacing = false;
  private pending: Promise<void> = Promise.resolve();
  private tail: Promise<void> = Promise.resolve();
  private unregister?: () => void;
  private detach?: () => void;
  private tools?: () => void;

  readonly core: RNOHCoreContext;
  private readonly options: RnohReactRuntimeOptions;

  constructor(core: RNOHCoreContext, options: RnohReactRuntimeOptions) {
    this.core = core;
    this.options = options;
    if ((options.instance === undefined) === (options.options === undefined)) {
      throw new ExpoModuleError('ERR_REACT_HOST_CONFIG', 'A runtime requires either creation options or an externally owned instance.');
    }
    if (options.options !== undefined && options.replace !== undefined) {
      throw new ExpoModuleError('ERR_RELOAD_HOST_REPLACEMENT', 'A replacement callback requires an externally owned instance.');
    }
    this.current = options.instance;
    this.lifetime = RnohContextLifecycle.install(core);
    if (this.current !== undefined && !this.lifetime.owns(this.current)) {
      throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'The supplied instance is not registered with this RNOH coordinator.');
    }
    if (options.options !== undefined || options.replace !== undefined) {
      this.tools = core.devToolsController.eventEmitter.subscribe('RELOAD', (): void => {
        this.reload('React Native developer reload').catch((): void => {});
      });
    }
  }

  get ready(): Promise<void> {
    return this.pending;
  }
  get isReloading(): boolean {
    return this.replacing;
  }
  get instance(): RNInstance | undefined {
    return this.current;
  }
  get bundle(): JSBundleProvider | undefined {
    return this.provider;
  }
  get sourceBundle(): JSBundleProvider | undefined {
    return this.current === undefined ? undefined : this.sourceProvider;
  }

  subscribe(observer: ReactRuntimeListener): () => void {
    const listener: Listener = { observer };
    this.listeners.add(listener);
    if (this.loaded && this.current !== undefined) {
      const instance = this.current;
      this.prepare(listener, instance).then(
        (): void => {
          if (this.listeners.has(listener) && this.loaded && this.current === instance) observer.changed(instance);
        },
        (error: Error): void => {
          if (this.listeners.has(listener)) observer.failed(error);
        },
      );
    }
    return (): void => {
      this.listeners.delete(listener);
    };
  }

  start(): Promise<void> {
    return this.enqueue((): Promise<void> => this.load());
  }

  reload(reason: string): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      const previous = this.current;
      if (this.options.options === undefined && this.options.replace === undefined) {
        throw new ExpoModuleError('ERR_RELOAD_UNAVAILABLE', 'The external runtime owner did not provide a replacement operation.');
      }

      const wasLoaded = this.loaded;
      this.replacing = true;
      this.loaded = false;

      try {
        this.changed(undefined);

        if (this.options.replace !== undefined) {
          const next = await this.options.replace(reason);
          // RNOH may keep the same ID on reload for the debugger connection.
          if (previous !== undefined && (next === previous || (next.getId() === previous.getId() && this.lifetime.owns(previous)))) {
            throw new ExpoModuleError('ERR_RELOAD_HOST_REPLACEMENT', 'The external owner must provide a new RNInstance.');
          }
          if (!this.lifetime.owns(next)) throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'The replacement belongs to another RNOH coordinator.');

          this.unbind();
          this.current = next;
        } else {
          if (previous !== undefined) await this.lifetime.destroyInstance(previous);
          this.unbind();
          this.current = undefined;
        }

        this.core.devToolsController.dismissRNOHErrorDialog();
        await this.load();
      } catch (error) {
        if (previous !== undefined && this.current === previous && this.lifetime.owns(previous)) {
          this.loaded = wasLoaded;
          if (wasLoaded) this.changed(previous);
        } else if (this.current === undefined || this.current === previous) {
          this.unbind();
          this.current = undefined;
          this.provider = undefined;
        }

        if (error instanceof Error) throw error;
        throw new Error(String(error));
      } finally {
        this.replacing = false;
      }
    });
  }

  suspend(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      if (this.options.options === undefined) {
        throw new ExpoModuleError('ERR_REACT_HOST_OWNER', 'This runtime wraps an externally owned React instance and cannot suspend it.');
      }

      const previous = this.current;
      const wasLoaded = this.loaded;
      this.replacing = true;
      this.loaded = false;

      try {
        this.changed(undefined);
        if (this.current !== undefined) await this.lifetime.destroyInstance(this.current);
        this.unbind();
        this.current = undefined;
        this.provider = undefined;
      } catch (error) {
        if (previous !== undefined && this.lifetime.owns(previous)) {
          this.loaded = wasLoaded;
          if (wasLoaded) this.changed(previous);
        } else {
          this.unbind();
          this.current = undefined;
          this.provider = undefined;
        }

        throw new ExpoModuleError(
          error instanceof ExpoModuleError ? error.code : 'ERR_REACT_HOST_RUNTIME',
          error instanceof Error ? error.message : String(error),
          error as Object,
        );
      } finally {
        this.replacing = false;
      }
    });
  }

  destroy(): Promise<void> {
    if (this.options.options === undefined) {
      return Promise.reject(new ExpoModuleError('ERR_REACT_HOST_OWNER', 'Only the external owner may destroy this React instance.'));
    }
    this.closing = true;
    return this.enqueue(async (): Promise<void> => {
      this.changed(undefined);
      if (this.current !== undefined) await this.lifetime.destroyInstance(this.current);
      this.current = undefined;
      this.loaded = false;
      this.unbind();
      this.tools?.();
      this.tools = undefined;
    }, true);
  }

  private enqueue(operation: () => Promise<void>, closing: boolean = false): Promise<void> {
    const pending = this.tail.then(async (): Promise<void> => {
      if (this.closing && !closing) throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'The runtime owner is being destroyed.');
      try {
        await operation();
      } catch (error) {
        const failure = error instanceof Error ? error : new ExpoModuleError('ERR_REACT_HOST_OPERATION', String(error));
        this.failed(failure);
        throw new ExpoModuleError(error instanceof ExpoModuleError ? error.code : 'ERR_REACT_HOST_OPERATION', failure.message, error as Object);
      }
    });
    this.pending = pending;
    this.tail = pending.catch((): void => {});
    return pending;
  }

  private async load(): Promise<void> {
    if (this.loaded) return;

    this.sourceProvider = undefined;
    if (this.current === undefined) {
      if (this.options.options === undefined) throw new ExpoModuleError('ERR_REACT_HOST_OWNER', 'The external runtime is no longer available.');
      // A launcher may select a different runtime between instance creations.
      const options = typeof this.options.options === 'function' ? this.options.options() : this.options.options;
      this.current = await this.core.createAndRegisterRNInstance(options);
    }

    const instance = this.current;
    installRnohBundleBarrier(instance);
    if (this.detach === undefined) this.bind(instance);
    await this.options.prepare(instance);
    for (const listener of this.listeners) await this.prepare(listener, instance);

    const url = instance.getInitialBundleUrl();
    const running = url !== undefined && instance.getBundleExecutionStatus(url) === 'RUNNING';
    if (!hasLoadedRnohBundle(instance) && !running) {
      this.provider = this.options.bundle?.();
      this.sourceProvider = this.provider;
      if (this.provider !== undefined) await instance.runJSBundle(this.provider);
    }
    await waitForRnohBundle(instance);

    // Roots can join while the bundle is running; prepare them before publishing this instance.
    for (const listener of this.listeners) await this.prepare(listener, instance);
    if (this.current !== instance || this.closing)
      throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'The runtime was destroyed while its bundle was loading.');

    this.provider = new LoadedBundle(instance);
    this.loaded = true;
    this.changed(instance);
  }

  private bind(instance: RNInstance): void {
    if (this.options.options !== undefined || this.options.replace !== undefined) {
      this.unregister = ExpoReloadRegistry.register(instance.getId(), (reason: string): Promise<void> => {
        if (this.current !== instance) throw new ExpoModuleError('ERR_RELOAD_UNAVAILABLE', 'The runtime owning this reload has been replaced.');
        return this.reload(reason);
      });
    }
    this.detach = this.lifetime.observeDestroy(instance, (): void => {
      if (this.current !== instance) return;

      this.current = undefined;
      this.loaded = false;
      if (!this.replacing) {
        this.changed(undefined);
        this.closing = true;
        this.tools?.();
        this.tools = undefined;
        this.unbind();
      }
    });
  }

  private unbind(): void {
    this.unregister?.();
    this.unregister = undefined;
    this.detach?.();
    this.detach = undefined;
  }

  private prepare(listener: Listener, instance: RNInstance): Promise<void> {
    if (!this.listeners.has(listener)) return Promise.resolve();
    if (listener.instance !== instance) {
      listener.instance = instance;
      listener.preparation = Promise.resolve().then(() => listener.observer.prepare(instance));
    }
    return listener.preparation!;
  }

  private changed(instance: RNInstance | undefined): void {
    for (const listener of Array.from(this.listeners)) {
      if (!this.listeners.has(listener)) continue;
      try {
        listener.observer.changed(instance);
      } catch (error) {
        console.error(`React root notification failed: ${String(error)}`);
      }
    }
  }

  private failed(error: Error): void {
    for (const listener of Array.from(this.listeners)) {
      if (!this.listeners.has(listener)) continue;
      try {
        listener.observer.failed(error);
      } catch (failure) {
        console.error(`React root error notification failed: ${String(failure)}`);
      }
    }
  }
}

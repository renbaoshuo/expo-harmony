/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import { JSBundleProvider, RNInstance } from '@rnoh/react-native-openharmony';
import {
  ExpoModuleError,
  ReactNativeHost,
  ReactNativeHostHandler,
  ReactNativeHostHandlerRegistration,
  ModulePriorities,
  ReactRuntimeBinding,
  ReactRuntimeContext,
  ReactRuntimeBindingRegistration,
  waitForRnohInitialization,
  waitForRnohBundle,
  hasLoadedRnohBundle,
  reportRnohBundleError,
  observeRnohDestroy,
} from '@expo-harmony/expo-modules-core';
import { ExpoRuntimeErrors } from './runtime/ExpoRuntimeErrors';

export class ExpoReactHostDelegate {
  private readonly registrations: ReactNativeHostHandlerRegistration[];
  private handlers: ReactNativeHostHandler[] = [];
  private bindings: ReactRuntimeBinding[] = [];
  private readonly registrationsForBindings: ReactRuntimeBindingRegistration[];
  private readonly notified: WeakSet<Object> = new WeakSet();
  private readonly managers: WeakSet<Object> = new WeakSet();
  private initialized: boolean = false;

  constructor(registrations: ReactNativeHostHandlerRegistration[], bindings: ReactRuntimeBindingRegistration[]) {
    const ids = new Set<string>();
    for (const registration of registrations) {
      if (registration.registrationId.length === 0 || ids.has(registration.registrationId)) {
        throw new ExpoModuleError('ERR_REACT_HOST_HANDLER', `Invalid or duplicate React host handler '${registration.registrationId}'.`);
      }
      ids.add(registration.registrationId);
    }

    const ordered: ReactNativeHostHandlerRegistration[] = [];
    registrations.forEach((registration: ReactNativeHostHandlerRegistration): void => {
      const priority = ModulePriorities.get(registration.packageName);
      let index = ordered.length;
      while (index > 0 && ModulePriorities.get(ordered[index - 1].packageName) < priority) index -= 1;
      ordered.splice(index, 0, registration);
    });
    this.registrations = ordered;
    const idsForBindings = new Set<string>();
    for (const binding of bindings) {
      if (binding.registrationId.length === 0 || idsForBindings.has(binding.registrationId)) {
        throw new ExpoModuleError('ERR_REACT_HOST_BIND', `Invalid or duplicate runtime binding '${binding.registrationId}'.`);
      }
      idsForBindings.add(binding.registrationId);
    }
    this.registrationsForBindings = bindings
      .slice()
      .sort((left, right) => ModulePriorities.get(right.packageName) - ModulePriorities.get(left.packageName));
  }

  initialize(context: common.Context, host: ReactNativeHost, debug: boolean): void {
    if (this.initialized) return;

    const handlers = this.registrations.map(
      (registration: ReactNativeHostHandlerRegistration): ReactNativeHostHandler => registration.create(context),
    );
    for (const handler of handlers) handler.onWillCreateReactInstance?.(debug);
    this.bindings = this.registrationsForBindings.map(
      (registration: ReactRuntimeBindingRegistration): ReactRuntimeBinding => registration.create(context),
    );
    this.handlers = handlers;
    this.initialized = true;

    try {
      for (const handler of handlers) handler.onDidCreateReactHost?.(context, host);
    } catch (error) {
      this.initialized = false;
      this.handlers = [];
      this.bindings = [];
      throw new ExpoModuleError('ERR_REACT_HOST_CONFIG', 'Unable to initialize React host handlers.', error as Object);
    }
  }

  useDeveloperSupport(fallback: boolean): boolean {
    this.requireInitialized();
    for (const handler of this.handlers) {
      const value = handler.getUseDeveloperSupport?.();
      if (value !== undefined) return value;
    }
    return fallback;
  }

  async getJSBundleFile(debug: boolean): Promise<string | undefined> {
    this.requireInitialized();
    for (const handler of this.handlers) {
      const path = await handler.getJSBundleFile?.(debug);
      if (path !== undefined) return path;
    }
    return undefined;
  }

  async getJSBundleProvider(debug: boolean): Promise<JSBundleProvider | undefined> {
    this.requireInitialized();
    for (const handler of this.handlers) {
      const provider = await handler.getJSBundleProvider?.(debug);
      if (provider !== undefined) return provider;
    }
    return undefined;
  }

  async getBundleAssetName(debug: boolean): Promise<string | undefined> {
    this.requireInitialized();
    for (const handler of this.handlers) {
      const name = await handler.getBundleAssetName?.(debug);
      if (name !== undefined) return name;
    }
    return undefined;
  }

  async prepare(context: ReactRuntimeContext): Promise<() => void> {
    this.requireInitialized();
    const instance = context.instance;
    const debug = this.useDeveloperSupport(context.core.isDebugModeEnabled);
    const subscriptions: (() => void)[] = [];
    let active = true;
    let destroyed = false;
    const cleanup = (): void => {
      if (!active) return;

      active = false;
      for (const unsubscribe of subscriptions.splice(0).reverse()) {
        try {
          unsubscribe();
        } catch (error) {
          console.error(`Unable to detach a React host handler: ${String(error)}`);
        }
      }
    };

    try {
      subscriptions.push(
        observeRnohDestroy(instance, (): void => {
          destroyed = true;
        }),
      );
      if (destroyed) throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'Cannot bind a destroyed React instance.');

      const manager = context.core.devToolsController;
      if (!this.managers.has(manager)) {
        for (const handler of this.handlers) handler.onDidCreateDevSupportManager?.(manager);
        this.managers.add(manager);
      }
      for (const binding of this.bindings) {
        const detach = await binding.bind(context);
        if (typeof detach === 'function') subscriptions.push(detach);
        if (destroyed) throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'The React instance was destroyed while binding its host.');
      }

      const initialized = (): void => {
        if (!active || destroyed || this.notified.has(instance)) return;

        this.notified.add(instance);
        for (const handler of this.handlers) {
          try {
            handler.onDidCreateReactInstance?.(debug, instance);
          } catch (error) {
            console.error(`React instance notification failed: ${String(error)}`);
          }
        }
      };
      // RNOH publishes the first bundle's lifecycle event after evaluation succeeds.
      waitForRnohInitialization(instance).then(initialized, (): void => {});

      const handlers = this.handlers.filter((handler: ReactNativeHostHandler): boolean => handler.onReactInstanceException !== undefined);
      const report = (error: Error): void => {
        if (!active || destroyed) return;
        for (const handler of handlers) {
          try {
            handler.onReactInstanceException?.(debug, instance, error);
          } catch (failure) {
            console.error(`React host error handler failed: ${String(failure)}`);
          }
        }
      };
      waitForRnohBundle(instance).catch(report);
      subscriptions.push(
        await ExpoRuntimeErrors.observe(instance, (error: Error): void => {
          reportRnohBundleError(instance, error);
          if (hasLoadedRnohBundle(instance)) report(error);
        }),
      );

      return cleanup;
    } catch (error) {
      cleanup();
      throw new ExpoModuleError('ERR_REACT_HOST_BIND', 'Unable to bind React host handlers.', error as Object);
    }
  }

  private requireInitialized(): void {
    if (!this.initialized) throw new ExpoModuleError('ERR_REACT_HOST_CONFIG', 'Initialize the Expo React host before using it.');
  }
}

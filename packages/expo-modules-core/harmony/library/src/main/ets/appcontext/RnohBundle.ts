/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { RNInstance, RNOHError } from '@rnoh/react-native-openharmony/ts';
import { observeRnohDestroy } from './RnohDestroyAdapter';

type BundleProvider = { getURL(): string; };

function sameBundle(left: BundleProvider, right: BundleProvider): boolean {
  if (left === right) return true;

  try {
    const leftUrl = left.getURL();
    const rightUrl = right.getURL();

    return typeof leftUrl === 'string' && leftUrl.length > 0 && leftUrl === rightUrl;
  } catch (_) {
    return false;
  }
}

interface BundleCompletion {
  completion: Promise<void>;
  loaded: boolean;
  failed: boolean;
  fail(error: Error): void;
}

const bundles = new WeakMap<RNInstance, BundleCompletion>();

class RnohBundleError extends Error {
  constructor(error: RNOHError) {
    super(error.getMessage());

    const stack = error.getStack()?.toString();
    if (stack) this.stack = `${this.message}\n${stack}`;
  }
}

export function waitForRnohBundle(instance: RNInstance): Promise<void> {
  return bundles.get(instance)?.completion ?? Promise.reject(new Error('Install the React bundle lifecycle before loading the runtime.'));
}

export function waitForRnohInitialization(instance: RNInstance): Promise<void> {
  return waitForRnohBundle(instance);
}

export function hasLoadedRnohBundle(instance: RNInstance): boolean {
  return bundles.get(instance)?.loaded === true;
}

export function hasFailedRnohBundle(instance: RNInstance): boolean {
  return bundles.get(instance)?.failed === true;
}

export function reportRnohBundleError(instance: RNInstance, error: Error): void {
  bundles.get(instance)?.fail(error);
}

export function installRnohBundleBarrier(instance: RNInstance): void {
  if (bundles.has(instance)) return;

  let finish: () => void = () => {};
  let reject: (error: Error) => void = () => {};
  const completion = new Promise<void>((resolve, failure) => {
    finish = resolve;
    reject = failure;
  });

  const fail = (error: Error): void => {
    if (!bundle.loaded && !bundle.failed) {
      bundle.failed = true;
      reject(error);
    }
  };

  const bundle: BundleCompletion = { completion, loaded: false, failed: false, fail };
  bundles.set(instance, bundle);

  const loaded = (): void => {
    if (bundle.failed) return;

    bundle.loaded = true;
    finish();
  };

  // RNOH 0.86 emits this after the app bundle, separately from its resource bootstrap.
  const stopLoaded = instance.subscribeToLifecycleEvents('JS_BUNDLE_EXECUTION_FINISH', loaded);
  let destroyed = false;
  observeRnohDestroy(instance, () => {
    destroyed = true;
    fail(new Error('The React runtime was destroyed before its first bundle completed.'));
  });
  completion.then(stopLoaded, stopLoaded);

  const url = instance.getInitialBundleUrl();
  const status = url === undefined ? undefined : instance.getBundleExecutionStatus(url);
  if (status === 'DONE') loaded();
  if (url !== undefined && status === 'RUNNING') {
    // An externally owned instance can already have started its first bundle.
    const stop = instance.subscribeToRNOHErrors(error => {
      if (instance.getBundleExecutionStatus(url) === undefined) fail(new RnohBundleError(error));
    });
    completion.then(stop, stop);
  }

  const run = instance.runJSBundle.bind(instance);
  let tail: Promise<void> = Promise.resolve();
  let first: { provider: BundleProvider; promise: Promise<void> } | undefined;
  instance.runJSBundle = provider => {
    if (first !== undefined && sameBundle(first.provider, provider)) {
      return first.promise;
    }

    const pending = tail.then(async () => {
      if (destroyed) throw new Error('Cannot load a bundle in a destroyed React runtime.');
      if (bundle.failed) return completion;

      let executed = false;
      let failure: RNOHError | undefined;
      const stopExecution = instance.subscribeToLifecycleEvents('JS_BUNDLE_EXECUTION_FINISH', () => { executed = true; });
      const stopFailure = instance.subscribeToRNOHErrors(error => { failure = error; });

      const execute = async (): Promise<void> => {
        // A RNOH error can occur during a successful bundle. Check execution after RNOH settles.
        await run(provider);

        if (executed) return;
        if (failure !== undefined) throw new RnohBundleError(failure);
        throw new Error('RNOH finished loading without executing the JavaScript bundle.');
      };

      try {
        await Promise.all([execute(), completion]);
      } catch (error) {
        if (bundle.loaded) return Promise.reject(error);

        fail(error instanceof Error ? error : new Error(String(error)));

        return completion;
      } finally {
        stopExecution();
        stopFailure();
      }
    });

    if (!bundle.loaded && !bundle.failed && first === undefined) {
      first = { provider, promise: pending };
      const clear = (): void => {
        if (first?.promise === pending) first = undefined;
      };
      pending.then(clear, clear);
    }

    tail = pending.catch(() => {});

    return pending;
  };
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoSharedObject } from '@expo-harmony/expo-modules-core';
import { ExpoFetchError } from './ExpoFetchError';
import { FetchInit } from './FetchTypes';
import { ExpoFetchRuntime } from './FetchRuntime';
import { NativeResponse } from './NativeResponse';
import { errorMessage } from './FetchUtils';

export class NativeRequest extends ExpoSharedObject {
  private readonly runtime: ExpoFetchRuntime;
  private readonly response: NativeResponse;
  private readonly id: string;
  private cancelled: boolean = false;
  private started: boolean = false;

  constructor(context: ExpoModuleContext, runtime: ExpoFetchRuntime, response: NativeResponse) {
    super(context);
    this.runtime = runtime;
    this.response = response;
    this.id = runtime.allocateRequestId();
    response.attach(this.id);
  }

  async start(inputUrl: string, init: FetchInit, body: Uint8Array | null): Promise<void> {
    if (this.started) throw new ExpoFetchError('ERR_FETCH_REQUEST', 'The fetch request has already been started.');

    this.started = true;
    try {
      if (this.cancelled) throw new ExpoFetchError('ERR_FETCH_REQUEST_CANCELED', 'Fetch request has been canceled');

      const result = await this.runtime.start(this.id, inputUrl, init, body);
      if (this.cancelled) {
        this.runtime.discard(this.id);
        throw new ExpoFetchError('ERR_FETCH_REQUEST_CANCELED', 'Fetch request has been canceled');
      }

      this.response.complete(result);
      this.response.watchCompletion();
    } catch (error) {
      this.response.watchCompletion();
      throw new ExpoFetchError(
        error instanceof ExpoFetchError ? error.code : 'ERR_FETCH_UNKNOWN',
        error instanceof ExpoFetchError ? error.message : errorMessage(error as Object),
        error instanceof ExpoFetchError ? error.cause : (error as Object),
      );
    }
  }

  cancel(): void {
    if (this.cancelled) return;
    this.cancelled = true;
    this.runtime.cancel(this.id, new ExpoFetchError('ERR_FETCH_REQUEST_CANCELED', 'Fetch request has been canceled'));
  }
}

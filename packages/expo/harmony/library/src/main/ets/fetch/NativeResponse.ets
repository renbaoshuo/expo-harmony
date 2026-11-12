/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoSharedObject } from '@expo-harmony/expo-modules-core';
import { ExpoFetchError } from './ExpoFetchError';
import { FetchResult } from './FetchTypes';
import { ExpoFetchRuntime } from './FetchRuntime';
import { errorMessage, formatError } from './FetchUtils';
import { statusText } from './FetchStatus';

export class NativeResponse extends ExpoSharedObject {
  private readonly runtime: ExpoFetchRuntime;
  private requestId?: string;
  private responseStatus: number = -1;
  private responseStatusText: string = '';
  private responseUrl: string = '';
  private responseRedirected: boolean = false;
  private responseHeaders: string[][] = [];
  private used: boolean = false;
  private streamingCancelled: boolean = false;
  private finalized: boolean = false;
  private released: boolean = false;

  constructor(context: ExpoModuleContext, runtime: ExpoFetchRuntime) {
    super(context);
    this.runtime = runtime;
  }

  attach(id: string): void {
    if (this.requestId !== undefined) {
      throw new ExpoFetchError('ERR_FETCH_REQUEST', 'The response is already attached to a request.');
    }
    this.requestId = id;
  }

  complete(result: FetchResult): void {
    this.responseStatus = result.status;
    this.responseStatusText = result.statusText;
    this.responseUrl = result.url;
    this.responseRedirected = result.redirected;
    this.responseHeaders = result.headers;
  }

  watchCompletion(): void {
    const id = this.requireRequestId();
    this.runtime
      .waitForCompletion(id)
      .then((): void => this.notifyUnusedCompletion())
      .catch((_error: Object): void => this.notifyUnusedCompletion());
  }

  async startStreaming(): Promise<Uint8Array | null> {
    this.beginBodyUse();
    try {
      const packet = await this.runtime.startStreaming(this.requireRequestId());
      if (this.streamingCancelled || this.released) {
        this.finalize();
        return null;
      }
      if (packet.error !== null) {
        this.emitStreamFailure(packet.error);
        return null;
      }
      if (packet.completed) {
        this.finalize();
        return packet.data;
      }

      if (packet.data.byteLength > 0) {
        this.sendEvent('didReceiveResponseData', packet.data);
      }
      this.pumpStream().catch((error: Object): void => {
        this.emitStreamFailure(
          new ExpoFetchError(
            error instanceof ExpoFetchError ? error.code : 'ERR_FETCH_UNKNOWN',
            error instanceof ExpoFetchError ? error.message : errorMessage(error as Object),
            error instanceof ExpoFetchError ? error.cause : (error as Object),
          ),
        );
      });

      return null;
    } catch (error) {
      this.emitStreamFailure(
        new ExpoFetchError(
          error instanceof ExpoFetchError ? error.code : 'ERR_FETCH_UNKNOWN',
          error instanceof ExpoFetchError ? error.message : errorMessage(error as Object),
          error instanceof ExpoFetchError ? error.cause : (error as Object),
        ),
      );
      return null;
    }
  }

  cancelStreaming(_reason: string): void {
    if (this.streamingCancelled) return;

    this.streamingCancelled = true;
    const id = this.requestId;
    if (id !== undefined) this.runtime.cancelStreaming(id);
    this.finalize();
  }

  async arrayBuffer(): Promise<ArrayBuffer> {
    this.beginBodyUse();
    try {
      return await this.runtime.consumeArrayBuffer(this.requireRequestId());
    } finally {
      this.finalize();
    }
  }

  async text(): Promise<string> {
    this.beginBodyUse();
    try {
      return await this.runtime.consumeText(this.requireRequestId());
    } finally {
      this.finalize();
    }
  }

  bodyUsed(): boolean {
    return this.used;
  }

  rawHeaders(): string[][] {
    return this.responseHeaders;
  }

  status(): number {
    return this.responseStatus;
  }

  statusText(): string {
    return this.responseStatusText;
  }

  url(): string {
    return this.responseUrl;
  }

  redirected(): boolean {
    return this.responseRedirected;
  }

  override sharedObjectWillRelease(): void {
    if (this.released) return;

    this.released = true;
    const id = this.requestId;
    if (id !== undefined) this.runtime.discard(id);
  }

  private beginBodyUse(): void {
    if (this.used) {
      throw new ExpoFetchError('ERR_FETCH_BODY_USED', 'The response body has already been consumed.');
    }
    this.used = true;
  }

  private async pumpStream(): Promise<void> {
    while (!this.streamingCancelled && !this.released) {
      const packet = await this.runtime.readChunk(this.requireRequestId());
      if (this.streamingCancelled || this.released) {
        this.finalize();
        return;
      }
      if (packet.error !== null) {
        this.emitStreamFailure(packet.error);
        return;
      }
      if (packet.done) {
        this.sendEvent('didComplete');
        this.finalize();
        return;
      }

      if (packet.data.byteLength > 0) {
        this.sendEvent('didReceiveResponseData', packet.data);
      }
    }
    this.finalize();
  }

  private notifyUnusedCompletion(): void {
    if (!this.used) this.finalize();
  }

  private emitStreamFailure(error: ExpoFetchError): void {
    if (this.streamingCancelled || this.released) return;
    this.sendEvent('didFailWithError', formatError(error));
    this.finalize();
  }

  private finalize(): void {
    if (this.finalized || this.released) return;
    this.finalized = true;
    this.sendEvent('readyForJSFinalization');
  }

  private requireRequestId(): string {
    if (this.requestId === undefined) {
      throw new ExpoFetchError('ERR_FETCH_REQUEST', 'The response is not attached to a request.');
    }
    return this.requestId;
  }
}

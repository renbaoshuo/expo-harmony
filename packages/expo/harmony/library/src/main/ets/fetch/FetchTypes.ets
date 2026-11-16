/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFetchError } from './ExpoFetchError';
import { statusText } from './FetchStatus';

export const EMPTY_BYTES: Uint8Array = new Uint8Array(0);

export class FetchInit {
  credentials: string = 'include';
  headers: string[][] = [];
  method: string = 'GET';
  redirect: string = 'follow';
}

export class FetchResult {
  status: number;
  statusText: string;
  url: string;
  redirected: boolean;
  headers: string[][];

  constructor(status: number, urlValue: string, redirected: boolean, headers: string[][], text: string | null = null) {
    this.status = status;
    this.statusText = text ?? statusText(status);
    this.url = urlValue;
    this.redirected = redirected;
    this.headers = headers;
  }
}

export class StreamPacket {
  data: Uint8Array;
  done: boolean;
  error: ExpoFetchError | null;

  constructor(data: Uint8Array, done: boolean, error: ExpoFetchError | null = null) {
    this.data = data;
    this.done = done;
    this.error = error;
  }
}

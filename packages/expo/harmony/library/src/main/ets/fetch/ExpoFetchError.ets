/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError } from '@expo-harmony/expo-modules-core';

export const FETCH_BLOB_MODULE_UNAVAILABLE_MESSAGE =
  "Unable to store the response body as a blob because React Native's BlobModule is not available. " +
  'Make sure your app includes the React Native blob support or read the body with arrayBuffer() instead';

export class ExpoFetchError extends ExpoModuleError {
  constructor(code: string, message: string, cause?: Object) {
    super(code, message, cause);
    this.name = 'ExpoFetchError';
  }
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoBackgroundTask, ExpoBackgroundTaskContext, ExpoModuleContext } from '@expo-harmony/expo-modules-core';
import { BlobTurboModule } from '@rnoh/react-native-openharmony/src/main/ets/RNOHCorePackage/turboModules/Blob/BlobTurboModule';
import { collections } from '@kit.ArkTS';
import { ExpoFetchError, FETCH_BLOB_MODULE_UNAVAILABLE_MESSAGE } from './ExpoFetchError';
import { errorMessage } from './FetchUtils';
import { storeBlob } from './FetchBlobStore';

@Sendable
class BlobDataResult {
  id: string | undefined;
  error: string | undefined;
  code: string | undefined;

  constructor(id?: string, error?: string, code?: string) {
    this.id = id;
    this.error = error;
    this.code = code;
  }
}

@Sendable
class StoreBlobTask implements ExpoBackgroundTask<collections.Uint8Array, BlobDataResult> {
  run(context: ExpoBackgroundTaskContext, data: collections.Uint8Array): BlobDataResult {
    // RNOH's worker task protocol has no error reply. Always return a result,
    // so an unavailable module or allocation failure cannot leave JS waiting.
    try {
      const blob = context.getTurboModule<BlobTurboModule | undefined>(BlobTurboModule.NAME);
      if (blob === undefined || typeof blob.createFromParts !== 'function') {
        return new BlobDataResult(undefined, FETCH_BLOB_MODULE_UNAVAILABLE_MESSAGE, 'ERR_FETCH_BLOB_MODULE_UNAVAILABLE');
      }

      const bytes = new Uint8Array(data.length);
      bytes.set(data);
      return new BlobDataResult(storeBlob(blob, bytes));
    } catch (error) {
      return new BlobDataResult(undefined, errorMessage(error as Object), 'ERR_FETCH_BLOB_STORE');
    }
  }
}

export async function createBlobData(context: ExpoModuleContext, data: Uint8Array): Promise<string> {
  // RNOH registers AnyThread modules on the UI thread only when no worker exists.
  const blob = context.getReactNativeModule<BlobTurboModule>(BlobTurboModule.NAME);
  if (blob !== undefined) {
    try {
      return storeBlob(blob, data);
    } catch (error) {
      throw new ExpoFetchError('ERR_FETCH_BLOB_STORE', errorMessage(error as Object), error as Object);
    }
  }

  const bytes = new collections.Uint8Array(data);
  const result = await context.runInBackground<collections.Uint8Array, BlobDataResult, StoreBlobTask>(new StoreBlobTask(), bytes);
  if (result.id === undefined) {
    throw new ExpoFetchError(result.code ?? 'ERR_FETCH_BLOB_STORE', result.error ?? 'Unable to store the response body as a blob.');
  }

  return result.id;
}

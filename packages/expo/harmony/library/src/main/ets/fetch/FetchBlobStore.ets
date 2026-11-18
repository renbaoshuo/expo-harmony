/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { BlobTurboModule } from '@rnoh/react-native-openharmony/src/main/ets/RNOHCorePackage/turboModules/Blob/BlobTurboModule';
import util from '@ohos.util';

export function storeBlob(blob: BlobTurboModule, data: Uint8Array): string {
  const id = util.generateRandomUUID();
  let stored = false;

  try {
    // A NUL part reserves a byte per character in the RNOH registry buffer.
    blob.createFromParts(data.byteLength === 0 ? [] : [{ type: 'string', data: '\0'.repeat(data.byteLength) }], id);
    const buffer = blob.findByMetaData({ blobId: id, offset: 0, size: data.byteLength });

    if (buffer === null || buffer.byteLength !== data.byteLength) {
      throw new Error('React Native could not allocate the response blob.');
    }

    new Uint8Array(buffer).set(data);
    stored = true;

    return id;
  } finally {
    if (!stored) blob.release(id);
  }
}

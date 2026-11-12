/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Blob as ExpoBlob } from 'expo-blob';

export * from 'expo-blob';

const DEFAULT_CHUNK_SIZE = 64 * 1024;

export class Blob extends ExpoBlob {
  override slice(start?: number, end?: number, contentType?: string): Blob {
    const slice = super.slice(start, end, contentType);
    Object.setPrototypeOf(slice, Blob.prototype);
    return slice;
  }

  override stream(): ReadableStream {
    const empty = this.size === 0;
    let loadBytes: (() => Promise<Uint8Array>) | undefined = empty ? undefined : this.bytes.bind(this);
    let bytes: Uint8Array | undefined;
    let offset = 0;

    return new ReadableStream({
      type: 'bytes',
      start(controller) {
        if (empty) controller.close();
      },
      async pull(controller) {
        if (loadBytes) {
          const loaded = await loadBytes();
          // Cancellation can clear the loader while the native read is pending.
          if (!loadBytes) return;

          bytes = loaded;
          loadBytes = undefined;
        }
        if (!bytes) return;

        const request = controller.byobRequest;
        const view = request?.view;
        const end = Math.min(offset + (view?.byteLength ?? DEFAULT_CHUNK_SIZE), bytes.length);
        if (request && view) {
          new Uint8Array(view.buffer, view.byteOffset, view.byteLength).set(bytes.subarray(offset, end));
          request.respond(end - offset);
        } else {
          // Enqueue can transfer the chunk's buffer, so give it a separate copy.
          controller.enqueue(bytes.slice(offset, end));
        }
        offset = end;

        if (offset === bytes.length) {
          bytes = undefined;
          controller.close();
          // A BYOB read with a minimum length may still be pending.
          controller.byobRequest?.respond(0);
        }
      },
      cancel() {
        loadBytes = undefined;
        bytes = undefined;
      },
    });
  }
}

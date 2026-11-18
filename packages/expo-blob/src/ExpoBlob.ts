/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Blob as ExpoBlob } from 'expo-blob/build/ExpoBlob';
import type { BlobPart } from 'expo-blob/build/ExpoBlob.types';
import { DEFAULT_CHUNK_SIZE } from 'expo-blob/build/utils';

export * from 'expo-blob/build/ExpoBlob';

function* normalizeViews(parts: Iterable<BlobPart>): Iterable<BlobPart> {
  for (const part of parts) {
    if (ArrayBuffer.isView(part) && !(part instanceof Uint8Array)) {
      yield new Uint8Array(part.buffer, part.byteOffset, part.byteLength);
    } else {
      yield part;
    }
  }
}

export class Blob extends ExpoBlob {
  static override get length(): number {
    return super.length;
  }

  constructor(parts?: Iterable<BlobPart>, options?: BlobPropertyBag) {
    super(parts !== null && typeof parts === 'object' ? normalizeViews(parts) : parts, options);
  }

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

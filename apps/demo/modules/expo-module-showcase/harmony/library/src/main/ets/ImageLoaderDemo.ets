/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext } from '@expo-harmony/expo-modules-core';
import { ImageLoaderInterfaceKey, ImageLoaderResultListener } from '@expo-harmony/expo-image-loader';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';

async function load(context: ExpoModuleContext, uri: string, editing: boolean, callback: boolean): Promise<image.PixelMap> {
  const loader = context.services.require(ImageLoaderInterfaceKey);

  if (!callback) {
    return editing ? loader.loadImageForManipulationFromURL(uri) : loader.loadImageForDisplayFromURL(uri);
  }

  return new Promise<image.PixelMap>((resolve, reject): void => {
    const listener = new PromiseResultListener(resolve, reject);
    if (editing) loader.loadImageForManipulationFromURL(uri, listener);
    else loader.loadImageForDisplayFromURL(uri, listener);
  });
}

class PromiseResultListener implements ImageLoaderResultListener {
  private readonly resolve: (pixel: image.PixelMap) => void;
  private readonly reject: (cause: Error) => void;

  constructor(resolve: (pixel: image.PixelMap) => void, reject: (cause: Error) => void) {
    this.resolve = resolve;
    this.reject = reject;
  }

  onSuccess(pixel: image.PixelMap): void {
    this.resolve(pixel);
  }

  onFailure(cause: Error): void {
    this.reject(cause);
  }
}

export async function readImage(context: ExpoModuleContext, uri: string, editing: boolean, callback: boolean): Promise<string> {
  const pixel = await load(context, uri, editing, callback);

  try {
    const info = await pixel.getImageInfo();
    const packer = image.createImagePacker();

    try {
      const data = await packer.packing(pixel, { format: 'image/png', quality: 100 });

      return JSON.stringify({
        width: info.size.width,
        height: info.size.height,
        editable: pixel.isEditable,
        bytes: pixel.getPixelBytesNumber(),
        preview: `data:image/png;base64,${new util.Base64Helper().encodeToStringSync(new Uint8Array(data))}`,
      });
    } finally {
      await packer.release();
    }
  } finally {
    await pixel.release();
  }
}

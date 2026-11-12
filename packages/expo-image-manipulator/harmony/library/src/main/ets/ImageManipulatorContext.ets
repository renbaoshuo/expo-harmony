/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ImageLoaderInterfaceKey } from '@expo-harmony/expo-image-loader';
import { ExpoModuleContext, ExpoModuleError, ExpoSharedObject, ExpoSharedRef } from '@expo-harmony/expo-modules-core';
import { image } from '@kit.ImageKit';

import { CropRect, FlipType, ResizeOptions } from './ImageManipulatorArguments';
import { copyPixelMap, releasePixelMap } from './ImageManipulatorPixels';

class ManipulatorTask {
  private readonly context: ExpoModuleContext;
  private pixel?: image.PixelMap;
  private error?: Error;
  private closed: boolean = false;
  private tail: Promise<void>;
  private resolve?: () => void;

  constructor(context: ExpoModuleContext, load: Promise<image.PixelMap>) {
    this.context = context;
    this.tail = new Promise<void>((resolve): void => {
      this.resolve = resolve;
    });

    load.then(
      (pixel: image.PixelMap): void => {
        // ImageLoader cannot cancel individual loads; release results arriving after close().
        if (this.closed) releasePixelMap(pixel);
        else this.pixel = pixel;

        this.completeLoading();
      },
      (error: Error): void => {
        if (!this.closed) this.error = error;

        this.completeLoading();
      },
    );
  }

  transform(body: (pixel: image.PixelMap) => Promise<void>): void {
    this.tail = this.tail.then(async (): Promise<void> => {
      if (this.error !== undefined || this.closed) return;

      try {
        await body(this.requirePixel());
      } catch (error) {
        this.error = error as Error;
      }
    });
  }

  render(): Promise<image.PixelMap> {
    const result = this.tail.then((): image.PixelMap => copyPixelMap(this.requirePixel()));

    // Snapshot failures must not poison later transforms.
    this.tail = result.then(
      (): void => {},
      (): void => {},
    );

    return result;
  }

  close(): void {
    if (this.closed) return;

    this.closed = true;

    // Wake pending renders now; release the bitmap only after active transforms finish.
    this.completeLoading();

    this.tail.then((): void => {
      if (this.pixel !== undefined) {
        releasePixelMap(this.pixel);
        this.pixel = undefined;
      }
    });
  }

  private completeLoading(): void {
    this.resolve?.();
    this.resolve = undefined;
  }

  private requirePixel(): image.PixelMap {
    this.context.assertActive();
    if (this.closed) throw new ExpoModuleError('ERR_IMAGE_MANIPULATOR_CANCELLED', 'The image manipulation was reset or released.');
    if (this.error !== undefined) {
      throw new ExpoModuleError(this.error instanceof ExpoModuleError ? this.error.code : 'ERR_IMAGE_MANIPULATOR', this.error.message, this.error);
    }
    if (this.pixel === undefined) throw new ExpoModuleError('ERR_IMAGE_MANIPULATOR', 'The image has not been loaded.');

    return this.pixel;
  }
}

export class ImageManipulatorContext extends ExpoSharedObject {
  private readonly source: string | image.PixelMap;
  private task: ManipulatorTask;
  private disposed: boolean = false;
  private unsubscribe?: () => void;

  constructor(context: ExpoModuleContext, source: string | ExpoSharedRef<image.PixelMap>) {
    super(context);

    this.source = typeof source === 'string' ? source : copyPixelMap(source.value);
    this.task = this.createTask();

    this.unsubscribe = context.session?.onClose((): void => this.sharedObjectWillRelease());
  }

  resize(options: ResizeOptions): ImageManipulatorContext {
    this.task.transform(async (pixel: image.PixelMap): Promise<void> => {
      const size = pixel.getImageInfoSync().size;
      const ratio = size.width / size.height;

      let width = options.width == null ? undefined : Math.trunc(options.width);
      let height = options.height == null ? undefined : Math.trunc(options.height);
      width = width ?? Math.trunc((height ?? 0) * ratio);
      height = height ?? Math.trunc(width / ratio);

      if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0) {
        throw new ExpoModuleError('ERR_IMAGE_INVALID_ARGUMENT', 'Resize dimensions must be positive and at least one pixel.');
      }

      await pixel.scale(width / size.width, height / size.height, image.AntiAliasingLevel.LOW);

      const resized = pixel.getImageInfoSync().size;
      // Older Image Kit versions can resolve scale() even if the transform failed internally.
      if (resized.width !== width || resized.height !== height) {
        throw new ExpoModuleError('ERR_IMAGE_MANIPULATOR', `Could not resize the image to ${width} × ${height} pixels.`);
      }
    });

    return this;
  }

  rotate(degrees: number): ImageManipulatorContext {
    this.task.transform(async (pixel: image.PixelMap): Promise<void> => {
      const angle = ((degrees % 360) + 360) % 360;
      if (angle === 0) return;

      const size = angle === 90 || angle === 270 ? pixel.getImageInfoSync().size : undefined;
      await pixel.rotate(angle);

      // Older Image Kit versions can resolve rotate() even if the transform failed internally.
      if (size !== undefined) {
        const rotated = pixel.getImageInfoSync().size;
        if (rotated.width !== size.height || rotated.height !== size.width) {
          throw new ExpoModuleError('ERR_IMAGE_MANIPULATOR', `Could not rotate the image by ${degrees} degrees.`);
        }
      }
    });

    return this;
  }

  flip(type: FlipType): ImageManipulatorContext {
    this.task.transform((pixel: image.PixelMap): Promise<void> => pixel.flip(type === FlipType.HORIZONTAL, type === FlipType.VERTICAL));
    return this;
  }

  crop(rect: CropRect): ImageManipulatorContext {
    this.task.transform(async (pixel: image.PixelMap): Promise<void> => {
      const size = pixel.getImageInfoSync().size;

      const x = Math.trunc(rect.originX);
      const y = Math.trunc(rect.originY);
      const width = Math.trunc(rect.width);
      const height = Math.trunc(rect.height);

      if (
        rect.originX < 0 ||
        rect.originY < 0 ||
        rect.width > size.width ||
        rect.height > size.height ||
        width <= 0 ||
        height <= 0 ||
        x + width > size.width ||
        y + height > size.height
      ) {
        throw new ExpoModuleError('ERR_IMAGE_INVALID_CROP', 'The crop rectangle must be inside the source image and at least one pixel.');
      }

      await pixel.crop({ x, y, size: { width, height } });
    });

    return this;
  }

  reset(): ImageManipulatorContext {
    this.task.close();
    this.task = this.createTask();
    return this;
  }

  render(): Promise<image.PixelMap> {
    return this.task.render();
  }

  override sharedObjectWillRelease(): void {
    if (this.disposed) return;

    this.disposed = true;
    this.unsubscribe?.();
    this.unsubscribe = undefined;

    this.task.close();
    if (typeof this.source !== 'string') releasePixelMap(this.source);
  }

  private createTask(): ManipulatorTask {
    return new ManipulatorTask(this.context, this.load());
  }

  private async load(): Promise<image.PixelMap> {
    this.context.assertActive();
    if (typeof this.source !== 'string') return copyPixelMap(this.source);

    const loader = this.context.services.get(ImageLoaderInterfaceKey);
    if (loader === undefined) {
      throw new ExpoModuleError(
        'ERR_IMAGE_LOADER_NOT_FOUND',
        "ImageLoader module not found, make sure '@expo-harmony/expo-image-loader' is linked correctly.",
      );
    }

    try {
      return await loader.loadImageForManipulationFromURL(this.source);
    } catch (error) {
      throw new ExpoModuleError('ERR_IMAGE_LOADING_FAILED', 'Could not load the image.', error as Object);
    }
  }
}

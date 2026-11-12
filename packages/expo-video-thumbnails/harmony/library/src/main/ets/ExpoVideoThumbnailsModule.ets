/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes, fileUriFromPath } from '@expo-harmony/expo-modules-core';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';

import { VIDEO_THUMBNAILS_OPTIONS, VideoThumbnailsOptions, timeInMicroseconds } from './VideoThumbnailsOptions';

const CACHE_DIRECTORY = 'VideoThumbnails';
const JPEG_MIME_TYPE = 'image/jpeg';
const ERROR_CODE = 'E_VIDEO_THUMBNAILS';

interface VideoThumbnailsResult {
  uri: string;
  width: number;
  height: number;
}

export class ExpoVideoThumbnailsModule extends ExpoModule {
  override definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition().name('ExpoVideoThumbnails').asyncFunction(
      'getThumbnail',
      ExpoFunction.typed2(
        ExpoValueTypes.string(),
        VIDEO_THUMBNAILS_OPTIONS,
        (source: string, options: VideoThumbnailsOptions): Promise<VideoThumbnailsResult> => this.getThumbnail(source, options),
      ),
    );
  }

  private async getThumbnail(source: string, options: VideoThumbnailsOptions): Promise<VideoThumbnailsResult> {
    this.context.assertActive();
    if (!canIUse('SystemCapability.Multimedia.Media.AVMetadataExtractor')) {
      throw new ExpoModuleError(ERROR_CODE, 'This device does not support video thumbnail extraction.');
    }

    // URI schemes are case-insensitive, but the system media implementation matches lowercase prefixes.
    const uri = source.replace(/^(https?|file):/i, (scheme: string): string => scheme.toLowerCase());
    const remote = /^https?:\/\//.test(uri);
    if (!remote && !uri.startsWith('/') && !/^file:\/\//.test(uri)) {
      throw new ExpoModuleError('ERR_INVALID_SOURCE_FILENAME', 'Invalid source URI. Use HTTP(S), a file URI, or an absolute path.');
    }

    let input: fileIo.File | undefined;
    let extractor: media.AVMetadataExtractor | undefined;
    let pixel: image.PixelMap | undefined;
    let packer: image.ImagePacker | undefined;
    let output: fileIo.File | undefined;
    let destination: string | undefined;

    try {
      let result: VideoThumbnailsResult;
      try {
        extractor = await media.createAVMetadataExtractor();
        this.context.assertActive();

        if (remote) {
          extractor.setUrlSource(uri, options.headers);
        } else {
          const target = this.context.fileSourceForRead(uri);
          // Open without blocking so a FIFO cannot stall the regular-file check.
          input = await fileIo.open(target, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);

          const stat = await fileIo.stat(input.fd);
          this.context.assertActive();
          if (!stat.isFile() || stat.size <= 0) {
            throw new ExpoModuleError('ERR_THUMBNAIL_FILE', "Can't read file: the video must be a nonempty regular file.");
          }
          this.context.readPathForDescriptor(target, input);

          extractor.fdSrc = { fd: input.fd, offset: 0, length: stat.size };
        }

        pixel = await extractor.fetchFrameByTime(timeInMicroseconds(options), media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC, {});
        this.context.assertActive();

        const size = (await pixel.getImageInfo()).size;

        const dir = `${this.context.cachePath}/${CACHE_DIRECTORY}`;
        try {
          await fileIo.mkdir(dir, true);
        } catch (error) {
          if (!(await fileIo.stat(dir)).isDirectory()) {
            throw new ExpoModuleError(ERROR_CODE, 'Could not create the thumbnail cache directory.', error as Object);
          }
        }

        this.context.assertActive();
        const path = `${dir}/${util.generateRandomUUID(true)}.jpg`;
        output = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        destination = path;
        this.context.assertActive();

        packer = image.createImagePacker();
        await packer.packToFile(pixel, output.fd, { format: JPEG_MIME_TYPE, quality: Math.trunc(options.quality * 100) });
        await fileIo.close(output);
        output = undefined;

        result = { uri: fileUriFromPath(path), width: size.width, height: size.height };
      } finally {
        if (packer !== undefined) await cleanup((): Promise<void> => packer!.release());
        if (output !== undefined) await cleanup((): Promise<void> => fileIo.close(output!));
        if (pixel !== undefined) await cleanup((): Promise<void> => pixel!.release());
        if (extractor !== undefined) await cleanup((): Promise<void> => extractor!.release());
        if (input !== undefined) await cleanup((): Promise<void> => fileIo.close(input!));
      }

      this.context.assertActive();
      return result;
    } catch (error) {
      if (destination !== undefined) await cleanup((): Promise<void> => fileIo.unlink(destination!));

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error, error.path);
      }

      throw new ExpoModuleError(ERROR_CODE, 'Could not generate or save the video thumbnail.', error as Object);
    }
  }
}

async function cleanup(action: () => Promise<void>): Promise<void> {
  try {
    await action();
  } catch (error) {
    console.warn(`ExpoVideoThumbnails cleanup failed: ${String(error)}`);
  }
}

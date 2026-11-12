/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoModuleError, ExpoSharedRef } from '@expo-harmony/expo-modules-core';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { isLocalHlsPlaylist, isRemote, normalizeUri, openVideoFile, requireFinite, VideoFile, VideoSource } from './VideoSource';

export interface ThumbnailOptions {
  maxWidth?: number;
  maxHeight?: number;
}

export class VideoThumbnail extends ExpoSharedRef<image.PixelMap> {
  readonly width: number;
  readonly height: number;
  readonly requestedTime: number;
  private released: boolean = false;

  constructor(context: ExpoModuleContext, pixel: image.PixelMap, time: number) {
    super(context, 'image', pixel);

    const size = pixel.getImageInfoSync().size;
    this.width = size.width;
    this.height = size.height;
    this.requestedTime = time;
  }

  override getAdditionalMemoryPressure(): number {
    return this.released ? 0 : this.value.getPixelBytesNumber();
  }

  override sharedObjectWillRelease(): void {
    if (this.released) return;
    this.released = true;
    this.value.release().catch((error: Error): void => console.warn(`ExpoVideo: thumbnail release failed: ${error.message}`));
  }
}

export async function generateThumbnails(
  context: ExpoModuleContext,
  source: VideoSource | null,
  times: number[],
  options: ThumbnailOptions,
): Promise<VideoThumbnail[]> {
  if (!source?.uri) throw new ExpoModuleError('ERR_VIDEO_NO_SOURCE', 'A video source is required to generate thumbnails.');
  if (isLocalHlsPlaylist(source)) {
    throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'HarmonyOS Media Kit cannot extract thumbnails from HLS playlists.');
  }

  times.forEach((time: number): void => {
    requireFinite(time, 'thumbnail time');
    if (!Number.isSafeInteger(Math.round(time * 1_000_000)))
      throw new ExpoModuleError('ERR_VIDEO_INVALID_ARGUMENT', 'Thumbnail time is outside the safe microsecond range.');
  });
  if (options.maxWidth !== undefined) requireFinite(options.maxWidth, 'maxWidth', 1);
  if (options.maxHeight !== undefined) requireFinite(options.maxHeight, 'maxHeight', 1);

  const extractor = await media.createAVMetadataExtractor();
  let file: VideoFile | undefined;
  const result: VideoThumbnail[] = [];

  try {
    if (isRemote(source.uri)) extractor.setUrlSource(normalizeUri(source.uri), source.headers);
    else {
      file = openVideoFile(context, source.uri);
      extractor.fdSrc = file.descriptor;
    }

    for (const time of times) {
      context.assertActive();

      const pixel = await extractor.fetchFrameByTime(Math.round(time * 1_000_000), media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST, {});

      try {
        context.assertActive();

        const size = pixel.getImageInfoSync().size;
        const scale = Math.min(1, (options.maxWidth ?? size.width) / size.width, (options.maxHeight ?? size.height) / size.height);
        if (scale < 1) await pixel.scale(scale, scale);

        result.push(new VideoThumbnail(context, pixel, time));
      } catch (error) {
        await pixel.release();

        throw new ExpoModuleError(
          error instanceof ExpoModuleError ? error.code : 'ERR_VIDEO_THUMBNAIL',
          error instanceof Error ? error.message : String(error),
          error as Object,
        );
      }
    }

    return result;
  } catch (error) {
    result.forEach((thumbnail: VideoThumbnail): void => thumbnail.sharedObjectWillRelease());

    throw new ExpoModuleError(
      error instanceof ExpoModuleError ? error.code : 'ERR_VIDEO_THUMBNAIL',
      error instanceof Error ? error.message : String(error),
      error as Object,
    );
  } finally {
    try {
      await extractor.release();
    } catch (error) {
      console.warn(`ExpoVideo: thumbnail extractor release failed: ${String(error)}`);
    } finally {
      try {
        file?.close();
      } catch (error) {
        console.warn(`ExpoVideo: thumbnail source close failed: ${String(error)}`);
      }
    }
  }
}

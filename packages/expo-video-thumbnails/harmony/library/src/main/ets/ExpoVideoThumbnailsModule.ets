/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes,
  fileUriFromPath, isRnohRawfileResourceUri, rawResourcePathFromUri,
} from '@expo-harmony/expo-modules-core';
import { util } from '@kit.ArkTS';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { resourceManager } from '@kit.LocalizationKit';
import { media } from '@kit.MediaKit';

import { VIDEO_THUMBNAILS_OPTIONS, VideoThumbnailsOptions, timeInMicroseconds } from './VideoThumbnailsOptions';

const CACHE_DIRECTORY = 'VideoThumbnails';
const JPEG_MIME_TYPE = 'image/jpeg';
const ERROR_CODE = 'E_VIDEO_THUMBNAILS';
const GENERATION_ERROR = 'Could not generate or save the video thumbnail.';
const NETWORK_THUMBNAIL_API = 20;
const FILE_ALREADY_EXISTS = 13900015;
const RAW_RESOURCE_NOT_FOUND = 9001005;

interface VideoThumbnailsResult {
  uri: string;
  width: number;
  height: number;
}

interface PackagedVideoSource {
  file: fileIo.File;
  offset: number;
  length: number;
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

    // URI schemes are case-insensitive, but the system media implementation matches lowercase prefixes.
    const uri = source.replace(/^(https?|file):/i, (scheme: string): string => scheme.toLowerCase());
    const remote = /^https?:\/\//.test(uri);
    const packaged = isRnohRawfileResourceUri(uri) || /^(asset|rawfile):/i.test(uri);

    if (!remote && !packaged && !uri.startsWith('/') && !uri.startsWith('file://')) {
      throw new ExpoModuleError('ERR_INVALID_SOURCE_FILENAME', 'Use HTTP(S), a file URI, an absolute path, or a packaged resource URI.');
    }
    if (!canIUse('SystemCapability.Multimedia.Image.ImagePacker')) {
      throw new ExpoModuleError(ERROR_CODE, 'This device does not support JPEG thumbnail encoding.');
    }

    let pixel: image.PixelMap | undefined;
    let packer: image.ImagePacker | undefined;
    let output: fileIo.File | undefined;
    let target: string | undefined;

    try {
      let result: VideoThumbnailsResult;
      try {
        const time = timeInMicroseconds(options);
        pixel = remote ? await this.fetchNetworkFrame(uri, time, options.headers) : await this.fetchLocalFrame(uri, time, packaged);

        this.context.assertActive();

        const size = (await pixel.getImageInfo()).size;
        if (size.width <= 0 || size.height <= 0) {
          throw new ExpoModuleError(ERROR_CODE, 'Media Kit returned a video frame with invalid dimensions.');
        }

        const dir = `${this.context.cachePath}/${CACHE_DIRECTORY}`;
        await ensureCacheDirectory(dir);

        this.context.assertActive();
        const path = `${dir}/${util.generateRandomUUID(true)}.jpg`;
        const temp = `${path}.tmp`;
        output = await fileIo.open(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        target = temp;
        this.context.assertActive();

        packer = image.createImagePacker();
        await packer.packToFile(pixel, output.fd, { format: JPEG_MIME_TYPE, quality: Math.trunc(options.quality * 100) });
        if ((await fileIo.stat(output.fd)).size <= 0) {
          throw new ExpoModuleError(ERROR_CODE, 'Image Kit produced an empty JPEG thumbnail.');
        }

        await fileIo.close(output);
        output = undefined;

        this.context.assertActive();
        await fileIo.rename(temp, path);
        target = path;

        result = { uri: fileUriFromPath(path), width: size.width, height: size.height };
      } finally {
        if (packer !== undefined) await cleanup((): Promise<void> => packer!.release());
        if (output !== undefined) await cleanup((): Promise<void> => fileIo.close(output!));
        if (pixel !== undefined) await cleanup((): Promise<void> => pixel!.release());
      }

      this.context.assertActive();

      return result;
    } catch (error) {
      if (target !== undefined) await cleanup((): Promise<void> => fileIo.unlink(target!));

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause ?? error, error.path);
      }

      throw new ExpoModuleError(ERROR_CODE, GENERATION_ERROR, error as Object);
    }
  }

  private async fetchNetworkFrame(uri: string, time: number, headers: Record<string, string>): Promise<image.PixelMap> {
    if (deviceInfo.sdkApiVersion < NETWORK_THUMBNAIL_API || !canIUse('SystemCapability.Multimedia.Media.AVMetadataExtractor')) {
      throw new ExpoModuleError(ERROR_CODE, 'Network video thumbnails require HarmonyOS API 20 and AVMetadataExtractor support.');
    }

    const extractor = await media.createAVMetadataExtractor();

    try {
      this.context.assertActive();
      extractor.setUrlSource(uri, headers);

      return await extractor.fetchFrameByTime(time, media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC, {});
    } finally {
      await cleanup((): Promise<void> => extractor.release());
    }
  }

  private async fetchLocalFrame(uri: string, time: number, packaged: boolean): Promise<image.PixelMap> {
    if (!canIUse('SystemCapability.Multimedia.Media.AVImageGenerator')) {
      throw new ExpoModuleError(ERROR_CODE, 'This device does not support local video thumbnail extraction.');
    }

    let input: fileIo.File | undefined;
    let generator: media.AVImageGenerator | undefined;

    try {
      let descriptor: media.AVFileDescriptor;
      if (packaged) {
        const resource = openPackagedVideo(this.context.uiAbilityContext.resourceManager, uri);
        input = resource.file;
        descriptor = { fd: input.fd, offset: resource.offset, length: resource.length };
      } else {
        // Open without blocking so a FIFO cannot stall the regular-file check.
        const path = this.context.fileSourceForRead(uri);
        input = await fileIo.open(path, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);

        const stat = await fileIo.stat(input.fd);
        if (!stat.isFile() || stat.size <= 0) {
          throw new ExpoModuleError('ERR_THUMBNAIL_FILE', "Can't read file: the video must be a nonempty regular file.");
        }
        this.context.readPathForDescriptor(path, input);
        descriptor = { fd: input.fd, offset: 0, length: stat.size };
      }

      this.context.assertActive();
      generator = await media.createAVImageGenerator();
      this.context.assertActive();
      generator.fdSrc = descriptor;

      return await generator.fetchFrameByTime(time, media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC, {});
    } finally {
      if (generator !== undefined) await cleanup((): Promise<void> => generator!.release());
      if (input !== undefined) await cleanup((): Promise<void> => fileIo.close(input!));
    }
  }
}

function openPackagedVideo(resources: resourceManager.ResourceManager, uri: string): PackagedVideoSource {
  let name: string;

  try {
    name = rawResourcePathFromUri(uri);
  } catch (error) {
    throw new ExpoModuleError('ERR_INVALID_SOURCE_FILENAME', 'Invalid packaged video URI.', error as Object);
  }

  let raw: resourceManager.RawFileDescriptor;
  try {
    raw = resources.getRawFdSync(name);
  } catch (error) {
    let fallback = name;
    if (/^asset:/i.test(uri) && (error as BusinessError).code === RAW_RESOURCE_NOT_FOUND) {
      try {
        fallback = rawResourcePathFromUri(uri, true);
      } catch (_) {
        // Metro asset names can contain literal percent signs.
      }
    }
    if (fallback === name) throw new ExpoModuleError(ERROR_CODE, GENERATION_ERROR, error as Object);

    name = fallback;
    raw = resources.getRawFdSync(name);
  }

  let file: fileIo.File | undefined;
  try {
    if (raw.length <= 0) throw new ExpoModuleError('ERR_THUMBNAIL_FILE', 'The packaged video is empty.');

    // Duplicate the descriptor before ResourceManager closes its handle.
    file = fileIo.dup(raw.fd);

    return { file, offset: raw.offset, length: raw.length };
  } finally {
    try {
      resources.closeRawFdSync(name);
    } catch (error) {
      if (file !== undefined) fileIo.closeSync(file);

      throw new ExpoModuleError(ERROR_CODE, GENERATION_ERROR, error as Object);
    }
  }
}

async function ensureCacheDirectory(path: string): Promise<void> {
  try {
    await fileIo.mkdir(path, true);
  } catch (error) {
    if ((error as BusinessError).code !== FILE_ALREADY_EXISTS) {
      throw new ExpoModuleError(ERROR_CODE, 'Could not create the thumbnail cache directory.', error as Object);
    }
  }

  if (!(await fileIo.lstat(path)).isDirectory()) {
    throw new ExpoModuleError(ERROR_CODE, 'The thumbnail cache path must be a directory.');
  }
}

async function cleanup(action: () => Promise<void>): Promise<void> {
  try {
    await action();
  } catch (error) {
    console.warn(`ExpoVideoThumbnails cleanup failed: ${String(error)}`);
  }
}

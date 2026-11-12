/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { util } from '@kit.ArkTS';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';
import { filePathFromUri, fileUriFromPath } from '@expo-harmony/expo-modules-core';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { media } from '@kit.MediaKit';

import { EXIF_KEYS, decodeExifProperties, orientationCode } from './ExpoImagePickerExif';
import { ExpoImagePickerError } from './ExpoImagePickerError';

const CACHE_DIRECTORY: string = 'expo-image-picker';
const AV_METADATA_CAPABILITY: string = 'SystemCapability.Multimedia.Media.AVMetadataExtractor';
const READ_CHUNK_SIZE: number = 64 * 1024;
const JPEG_MIME_TYPE: string = 'image/jpeg';
const PNG_MIME_TYPE: string = 'image/png';
const GIF_MIME_TYPE: string = 'image/gif';
const BMP_MIME_TYPE: string = 'image/bmp';
const WEBP_MIME_TYPE: string = 'image/webp';
const ROTATED_ORIENTATIONS: number[] = [5, 6, 7, 8];
const CODE_CAPTURE_FILE: string = 'ERR_IMAGE_PICKER_CAPTURE_FILE';
const CODE_MEDIA_PROCESSING: string = 'ERR_IMAGE_PICKER_MEDIA_PROCESSING';
const CODE_FILE_READ: string = 'ERR_IMAGE_PICKER_FILE_READ';
const CODE_CACHE: string = 'ERR_IMAGE_PICKER_CACHE';
const CODE_UNAVAILABLE: string = 'ERR_IMAGE_PICKER_UNAVAILABLE';

export type PickerMediaType = 'image' | 'video';
type ImagePickerAssetType = PickerMediaType | 'livePhoto' | 'pairedVideo';

export interface ProcessingOptions {
  quality: number;
  base64: boolean;
  exif: boolean;
}

interface ImageInfo {
  width: number;
  height: number;
  mimeType: string;
  fileSize: number;
  fileName?: string;
  exif?: Record<string, ESObject>;
}

interface VideoInfo {
  width: number;
  height: number;
  duration: number | null;
  rotation: number | null;
  mimeType?: string;
  fileName?: string;
}

export class ImagePickerAsset {
  assetId: string | null = null;
  type: ImagePickerAssetType;
  uri: string;
  width: number;
  height: number;
  fileName: string;
  fileSize: number;
  mimeType?: string;
  base64?: string;
  exif?: Record<string, ESObject>;
  duration?: number | null;
  rotation?: number | null;
  pairedVideoAsset?: ImagePickerAsset;

  constructor(type: ImagePickerAssetType, uri: string, width: number, height: number, fileName: string, fileSize: number, mimeType?: string) {
    this.type = type;
    this.uri = uri;
    this.width = width;
    this.height = height;
    this.fileName = fileName;
    this.fileSize = fileSize;
    this.mimeType = mimeType;
  }
}

export interface CaptureFile {
  path: string;
  uri: string;
}

export async function createCapture(cache: string, type: PickerMediaType): Promise<CaptureFile> {
  const dir = `${cache}/${CACHE_DIRECTORY}`;
  await ensureDirectory(dir);

  const path = `${dir}/${uniqueFilename('capture', type === 'video' ? 'mp4' : 'jpg')}`;
  let file: fileIo.File | undefined;

  try {
    file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);

    return { path, uri: fileUri.getUriFromPath(path) };
  } catch (cause) {
    await removeFile(path);

    if (cause instanceof ExpoImagePickerError) {
      throw new ExpoImagePickerError(cause.code, cause.message, cause);
    }

    throw new ExpoImagePickerError(CODE_CAPTURE_FILE, `Failed to prepare the camera output file: ${String(cause)}`, cause as Object);
  } finally {
    await closeFile(file);
  }
}

export async function removeCapture(file: CaptureFile): Promise<void> {
  await removeFile(file.path);
}

export async function exportImage(uri: string, cache: string, options: ProcessingOptions, name?: string): Promise<ImagePickerAsset> {
  let path: string | undefined;

  try {
    const source = await inspectImage(uri, options.exif);

    const compress = options.quality < 1;
    const mime = compress ? compressionMimeType(source.mimeType) : source.mimeType;

    const dir = `${cache}/${CACHE_DIRECTORY}`;
    await ensureDirectory(dir);

    const filename = uniqueFilename('image', extensionForMime(mime, 'img'));
    path = `${dir}/${filename}`;

    if (compress) {
      await packImage(uri, path, mime, options.quality);
    } else {
      await copyFile(uri, path);
    }

    const output = await inspectImage(path);
    if (output.mimeType !== mime) {
      throw new ExpoImagePickerError(CODE_MEDIA_PROCESSING, `Expected ${mime}, but the exported image is ${output.mimeType}.`);
    }

    const original = name ?? source.fileName ?? filename;
    const display = mime === source.mimeType ? original : replaceExtension(original, filename);
    const asset = new ImagePickerAsset('image', fileUriFromPath(path), output.width, output.height, display, output.fileSize, output.mimeType);

    if (options.base64) {
      // Reuse JPEG bytes already encoded at the requested quality. For other
      // exports, encode from the original to avoid a second compression pass.
      asset.base64 = compress && mime === JPEG_MIME_TYPE
        ? await readJpegBase64(path)
        : await encodeJpegBase64(uri, path, options.quality);
    }

    if (options.exif) asset.exif = source.exif;

    return asset;
  } catch (cause) {
    if (path !== undefined) await removeFile(path);

    if (cause instanceof ExpoImagePickerError) {
      throw new ExpoImagePickerError(cause.code, cause.message, cause);
    }

    throw new ExpoImagePickerError(CODE_MEDIA_PROCESSING, `Failed to process the selected image: ${String(cause)}`, cause as Object);
  }
}

export async function exportVideo(uri: string, cache: string, name?: string): Promise<ImagePickerAsset> {
  let path: string | undefined;

  try {
    const info = await inspectVideo(uri);

    const dir = `${cache}/${CACHE_DIRECTORY}`;
    await ensureDirectory(dir);

    const display = name ?? info.fileName;
    const fallback = display?.match(/\.([a-zA-Z0-9]+)$/)?.[1] ?? 'video';
    const filename = uniqueFilename('video', info.mimeType === undefined ? fallback : extensionForMime(info.mimeType, fallback));
    path = `${dir}/${filename}`;

    await copyFile(uri, path);

    return await videoAsset('video', path, display ?? filename, info);
  } catch (cause) {
    if (path !== undefined) await removeFile(path);

    if (cause instanceof ExpoImagePickerError) {
      throw new ExpoImagePickerError(cause.code, cause.message, cause);
    }

    throw new ExpoImagePickerError(CODE_MEDIA_PROCESSING, `Failed to process the selected video: ${String(cause)}`, cause as Object);
  }
}

export async function exportMovingPhoto(
  photo: photoAccessHelper.MovingPhoto,
  cache: string,
  options: ProcessingOptions,
  name: string,
): Promise<ImagePickerAsset> {
  const dir = `${cache}/${CACHE_DIRECTORY}`;
  const stem = `live-photo-${util.generateRandomUUID(true)}`;
  const imageExtension = name.match(/\.([a-zA-Z0-9]+)$/)?.[1] ?? 'jpg';
  let imagePath = `${dir}/${stem}-image.${imageExtension}`;
  let videoPath = `${dir}/${stem}-video.mp4`;

  try {
    await ensureDirectory(dir);
    // MovingPhoto requires sandbox URIs with the app authority.
    await photo.requestContent(fileUri.getUriFromPath(imagePath), fileUri.getUriFromPath(videoPath));

    const imageInfo = await inspectImage(imagePath, options.exif);
    const videoInfo = await inspectVideo(videoPath);
    const coverExtension = extensionForMime(imageInfo.mimeType, imageExtension);
    const videoExtension = videoInfo.mimeType === undefined ? 'mp4' : extensionForMime(videoInfo.mimeType, 'mp4');
    if (coverExtension !== imageExtension) {
      const target = `${dir}/${stem}-image.${coverExtension}`;
      await fileIo.rename(imagePath, target);
      imagePath = target;
    }
    if (videoExtension !== 'mp4') {
      const target = `${dir}/${stem}-video.${videoExtension}`;
      await fileIo.rename(videoPath, target);
      videoPath = target;
    }
    const coverName = name || `${stem}.${coverExtension}`;
    const asset = new ImagePickerAsset('livePhoto', fileUriFromPath(imagePath), imageInfo.width, imageInfo.height, coverName,
      imageInfo.fileSize, imageInfo.mimeType);
    asset.pairedVideoAsset = await videoAsset('pairedVideo', videoPath, replaceExtension(coverName, videoPath), videoInfo);
    if (options.exif) asset.exif = imageInfo.exif;
    if (options.base64) {
      asset.base64 = imageInfo.mimeType === JPEG_MIME_TYPE
        ? await readJpegBase64(imagePath)
        : await encodeJpegBase64(imagePath, imagePath, 1);
    }

    return asset;
  } catch (cause) {
    await removeFile(imagePath);
    await removeFile(videoPath);
    if (cause instanceof ExpoImagePickerError) throw new ExpoImagePickerError(cause.code, cause.message, cause);
    throw new ExpoImagePickerError(CODE_MEDIA_PROCESSING, `Failed to export the selected moving photo: ${String(cause)}`, cause as Object);
  }
}

async function videoAsset(type: ImagePickerAssetType, path: string, name: string, info: VideoInfo): Promise<ImagePickerAsset> {
  const size = checkedFileSize((await fileIo.stat(path)).size);
  const asset = new ImagePickerAsset(type, fileUriFromPath(path), info.width, info.height, name, size, info.mimeType);
  asset.duration = info.duration;
  asset.rotation = info.rotation;

  return asset;
}

export async function removeAssets(assets: ImagePickerAsset[]): Promise<void> {
  for (const asset of assets) {
    await removeFile(filePathFromUri(asset.uri));
    if (asset.pairedVideoAsset !== undefined) await removeFile(filePathFromUri(asset.pairedVideoAsset.uri));
  }
}

async function inspectImage(uri: string, includeExif: boolean = false): Promise<ImageInfo> {
  let file: fileIo.File | undefined;
  let source: image.ImageSource | undefined;

  try {
    file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    const stat = await fileIo.stat(file.fd);
    source = image.createImageSource(file.fd);

    const info = await source.getImageInfo();
    const mimeType = normalizedMimeType(info.mimeType);
    if (mimeType === undefined || !mimeType.startsWith('image/')) {
      throw new ExpoImagePickerError(CODE_MEDIA_PROCESSING, 'The selected image has no supported MIME type.');
    }

    const orientation = await readOrientation(source);
    const rotated = orientation !== undefined && ROTATED_ORIENTATIONS.includes(orientation);

    return {
      width: rotated ? info.size.height : info.size.width,
      height: rotated ? info.size.width : info.size.height,
      mimeType,
      fileSize: checkedFileSize(stat.size),
      fileName: file.name.length > 0 ? file.name : undefined,
      exif: includeExif ? await readExif(source, mimeType) : undefined,
    };
  } finally {
    await releaseImageSource(source);
    await closeFile(file);
  }
}

async function readOrientation(source: image.ImageSource): Promise<number | undefined> {
  try {
    const data = await source.getImageProperties([image.PropertyKey.ORIENTATION]);
    const value = data[image.PropertyKey.ORIENTATION];
    if (value === null || value === undefined) return undefined;

    return orientationCode(value);
  } catch (_) {
    return undefined;
  }
}

async function inspectVideo(uri: string): Promise<VideoInfo> {
  if (!canIUse(AV_METADATA_CAPABILITY)) {
    throw new ExpoImagePickerError(CODE_UNAVAILABLE, 'The HarmonyOS AVMetadataExtractor capability is unavailable on this device.');
  }

  let file: fileIo.File | undefined;
  let extractor: media.AVMetadataExtractor | undefined;

  try {
    file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    const size = checkedFileSize((await fileIo.stat(file.fd)).size);
    if (size === 0) throw new ExpoImagePickerError(CODE_FILE_READ, 'The selected video is empty.');

    extractor = await media.createAVMetadataExtractor();
    extractor.fdSrc = { fd: file.fd, offset: 0, length: size };

    const data = await extractor.fetchMetadata();
    if (data == null) {
      throw new ExpoImagePickerError(CODE_MEDIA_PROCESSING, 'The system did not return metadata for the selected video.');
    }

    let width = nonNegativeInteger(data.videoWidth) ?? 0;
    let height = nonNegativeInteger(data.videoHeight) ?? 0;
    const rotation = integerValue(data.videoOrientation);
    if (rotation !== undefined && Math.abs(rotation) % 180 === 90) {
      const previous = width;
      width = height;
      height = previous;
    }

    const mimeType = normalizedMimeType(data.mimeType);
    return {
      width,
      height,
      duration: nonNegativeInteger(data.duration) ?? null,
      rotation: rotation ?? null,
      mimeType: mimeType?.startsWith('video/') ? mimeType : undefined,
      fileName: file.name.length > 0 ? file.name : undefined,
    };
  } finally {
    await releaseMetadataExtractor(extractor);
    await closeFile(file);
  }
}

async function packImage(uri: string, path: string, mime: string, quality: number): Promise<void> {
  let input: fileIo.File | undefined;
  let output: fileIo.File | undefined;
  let source: image.ImageSource | undefined;
  let packer: image.ImagePacker | undefined;

  try {
    input = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    source = image.createImageSource(input.fd);
    packer = image.createImagePacker();
    if (!packer.supportedFormats.includes(mime)) {
      throw new ExpoImagePickerError(CODE_MEDIA_PROCESSING, `This device cannot encode ${mime}.`);
    }

    output = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);

    await packer.packToFile(source, output.fd, {
      format: mime,
      quality: Math.floor(quality * 100),
      needsPackProperties: true,
    });
  } finally {
    await releaseImagePacker(packer);
    await releaseImageSource(source);
    await closeFile(output);
    await closeFile(input);
  }
}

async function readExif(source: image.ImageSource, mime: string): Promise<Record<string, ESObject>> {
  try {
    // ImageKit's EXIF APIs support JPEG/PNG/HEIF at the minimum SDK; WebP and
    // DNG are added at API 23. Missing EXIF must not fail an otherwise valid GIF.
    const supported =
      [JPEG_MIME_TYPE, PNG_MIME_TYPE, 'image/heif', 'image/heic'].includes(mime) ||
      (deviceInfo.sdkApiVersion >= 23 && [WEBP_MIME_TYPE, 'image/x-adobe-dng'].includes(mime));
    if (!supported) return {};

    const data = await source.getImageProperties(EXIF_KEYS);

    return data == null ? {} : decodeExifProperties(data);
  } catch (_) {
    // ImageKit can reject the entire batch when the image has no EXIF fields.
    return {};
  }
}

async function encodeJpegBase64(uri: string, cachedPath: string, quality: number): Promise<string> {
  // File encoding has no ImagePacker.packToData 25 MB buffer ceiling.
  const path = `${cachedPath}.${util.generateRandomUUID(true)}.jpg`;
  try {
    await packImage(uri, path, JPEG_MIME_TYPE, quality);
    return await readJpegBase64(path);
  } finally {
    await removeFile(path);
  }
}

async function readJpegBase64(path: string): Promise<string> {
  const data = new Uint8Array(await readBuffer(path));
  if (data.byteLength < 3 || data[0] !== 0xff || data[1] !== 0xd8 || data[2] !== 0xff) {
    throw new ExpoImagePickerError(CODE_MEDIA_PROCESSING, 'The image encoder did not produce JPEG data.');
  }
  return await new util.Base64Helper().encodeToString(data);
}

async function readBuffer(path: string): Promise<ArrayBuffer> {
  let file: fileIo.File | undefined;

  try {
    file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    const size = checkedFileSize((await fileIo.stat(file.fd)).size);
    const data = new ArrayBuffer(size);
    const view = new Uint8Array(data);
    const chunk = new ArrayBuffer(Math.min(READ_CHUNK_SIZE, size));
    let offset = 0;

    while (offset < data.byteLength) {
      const length = Math.min(chunk.byteLength, data.byteLength - offset);
      const count = await fileIo.read(file.fd, chunk, { length });
      if (count <= 0) throw new ExpoImagePickerError(CODE_FILE_READ, 'The selected image could not be read completely.');

      view.set(new Uint8Array(chunk, 0, count), offset);
      offset += count;
    }

    return data;
  } finally {
    await closeFile(file);
  }
}

async function copyFile(uri: string, path: string): Promise<void> {
  let source: fileIo.File | undefined;

  try {
    source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);

    await fileIo.copyFile(source.fd, path, 0);
  } finally {
    await closeFile(source);
  }
}

async function ensureDirectory(path: string): Promise<void> {
  if (await fileIo.access(path)) {
    const info = await fileIo.stat(path);
    if (!info.isDirectory()) {
      throw new ExpoImagePickerError(CODE_CACHE, `The image picker cache path '${path}' is not a directory.`);
    }

    return;
  }

  await fileIo.mkdir(path, true);
}

function checkedFileSize(size: number): number {
  if (!Number.isSafeInteger(size) || size < 0) {
    throw new ExpoImagePickerError(CODE_FILE_READ, 'The selected media has an invalid file size.');
  }
  return size;
}

async function removeFile(path: string): Promise<void> {
  try {
    await fileIo.unlink(path);
  } catch (_) {}
}

async function closeFile(file: fileIo.File | undefined): Promise<void> {
  if (file === undefined) return;
  try {
    await fileIo.close(file.fd);
  } catch (_) {}
}

async function releaseImageSource(source: image.ImageSource | undefined): Promise<void> {
  if (source === undefined) return;
  try {
    await source.release();
  } catch (_) {}
}

async function releaseImagePacker(packer: image.ImagePacker | undefined): Promise<void> {
  if (packer === undefined) return;
  try {
    await packer.release();
  } catch (_) {}
}

async function releaseMetadataExtractor(extractor: media.AVMetadataExtractor | undefined): Promise<void> {
  if (extractor === undefined) return;
  try {
    await extractor.release();
  } catch (_) {}
}

function compressionMimeType(mime: string): string {
  return mime === PNG_MIME_TYPE || mime === GIF_MIME_TYPE || mime === BMP_MIME_TYPE || mime === WEBP_MIME_TYPE ? PNG_MIME_TYPE : JPEG_MIME_TYPE;
}

function uniqueFilename(prefix: string, ext: string): string {
  return `${prefix}-${util.generateRandomUUID(true)}.${ext}`;
}

function replaceExtension(name: string, output: string): string {
  const index = name.lastIndexOf('.');
  const stem = index > 0 ? name.slice(0, index) : name;
  return `${stem}${output.slice(output.lastIndexOf('.'))}`;
}

function extensionForMime(mime: string, fallback: string): string {
  const type = uniformTypeDescriptor.getUniformDataTypeByMIMEType(mime);
  const extensions = uniformTypeDescriptor.getTypeDescriptor(type)?.filenameExtensions ?? [];
  const extension = extensions.find((value: string): boolean => /^\.[a-zA-Z0-9]+$/.test(value));
  return extension === undefined ? fallback : extension.slice(1);
}

function normalizedMimeType(value?: string): string | undefined {
  if (value == null) return undefined;
  const mime = value.split(';')[0].trim().toLowerCase();
  return mime.length > 0 ? mime : undefined;
}

function integerValue(value?: string): number | undefined {
  if (value == null) return undefined;
  if (value.trim().length === 0) return undefined;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : undefined;
}

function nonNegativeInteger(value?: string): number | undefined {
  const parsed = integerValue(value);
  return parsed !== undefined && parsed >= 0 ? parsed : undefined;
}

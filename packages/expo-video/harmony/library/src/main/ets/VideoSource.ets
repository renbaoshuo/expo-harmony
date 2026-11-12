/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoModuleContext, ExpoModuleError, ExpoRecordShape, ExpoValueTypes, isRnohRawfileResourceUri, rawResourcePathFromUri,
} from '@expo-harmony/expo-modules-core';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { resourceManager } from '@kit.LocalizationKit';
import { media } from '@kit.MediaKit';

const RAW_RESOURCE_NOT_FOUND: number = 9001005;

export interface VideoMetadata {
  title?: string;
  artist?: string;
  artwork?: string;
}

export interface VideoSource {
  uri?: string;
  assetId?: number;
  headers?: Record<string, string>;
  metadata?: VideoMetadata;
  useCaching?: boolean;
  contentType?: string;
  drm?: Record<string, string>;
}

export function requireFinite(value: number, name: string, min: number = 0): number {
  if (!Number.isFinite(value) || value < min) {
    throw new ExpoModuleError('ERR_VIDEO_INVALID_ARGUMENT', `${name} must be a finite number >= ${min}.`);
  }

  return value;
}

const METADATA = ExpoValueTypes.shapedRecord<VideoMetadata>(
  'VideoMetadata',
  new ExpoRecordShape()
    .field('title', ExpoValueTypes.string().optional())
    .field('artist', ExpoValueTypes.string().optional())
    .field('artwork', ExpoValueTypes.string().optional()),
  (fields: Record<string, ESObject>): VideoMetadata => fields as VideoMetadata,
  (value: VideoMetadata): Record<string, ESObject> => value as Record<string, ESObject>,
);

const DRM = ExpoValueTypes.shapedRecord<Record<string, string>>(
  'DRMOptions',
  new ExpoRecordShape().field('type', ExpoValueTypes.string()),
  (fields: Record<string, ESObject>): Record<string, string> => fields as Record<string, string>,
  (value: Record<string, string>): Record<string, ESObject> => value,
);

export const VIDEO_SOURCE = ExpoValueTypes.shapedRecord<VideoSource>(
  'VideoSource',
  new ExpoRecordShape()
    .field('uri', ExpoValueTypes.string().optional())
    .field('assetId', ExpoValueTypes.number().optional())
    .field('headers', ExpoValueTypes.record(ExpoValueTypes.string()).optional())
    .field('metadata', METADATA.optional())
    .field('useCaching', ExpoValueTypes.boolean().optional())
    .field('contentType', ExpoValueTypes.string().optional())
    .field('drm', DRM.optional()),
  (fields: Record<string, ESObject>): VideoSource => fields as VideoSource,
  (value: VideoSource): Record<string, ESObject> => value as Record<string, ESObject>,
).nullable();

export function validateSource(source: VideoSource | null): void {
  // Upstream treats a source record with no URI as an empty player.
  if (source?.uri === undefined) return;

  if (!source.uri)
    throw new ExpoModuleError('ERR_VIDEO_INVALID_SOURCE', 'The source must contain a URI resolved by the official expo-video JS implementation.');

  if (source.drm !== undefined) throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'DRM is not supported by expo-video on HarmonyOS.');
  if (source.useCaching) throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'Persistent video caching is not supported by expo-video on HarmonyOS.');
  if (source.contentType === 'smoothStreaming')
    throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'SmoothStreaming is not supported by expo-video on HarmonyOS.');

  const contentType = source.contentType ?? 'auto';
  if (!['auto', 'progressive', 'hls', 'dash'].includes(contentType)) {
    throw new ExpoModuleError('ERR_VIDEO_INVALID_SOURCE', 'Invalid video contentType.');
  }
  if (contentType !== 'auto' && !isLocalHlsPlaylist(source)) {
    throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'HarmonyOS supports an explicit HLS type for local playlists. Use auto detection for other sources.');
  }
}

export function isRemote(uri: string): boolean {
  return /^https?:\/\//i.test(uri);
}

export function isLocalHlsPlaylist(source: VideoSource): boolean {
  return source.contentType === 'hls' && source.uri !== undefined && !isRemote(source.uri);
}

export function normalizeUri(uri: string): string {
  // Normalize only the case-insensitive scheme; paths and signed query parameters must stay intact.
  return uri.replace(/^(https?|file):/i, (scheme: string): string => scheme.toLowerCase());
}

export class VideoFile {
  readonly descriptor: media.AVFileDescriptor;
  private closed: boolean = false;
  private readonly file: fs.File;

  constructor(file: fs.File, offset: number, length: number) {
    this.file = file;
    this.descriptor = { fd: file.fd, offset, length };
  }

  close(): void {
    if (this.closed) return;

    fs.closeSync(this.file);
    this.closed = true;
  }
}

export function openVideoFile(context: ExpoModuleContext, uri: string): VideoFile {
  if (isRnohRawfileResourceUri(uri) || /^(asset|rawfile):\/\//i.test(uri)) {
    let name: string;

    try {
      name = rawResourcePathFromUri(uri);
    } catch (error) {
      throw new ExpoModuleError('ERR_VIDEO_INVALID_SOURCE', String(error));
    }

    const resources = context.uiAbilityContext.resourceManager;
    let raw: resourceManager.RawFileDescriptor;
    try {
      raw = resources.getRawFdSync(name);
    } catch (error) {
      if (!/^asset:\/\//i.test(uri) || (error as BusinessError).code !== RAW_RESOURCE_NOT_FOUND) throw error as Error;

      let fallback = name;
      try {
        fallback = rawResourcePathFromUri(uri, true);
      } catch (_) {
        // RNOH can use literal percent signs that are not valid URL escapes.
      }
      if (fallback === name) throw error as Error;

      name = fallback;
      raw = resources.getRawFdSync(name);
    }

    let file: fs.File | undefined;

    try {
      // Duplicate because ResourceManager owns the original descriptor.
      file = fs.dup(raw.fd);
    } finally {
      try {
        resources.closeRawFdSync(name);
      } catch (error) {
        if (file) fs.closeSync(file);

        throw new ExpoModuleError(
          error instanceof ExpoModuleError ? error.code : 'ERR_VIDEO_INVALID_SOURCE',
          error instanceof Error ? error.message : String(error),
          error as Object,
        );
      }
    }

    return new VideoFile(file, raw.offset, raw.length);
  }

  if (!uri.startsWith('/') && !/^file:\/\//i.test(uri)) {
    throw new ExpoModuleError('ERR_VIDEO_INVALID_SOURCE', 'Use HTTP(S), a file URI, an absolute path, or a packaged resource URI.');
  }

  const file = context.openFileForRead(normalizeUri(uri));

  try {
    const stat = fs.statSync(file.fd);
    if (!stat.isFile() || stat.size <= 0) throw new ExpoModuleError('ERR_VIDEO_INVALID_SOURCE', 'The video file is empty or is not a regular file.');

    return new VideoFile(file, 0, stat.size);
  } catch (error) {
    fs.closeSync(file);

    throw new ExpoModuleError(
      error instanceof ExpoModuleError ? error.code : 'ERR_VIDEO_INVALID_SOURCE',
      error instanceof Error ? error.message : String(error),
      error as Object,
    );
  }
}

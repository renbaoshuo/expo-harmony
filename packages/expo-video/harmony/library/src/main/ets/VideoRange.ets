/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext } from '@expo-harmony/expo-modules-core';
import metadata from 'libexpo_video_metadata.so';
import { isRemote, openVideoFile, VideoFile, VideoSource } from './VideoSource';

export type VideoRange = 'sdr' | 'hlg' | 'pq';

export async function getVideoRanges(context: ExpoModuleContext, source: VideoSource): Promise<Record<string, VideoRange>> {
  // AVSource reports the H.273 transfer characteristic for local files. Its URI API
  // cannot pass HTTP headers or inspect HLS/DASH.
  if (!source.uri || isRemote(source.uri) || !canIUse('SystemCapability.Multimedia.Media.Spliter')) return {};

  let file: VideoFile | undefined;
  try {
    context.assertActive();
    // Open independently: Media Kit consumers must not share their source descriptor.
    file = openVideoFile(context, source.uri);
    const descriptor = file.descriptor;

    return await metadata.readVideoRanges(descriptor.fd, descriptor.offset ?? 0, descriptor.length ?? 0);
  } catch (error) {
    console.warn(`ExpoVideo: video range metadata unavailable: ${String(error)}`);
    return {};
  } finally {
    try {
      file?.close();
    } catch (error) {
      console.warn(`ExpoVideo: video range source close failed: ${String(error)}`);
    }
  }
}

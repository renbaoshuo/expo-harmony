/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { RecordingOptions } from 'expo-audio';
import { createRecordingOptions as createUpstreamRecordingOptions } from 'expo-audio/src/utils/options';

// Upstream treats other platforms as web and omits native recording directories.
export function createRecordingOptions(options: RecordingOptions) {
  return { ...createUpstreamRecordingOptions(options), directory: options.directory };
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

declare module 'libexpo_video_metadata.so' {
  export interface VideoTrackMetadata {
    ranges: Record<string, 'sdr' | 'hlg' | 'pq'>;
    audioOnly: boolean;
  }

  const metadata: {
    readTrackMetadata(fd: number, offset: number, length: number): Promise<VideoTrackMetadata>;
  };

  export default metadata;
}

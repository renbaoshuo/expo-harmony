/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

declare module 'libexpo_video_metadata.so' {
  const metadata: {
    readVideoRanges(fd: number, offset: number, length: number): Promise<Record<string, 'sdr' | 'hlg' | 'pq'>>;
  };

  export default metadata;
}

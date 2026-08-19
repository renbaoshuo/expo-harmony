import { ExpoFontError } from './ExpoFontError';

export function bundledFontCachePath(directory: string, source: string, hash: string): string {
  const name = source.slice(source.lastIndexOf('/') + 1);
  const dot = name.lastIndexOf('.');
  if (dot <= 0 || dot === name.length - 1 || !/^[A-Fa-f0-9]{64}$/.test(hash)) {
    throw new ExpoFontError('ERR_FONT_BUNDLED_MANIFEST', 'Invalid bundled font cache identity.');
  }

  return `${directory}/${name.slice(0, dot)}-${hash.toLowerCase()}${name.slice(dot).toLowerCase()}`;
}

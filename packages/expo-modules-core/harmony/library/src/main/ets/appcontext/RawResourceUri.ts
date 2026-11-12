/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

const RNOH_RAWFILE_PREFIX = 'resource://RAWFILE/';

export function isRnohRawfileResourceUri(uri: string): boolean {
  return uri.startsWith(RNOH_RAWFILE_PREFIX);
}

/**
 * Resolves an already accepted package resource URI to a ResourceManager rawfile name.
 * RNOH emits literal paths for Metro assets and split bundles. Older asset and
 * bare paths can opt into URL decoding, which always applies to rawfile: URLs.
 */
export function rawResourcePathFromUri(uri: string, legacyEncoded: boolean = false): string {
  if (isRnohRawfileResourceUri(uri)) {
    return requireRawResourcePath(uri.slice(RNOH_RAWFILE_PREFIX.length));
  }

  const scheme = /^([A-Za-z][A-Za-z0-9+.-]*):/.exec(uri);
  const kind = scheme?.[1].toLowerCase();
  if (kind !== undefined && kind !== 'asset' && kind !== 'rawfile') {
    throw new Error('Unsupported packaged resource URI scheme.');
  }

  const path = uri.slice(scheme?.[0].length ?? 0).replace(/^\/+/, '');
  const name = requireRawResourcePath(kind === 'rawfile' || legacyEncoded ? decodeRawResourcePath(path) : path);

  return kind === 'asset' ? `assets/${name}` : name;
}

function decodeRawResourcePath(path: string): string {
  const encoded = path.split(/[?#]/, 1)[0];
  if (/%(?:00|2f|5c)/i.test(encoded)) {
    throw new Error('Packaged resource URI contains an escaped separator or null byte.');
  }
  return decodeURIComponent(encoded);
}

function requireRawResourcePath(path: string): string {
  if (/[\0\\]/.test(path) || path.split('/').some((part: string): boolean => part === '' || part === '.' || part === '..')) {
    throw new Error('Invalid packaged resource path.');
  }
  return path;
}

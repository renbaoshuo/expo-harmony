/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ExpoConfigWithHarmony } from '@expo-harmony/config-plugins';

import { HarmonyCliError } from '../errors';

export const HarmonyManifestPath = '/manifest';

export function harmonyDevelopmentProjectId(
  config: Pick<ExpoConfigWithHarmony, 'owner' | 'slug' | 'extra'>,
  bundleName: string
): string {
  return config.extra?.eas?.projectId || `@${config.owner || 'anonymous'}/${config.slug}/${bundleName}`;
}

export function canonicalHarmonyManifestURL(value: string): string {
  let url: URL;

  try {
    url = new URL(value);
    decodeURIComponent(url.search);
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_MANIFEST_URL',
      'Expected an absolute HTTP(S) Harmony manifest URL.',
      { cause, operation: 'development-manifest' }
    );
  }

  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.hash
    || !['/', HarmonyManifestPath, '/index.exp'].includes(url.pathname)
    || url.searchParams.getAll('platform').length !== 1 || url.searchParams.get('platform') !== 'harmony') {
    throw new HarmonyCliError(
      'ERR_HARMONY_MANIFEST_URL',
      'Expected an HTTP(S) Expo manifest URL with platform=harmony and without credentials or a fragment.',
      { operation: 'development-manifest' }
    );
  }

  url.pathname = HarmonyManifestPath;
  // Keep all other query values (including repetitions) in order. Platform has
  // one canonical position, and URLSearchParams normalizes equivalent encoding.
  url.searchParams.delete('platform');
  url.searchParams.append('platform', 'harmony');
  return url.toString();
}

export function createHarmonyLaunchLink(manifest: string): string {
  const url = new URL('expo-harmony://open');
  url.searchParams.set('url', canonicalHarmonyManifestURL(manifest));

  return url.toString();
}

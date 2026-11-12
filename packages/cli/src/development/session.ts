/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import http from 'node:http';

import type { HarmonyDevelopmentManifest } from '@expo-harmony/expo-modules-autolinking/runtime';

import { HarmonyCliError } from '../errors';
import { readProjectRuntimeAsync } from '../runtime/config';
import { resolveDevelopmentHostAsync } from './host';
import { createHarmonyLaunchLink, harmonyDevelopmentProjectId, HarmonyManifestPath } from './protocol';

export async function readDevelopmentSessionAsync(root: string, port: number, hostname?: string) {
  const project = await readProjectRuntimeAsync(root);
  const { config } = project;

  const host = await resolveDevelopmentHostAsync(root, hostname);

  const manifest = await new Promise<HarmonyDevelopmentManifest>((resolve, reject) => {
    const request = http.get({
      host: '127.0.0.1',
      port,
      path: `${HarmonyManifestPath}?platform=harmony`,
      headers: { 'host': `${host}:${port}`, 'accept': 'application/json', 'expo-platform': 'harmony', 'expo-protocol-version': '0' },
    }, (response) => {
      let body = '';

      response.setEncoding('utf8');
      response.on('data', (chunk) => {
        body += chunk;

        if (body.length > 2 * 1024 * 1024) request.destroy(new Error('Harmony manifest exceeded 2 MB.'));
      });
      response.on('error', reject);
      response.on('end', () => {
        try {
          const value = JSON.parse(body);
          if (response.statusCode !== 200 || response.headers['expo-protocol-version'] !== '0'
            || !response.headers['content-type']?.startsWith('application/json')) {
            reject(new Error(value.error?.message || 'Metro did not return an Expo development manifest with protocol version 0.'));

            return;
          }

          resolve(value);
        } catch (cause) {
          reject(new Error('Metro did not return a valid Harmony manifest.', { cause }));
        }
      });
    });

    request.setTimeout(60_000, () => request.destroy(new Error('Harmony manifest request timed out.')));
    request.on('error', reject);
  }).catch((cause) => {
    throw new HarmonyCliError(
      'ERR_HARMONY_METRO_MANIFEST',
      `Cannot use this Metro server: ${cause.message}`,
      { cause, operation: 'development-manifest' }
    );
  });

  const identity = harmonyDevelopmentProjectId(config, project.bundleName);
  if (manifest.extra?.harmony?.projectId !== identity
    || manifest.runtimeVersion !== project.runtimeVersion) {
    throw new HarmonyCliError(
      'ERR_HARMONY_METRO_PROJECT',
      'This Metro server belongs to another Harmony project.',
      { operation: 'development-manifest' }
    );
  }

  return {
    manifestUrl: manifest.extra.harmony.manifestUrl,
    launchLink: createHarmonyLaunchLink(manifest.extra.harmony.manifestUrl),
    bundleUrl: manifest.launchAsset.url,
  };
}

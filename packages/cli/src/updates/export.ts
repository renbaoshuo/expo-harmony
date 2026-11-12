/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import type { ExpoConfigWithHarmony } from '@expo-harmony/config-plugins';
import type { EnvMode } from '@expo-harmony/expo__config/internal/project-config';
import { atomicWriteJson } from '../file';
import { HarmonyCliError } from '../errors';
import { readProjectRuntimeAsync } from '../runtime/config';

export interface UpdateAsset {
  key: string;
  hash: string;
  contentType: string;
  fileExtension: string;
  embeddedAssetFilename: string;
}

export async function publishUpdatesConfigurationAsync(
  root: string,
  directory: string,
  config: ExpoConfigWithHarmony,
  runtime: string
): Promise<void> {
  const updates = { ...config.updates, runtimeVersion: runtime };
  if (updates.url) {
    const url = new URL(updates.url);
    if (!['http:', 'https:'].includes(url.protocol)) throw new HarmonyCliError('ERR_HARMONY_UPDATES_CONFIG', 'Updates URL must use HTTP or HTTPS.', { operation: 'updates-config' });
  }
  if (updates.codeSigningCertificate) {
    const certificate = await fs.readFile(path.resolve(root, updates.codeSigningCertificate), 'utf8');
    new crypto.X509Certificate(certificate);
    updates.codeSigningCertificate = certificate;
  }

  await atomicWriteJson(updates, path.join(directory, 'expo-updates/config.json'), directory);
}

export async function publishEmbeddedUpdateAsync(
  root: string,
  paths: { rawfileRoot: string; bundle: string; metadataRoot: string },
  assets: UpdateAsset[],
  mode: EnvMode
): Promise<void> {
  const project = await readProjectRuntimeAsync(root, { mode });
  const bundle = await fs.readFile(paths.bundle);
  const hash = crypto.createHash('sha256').update(Uint8Array.from(bundle)).digest('base64url');
  const directory = path.join(paths.rawfileRoot, 'expo-updates');
  const id = crypto.randomUUID();
  const manifest = {
    id, commitTime: Date.now(),
    launchAsset: { packagerHash: `bundle-${id}`, hash, type: 'hbc',
      embeddedAssetFilename: path.relative(paths.rawfileRoot, paths.bundle).split(path.sep).join('/') },
    assets: [...new Map(assets.map(asset => [asset.key, asset])).values()].map(asset => ({
      packagerHash: asset.key, hash: asset.hash, type: asset.fileExtension.replace(/^\./, ''),
      embeddedAssetFilename: asset.embeddedAssetFilename,
    })),
  };

  await publishUpdatesConfigurationAsync(root, paths.rawfileRoot, project.config, project.runtimeVersion);
  await atomicWriteJson(manifest, path.join(directory, 'manifest.json'), paths.rawfileRoot);
  await atomicWriteJson(manifest, path.join(paths.metadataRoot, 'update.json'), paths.metadataRoot);
}

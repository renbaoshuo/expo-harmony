/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import { getHarmonyProjectConfig } from '@expo-harmony/expo__config/internal/project-config';
import path from 'node:path';
import { lookup } from 'mime-types';
import { CommonOptions, parseArgs } from '../args';
import { parseCommandArgs, type Command } from '../command';
import { exportEmbedAsync } from '../exportEmbed/export';
import { HarmonyCliError } from '../errors';
import { atomicCopy, atomicWriteJson } from '../file';
import { assertSafeRelative } from '../path';
import { requireFromExpoCli } from '../expo';

export const command: Command = async (argv, io) => {
  const args = parseCommandArgs((values) => {
    const { values: options, positionals } = parseArgs({ ...CommonOptions,
      'output-dir': { type: 'string' }, 'asset-url': { type: 'string' },
      'private-key-path': { type: 'string' }, 'reset-cache': { type: 'boolean' },
    }, values);
    if (positionals.length > 1) throw new HarmonyCliError('ERR_HARMONY_EXPORT_ARGUMENTS', 'Expected at most one project directory.', { operation: 'export' });

    return { ...options, project: positionals[0], help: Boolean(options.help) };
  }, argv, io);
  if (!args) return 0;

  const { projectRoot: root, options } = args;
  const base = options['asset-url'];
  if (!base || !['http:', 'https:'].includes(new URL(base).protocol)) {
    throw new HarmonyCliError('ERR_HARMONY_EXPORT_ARGUMENTS', 'OTA export requires --asset-url with the HTTP(S) directory that will host its assets.', { operation: 'export' });
  }

  const output = path.resolve(root, options['output-dir'] ?? 'dist');
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), 'expo-harmony-update-'));

  try {
    await exportEmbedAsync(root, { outputDirectory: temporary, resetCache: options['reset-cache'] });
    const embedded = JSON.parse(await fs.readFile(path.join(temporary, 'update.json'), 'utf8'));
    const { runtimeVersion, codeSigningMetadata } = JSON.parse(
      await fs.readFile(path.join(temporary, 'embedded/expo-updates/config.json'), 'utf8')
    );
    const { exp } = getHarmonyProjectConfig(root, { isPublicConfig: true }, 'production');
    const upstream = requireFromExpoCli(root);
    const { DOM_COMPONENTS_BUNDLE_DIR } = upstream('./build/src/start/server/middleware/DomComponentsMiddleware');
    const assets = [embedded.launchAsset, ...embedded.assets].map(asset => ({
      key: asset.packagerHash, hash: asset.hash,
      contentType: asset.type === 'hbc' ? 'application/javascript' : lookup(asset.type) || 'application/octet-stream',
      fileExtension: asset.type ? '.' + asset.type : '', embeddedAssetFilename: asset.embeddedAssetFilename,
    }));
    const manifest = {
      id: embedded.id, createdAt: new Date(embedded.commitTime).toISOString(), runtimeVersion,
      launchAsset: assets[0], assets: assets.slice(1), metadata: {},
      extra: { expoClient: exp, eas: { projectId: exp.extra?.eas?.projectId },
        scopeKey: exp.originalFullName ?? `@${exp.owner ?? 'anonymous'}/${exp.slug}` },
    };
    const metadata: { path: string; ext: string }[] = [];
    for (const asset of assets) {
      const relative = `assets/${asset.hash}${asset.fileExtension}`;
      await atomicCopy(path.join(temporary, 'embedded', assertSafeRelative(asset.embeddedAssetFilename, 'Embedded update asset')), path.join(output, relative), output);
      Object.assign(asset, { url: new URL(relative, base.endsWith('/') ? base : base + '/').href });
      if (asset === manifest.launchAsset || !asset.embeddedAssetFilename.startsWith(`${DOM_COMPONENTS_BUNDLE_DIR}/`)) {
        delete asset.embeddedAssetFilename;
      }
      if (asset !== manifest.launchAsset) metadata.push({ path: relative, ext: asset.fileExtension.replace(/^\./, '') });
    }
    await atomicCopy(path.join(temporary, 'hermes_bundle.hbc.map'), path.join(output, 'bundle.hbc.map'), output);
    await atomicWriteJson({ version: 0, bundler: 'metro', fileMetadata: { harmony: {
      bundle: `assets/${manifest.launchAsset.hash}.hbc`, assets: metadata,
    } } }, path.join(output, 'metadata.json'), output);
    await atomicWriteJson(manifest, path.join(output, 'manifest.json'), output);
    if (options['private-key-path']) {
      const key = await fs.readFile(path.resolve(root, options['private-key-path']), 'utf8');
      if (crypto.createPrivateKey(key).asymmetricKeyType !== 'rsa') throw new HarmonyCliError('ERR_HARMONY_UPDATES_SIGNING', 'Expo Updates signing requires an RSA private key.', { operation: 'export' });

      const body = await fs.readFile(path.join(output, 'manifest.json'));
      const signature = crypto.sign('RSA-SHA256', Uint8Array.from(body), key).toString('base64');
      const id = codeSigningMetadata?.keyid ?? 'root';
      const { serializeDictionary } = upstream('structured-headers');

      await fs.writeFile(path.join(temporary, 'signature.txt'), serializeDictionary(new Map([
        ['sig', [signature, new Map()]], ['keyid', [id, new Map()]], ['alg', ['rsa-v1_5-sha256', new Map()]],
      ])));
      await atomicCopy(path.join(temporary, 'signature.txt'), path.join(output, 'signature.txt'), output);
    } else {
      await fs.rm(path.join(output, 'signature.txt'), { force: true });
    }
    io.log(`Exported Harmony update ${manifest.id} for runtime ${manifest.runtimeVersion} to ${output}.`);
  } finally {
    await fs.rm(temporary, { recursive: true, force: true });
  }

  return 0;
};

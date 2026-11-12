/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { lookup } from 'mime-types';
import { HarmonyCliError } from '../errors';
import { requireFromExpoCli } from '../expo';
import { assertSafeRelative, toPosixPath } from '../path';
import type { UpdateAsset } from '../updates/export';

async function collectDomAssets(directory: string, assetsDest: string): Promise<UpdateAsset[]> {
  const metadata: UpdateAsset[] = [];
  const entries = await fs.readdir(directory, { recursive: true, withFileTypes: true }).catch((error) => {
    if (error.code === 'ENOENT') return [];
    throw error;
  });
  for (const entry of entries) {
    if (!entry.isFile()) continue;

    const file = path.join(entry.parentPath, entry.name);
    const data = await fs.readFile(file);
    const ext = path.extname(file);
    const relative = toPosixPath(path.relative(assetsDest, file));
    // Public files can share a basename across directories and can change without being renamed.
    const key = crypto.createHash('sha256').update(relative).update('\0').update(data).digest('hex');
    metadata.push({ key, hash: crypto.createHash('sha256').update(data).digest('base64url'),
      contentType: lookup(ext) || 'application/octet-stream', fileExtension: ext,
      embeddedAssetFilename: relative });
  }
  return metadata;
}

async function main(): Promise<void> {
  const [root, serialized, destination] = process.argv.slice(2);
  const require = requireFromExpoCli(root);

  const options = JSON.parse(serialized);
  require('./build/src/utils/nodeEnv').setNodeEnv('production');
  require('./build/src/utils/nodeEnv').loadEnvFiles(root);
  const { DOM_COMPONENTS_BUNDLE_DIR } = require('./build/src/start/server/middleware/DomComponentsMiddleware');
  const { copyPublicFolderAsync, getPublicFolderPath } = require('./build/src/export/publicFolder');
  const domDirectory = path.join(options.assetsDest, DOM_COMPONENTS_BUNDLE_DIR);
  if (options.update) {
    const directory = path.join(path.dirname(destination), 'export');
    await require('./build/src/export/exportApp').exportAppAsync(root, {
      platforms: ['harmony'], outputDir: directory, clear: options.resetCache,
      dev: false, sourceMaps: true, minify: false, bytecode: false,
    });
    const metadata = JSON.parse(await fs.readFile(path.join(directory, 'metadata.json'), 'utf8')).fileMetadata?.harmony;
    if (typeof metadata?.bundle !== 'string' || !Array.isArray(metadata.assets)) {
      throw new HarmonyCliError('ERR_HARMONY_EXPORT_METADATA', 'Expo did not export Harmony bundle and asset metadata.', { operation: 'export' });
    }

    const assets: UpdateAsset[] = [];
    const domPrefix = `${DOM_COMPONENTS_BUNDLE_DIR}/`;
    const hasDom = metadata.assets.some(asset => toPosixPath(asset.path).startsWith(domPrefix));
    if (hasDom) await copyPublicFolderAsync(getPublicFolderPath(root), domDirectory);
    for (const asset of metadata.assets) {
      const assetPath = toPosixPath(asset.path);
      const source = path.join(directory, assertSafeRelative(assetPath, 'Expo update asset'));
      const domAsset = assetPath.startsWith(domPrefix);
      const key = path.posix.basename(assetPath, path.posix.extname(assetPath));
      const relative = domAsset ? assetPath : `assets/${key}.${asset.ext}`;
      const target = path.join(options.assetsDest, assertSafeRelative(relative, 'Harmony update asset'));

      await fs.mkdir(path.dirname(target), { recursive: true });
      await fs.copyFile(source, target);
      if (domAsset) continue;

      const data = await fs.readFile(target);
      assets.push({ key, hash: crypto.createHash('sha256').update(Uint8Array.from(data)).digest('base64url'),
        contentType: lookup(asset.ext) || 'application/octet-stream', fileExtension: '.' + asset.ext,
        embeddedAssetFilename: relative });
    }
    if (hasDom) assets.push(...await collectDomAssets(domDirectory, options.assetsDest));
    await require('@expo/metro/metro/shared/output/bundle').save({
      code: await fs.readFile(path.join(directory, assertSafeRelative(toPosixPath(metadata.bundle), 'Expo update bundle')), 'utf8'),
      map: await fs.readFile(path.join(directory, assertSafeRelative(toPosixPath(metadata.bundle + '.map'), 'Expo update source map')), 'utf8'),
    }, options, console.log);
    await fs.writeFile(destination, JSON.stringify(assets));

    return;
  }

  const { bundle, assets, files } = await require('./build/src/export/embed/exportEmbedAsync').exportEmbedBundleAndAssetsAsync(root, options);
  const { getAssetLocalPath } = require('./build/src/export/metroAssetLocalPath');
  const metadata: UpdateAsset[] = [];

  for (const asset of assets) {
    if (!Array.isArray(asset.fileHashes) || asset.fileHashes.length !== asset.files.length) {
      throw new HarmonyCliError('ERR_HARMONY_EXPORT_ASSETS', 'Metro assets must include expo-asset fileHashes.', { operation: 'export' });
    }
    for (let index = 0; index < asset.files.length; index++) {
      const data = await fs.readFile(asset.files[index]);
      metadata.push({ key: asset.fileHashes[index], hash: crypto.createHash('sha256').update(Uint8Array.from(data)).digest('base64url'),
        contentType: lookup(asset.type) || 'application/octet-stream', fileExtension: '.' + asset.type,
        embeddedAssetFilename: getAssetLocalPath(asset, { platform: 'harmony', scale: asset.scales[index] }) });
    }
  }

  await fs.mkdir(path.dirname(options.bundleOutput), { recursive: true });
  await Promise.all([
    require('@expo/metro/metro/shared/output/bundle').save(bundle, options, console.log),
    require('./build/src/export/persistMetroAssets').persistMetroAssetsAsync(root, assets, { platform: 'harmony', outputDirectory: options.assetsDest }),
  ]);
  if (files.size > 0) {
    await require('./build/src/export/saveAssets').persistMetroFilesAsync(files, options.assetsDest);
    await copyPublicFolderAsync(getPublicFolderPath(root), domDirectory);
    metadata.push(...await collectDomAssets(domDirectory, options.assetsDest));
  }
  await fs.writeFile(destination, JSON.stringify(metadata));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { HarmonyCliError } from '../errors';

async function main(): Promise<void> {
  const [root, serialized, destination] = process.argv.slice(2);
  const project = createRequire(path.join(root, 'package.json'));
  const expo = createRequire(project.resolve('expo/package.json'));
  const require = createRequire(expo.resolve('@expo/cli/package.json'));

  const options = JSON.parse(serialized);
  require('./build/src/utils/nodeEnv').setNodeEnv('production');
  require('./build/src/utils/nodeEnv').loadEnvFiles(root);
  if (options.update) {
    const directory = path.join(path.dirname(destination), 'export');
    await require('./build/src/export/exportApp').exportAppAsync(root, {
      platforms: ['harmony'], outputDir: directory, clear: options.resetCache,
      dev: false, sourceMaps: true, minify: false, bytecode: false,
    });
    const metadata = JSON.parse(await fs.readFile(path.join(directory, 'metadata.json'), 'utf8')).fileMetadata.harmony;
    const mime = require('mime-types');
    const assets = [];
    for (const asset of metadata.assets) {
      const source = path.join(directory, asset.path);
      const data = await fs.readFile(source);
      const key = path.basename(asset.path, path.extname(asset.path));
      const relative = `assets/${key}.${asset.ext}`;
      await fs.mkdir(path.join(options.assetsDest, 'assets'), { recursive: true });
      await fs.copyFile(source, path.join(options.assetsDest, relative));
      assets.push({ key, hash: crypto.createHash('sha256').update(Uint8Array.from(data)).digest('base64url'),
        contentType: mime.lookup(asset.ext) || 'application/octet-stream', fileExtension: '.' + asset.ext,
        embeddedAssetFilename: relative });
    }
    await require('@expo/metro/metro/shared/output/bundle').save({
      code: await fs.readFile(path.join(directory, metadata.bundle), 'utf8'),
      map: await fs.readFile(path.join(directory, metadata.bundle + '.map'), 'utf8'),
    }, options, console.log);
    await fs.writeFile(destination, JSON.stringify(assets));

    return;
  }

  const { bundle, assets, files } = await require('./build/src/export/embed/exportEmbedAsync').exportEmbedBundleAndAssetsAsync(root, options);
  const { getAssetLocalPath } = require('./build/src/export/metroAssetLocalPath');
  const mime = require('mime-types');
  const metadata: Record<string, unknown>[] = [];

  for (const asset of assets) {
    if (!Array.isArray(asset.fileHashes) || asset.fileHashes.length !== asset.files.length) {
      throw new HarmonyCliError('ERR_HARMONY_EXPORT_ASSETS', 'Metro assets must include expo-asset fileHashes.', { operation: 'export' });
    }
    for (let index = 0; index < asset.files.length; index++) {
      const data = await fs.readFile(asset.files[index]);
      metadata.push({ key: asset.fileHashes[index], hash: crypto.createHash('sha256').update(Uint8Array.from(data)).digest('base64url'),
        contentType: mime.lookup(asset.type) || 'application/octet-stream', fileExtension: '.' + asset.type,
        embeddedAssetFilename: getAssetLocalPath(asset, { platform: 'harmony', scale: asset.scales[index] }) });
    }
  }

  await fs.mkdir(path.dirname(options.bundleOutput), { recursive: true });
  await Promise.all([
    require('@expo/metro/metro/shared/output/bundle').save(bundle, options, console.log),
    require('./build/src/export/persistMetroAssets').persistMetroAssetsAsync(root, assets, { platform: 'harmony', outputDirectory: options.assetsDest }),
  ]);
  if (files.size > 0) {
    const { copyPublicFolderAsync, getPublicFolderPath } = require('./build/src/export/publicFolder');
    const { DOM_COMPONENTS_BUNDLE_DIR } = require('./build/src/start/server/middleware/DomComponentsMiddleware');
    await require('./build/src/export/saveAssets').persistMetroFilesAsync(files, options.assetsDest);
    await copyPublicFolderAsync(getPublicFolderPath(root), path.join(options.assetsDest, DOM_COMPONENTS_BUNDLE_DIR));
  }
  await fs.writeFile(destination, JSON.stringify(metadata));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

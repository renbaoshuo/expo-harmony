/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { applyPatchFile } from '@expo-harmony/expo-module-scripts/patch';

const root = path.resolve(import.meta.dirname, '..');
const routerRoot = path.resolve(root, '../..');
const output = path.join(root, 'build');

async function exists(file) {
  return fs.access(file).then(() => true, (error) => {
    if (error.code === 'ENOENT') return false;
    throw error;
  });
}

async function buildScreens() {
  const require = createRequire(path.join(routerRoot, 'package.json'));
  const name = '@react-native-ohos/react-native-screens';
  const vendorManifest = require.resolve(`${name}/package.json`);
  const { version } = require(vendorManifest);
  const { harmony, devDependencies } = require('./package.json');
  if (version !== harmony.modules[name].version) {
    throw new Error(`The Screens patches target ${harmony.modules[name].version}, but ${version} is installed.`);
  }
  const vendor = path.dirname(vendorManifest);
  const tar = await import('tar');

  const stage = await fs.mkdtemp(path.join(root, '.build-'));
  const prepared = path.join(stage, 'screens');
  const har = path.join(stage, 'package');
  const backup = path.join(stage, 'previous');
  try {
    await fs.mkdir(path.join(prepared, 'harmony'), { recursive: true });
    await fs.cp(path.join(vendor, 'src'), path.join(prepared, 'src'), { recursive: true });
    await fs.copyFile(path.join(vendor, 'LICENSE'), path.join(prepared, 'LICENSE'));
    await tar.x({ cwd: stage, file: path.join(vendor, 'harmony/screens.har'), strict: true });
    const patchName = `react-native-ohos__react-native-screens+${version}`;
    await applyPatchFile({ root: prepared, patchFile: path.join(root, 'patches', `${patchName}.js.patch`) });
    await applyPatchFile({ root: har, patchFile: path.join(root, 'patches', `${patchName}.har.patch`) });

    const manifestPath = path.join(har, 'oh-package.json5');
    const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
    manifest.dependencies['@rnoh/react-native-openharmony'] = devDependencies['@react-native-oh/react-native-harmony'];
    await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
    await fs.rm(path.join(har, 'oh-package-lock.json5'), { force: true });
    await tar.c({ cwd: stage, file: path.join(prepared, 'harmony/screens.har'), gzip: true, portable: true, noMtime: true }, ['package']);
    await fs.writeFile(path.join(prepared, 'package.json'), JSON.stringify({
      name, version, harmony: { alias: 'react-native-screens' },
    }, null, 2) + '\n');

    const hadOutput = await exists(output);
    if (hadOutput) await fs.rename(output, backup);
    try {
      await fs.rename(prepared, output);
    } catch (error) {
      if (hadOutput) await fs.rename(backup, output);
      throw error;
    }
  } finally {
    await fs.rm(stage, { recursive: true, force: true });
  }
}

await buildScreens();

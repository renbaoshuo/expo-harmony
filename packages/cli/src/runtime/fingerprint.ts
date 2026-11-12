/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import type { ExpoConfigWithHarmony } from '@expo-harmony/config-plugins';
import { getBuildPropertiesInputFiles } from '@expo-harmony/expo-build-properties/internal';
import { getHarmonyProjectConfig, type EnvMode } from '@expo-harmony/expo__config/internal/project-config';
import type { Fingerprint, HashSource } from '@expo/fingerprint';
import { createNativeModuleContracts, GeneratedNativeSources, prepareRuntimeModulesAsync } from '@expo-harmony/expo-modules-autolinking';
import type { HarmonyRuntimeContract } from '@expo-harmony/expo-modules-autolinking/runtime';
import { escape } from 'minimatch';
import { HarmonyCliError } from '../errors';
import { readExpoConfigInChildAsync } from '../expo';
import { resolveHarmonyBuildPlanIfPresentAsync } from '../native/project';
import { createHarmonyToolchainEnv } from '../native/toolchain';
import { assertSafeRelative } from '../path';

export async function fingerprintHarmonyAsync(
  root: string,
  runtimeRoot: string,
  modules?: Readonly<HarmonyRuntimeContract['modules']>,
  config?: ExpoConfigWithHarmony,
  mode?: EnvMode
) {
  if (!modules) {
    const result = await prepareRuntimeModulesAsync({
      projectRoot: root,
      env: createHarmonyToolchainEnv(),
      ...(mode === 'production' ? { buildType: 'release' } : {}),
    });
    if (!result.valid) throw new HarmonyCliError('ERR_HARMONY_FINGERPRINT', 'Build and verify Harmony native modules before calculating the runtime fingerprint.', { operation: 'fingerprint' });

    modules = createNativeModuleContracts(result.modules);
  }

  const project = createRequire(path.join(root, 'package.json'));
  const prebuildPackage = '@expo-harmony/prebuild-config/package.json';
  let prebuildManifest: string;
  try {
    prebuildManifest = project.resolve(prebuildPackage);
  } catch (cause) {
    if (cause.code !== 'MODULE_NOT_FOUND') throw cause;
    prebuildManifest = require.resolve(prebuildPackage);
  }
  const prebuild = createRequire(prebuildManifest);
  const exp: ExpoConfigWithHarmony = config ?? getHarmonyProjectConfig(root, {
    skipSDKVersionRequirement: true,
    isModdedConfig: true,
  }, mode).exp;
  const relative = (file: string) => path.relative(root, file).split(path.sep).join('/');
  const plan = await resolveHarmonyBuildPlanIfPresentAsync(root);
  const generated = [
    ...GeneratedNativeSources.files.map(file => `**/harmony/${file}`),
    ...GeneratedNativeSources.directories.map(directory => `**/harmony/${directory}/**`),
  ];
  const previous = plan?.exportPaths.manifest ?? path.join(root, '.expo/harmony/export-manifest.json');

  if (fs.existsSync(previous)) {
    const manifest = JSON.parse(fs.readFileSync(previous, 'utf8'));
    const rawfiles = plan
      ? escape(relative(plan.exportPaths.rawfileRoot))
      : '**/harmony/**/src/main/resources/rawfile';
    for (const asset of manifest.assets) {
      generated.push(`${rawfiles}/${escape(assertSafeRelative(asset.path, 'Export manifest'))}`);
    }
  }

  const sources: HashSource[] = [{ type: 'contents', id: 'harmonyAutolinking', contents: JSON.stringify(modules), reasons: ['harmonyAutolinking'] }];

  // Only the selected RNOH archive contributes to this build. Upstream hashes
  // it as a file using the same algorithm and transforms as all other sources.
  const runtimeHar = path.join(runtimeRoot, 'react_native_openharmony.har');
  const selectedArchive = fs.existsSync(runtimeHar) ? fs.realpathSync(runtimeHar) : undefined;
  for (const file of fs.readdirSync(runtimeRoot)) {
    const archive = path.join(runtimeRoot, file);
    if (archive !== runtimeHar && archive !== selectedArchive && path.extname(file) === '.har') {
      generated.push(escape(relative(archive)));
    }
  }
  if (selectedArchive !== undefined && selectedArchive !== runtimeHar) {
    // Directory hashing skips symlinks. Include the selected archive target.
    sources.push({ type: 'file', filePath: relative(selectedArchive), reasons: ['harmonyNativeToolchain'] });
  }
  sources.push({ type: 'dir', filePath: relative(runtimeRoot), reasons: ['harmonyNativeToolchain'] });
  const toolchain = prebuild('./package.json').dependencies ?? {};
  const packages = Object.keys(toolchain).filter(name => name.startsWith('@expo-harmony/'));
  for (const file of [prebuildManifest, ...packages.map(name => prebuild.resolve(`${name}/package.json`))]) {
    sources.push({ type: 'dir', filePath: relative(path.dirname(file)), reasons: ['harmonyNativeToolchain'] });
  }

  const icon = exp.harmony?.icon;
  if (typeof icon === 'string' && !/^https?:\/\//iu.test(icon)) {
    const file = path.resolve(root, icon);
    if (fs.statSync(file, { throwIfNoEntry: false })?.isFile()) {
      sources.push({ type: 'file', filePath: relative(file), reasons: ['harmonyIcon'] });
    }
  }

  for (const file of getBuildPropertiesInputFiles(exp)) {
    sources.push({
      type: 'file', filePath: relative(path.resolve(root, file)), reasons: ['harmonyObfuscationRules'],
    });
  }

  if (fs.existsSync(path.join(root, 'harmony'))) sources.push({ type: 'dir', filePath: 'harmony', reasons: ['harmonyNativeProject'] });

  return readExpoConfigInChildAsync<Fingerprint>(root, 'fingerprint', mode, {
    platforms: [], extraSources: sources,
    ignorePaths: [
      ...generated,
      '**/harmony/**/build/**', '**/harmony/**/.hvigor/**', '**/harmony/**/.cxx/**', '**/harmony/**/oh_modules/**',
      '**/harmony/**/oh-package-lock.json5', '**/harmony/**/local.properties', '**/harmony/**/native-inputs.cmake',
      '**/harmony/**/expo-harmony-runtime.json', '**/harmony/**/expo-updates/**',
      '**/harmony/**/hermes_bundle.hbc', '**/harmony/**/hermes_bundle.hbc.*', '**/harmony/**/.expo-harmony/**',
      '**/*.hap', '**/.git/**',
      ...(selectedArchive === undefined ? [] : [`!${escape(relative(selectedArchive))}`]),
    ],
  });
}

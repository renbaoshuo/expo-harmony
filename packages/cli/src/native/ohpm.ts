/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import path from 'node:path';
import { localOhpmDependenciesFromManifest, ManifestArtifact, resolveBundledRnohRuntime } from '@expo-harmony/expo-modules-autolinking';
import JSON5 from 'json5';

import { HarmonyCliError } from '../errors';
import { toPosixPath } from '../path';

const RnohOhpmPackage = '@rnoh/react-native-openharmony';

// Keep generated manifests portable; only OHPM's ignored lock/cache stores local HAR paths.
export function prepareLocalOhpmOverrides(root: string, harmony: string): () => void {
  const file = path.join(harmony, 'oh-package.json5');
  const source = fs.readFileSync(file, 'utf8');
  const config = JSON5.parse(source);
  const manifest = path.join(root, ManifestArtifact);
  const overrides = fs.existsSync(manifest)
    ? { ...localOhpmDependenciesFromManifest(JSON.parse(fs.readFileSync(manifest, 'utf8'))) }
    : {};
  const rnoh = config.overrides?.[RnohOhpmPackage] ?? config.dependencies?.[RnohOhpmPackage];
  if (typeof rnoh === 'string' && /^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/u.test(rnoh)) {
    const directory = resolveBundledRnohRuntime(root);
    const { version } = JSON.parse(fs.readFileSync(path.join(directory, 'package.json'), 'utf8'));
    if (version === rnoh) {
      const runtime = path.join(directory, 'react_native_openharmony.har');
      if (!fs.existsSync(runtime)) {
        throw new HarmonyCliError('ERR_HARMONY_OHPM_RUNTIME', `Cannot find the bundled RNOH HAR at ${runtime}.`, { operation: 'ohpm-install' });
      }

      overrides[RnohOhpmPackage] = `file:${toPosixPath(runtime)}`;
    }
  }
  if (Object.keys(overrides).length === 0) return () => {};

  fs.writeFileSync(file, JSON5.stringify({ ...config, overrides: { ...config.overrides, ...overrides } }, null, 2) + '\n');

  return () => fs.writeFileSync(file, source);
}

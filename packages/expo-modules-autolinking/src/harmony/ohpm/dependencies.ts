/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import JSON5 from 'json5';
import * as tar from 'tar';

import { resolveRnohMetadata } from '../rnoh/packageMetadata';
import { HarmonyAutolinkingError } from '../../errors';
import type { ModuleDescriptor } from '../../types';
import { normalizeSlashes } from '../../utilities/values';

function collectOhpmDeps(descriptors) {
  const dependencies = new Map();

  for (const descriptor of descriptors) {
    if (!descriptor.arkTs) continue;
    dependencies.set(descriptor.arkTs.ohPackageName, {
      descriptor,
      mapping: {
        harPath: descriptor.arkTs.harPath,
        ohPackageName: descriptor.arkTs.ohPackageName,
      },
    });
  }

  for (const descriptor of descriptors.filter(item => item.rnoh.harPaths.length > 0)) {
    for (const mapping of resolveRnohMetadata(descriptor).harMappings) {
      dependencies.set(mapping.ohPackageName, { descriptor, mapping });
    }
  }

  return [...dependencies.values()].sort((left, right) => {
    return left.mapping.ohPackageName.localeCompare(right.mapping.ohPackageName, 'en');
  });
}

function resolveHarPath(descriptor: Pick<ModuleDescriptor, 'arkTs' | 'packageRoot' | 'packageLinkPath'>, harPath: string): string {
  if (harPath === descriptor.arkTs?.harPath && descriptor.arkTs.builtHarPath) {
    return descriptor.arkTs.builtHarPath;
  }

  return path.resolve(descriptor.packageLinkPath || descriptor.packageRoot, ...harPath.split('/'));
}

function readOhpmVersion(file: string): string {
  let source: string;

  try {
    if (fs.statSync(file).isDirectory()) {
      source = fs.readFileSync(path.join(file, 'oh-package.json5'), 'utf8');
    } else {
      const manifests: string[] = [];

      tar.t({
        file,
        sync: true,
        strict: true,
        onentry(entry) {
          if (entry.type !== 'File'
            || !['package/oh-package.json5', 'oh-package.json5'].includes(entry.path)) return;

          const chunks: Buffer[] = [];
          entry.on('data', chunk => chunks.push(chunk));
          entry.on('end', () => manifests.push(Buffer.concat(chunks).toString('utf8')));
        },
      });

      if (manifests.length !== 1) {
        throw new HarmonyAutolinkingError('INVALID_METADATA', `Expected one OHPM package manifest in ${file}.`, { stage: 'ohpm-dependencies' });
      }

      source = manifests[0];
    }
  } catch (cause) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `Cannot read the OHPM dependency manifest at ${file}.`, { cause, stage: 'ohpm-dependencies' });
  }

  let manifest;

  try {
    manifest = JSON5.parse(source);
  } catch (cause) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `Invalid OHPM dependency manifest at ${file}.`, { cause, stage: 'ohpm-dependencies' });
  }

  const version = manifest?.version;

  if (typeof version !== 'string' || !version.trim()) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `The OHPM dependency at ${file} must declare a version.`, { stage: 'ohpm-dependencies' });
  }

  return version;
}

function resolveOhpmSpecifier(descriptor, mapping): string {
  return mapping.version ?? readOhpmVersion(resolveHarPath(descriptor, mapping.harPath));
}

function resolveRnohRuntimeFromCore(coreManifest: string): string {
  const require = createRequire(coreManifest);
  return path.dirname(require.resolve('@react-native-oh/react-native-harmony/package.json'));
}

function resolveBundledRnohRuntime(projectRoot: string): string {
  const require = createRequire(path.join(projectRoot, 'package.json'));
  return resolveRnohRuntimeFromCore(require.resolve('@expo-harmony/expo-modules-core/package.json'));
}

function resolveBuildOhpmDependencies(modules: readonly ModuleDescriptor[]) {
  const overrides: Record<string, string> = Object.create(null);
  const versions: Record<string, string> = Object.create(null);

  for (const { descriptor, mapping } of collectOhpmDeps(modules)) {
    versions[mapping.ohPackageName] = resolveOhpmSpecifier(descriptor, mapping);
    overrides[mapping.ohPackageName] = `file:${normalizeSlashes(resolveHarPath(descriptor, mapping.harPath))}`;
  }

  // Compile against the same RNOH runtime as Core, including npm-bundled HARs.
  const core = modules.find(module => module.packageName === '@expo-harmony/expo-modules-core');
  if (core) {
    const runtime = path.join(resolveRnohRuntimeFromCore(path.join(core.packageRoot, 'package.json')), 'react_native_openharmony.har');

    versions['@rnoh/react-native-openharmony'] = readOhpmVersion(runtime);
    overrides['@rnoh/react-native-openharmony'] = `file:${normalizeSlashes(runtime)}`;
  }

  return { overrides, versions };
}

export {
  collectOhpmDeps,
  readOhpmVersion,
  resolveBuildOhpmDependencies,
  resolveBundledRnohRuntime,
  resolveHarPath,
  resolveOhpmSpecifier,
};

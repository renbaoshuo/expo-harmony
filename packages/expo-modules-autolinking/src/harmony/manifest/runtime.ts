/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

import * as tar from 'tar';

import type { HarmonyNativeModule } from '../../../runtime';
import { HarmonyAutolinkingError } from '../../errors';
import type { ModuleDescriptor } from '../../types';
import { readInlineModuleContent } from '../inlineModules';
import { resolveHarPath } from '../ohpm/dependencies';

function digest(file: string): string {
  if (!fs.statSync(file).isFile()) {
    throw new HarmonyAutolinkingError('RUNTIME_ARTIFACT', 'Native runtime artifacts must be regular files.', { stage: 'runtime-contract' });
  }

  const entries: string[] = [];
  const names = new Set<string>();

  tar.t({
    file,
    sync: true,
    strict: true,
    onentry(entry) {
      if (entry.type === 'Directory') return;
      if (entry.type !== 'File' || names.has(entry.path)) {
        throw new HarmonyAutolinkingError(
          'RUNTIME_ARTIFACT',
          'Native HARs must contain unique regular files.',
          { stage: 'runtime-contract' }
        );
      }

      names.add(entry.path);

      const hash = crypto.createHash('sha256');
      if (entry.path === 'package/ResourceTable.txt') {
        // Hvigor assigns relocatable resource IDs from its local build cache.
        // Keep exported resource names/types in the contract, without treating
        // a clean build's different numeric assignments as a native API change.
        const chunks: Buffer[] = [];
        entry.on('data', chunk => chunks.push(chunk));
        entry.on('end', () => {
          hash.update(Buffer.concat(chunks).toString('utf8').replace(/\b0x[0-9a-f]{8}\b/giu, '0x00000000'));
          entries.push(`${entry.path}\0${hash.digest('hex')}`);
        });
      } else {
        entry.on('data', chunk => hash.update(chunk));
        entry.on('end', () => entries.push(`${entry.path}\0${hash.digest('hex')}`));
      }
    },
  });

  if (entries.length === 0) {
    throw new HarmonyAutolinkingError('RUNTIME_ARTIFACT', 'Native HARs must not be empty.', { stage: 'runtime-contract' });
  }

  // Archive timestamps, owners, and entry order are not native runtime inputs.
  return crypto.createHash('sha256').update(entries.sort().join('\0')).digest('hex');
}

function sourceDigest(root: string): string {
  const hash = crypto.createHash('sha256');
  const ignored = new Set(['build', '.hvigor', '.cxx', 'oh_modules', 'node_modules', '.git', 'oh-package-lock.json5']);
  const visit = (directory: string) => {
    const entries = fs.readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => left.name < right.name ? -1 : 1);

    for (const entry of entries) {
      if (ignored.has(entry.name)) continue;

      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(file);
      else if (entry.isFile() && /\.(ets|ts|cpp|c|h|hpp|cmake|json|json5|so|a)$|CMakeLists\.txt$/.test(entry.name)) {
        hash.update(path.relative(root, file).split(path.sep).join('/'));
        hash.update('\0');
        hash.update(Uint8Array.from(fs.readFileSync(file)));
        hash.update('\0');
      }
    }
  };

  visit(root);

  return hash.digest('hex');
}

function inlineSourceDigest(module: ModuleDescriptor): string {
  const hash = crypto.createHash('sha256');
  const files = [...module.inlineModules.files]
    .sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0);

  for (const file of files) {
    hash.update(file.path).update('\0').update(Uint8Array.from(readInlineModuleContent(module.packageRoot, file))).update('\0');
  }

  return hash.digest('hex');
}

export function createNativeModuleContracts(modules: readonly ModuleDescriptor[]): HarmonyNativeModule[] {
  return modules.map((module) => {
    const files = new Set([...module.rnoh.harPaths, ...(module.arkTs ? [module.arkTs.harPath] : [])]
      .map(file => resolveHarPath(module, file)));

    let artifacts: string[];

    try {
      artifacts = [...new Set([...files].map(digest))];
      if (module.inlineModules) artifacts.push(inlineSourceDigest(module));
      if (module.source === 'nativeModulesDir') artifacts.push(sourceDigest(path.join(module.packageRoot, 'harmony')));
      artifacts.sort();
    } catch (cause) {
      throw new HarmonyAutolinkingError(
        'RUNTIME_ARTIFACT',
        module.inlineModules
          ? `Inline sources for ${module.packageName} are missing or unreadable. Relink the app before requesting its runtime contract.`
          : `Build the native HAR for ${module.packageName} before publishing or requesting its runtime contract.`,
        { cause, packageName: module.packageName, stage: 'runtime-contract' }
      );
    }

    const registrations = [
      ...module.expo.rootViewComponents.map(name => `view:${name}`),
      ...module.expo.appLifecycleSubscribers.map(name => `app:${name}`),
      ...module.expo.abilityLifecycleSubscribers.map(name => `ability:${name}`),
      ...module.expo.reactNativeHostHandlers.map(name => `host:${name}`),
      ...module.expo.reactActivityHandlers.map(name => `activity:${name}`),
      ...module.expo.runtimeBindings.map(name => `binding:${name}`),
      ...['etsPackageClassName', 'etsPackageImport', 'cppPackageClassName', 'cmakeLibraryTargetName']
        .flatMap(field => module.rnoh[field] ? [`${field}:${module.rnoh[field]}`] : []),
      ...(!module.rnoh.etsPackageScope || module.rnoh.etsPackageScope === 'shared'
        ? [] : [`etsPackageScope:${module.rnoh.etsPackageScope}`]),
    ];

    return {
      packageName: module.packageName,
      packageVersion: module.packageVersion,
      modules: [...module.harmony.modules].sort(),
      services: [...module.harmony.services].sort(),
      registrations: registrations.sort(),
      artifacts,
    };
  }).sort((left, right) => left.packageName < right.packageName ? -1 : left.packageName > right.packageName ? 1 : 0);
}

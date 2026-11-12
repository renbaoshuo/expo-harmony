/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import path from 'node:path';

import {
  HarmonyPaths, registerHarmonyConfigPlugin, type HarmonyConfigPluginOwnership, type HarmonyModConfig,
} from '@expo-harmony/config-plugins';
import { getHarmonyConfigPlugins } from '@expo-harmony/config-plugins/internal';

import { resolveHarmonyBuildPath } from './buildDescriptor';
import { HarmonyPrebuildError } from './errors';
import { CngManifestPath, validateCngManifest, type CngManifest } from './manifest';

async function readPreviousCngManifestAsync(root) {
  const file = resolveHarmonyBuildPath(root, CngManifestPath);

  let manifest;

  try {
    manifest = JSON.parse(await fs.promises.readFile(file, 'utf8'));
  } catch (cause) {
    if (cause.code === 'ENOENT') return null;

    throw new HarmonyPrebuildError(
      cause.code || 'ERR_HARMONY_MANIFEST_INVALID',
      cause.message || `Cannot read Harmony CNG manifest ${file}.`,
      { cause, file, operation: 'read-manifest' }
    );
  }

  return validateCngManifest(manifest, { file });
}

function findStaleConfigPlugins(manifest, plugins) {
  const owners = new Set(plugins.map(plugin => plugin.owner));

  return (manifest?.configPlugins || []).filter(plugin => !owners.has(plugin.owner));
}

function findDeferredPluginFiles(
  manifest: CngManifest | null, current: readonly HarmonyConfigPluginOwnership[]
): CngManifest['managedFiles'] {
  if (!manifest) return [];

  const pending = new Set(current.filter(plugin => plugin.files === undefined).map(plugin => plugin.owner));
  const previous = new Map<string, Set<string>>();
  for (const plugin of manifest.configPlugins) {
    if (plugin.files && pending.has(plugin.owner)) {
      previous.set(plugin.owner, new Set(plugin.files.map(file => `harmony/${file}`)));
    }
  }
  return manifest.managedFiles.filter(entry => previous.get(entry.owner)?.has(entry.path));
}

async function removeManagedFileAsync(root: string, relative: string) {
  const directory = await HarmonyPaths.resolveHarmonyPath(root, path.dirname(relative));
  const target = path.join(directory, path.basename(relative));

  let stat;

  try {
    stat = await fs.promises.lstat(target);
  } catch (cause) {
    if (cause.code === 'ENOENT') return;

    throw new HarmonyPrebuildError(
      cause.code || 'ERR_HARMONY_MANIFEST_INVALID',
      cause.message || `Cannot inspect stale plugin output ${target}.`,
      { cause, file: target, operation: 'remove-stale-plugin-output' }
    );
  }

  if (stat.isDirectory()) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      `A stale config plugin claims a managed directory instead of a file: ${relative}`,
      { file: target, operation: 'remove-stale-plugin-output' }
    );
  }

  await fs.promises.rm(target, { force: true });
}

async function removeStalePluginFilesAsync(
  root,
  manifest,
  plugins,
  current: readonly HarmonyConfigPluginOwnership[] = [],
  dryRun = false
) {
  const owners = new Set(plugins.map(plugin => plugin.owner));
  const active = new Map(current.map(plugin => [plugin.owner, plugin]));
  const obsolete = new Map<string, Set<string>>();
  for (const previous of manifest?.configPlugins || []) {
    const next = active.get(previous.owner);
    if (next?.files === undefined || previous.files === undefined) continue;

    obsolete.set(previous.owner, new Set(
      previous.files.filter(file => !next.files.includes(file)).map(file => `harmony/${file}`)
    ));
  }

  // A path can transfer to another plugin; do not remove its newly written output.
  const claimed = new Set(current.flatMap(plugin => (plugin.files || []).map(file => `harmony/${file}`)));
  const files = (manifest?.managedFiles || []).filter(entry => entry.path.startsWith('harmony/') && !claimed.has(entry.path)
    && (owners.has(entry.owner) || obsolete.get(entry.owner)?.has(entry.path)));

  for (const entry of dryRun ? [] : files) {
    await removeManagedFileAsync(root, entry.path);
  }

  // Keep missing files in the result so a retry also removes their declarations.
  return files.map(entry => entry.path);
}

async function reconcileDeferredPluginFilesAsync(mod: HarmonyModConfig<null>): Promise<CngManifest['managedFiles']> {
  const previous: Readonly<CngManifest['managedFiles']> = mod._internal?.harmonyDeferredPluginFiles ?? [];
  if (!previous.length) return [];

  const plugins = getHarmonyConfigPlugins(mod);
  const active = new Map(plugins.map(plugin => [plugin.owner, plugin]));
  const claimed = new Set(plugins.flatMap(plugin => (plugin.files || []).map(file => `harmony/${file}`)));
  for (const entry of mod._internal?.harmonyManagedFiles ?? []) claimed.add(entry.path);

  const retained: CngManifest['managedFiles'] = [];
  const pending = new Map<string, string[]>();
  for (const entry of previous) {
    if (claimed.has(entry.path)) continue;
    const plugin = active.get(entry.owner);
    if (!plugin || plugin.files !== undefined) {
      await removeManagedFileAsync(mod.modRequest.projectRoot, entry.path);
      continue;
    }

    // Unresolved ownership keeps the prior hash so edits remain visible to --check.
    retained.push(entry);
    const relative = path.posix.relative('harmony', entry.path);
    const files = pending.get(entry.owner);
    if (files) files.push(relative);
    else pending.set(entry.owner, [relative]);
  }
  for (const [owner, files] of pending) registerHarmonyConfigPlugin(mod, owner, { ...active.get(owner), files });

  return retained;
}

function removeStaleExtensionAbilities(module, file: string, files: readonly string[]) {
  if (!Array.isArray(module.extensionAbilities) || files.length === 0) return module;

  const stale = new Set(files);
  const directory = path.posix.dirname(file);

  return {
    ...module,
    extensionAbilities: module.extensionAbilities.filter(extension => (
      typeof extension?.srcEntry !== 'string'
      || !stale.has(path.posix.join(directory, extension.srcEntry))
    )),
  };
}

function removeStaleResources(results, kind, plugins, current) {
  for (const plugin of plugins) {
    for (const [scope, values] of Object.entries(plugin.resources?.[kind] || {})) {
      const names = (values as readonly string[]).filter(name => (
        !current.some(owner => owner.resources?.[kind]?.[scope]?.includes(name))
      ));
      const resource = results[scope];

      if (!resource || typeof resource !== 'object') continue;

      if (kind === 'media') {
        for (const name of Object.keys(resource)) {
          if (names.includes(path.parse(name).name)) delete resource[name];
        }
      } else {
        const field = kind === 'colors' ? 'color' : 'string';
        resource[field] = (resource[field] || []).filter(item => !names.includes(item?.name));
      }
    }
  }

  return results;
}

export {
  findDeferredPluginFiles,
  findStaleConfigPlugins,
  readPreviousCngManifestAsync,
  reconcileDeferredPluginFilesAsync,
  removeStaleExtensionAbilities,
  removeStalePluginFilesAsync,
  removeStaleResources,
};

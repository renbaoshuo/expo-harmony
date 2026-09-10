import fs from 'node:fs';
import path from 'node:path';

import { HarmonyPaths, type HarmonyConfigPluginOwnership } from '@expo-harmony/config-plugins';

import { resolveHarmonyBuildPath } from './buildDescriptor';
import { HarmonyPrebuildError } from './errors';
import { CngManifestPath, validateCngManifest } from './manifest';

async function readPreviousCngManifestAsync(root) {
  const file = resolveHarmonyBuildPath(root, CngManifestPath);

  let manifest;

  try {
    manifest = JSON.parse(await fs.promises.readFile(file, 'utf8'));
  } catch (cause) {
    if (cause.code === 'ENOENT' || cause instanceof SyntaxError) return null;

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
    if (!next || previous.files === undefined) continue;

    obsolete.set(previous.owner, new Set(
      previous.files.filter(file => !next.files?.includes(file)).map(file => `harmony/${file}`)
    ));
  }

  // A path can transfer to another plugin; do not remove its newly written output.
  const claimed = new Set(current.flatMap(plugin => (plugin.files || []).map(file => `harmony/${file}`)));
  const files = (manifest?.managedFiles || []).filter(entry => !claimed.has(entry.path)
    && (owners.has(entry.owner) || obsolete.get(entry.owner)?.has(entry.path)));

  for (const entry of dryRun ? [] : files) {
    const directory = await HarmonyPaths.resolveHarmonyPath(root, path.dirname(entry.path));
    const target = path.join(directory, path.basename(entry.path));

    let stat;

    try {
      stat = await fs.promises.lstat(target);
    } catch (cause) {
      if (cause.code === 'ENOENT') continue;

      throw new HarmonyPrebuildError(
        cause.code || 'ERR_HARMONY_MANIFEST_INVALID',
        cause.message || `Cannot inspect stale plugin output ${target}.`,
        { cause, file: target, operation: 'remove-stale-plugin-output' }
      );
    }

    if (stat.isDirectory()) {
      throw new HarmonyPrebuildError(
        'ERR_HARMONY_MANIFEST_INVALID',
        `A stale config plugin claims a managed directory instead of a file: ${entry.path}`,
        { file: target, operation: 'remove-stale-plugin-output' }
      );
    }

    await fs.promises.rm(target, { force: true });
  }

  // Keep missing files in the result so a retry also removes their declarations.
  return files.map(entry => entry.path);
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

function removeStaleResources(results, kind, plugins) {
  for (const plugin of plugins) {
    for (const [scope, values] of Object.entries(plugin.resources?.[kind] || {})) {
      const names = values as readonly string[];
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
  findStaleConfigPlugins,
  readPreviousCngManifestAsync,
  removeStaleExtensionAbilities,
  removeStalePluginFilesAsync,
  removeStaleResources,
};

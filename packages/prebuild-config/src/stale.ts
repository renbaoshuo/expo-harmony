import fs from 'node:fs';
import path from 'node:path';

import { resolveHarmonyBuildPath } from './buildDescriptor';
import { HarmonyPrebuildError } from './errors';
import { CngManifestPath, validateCngManifest } from './manifest';

async function readPreviousCngManifestAsync(projectRoot) {
  const file = resolveHarmonyBuildPath(projectRoot, CngManifestPath);

  let parsed;
  try {
    parsed = JSON.parse(await fs.promises.readFile(file, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT' || error instanceof SyntaxError) return null;
    return Promise.reject(error);
  }

  return validateCngManifest(parsed, { file });
}

function findStaleConfigPlugins(previousManifest, currentPlugins) {
  const currentOwners = new Set(currentPlugins.map(plugin => plugin.owner));
  return (previousManifest?.configPlugins || []).filter(plugin => !currentOwners.has(plugin.owner));
}

async function removeStalePluginFilesAsync(projectRoot, previousManifest, stalePlugins) {
  const staleOwners = new Set(stalePlugins.map(plugin => plugin.owner));
  for (const descriptor of previousManifest?.managedFiles || []) {
    if (!staleOwners.has(descriptor.owner)) continue;

    const target = path.join(projectRoot, ...descriptor.path.split('/'));
    let stat;
    try {
      stat = await fs.promises.lstat(target);
    } catch (cause) {
      if (cause.code === 'ENOENT') continue;
      return Promise.reject(cause);
    }
    if (stat.isDirectory()) {
      throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', `A stale config plugin claims a managed directory instead of a file: ${descriptor.path}`, { file: target, operation: 'remove-stale-plugin-output' });
    }
    await fs.promises.rm(target, { force: true });
  }
}

function removeStaleResources(modResults, kind, stalePlugins) {
  for (const plugin of stalePlugins) {
    for (const [scope, values] of Object.entries(plugin.resources?.[kind] || {})) {
      const names = values as readonly string[];
      const resource = modResults[scope];
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
  return modResults;
}

export {
  findStaleConfigPlugins,
  readPreviousCngManifestAsync,
  removeStalePluginFilesAsync,
  removeStaleResources,
};

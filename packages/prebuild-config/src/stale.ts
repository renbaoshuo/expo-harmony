import fs from 'node:fs';
import path from 'node:path';

import { resolveHarmonyBuildPath } from './buildDescriptor';
import { HarmonyPrebuildError } from './errors';
import { CngManifestPath, validateCngManifest } from './manifest';

async function readPreviousCngManifestAsync(root) {
  const file = resolveHarmonyBuildPath(root, CngManifestPath);

  let parsed;

  try {
    parsed = JSON.parse(await fs.promises.readFile(file, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT' || error instanceof SyntaxError) return null;
    return Promise.reject(error);
  }

  return validateCngManifest(parsed, { file });
}

function findStaleConfigPlugins(manifest, plugins) {
  const owners = new Set(plugins.map(plugin => plugin.owner));

  return (manifest?.configPlugins || []).filter(plugin => !owners.has(plugin.owner));
}

async function removeStalePluginFilesAsync(root, manifest, plugins) {
  const owners = new Set(plugins.map(plugin => plugin.owner));

  for (const descriptor of manifest?.managedFiles || []) {
    if (!owners.has(descriptor.owner)) continue;

    const target = path.join(root, ...descriptor.path.split('/'));

    let stat;

    try {
      stat = await fs.promises.lstat(target);
    } catch (cause) {
      if (cause.code === 'ENOENT') continue;
      return Promise.reject(cause);
    }

    if (stat.isDirectory()) {
      throw new HarmonyPrebuildError(
        'ERR_HARMONY_MANIFEST_INVALID',
        `A stale config plugin claims a managed directory instead of a file: ${descriptor.path}`,
        { file: target, operation: 'remove-stale-plugin-output' }
      );
    }

    await fs.promises.rm(target, { force: true });
  }
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
  removeStalePluginFilesAsync,
  removeStaleResources,
};

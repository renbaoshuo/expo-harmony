import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

import { stableHarmonyJson } from '@expo-harmony/config-plugins';
import JSON5 from 'json5';

import { HarmonyPrebuildError } from './errors';
import { validateCngManifest } from './manifest';

async function upgradeLegacyCngManifestAsync(projectRoot, normalized, manifest) {
  if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest) || manifest.managedIdentity !== undefined) {
    return null;
  }

  let profile;
  let moduleJson;
  try {
    const [profileSource, moduleSource] = await Promise.all([
      fs.promises.readFile(path.join(projectRoot, 'harmony/build-profile.json5'), 'utf8'),
      fs.promises.readFile(path.join(projectRoot, 'harmony/entry/src/main/module.json5'), 'utf8'),
    ]);
    profile = JSON5.parse(profileSource);
    moduleJson = JSON5.parse(moduleSource);
  } catch (_cause) {
    return null;
  }

  const currentConfigHash = createHash('sha256').update(stableHarmonyJson(normalized)).digest('hex');
  const configIsUnchanged = manifest.inputs?.configHash === currentConfigHash;
  const moduleName = configIsUnchanged ? normalized.moduleName : moduleJson?.module?.name;
  const abilityName = configIsUnchanged ? normalized.abilityName : moduleJson?.module?.mainElement;
  const moduleProfiles = Array.isArray(profile?.modules) ? profile.modules.filter(m => m?.name === moduleName) : [];
  const abilities = Array.isArray(moduleJson?.module?.abilities)
    ? moduleJson.module.abilities.filter(item => item?.name === abilityName)
    : [];
  const targets = Array.isArray(moduleProfiles[0]?.targets)
    ? moduleProfiles[0].targets.filter(item => item?.name === 'default')
    : [];
  const products = Array.isArray(profile?.app?.products) ? profile.app.products : [];
  const appliedProducts = Array.isArray(targets[0]?.applyToProducts)
    ? [...new Set(targets[0].applyToProducts)]
    : [];
  const candidates = products.filter(item => appliedProducts.includes(item?.name));
  const product = configIsUnchanged
    ? candidates.find(item => item?.name === normalized.productName)
    : candidates.length === 1 ? candidates[0] : null;
  if (moduleProfiles.length !== 1 || targets.length !== 1 || abilities.length !== 1
    || moduleJson?.module?.name !== moduleName
    || moduleJson?.module?.mainElement !== abilityName
    || !product
    || products.filter(item => item?.name === product.name).length !== 1) {
    return null;
  }

  const signingConfigName = typeof product.signingConfig === 'string' && product.signingConfig ? product.signingConfig : null;
  if (manifest.signingConfigName !== undefined && manifest.signingConfigName !== signingConfigName) {
    return null;
  }

  try {
    return validateCngManifest({
      ...manifest,
      managedIdentity: {
        abilityName,
        moduleName,
        productName: product.name,
        targetName: 'default',
      },
      signingConfigName,
    });
  } catch (_cause) {
    return null;
  }
}

async function readPreviousCngManifestAsync(projectRoot, normalized) {
  const file = path.join(projectRoot, '.expo/harmony/cng-manifest.json');

  let parsed;
  try {
    parsed = JSON.parse(await fs.promises.readFile(file, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT' || error instanceof SyntaxError) return null;
    return Promise.reject(error);
  }

  try {
    return validateCngManifest(parsed, { file });
  } catch (error) {
    if (error.code !== 'ERR_HARMONY_MANIFEST_INVALID') return Promise.reject(error);
    return upgradeLegacyCngManifestAsync(projectRoot, normalized, parsed);
  }
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

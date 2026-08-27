import fs from 'node:fs';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';

import { getConfig } from '@expo/config';
import { stableHarmonyJson } from '@expo-harmony/config-plugins';
import {
  ohpmDependenciesFromManifest,
  readManifestAsync as readAutolinkingManifestAsync,
} from '@expo-harmony/expo-modules-autolinking';
import JSON5 from 'json5';

import { HarmonyPrebuildError } from './errors';
import {
  hashSha256,
  validateCngManifest,
  type CngManifest,
} from './manifest';
import { normalizeHarmonyConfig } from './normalizeHarmonyConfig';
import { validateHarmonySigningConfigFile } from './signing';

interface Change {
  path: string;
  type: 'added' | 'changed' | 'deleted';
}

interface Result {
  changes: Change[];
  clean: boolean;
  expected: CngManifest;
}

function isInside(root: string, target: string): boolean {
  const relative = path.relative(root, target);
  return relative === ''
    || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function mirrorPath(temp: string, source: string): string {
  const absolute = path.resolve(source);
  const parsed = path.parse(absolute);
  const volume = parsed.root.replace(/[^A-Za-z0-9]+/gu, '') || 'root';
  const segments = absolute.slice(parsed.root.length).split(path.sep).filter(Boolean);

  return path.join(temp, 'filesystem', volume, ...segments);
}

async function stageAutolinkingAsync(project: string, target: string): Promise<void> {
  const source = path.join(project, '.expo/harmony/autolinking.json');
  let stat;

  try {
    stat = await fs.promises.lstat(source);
  } catch (error) {
    if (error.code === 'ENOENT') return;
    throw new HarmonyPrebuildError(
      error.code || 'ERR_HARMONY_MANIFEST_DRIFT',
      error.message || `Cannot inspect the previous autolinking manifest: ${source}`,
      { cause: error, operation: error.operation || 'check' }
    );
  }

  if (!stat.isFile() || stat.isSymbolicLink()) return;

  const content = await fs.promises.readFile(source, 'utf8');
  const file = path.join(target, '.expo/harmony/autolinking.json');
  await fs.promises.mkdir(path.dirname(file), { recursive: true });
  await fs.promises.writeFile(file, content);

  // RNOH regenerates managed dependency entries but preserves `overrides`.
  // Drop only overrides owned by the validated previous module set; the
  // prebuild repair step recreates them while unrelated dependencies stay intact.
  let manifest;

  try {
    manifest = await readAutolinkingManifestAsync(source);
  } catch (_cause) {
    return;
  }
  const packages = new Set(
    Object.keys(ohpmDependenciesFromManifest(manifest))
  );

  if (packages.size === 0) return;

  const ohpm = path.join(target, 'harmony/oh-package.json5');
  let config;

  try {
    config = JSON5.parse(await fs.promises.readFile(ohpm, 'utf8'));
  } catch (_cause) {
    return;
  }

  if (!config?.dependencies || !config?.overrides) return;

  let changed = false;

  for (const name of Object.keys(config.dependencies)) {
    if (packages.has(name) && Object.hasOwn(config.overrides, name)) {
      delete config.overrides[name];
      changed = true;
    }
  }

  if (changed) {
    await fs.promises.writeFile(ohpm, `${JSON5.stringify(config, null, 2)}\n`);
  }
}

async function matchesIdentity(
  project: string,
  identity: CngManifest['managedIdentity']
): Promise<boolean> {
  let profile;
  let moduleJson;

  try {
    const [profileSource, moduleSource] = await Promise.all([
      fs.promises.readFile(path.join(project, 'harmony/build-profile.json5'), 'utf8'),
      fs.promises.readFile(path.join(project, 'harmony/entry/src/main/module.json5'), 'utf8'),
    ]);
    profile = JSON5.parse(profileSource);
    moduleJson = JSON5.parse(moduleSource);
  } catch (_cause) {
    return false;
  }

  const moduleProfile = Array.isArray(profile?.modules)
    ? profile.modules.find(item => item?.name === identity.moduleName)
    : null;
  const target = Array.isArray(moduleProfile?.targets)
    ? moduleProfile.targets.find(item => item?.name === identity.targetName)
    : null;
  const products = Array.isArray(profile?.app?.products) ? profile.app.products : [];
  const abilities = Array.isArray(moduleJson?.module?.abilities) ? moduleJson.module.abilities : [];

  return moduleJson?.module?.name === identity.moduleName
    && moduleJson?.module?.mainElement === identity.abilityName
    && abilities.some(item => item?.name === identity.abilityName)
    && products.some(item => item?.name === identity.productName)
    && Array.isArray(target?.applyToProducts)
    && target.applyToProducts.includes(identity.productName);
}

async function readManifestAsync(project: string): Promise<CngManifest> {
  const file = path.join(project, '.expo/harmony/cng-manifest.json');
  try {
    return validateCngManifest(JSON.parse(await fs.promises.readFile(file, 'utf8')), { file });
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      `Cannot read CNG manifest: ${file}`,
      { cause, file, operation: 'check' }
    );
  }
}

async function stageManifestAsync(project: string, target: string): Promise<void> {
  const source = path.join(project, '.expo/harmony/cng-manifest.json');
  let stat;

  try {
    stat = await fs.promises.lstat(source);
  } catch (error) {
    if (error.code === 'ENOENT') return;
    throw new HarmonyPrebuildError(
      error.code || 'ERR_HARMONY_MANIFEST_DRIFT',
      error.message || `Cannot inspect the previous CNG manifest: ${source}`,
      { cause: error, operation: error.operation || 'check' }
    );
  }

  if (!stat.isFile() || stat.isSymbolicLink()) return;

  let manifest;

  try {
    manifest = validateCngManifest(JSON.parse(await fs.promises.readFile(source, 'utf8')), {
      file: source,
    });
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      `Cannot stage the CNG manifest for isolated --check: ${source}`,
      { cause, file: source, operation: 'check' }
    );
  }

  const config = getConfig(project, {
    isModdedConfig: true,
    skipSDKVersionRequirement: true,
  }).exp;
  const normalized = normalizeHarmonyConfig(config);
  const hash = hashSha256(stableHarmonyJson(normalized));
  let identity = manifest.managedIdentity;
  let signing = manifest.signingConfigName;

  if (hash === manifest.inputs.configHash) {
    // A matching input hash lets us reconstruct these two pieces of mutable
    // re-entry state from authoritative inputs. This prevents a corrupted
    // manifest identity from making isolated prebuild overwrite a user-owned
    // product/module/ability while still allowing --check to report the
    // manifest itself as drifted.
    identity = {
      abilityName: normalized.abilityName,
      moduleName: normalized.moduleName,
      productName: normalized.productName,
      targetName: 'default',
    };
    signing = normalized.signingConfigFile
      ? (await validateHarmonySigningConfigFile(project, normalized.signingConfigFile)).name
      : null;
  } else if (!await matchesIdentity(project, identity)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      'The CNG manifest identity does not match the generated Harmony project. Run prebuild to repair it before changing Harmony identity fields.',
      { operation: 'check' }
    );
  }

  const file = path.join(target, '.expo/harmony/cng-manifest.json');
  await fs.promises.mkdir(path.dirname(file), { recursive: true });
  await fs.promises.writeFile(file, stableHarmonyJson({
    ...manifest,
    managedIdentity: identity,
    signingConfigName: signing,
  }));
}

async function stageSigningAsync(
  project: string,
  temp: string
): Promise<void> {
  const config = getConfig(project, {
    isModdedConfig: true,
    skipSDKVersionRequirement: true,
  }).exp;
  const reference = (config as typeof config & {
    harmony?: { signingConfigFile?: string };
  }).harmony?.signingConfigFile;

  if (!reference) return;

  const signing = await validateHarmonySigningConfigFile(project, reference);
  const inputs = [signing.file, ...Object.values(signing.materialFiles)];

  for (const source of inputs) {
    if (isInside(project, source)) continue;

    const target = mirrorPath(temp, source);

    if (!isInside(temp, target)) {
      throw new HarmonyPrebuildError(
        'ERR_HARMONY_SIGNING_INVALID',
        `External Harmony signing input escapes the isolated --check workspace: ${source}`,
        { operation: 'check-signing' }
      );
    }

    await fs.promises.mkdir(path.dirname(target), { recursive: true });
    await fs.promises.copyFile(source, target);
  }
}

async function stageAsync(
  project: string,
  expected: string,
  temp: string
): Promise<void> {
  await stageManifestAsync(project, expected);
  await stageAutolinkingAsync(project, expected);
  await stageSigningAsync(project, temp);
}

async function normalizeAutolinkingAsync(
  expected: string,
  project: string,
  cng: CngManifest
) {
  const file = path.join(expected, '.expo/harmony/autolinking.json');
  let manifest;

  try {
    manifest = await readAutolinkingManifestAsync(file, { allowMissing: true });
  } catch (error) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      `Cannot normalize the isolated autolinking manifest: ${file}`,
      { cause: error, file, operation: 'check' }
    );
  }

  if (!manifest) return null;

  const [expectedPath, projectPath] = await Promise.all([
    fs.promises.realpath(expected),
    fs.promises.realpath(project),
  ]);

  for (const module of manifest.modules) {
    for (const field of ['packageRoot', 'packageLinkPath'] as const) {
      const current = module?.[field];
      if (typeof current === 'string' && path.isAbsolute(current)
        && isInside(expectedPath, current)) {
        module[field] = path.join(projectPath, path.relative(expectedPath, current));
      }
    }
  }

  const content = `${JSON.stringify(manifest, null, 2)}\n`;
  const hash = hashSha256(content);
  cng.inputs.autolinkingHash = hash;
  const descriptor = cng.managedFiles.find(
    item => item.path === '.expo/harmony/autolinking.json'
  );

  if (descriptor) descriptor.sha256 = hash;

  return manifest;
}

async function normalizeOhpmAsync(
  expected: string,
  cng: CngManifest,
  autolinking
): Promise<void> {
  if (!autolinking) return;

  const file = path.join(expected, 'harmony/oh-package.json5');
  let config;

  try {
    config = JSON5.parse(await fs.promises.readFile(file, 'utf8'));
  } catch (_cause) {
    return;
  }

  const specifiers = ohpmDependenciesFromManifest(autolinking);

  for (const field of ['dependencies', 'overrides']) {
    if (!config?.[field]) continue;
    for (const name of Object.keys(config[field])) {
      if (Object.hasOwn(specifiers, name)) {
        config[field][name] = specifiers[name];
      }
    }
  }

  const content = `${JSON5.stringify(config, null, 2)}\n`;
  const descriptor = cng.managedFiles.find(
    item => item.path === 'harmony/oh-package.json5'
  );

  if (descriptor) descriptor.sha256 = hashSha256(content);
}

async function compareAsync(
  project: string,
  expectedRoot: string
): Promise<Result> {
  const expected = await readManifestAsync(expectedRoot);
  const autolinking = await normalizeAutolinkingAsync(
    expectedRoot,
    project,
    expected
  );
  await normalizeOhpmAsync(expectedRoot, expected, autolinking);

  const actual = await readManifestAsync(project);
  const expectedFiles = new Map(expected.managedFiles.map(item => [item.path, item]));
  const actualFiles = new Map(actual.managedFiles.map(item => [item.path, item]));
  const changes: Change[] = [];

  for (const [relative, descriptor] of expectedFiles) {
    const file = path.join(project, ...relative.split('/'));
    let currentHash = null;

    try {
      currentHash = hashSha256(Uint8Array.from(await fs.promises.readFile(file)));
    } catch (error) {
      if (error.code !== 'ENOENT') {
        throw new HarmonyPrebuildError(
          error.code || 'ERR_HARMONY_MANIFEST_DRIFT',
          error.message || `Cannot read a managed Harmony file: ${file}`,
          { cause: error, file, operation: error.operation || 'check' }
        );
      }
    }

    if (currentHash === null) changes.push({ path: relative, type: 'added' });
    else if (currentHash !== descriptor.sha256) changes.push({ path: relative, type: 'changed' });
  }

  for (const relative of actualFiles.keys()) {
    if (!expectedFiles.has(relative)) changes.push({ path: relative, type: 'deleted' });
  }

  if (!isDeepStrictEqual(expected, actual)) {
    changes.push({ path: '.expo/harmony/cng-manifest.json', type: 'changed' });
  }

  changes.sort((left, right) => (
    left.path.localeCompare(right.path, 'en') || left.type.localeCompare(right.type, 'en')
  ));

  return { changes, clean: changes.length === 0, expected };
}

export {
  compareAsync,
  readManifestAsync,
  stageAsync,
};
export type {
  Change,
  Result,
};

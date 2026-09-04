import fs from 'node:fs';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';

import { getConfig } from '@expo/config';
import { normalizeHarmonyConfig, stableHarmonyJson } from '@expo-harmony/config-plugins';
import { canonicalizeAutolinkingArtifacts } from '@expo-harmony/expo-modules-autolinking';
import JSON5 from 'json5';

import { HarmonyPrebuildError } from './errors';
import {
  createHarmonyBuildDescriptor,
  resolveHarmonyBuildPath,
} from './buildDescriptor';
import {
  CngManifestPath,
  hashSha256,
  validateCngManifest,
  type CngManifest,
} from './manifest';
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
}

async function matchesIdentity(
  project: string,
  cng: CngManifest
): Promise<boolean> {
  const identity = cng.managedIdentity;
  let profile;
  let module;

  try {
    const [profileSource, moduleSource] = await Promise.all([
      fs.promises.readFile(resolveHarmonyBuildPath(
        project,
        cng.build.projectFiles.projectBuildProfile
      ), 'utf8'),
      fs.promises.readFile(resolveHarmonyBuildPath(
        project,
        cng.build.projectFiles.moduleJson
      ), 'utf8'),
    ]);

    profile = JSON5.parse(profileSource);
    module = JSON5.parse(moduleSource);
  } catch {
    return false;
  }

  const moduleProfile = Array.isArray(profile?.modules)
    ? profile.modules.find(item => item?.name === identity.moduleName)
    : null;
  const target = Array.isArray(moduleProfile?.targets)
    ? moduleProfile.targets.find(item => item?.name === identity.targetName)
    : null;
  const products = Array.isArray(profile?.app?.products) ? profile.app.products : [];
  const abilities = Array.isArray(module?.module?.abilities) ? module.module.abilities : [];

  return module?.module?.name === identity.moduleName
    && module?.module?.mainElement === identity.abilityName
    && abilities.some(item => item?.name === identity.abilityName)
    && products.some(item => item?.name === identity.productName)
    && Array.isArray(target?.applyToProducts)
    && target.applyToProducts.includes(identity.productName);
}

async function readManifestIfPresentAsync(project: string): Promise<CngManifest | null> {
  const file = resolveHarmonyBuildPath(project, CngManifestPath);

  let source;

  try {
    source = await fs.promises.readFile(file, 'utf8');
  } catch (cause) {
    if (cause.code === 'ENOENT') return null;

    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      `Cannot read CNG manifest: ${file}`,
      { cause, file, operation: 'check' }
    );
  }

  try {
    return validateCngManifest(JSON.parse(source), { file });
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      `Cannot read CNG manifest: ${file}`,
      { cause, file, operation: 'check' }
    );
  }
}

async function readManifestAsync(project: string): Promise<CngManifest> {
  const manifest = await readManifestIfPresentAsync(project);

  if (!manifest) {
    const file = resolveHarmonyBuildPath(project, CngManifestPath);
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      `Cannot read CNG manifest: ${file}`,
      { file, operation: 'check' }
    );
  }

  return manifest;
}

async function stageManifestAsync(project: string, target: string): Promise<void> {
  const source = resolveHarmonyBuildPath(project, CngManifestPath);

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

  let cng;

  try {
    cng = validateCngManifest(JSON.parse(await fs.promises.readFile(source, 'utf8')), {
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

  const harmony = normalizeHarmonyConfig(config);
  const hash = hashSha256(stableHarmonyJson(harmony));
  let identity = cng.managedIdentity;
  let build = cng.build;
  let signing = cng.signingConfigName;

  if (hash === cng.inputs.configHash) {
    // Reconstruct mutable re-entry state from authoritative inputs so a corrupt
    // manifest cannot make isolated prebuild overwrite user-owned identities.
    signing = harmony.signingConfigFile
      ? (await validateHarmonySigningConfigFile(project, harmony.signingConfigFile)).name
      : null;
    build = createHarmonyBuildDescriptor(harmony, signing);
    identity = {
      abilityName: build.identity.abilityName,
      moduleName: build.identity.moduleName,
      productName: build.identity.productName,
      targetName: build.identity.targetName,
    };
  } else if (!await matchesIdentity(project, cng)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      'The CNG manifest identity does not match the generated Harmony project. Run prebuild to repair it before changing Harmony identity fields.',
      { operation: 'check' }
    );
  }

  const file = resolveHarmonyBuildPath(target, CngManifestPath);

  await fs.promises.mkdir(path.dirname(file), { recursive: true });
  await fs.promises.writeFile(file, stableHarmonyJson({
    ...cng,
    build,
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

async function canonicalizeAutolinkingAsync(
  expected: string,
  project: string,
  cng: CngManifest
): Promise<void> {
  const manifestFile = path.join(expected, '.expo/harmony/autolinking.json');
  const ohpmPath = cng.build.nativeInputs.manifest;
  const ohpmFile = resolveHarmonyBuildPath(expected, ohpmPath);

  try {
    const [manifest, ohpm, generatedRoot, projectRoot]
      = await Promise.all([
        fs.promises.readFile(manifestFile, 'utf8'),
        fs.promises.readFile(ohpmFile, 'utf8'),
        fs.promises.realpath(expected),
        fs.promises.realpath(project),
      ]);

    const result = canonicalizeAutolinkingArtifacts({
      manifestSource: manifest,
      ohPackageSource: ohpm,
      generatedProjectRoot: generatedRoot,
      canonicalProjectRoot: projectRoot,
      harmonyProjectPath: resolveHarmonyBuildPath(projectRoot, cng.build.harmonyRoot),
    });
    const manifestHash = hashSha256(result.manifestSource);
    const ohpmHash = hashSha256(result.ohPackageSource);

    cng.inputs.autolinkingHash = manifestHash;

    const manifestEntry = cng.managedFiles.find(
      item => item.path === '.expo/harmony/autolinking.json'
    );
    const ohpmEntry = cng.managedFiles.find(
      item => item.path === ohpmPath
    );

    if (manifestEntry) manifestEntry.sha256 = manifestHash;
    if (ohpmEntry) ohpmEntry.sha256 = ohpmHash;
  } catch (error) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      'Cannot canonicalize the isolated autolinking artifacts.',
      { cause: error, file: manifestFile, operation: 'check' }
    );
  }
}

async function compareAsync(
  project: string,
  generated: string
): Promise<Result> {
  const expected = await readManifestAsync(generated);

  await canonicalizeAutolinkingAsync(
    generated,
    project,
    expected
  );

  const actual = await readManifestAsync(project);
  const expectedFiles = new Map(expected.managedFiles.map(item => [item.path, item]));
  const actualFiles = new Map(actual.managedFiles.map(item => [item.path, item]));
  const changes: Change[] = [];

  for (const [relative, descriptor] of expectedFiles) {
    const file = path.join(project, ...relative.split('/'));
    let hash = null;

    try {
      hash = hashSha256(Uint8Array.from(await fs.promises.readFile(file)));
    } catch (error) {
      if (error.code !== 'ENOENT') {
        throw new HarmonyPrebuildError(
          error.code || 'ERR_HARMONY_MANIFEST_DRIFT',
          error.message || `Cannot read a managed Harmony file: ${file}`,
          { cause: error, file, operation: error.operation || 'check' }
        );
      }
    }

    if (hash === null) changes.push({ path: relative, type: 'added' });
    else if (hash !== descriptor.sha256) changes.push({ path: relative, type: 'changed' });
  }

  for (const relative of actualFiles.keys()) {
    if (!expectedFiles.has(relative)) changes.push({ path: relative, type: 'deleted' });
  }

  if (!isDeepStrictEqual(expected, actual)) {
    changes.push({ path: CngManifestPath, type: 'changed' });
  }

  changes.sort((left, right) => (
    left.path.localeCompare(right.path, 'en') || left.type.localeCompare(right.type, 'en')
  ));

  return { changes, clean: changes.length === 0, expected };
}

export {
  compareAsync,
  readManifestAsync,
  readManifestIfPresentAsync,
  stageAsync,
};
export type {
  Change,
  Result,
};

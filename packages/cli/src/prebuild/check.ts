import nodeCrypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';

import { getConfig } from '@expo/config';
import { stableHarmonyJson } from '@expo-harmony/config-plugins';
import { ohpmDependenciesFromManifest, readManifestAsync } from '@expo-harmony/expo-modules-autolinking';
import JSON5 from 'json5';
import { normalizeHarmonyConfig, validateCngManifest, validateHarmonySigningConfigFile } from '@expo-harmony/prebuild-config';

import { HarmonyCliError } from '../errors';
import { isInside } from '../path';
import { spawnAsync } from '../process';
import { resolveExpoCli } from '../expo';
import { packTemplateAsync } from './template';

export interface CheckChange {
  path: string;
  type: 'added' | 'changed' | 'deleted';
}

function sha256(content) {
  return nodeCrypto.createHash('sha256').update(content).digest('hex');
}

function mirrorAbsolutePath(temporaryRoot, source) {
  const absolute = path.resolve(source);
  const parsed = path.parse(absolute);
  const volume = parsed.root.replace(/[^A-Za-z0-9]+/gu, '') || 'root';
  const segments = absolute.slice(parsed.root.length).split(path.sep).filter(Boolean);

  return path.join(temporaryRoot, 'filesystem', volume, ...segments);
}

function mirrorProjectRoot(temporaryRoot, projectRoot) {
  return mirrorAbsolutePath(temporaryRoot, projectRoot);
}

async function stageAutolinkingReentryAsync(projectRoot, target) {
  const sourceManifest = path.join(projectRoot, '.expo/harmony/autolinking.json');
  let stat;

  try {
    stat = await fs.promises.lstat(sourceManifest);
  } catch (error) {
    if (error.code === 'ENOENT') return;
    throw new HarmonyCliError(
      error.code || 'ERR_HARMONY_MANIFEST_DRIFT',
      error.message || `Cannot inspect the previous autolinking manifest: ${sourceManifest}`,
      { cause: error, exitCode: error.exitCode, operation: error.operation }
    );
  }

  if (!stat.isFile() || stat.isSymbolicLink()) return;

  const manifestContent = await fs.promises.readFile(sourceManifest, 'utf8');
  const destination = path.join(target, '.expo/harmony/autolinking.json');
  await fs.promises.mkdir(path.dirname(destination), { recursive: true });
  await fs.promises.writeFile(destination, manifestContent);

  // RNOH regenerates managed dependency entries but preserves `overrides`.
  // Drop only overrides owned by the validated previous module set; the
  // prebuild repair step recreates them while unrelated dependencies stay intact.
  let manifest;

  try {
    manifest = await readManifestAsync(sourceManifest);
  } catch (_cause) {
    return;
  }
  const managedOhpmPackageNames = new Set(
    Object.keys(ohpmDependenciesFromManifest(manifest))
  );

  if (managedOhpmPackageNames.size === 0) return;

  const ohPackageFile = path.join(target, 'harmony/oh-package.json5');
  let ohPackage;

  try {
    ohPackage = JSON5.parse(await fs.promises.readFile(ohPackageFile, 'utf8'));
  } catch (_cause) {
    return;
  }

  if (!ohPackage?.dependencies || !ohPackage?.overrides) return;

  let changed = false;

  for (const name of Object.keys(ohPackage.dependencies)) {
    if (managedOhpmPackageNames.has(name) && Object.hasOwn(ohPackage.overrides, name)) {
      delete ohPackage.overrides[name];
      changed = true;
    }
  }

  if (changed) {
    await fs.promises.writeFile(ohPackageFile, `${JSON5.stringify(ohPackage, null, 2)}\n`);
  }
}

async function manifestIdentityMatchesNativeProject(projectRoot, identity) {
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

async function stageCngReentryAsync(projectRoot, target) {
  const source = path.join(projectRoot, '.expo/harmony/cng-manifest.json');
  let stat;

  try {
    stat = await fs.promises.lstat(source);
  } catch (error) {
    if (error.code === 'ENOENT') return;
    throw new HarmonyCliError(
      error.code || 'ERR_HARMONY_MANIFEST_DRIFT',
      error.message || `Cannot inspect the previous CNG manifest: ${source}`,
      { cause: error, exitCode: error.exitCode, operation: error.operation }
    );
  }

  if (!stat.isFile() || stat.isSymbolicLink()) return;

  let manifest;

  try {
    manifest = validateCngManifest(JSON.parse(await fs.promises.readFile(source, 'utf8')), {
      file: source,
    });
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      `Cannot stage the CNG manifest for isolated --check: ${source}`,
      { cause, operation: 'check' }
    );
  }

  const config = getConfig(projectRoot, {
    isModdedConfig: true,
    skipSDKVersionRequirement: true,
  }).exp;
  const normalized = normalizeHarmonyConfig(config);
  const currentConfigHash = sha256(stableHarmonyJson(normalized));
  let managedIdentity = manifest.managedIdentity;
  let signingConfigName = manifest.signingConfigName;

  if (currentConfigHash === manifest.inputs.configHash) {
    // A matching input hash lets us reconstruct these two pieces of mutable
    // re-entry state from authoritative inputs. This prevents a corrupted
    // manifest identity from making isolated prebuild overwrite a user-owned
    // product/module/ability while still allowing --check to report the
    // manifest itself as drifted.
    managedIdentity = {
      abilityName: normalized.abilityName,
      moduleName: normalized.moduleName,
      productName: normalized.productName,
      targetName: 'default',
    };
    signingConfigName = normalized.signingConfigFile
      ? (await validateHarmonySigningConfigFile(projectRoot, normalized.signingConfigFile)).name
      : null;
  } else if (!await manifestIdentityMatchesNativeProject(projectRoot, managedIdentity)) {
    throw new HarmonyCliError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      'The CNG manifest identity does not match the generated Harmony project. Run prebuild to repair it before changing Harmony identity fields.',
      { operation: 'check' }
    );
  }

  const destination = path.join(target, '.expo/harmony/cng-manifest.json');
  await fs.promises.mkdir(path.dirname(destination), { recursive: true });
  await fs.promises.writeFile(destination, stableHarmonyJson({
    ...manifest,
    managedIdentity,
    signingConfigName,
  }));
}

async function stageExternalSigningInputsAsync(projectRoot, temporaryRoot) {
  const config = getConfig(projectRoot, {
    isModdedConfig: true,
    skipSDKVersionRequirement: true,
  }).exp;
  const reference = (config as typeof config & {
    harmony?: { signingConfigFile?: string };
  }).harmony?.signingConfigFile;

  if (!reference) return;

  const signing = await validateHarmonySigningConfigFile(projectRoot, reference);
  const inputs = [signing.file, ...Object.values(signing.materialFiles)];

  for (const source of inputs) {
    if (isInside(projectRoot, source)) continue;

    const destination = mirrorAbsolutePath(temporaryRoot, source);

    if (!isInside(temporaryRoot, destination)) {
      throw new HarmonyCliError(
        'ERR_HARMONY_SIGNING_INVALID',
        `External Harmony signing input escapes the isolated --check workspace: ${source}`,
        { operation: 'check-signing' }
      );
    }

    await fs.promises.mkdir(path.dirname(destination), { recursive: true });
    await fs.promises.copyFile(source, destination);
  }
}

async function linkNodeModulesEntriesAsync(sourceRoot, targetRoot) {
  await fs.promises.mkdir(targetRoot, { recursive: true });

  for (const entry of await fs.promises.readdir(sourceRoot, { withFileTypes: true })) {
    const source = path.join(sourceRoot, entry.name);
    const target = path.join(targetRoot, entry.name);

    if (entry.name.startsWith('@') && entry.isDirectory() && !entry.isSymbolicLink()) {
      await fs.promises.mkdir(target);
      for (const child of await fs.promises.readdir(source, { withFileTypes: true })) {
        await fs.promises.symlink(
          path.join(source, child.name),
          path.join(target, child.name),
          process.platform === 'win32' && (child.isDirectory() || child.isSymbolicLink())
            ? 'junction'
            : child.isDirectory() ? 'dir' : 'file'
        );
      }
      continue;
    }

    await fs.promises.symlink(
      source,
      target,
      process.platform === 'win32' && (entry.isDirectory() || entry.isSymbolicLink())
        ? 'junction'
        : entry.isDirectory() ? 'dir' : 'file'
    );
  }
}

async function copyProjectAsync(projectRoot, target, temporaryRoot = path.dirname(target)) {
  const ignoredRoots = new Set(['.expo', '.git', '.hvigor', '.yarn', 'node_modules']);
  const ignoredHarmonyDirectories = new Set(['.cxx', '.git', '.hvigor', 'build', 'node_modules', 'oh_modules']);

  await fs.promises.cp(projectRoot, target, {
    recursive: true,
    filter(source) {
      const relative = path.relative(projectRoot, source);
      if (!relative) return true;
      const segments = relative.split(path.sep);
      if (ignoredRoots.has(segments[0])) return false;
      if (segments[0] === 'harmony'
        && segments.slice(1).some(segment => ignoredHarmonyDirectories.has(segment))) {
        return false;
      }
      return relative !== path.join(
        'harmony',
        'entry',
        'src',
        'main',
        'resources',
        'rawfile',
        'hermes_bundle.hbc'
      );
    },
  });

  const nodeModules = path.join(projectRoot, 'node_modules');

  if (!fs.existsSync(nodeModules)) {
    throw new HarmonyCliError('ERR_HARMONY_DEPENDENCIES_MISSING', 'node_modules is required for --check.', {
      operation: 'check',
    });
  }

  // Keep a real node_modules directory in the isolated project and link its
  // entries. Dependency scanners then retain the isolated lexical package path
  // (including scoped packages) instead of collapsing the entire node_modules
  // root to the source project's realpath. The packages remain read-only and
  // are never copied or modified by --check.
  await linkNodeModulesEntriesAsync(nodeModules, path.join(target, 'node_modules'));
  await stageCngReentryAsync(projectRoot, target);
  await stageAutolinkingReentryAsync(projectRoot, target);
  await stageExternalSigningInputsAsync(projectRoot, temporaryRoot);
}

async function readManifest(projectRoot) {
  const file = path.join(projectRoot, '.expo/harmony/cng-manifest.json');
  try {
    return validateCngManifest(JSON.parse(await fs.promises.readFile(file, 'utf8')), { file });
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_MANIFEST_DRIFT', `Cannot read CNG manifest: ${file}`, {
      cause,
      operation: 'check',
    });
  }
}

async function normalizeExpectedAutolinkingAsync(expectedRoot, projectRoot, expectedManifest) {
  const file = path.join(expectedRoot, '.expo/harmony/autolinking.json');
  let manifest;

  try {
    manifest = await readManifestAsync(file, { allowMissing: true });
  } catch (error) {
    throw new HarmonyCliError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      `Cannot normalize the isolated autolinking manifest: ${file}`,
      { cause: error, operation: 'check' }
    );
  }

  if (!manifest) return null;

  const [expectedPhysicalRoot, projectPhysicalRoot] = await Promise.all([
    fs.promises.realpath(expectedRoot),
    fs.promises.realpath(projectRoot),
  ]);

  for (const module of manifest.modules) {
    for (const field of ['packageRoot', 'packageLinkPath']) {
      const current = module?.[field];
      if (typeof current === 'string' && path.isAbsolute(current)
        && isInside(expectedPhysicalRoot, current)) {
        module[field] = path.join(projectPhysicalRoot, path.relative(expectedPhysicalRoot, current));
      }
    }
  }

  const normalizedContent = `${JSON.stringify(manifest, null, 2)}\n`;
  const normalizedHash = sha256(normalizedContent);
  expectedManifest.inputs.autolinkingHash = normalizedHash;
  const descriptor = expectedManifest.managedFiles.find(
    item => item.path === '.expo/harmony/autolinking.json'
  );

  if (descriptor) descriptor.sha256 = normalizedHash;

  return manifest;
}

async function normalizeExpectedOhPackageAsync(
  expectedRoot,
  expectedManifest,
  autolinkingManifest
) {
  if (!autolinkingManifest) return;

  const file = path.join(expectedRoot, 'harmony/oh-package.json5');
  let ohPackage;

  try {
    ohPackage = JSON5.parse(await fs.promises.readFile(file, 'utf8'));
  } catch (_cause) {
    return;
  }

  const managedOhpmSpecifiers = ohpmDependenciesFromManifest(autolinkingManifest);

  for (const field of ['dependencies', 'overrides']) {
    if (!ohPackage?.[field]) continue;
    for (const name of Object.keys(ohPackage[field])) {
      if (Object.hasOwn(managedOhpmSpecifiers, name)) {
        ohPackage[field][name] = managedOhpmSpecifiers[name];
      }
    }
  }

  const normalizedContent = `${JSON5.stringify(ohPackage, null, 2)}\n`;
  const descriptor = expectedManifest.managedFiles.find(
    item => item.path === 'harmony/oh-package.json5'
  );

  if (descriptor) descriptor.sha256 = sha256(normalizedContent);
}

async function checkAsync(projectRoot) {
  projectRoot = path.resolve(projectRoot);
  const temporaryParent = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-harmony-check-'));
  const expectedRoot = mirrorProjectRoot(temporaryParent, projectRoot);
  let packed;

  try {
    await copyProjectAsync(projectRoot, expectedRoot, temporaryParent);
    packed = await packTemplateAsync(projectRoot);

    const expo = resolveExpoCli(projectRoot);
    const result = await spawnAsync(process.execPath, [
      expo.cliPath,
      'prebuild',
      expectedRoot,
      '--platform',
      'harmony',
      '--template',
      packed.tarball,
      '--no-install',
    ], {
      capture: true,
      cwd: expectedRoot,
      env: {
        ...process.env,
        EXPO_HARMONY_CHECK_MIRROR_ROOT: temporaryParent,
      },
      operation: 'check-prebuild',
    });

    if (result.code !== 0) {
      throw new HarmonyCliError('ERR_HARMONY_MANIFEST_DRIFT', `Isolated Expo prebuild failed:\n${result.stderr || result.stdout}`, {
        exitCode: result.code,
        operation: 'check-prebuild',
      });
    }

    const expected = await readManifest(expectedRoot);
    const autolinkingManifest = await normalizeExpectedAutolinkingAsync(
      expectedRoot,
      projectRoot,
      expected
    );
    await normalizeExpectedOhPackageAsync(
      expectedRoot,
      expected,
      autolinkingManifest
    );

    const actual = await readManifest(projectRoot);
    const expectedFiles = new Map(expected.managedFiles.map(item => [item.path, item]));
    const actualFiles = new Map(actual.managedFiles.map(item => [item.path, item]));
    const changes = [];

    for (const [relative, descriptor] of expectedFiles) {
      const file = path.join(projectRoot, ...relative.split('/'));
      let currentHash = null;

      try {
        currentHash = sha256(await fs.promises.readFile(file));
      } catch (error) {
        if (error.code !== 'ENOENT') {
          throw new HarmonyCliError(
            error.code || 'ERR_HARMONY_MANIFEST_DRIFT',
            error.message || `Cannot read a managed Harmony file: ${file}`,
            { cause: error, exitCode: error.exitCode, operation: error.operation }
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

    changes.sort((left, right) => left.path.localeCompare(right.path, 'en') || left.type.localeCompare(right.type, 'en'));

    return { changes, clean: changes.length === 0, expected };
  } finally {
    if (packed) await packed.cleanup();
    await fs.promises.rm(temporaryParent, { recursive: true, force: true });
  }
}

export { checkAsync };

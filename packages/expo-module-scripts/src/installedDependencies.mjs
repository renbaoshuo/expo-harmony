/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import semver from 'semver';

const CorePackage = '@expo-harmony/expo-modules-core';
const RuntimePackage = '@react-native-oh/react-native-harmony';
const RuntimeOhPackage = '@rnoh/react-native-openharmony';

async function nonEmptyFile(file) {
  const stat = await fs.lstat(file).catch((error) => {
    if (error.code === 'ENOENT') return undefined;
    throw error;
  });
  if (!stat?.isFile() || stat.size === 0) throw new Error(`Installed native artifact is missing or empty: ${file}`);

  return `file:${file.replaceAll(path.sep, '/')}`;
}

export async function installedDependencyOverrides(project, overrides = {}, dependencies = []) {
  const isCore = project.packageJson.name === CorePackage;
  const workspaceCore = isCore ? project : dependencies.find(dependency => dependency.packageJson.name === CorePackage);
  const hasCoreOverride = Object.hasOwn(overrides, CorePackage);
  const hasRuntimeOverride = Object.hasOwn(overrides, RuntimeOhPackage);
  if (hasRuntimeOverride && (isCore || hasCoreOverride)) return {};

  let coreManifest;
  if (workspaceCore) {
    coreManifest = path.join(workspaceCore.packageRoot, 'package.json');
  } else {
    const sections = ['dependencies', 'devDependencies', 'dynamicDependencies', 'overrides'];
    const declaresCore = [project.ohPackage, project.ohProjectPackage].some(manifest =>
      sections.some(section => Object.hasOwn(manifest[section] ?? {}, CorePackage)));
    if (!declaresCore && !hasCoreOverride) return {};

    const require = createRequire(path.join(project.packageRoot, 'package.json'));
    try {
      coreManifest = require.resolve(`${CorePackage}/package.json`);
    } catch (error) {
      // Modules using OHPM-only dependencies can build without a Core npm package.
      if (error.code === 'MODULE_NOT_FOUND') return {};
      throw error;
    }
  }

  const coreRoot = path.dirname(coreManifest);
  const core = workspaceCore?.packageJson ?? JSON.parse(await fs.readFile(coreManifest, 'utf8'));
  // Core declares the npm runtime when it owns the native HAR (SDK 57 onward).
  const runtimeRange = core.dependencies?.[RuntimePackage];
  if (!runtimeRange) return {};
  if (core.name !== CorePackage) throw new Error(`Expected ${CorePackage} at ${coreManifest}, found ${core.name}.`);

  const installed = {};
  if (!isCore && !hasCoreOverride) {
    const relative = core.harmony?.autolinking?.mainHarPath ?? 'harmony';
    const directory = await fs.realpath(path.resolve(coreRoot, relative));
    const relation = path.relative(await fs.realpath(coreRoot), directory);
    if (relation === '..' || relation.startsWith(`..${path.sep}`) || path.isAbsolute(relation)) {
      throw new Error('Core HAR directory escapes its npm package.');
    }

    const files = (await fs.readdir(directory, { withFileTypes: true })).filter(file => file.isFile() && file.name.endsWith('.har'));
    if (files.length !== 1) throw new Error(`Expected one prebuilt Core HAR in ${directory}; build/install Core first.`);

    installed[CorePackage] = await nonEmptyFile(path.join(directory, files[0].name));
  }

  if (!hasRuntimeOverride) {
    const nativeRequire = createRequire(coreManifest);
    const runtimeManifest = nativeRequire.resolve(`${RuntimePackage}/package.json`);
    const runtime = JSON.parse(await fs.readFile(runtimeManifest, 'utf8'));
    if (runtime.name !== RuntimePackage || !semver.valid(runtime.version)
      || (semver.validRange(runtimeRange) && !semver.satisfies(runtime.version, runtimeRange))) {
      throw new Error(`Expected Core's ${RuntimePackage}@${runtimeRange}, found ${runtime.name}@${runtime.version} at ${runtimeManifest}.`);
    }

    installed[RuntimeOhPackage] = await nonEmptyFile(path.join(path.dirname(runtimeManifest), 'react_native_openharmony.har'));
  }

  return installed;
}

export function npmPackFiles(result) {
  const packages = Array.isArray(result) ? result : result && typeof result === 'object' ? Object.values(result) : [];
  if (packages.length !== 1 || !Array.isArray(packages[0]?.files)
    || packages[0].files.some(file => typeof file?.path !== 'string' || !file.path)) {
    throw new TypeError('Invalid npm pack JSON: expected one package with a files array.');
  }

  return packages[0].files.map(file => file.path);
}

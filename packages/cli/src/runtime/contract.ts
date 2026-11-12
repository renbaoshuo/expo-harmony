/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { getHarmonyProjectConfig } from '@expo-harmony/expo__config/internal/project-config';
import { createNativeModuleContracts, ManifestArtifact, prepareRuntimeModulesAsync, type Manifest } from '@expo-harmony/expo-modules-autolinking';
import { harmonyRuntimeSchemaVersion, type HarmonyRuntimeContract } from '@expo-harmony/expo-modules-autolinking/runtime';
import JSON5 from 'json5';

import { publishUpdatesConfigurationAsync } from '../updates/export';
import { HarmonyCliError } from '../errors';
import { atomicWriteJson } from '../file';
import type { HarmonyMetroRuntime } from '../expo';
import type { HarmonyBuildPlan } from '../native/types';
import { createHarmonyToolchainEnv } from '../native/toolchain';
import { readMetroRuntimeAsync, readNativeRuntime, readProjectRuntimeAsync, resolveMetroRuntimeRoot, resolveRuntimeVersionAsync } from './config';

function createRuntimeContract(
  root: string,
  project: Pick<Awaited<ReturnType<typeof readProjectRuntimeAsync>>, 'native' | 'runtimeVersion'>,
  modules: Readonly<HarmonyRuntimeContract['modules']>,
  resolution: HarmonyMetroRuntime
): HarmonyRuntimeContract {
  const require = createRequire(path.join(root, 'package.json'));
  const version = (name: string) => require(`${name}/package.json`).version as string;
  const native = createRequire(path.join(resolveMetroRuntimeRoot(root, resolution), 'package.json'));

  return {
    schemaVersion: harmonyRuntimeSchemaVersion(project.native),
    platform: 'harmony',
    runtimeVersion: project.runtimeVersion,
    development: true,
    expo: version('expo'),
    expoModulesCore: version('expo-modules-core'),
    rnoh: native('./package.json').version,
    react: version(resolution.reactPackage),
    hermes: native('hermes-compiler/package.json').version,
    engine: 'hermes-v1',
    bundleFormat: 'js-source',
    renderer: 'rnoh',
    modules: [...modules],
    config: project.native,
  };
}

export async function resolveRuntimeProjectAsync(
  root: string,
  metro?: HarmonyMetroRuntime
) {
  const result = await prepareRuntimeModulesAsync({
    projectRoot: root,
    env: createHarmonyToolchainEnv(),
  });
  if (!result.valid) {
    throw new HarmonyCliError(
      'ERR_HARMONY_RUNTIME_MODULES',
      result.diagnostics.filter(item => item.severity === 'error').map(item => item.message).join('\n'),
      { operation: 'runtime-contract' }
    );
  }

  const modules = createNativeModuleContracts(result.modules);
  const resolution = metro ?? await readMetroRuntimeAsync(root);
  const project = await readProjectRuntimeAsync(root, { modules, metro: resolution });

  return {
    bundleName: project.bundleName,
    requirements: createRuntimeContract(root, project, modules, resolution),
  };
}

export async function resolveRuntimeRequirementsAsync(root: string): Promise<HarmonyRuntimeContract> {
  return (await resolveRuntimeProjectAsync(root)).requirements;
}

export async function publishRuntimeContractAsync(
  root: string,
  plan: HarmonyBuildPlan
): Promise<HarmonyRuntimeContract> {
  const manifest = JSON.parse(await fs.promises.readFile(path.join(root, ManifestArtifact), 'utf8')) as Manifest;
  const mode = plan.buildMode === 'release' ? 'production' : 'development';
  const { exp: config } = getHarmonyProjectConfig(root, {
    skipSDKVersionRequirement: true,
    isModdedConfig: true,
  }, mode);
  const native = readNativeRuntime(plan);
  // Older manifests lack the link-time snapshot.
  const modules = manifest.runtimeModules ?? createNativeModuleContracts(manifest.modules);
  const metro = await readMetroRuntimeAsync(root, mode);
  const contract = createRuntimeContract(root, {
    native: native.config,
    runtimeVersion: await resolveRuntimeVersionAsync(root, config, native.app, modules, mode, metro),
  }, modules, metro);
  const read = (file: string) => JSON5.parse(fs.readFileSync(file, 'utf8'));
  const directory = path.join(plan.harmonyRoot, 'oh_modules/@rnoh/react-native-openharmony');
  contract.rnoh = read(path.join(directory, 'oh-package.json5')).version;
  // RNOH 0.86's trimmed Hermes sources no longer contain npm package metadata.
  // The compiler resolved above is also the one used for Harmony bytecode export.
  contract.development = plan.buildMode === 'debug';

  const file = path.join(plan.exportPaths.rawfileRoot, 'expo-harmony-runtime.json');

  await atomicWriteJson(contract, file, root);
  await atomicWriteJson(contract, path.join(root, '.expo/harmony/runtime.json'), root);
  await publishUpdatesConfigurationAsync(root, plan.exportPaths.rawfileRoot, config, contract.runtimeVersion);

  return contract;
}

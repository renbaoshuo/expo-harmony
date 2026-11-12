/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import path from 'node:path';

import { compileHarmonyModsAsync, normalizeHarmonyConfig, parseHarmonySdkVersion, type ExpoConfigWithHarmony } from '@expo-harmony/config-plugins';
import type { HarmonyRuntimeContract } from '@expo-harmony/expo-modules-autolinking/runtime';
import { withHarmonyPrebuildConfig } from '@expo-harmony/prebuild-config';
import { getHarmonyProjectConfig, type EnvMode } from '@expo-harmony/expo__config/internal/project-config';
import JSON5 from 'json5';

import { fingerprintHarmonyAsync } from './fingerprint';
import { HarmonyCliError } from '../errors';
import { loadHarmonyMetroMetadataAsync, readExpoConfigInChildAsync, requireFromExpo, type HarmonyMetroRuntime } from '../expo';
import { isBareHarmonyProject } from '../native/bare';
import { resolveBundledRnohRuntime } from '@expo-harmony/expo-modules-autolinking';
import { resolveHarmonyBuildPlanAsync } from '../native/project';
import type { HarmonyBuildPlan } from '../native/types';
import { ProjectPackages } from '../upstream';

export async function resolveRuntimeVersionAsync(
  root: string,
  config: ExpoConfigWithHarmony,
  app,
  modules?: Readonly<HarmonyRuntimeContract['modules']>,
  mode?: EnvMode,
  metro?: HarmonyMetroRuntime
): Promise<string> {
  const runtimeVersion = config.harmony?.runtimeVersion ?? config.runtimeVersion;

  if (typeof runtimeVersion === 'object' && runtimeVersion?.policy === 'nativeVersion') {
    return `${app.versionName}(${app.versionCode})`;
  }

  if (typeof runtimeVersion === 'object' && runtimeVersion?.policy === 'fingerprint') {
    const runtime = metro ?? await readMetroRuntimeAsync(root, mode);
    return (await fingerprintHarmonyAsync(root, resolveMetroRuntimeRoot(root, runtime), modules, config, mode)).hash;
  }

  if (typeof runtimeVersion === 'object' && runtimeVersion?.policy === 'appVersion') {
    return config.harmony?.versionName ?? config.version ?? '1.0.0';
  }

  const { getRuntimeVersionAsync } = requireFromExpo(root)('@expo/config-plugins/build/utils/Updates');
  const version = await getRuntimeVersionAsync(root, {
    sdkVersion: config.sdkVersion,
    runtimeVersion: runtimeVersion ?? { policy: 'sdkVersion' },
  }, 'harmony');

  if (typeof version !== 'string' || !version) {
    throw new HarmonyCliError(
      'ERR_HARMONY_RUNTIME_CONFIG',
      'Cannot resolve expo.runtimeVersion for Harmony.',
      { operation: 'runtime-contract' }
    );
  }

  return version;
}

export async function readMetroRuntimeAsync(root: string, mode?: EnvMode): Promise<HarmonyMetroRuntime> {
  const { runtime } = await loadHarmonyMetroMetadataAsync(root, mode);
  return runtime ?? {
    reactPackage: 'react',
    harmonyPackage: ProjectPackages.rnohRuntime,
  };
}

export function resolveMetroRuntimeRoot(root: string, runtime: HarmonyMetroRuntime): string {
  if (runtime.harmonyPackageRoot) return runtime.harmonyPackageRoot;
  if (runtime.harmonyPackage === ProjectPackages.rnohRuntime) return resolveBundledRnohRuntime(root);

  const require = createRequire(path.join(root, 'package.json'));
  return path.dirname(require.resolve(runtime.harmonyPackage + '/package.json'));
}

function nativeLibFilterHash(filter): string | undefined {
  if (filter === undefined) return undefined;

  const values = {};

  for (const key of ['excludes', 'pickFirsts', 'pickLasts']) {
    if (filter[key]?.length) values[key] = [...new Set(filter[key])].sort();
  }
  if (filter.enableOverride) values['enableOverride'] = true;

  return Object.keys(values).length ? createHash('sha256').update(JSON.stringify(values)).digest('hex') : undefined;
}

function nativeConfig(profile, module, build, product: string, ability: string): HarmonyRuntimeContract['config'] {
  const selected = profile?.app?.products?.find(item => item.name === product);
  const entry = module?.abilities?.find(item => item.name === ability);
  const targetSdk = selected.targetSdkVersion ?? selected.compileSdkVersion;
  const hash = nativeLibFilterHash(build.buildOption?.nativeLib?.filter);

  return {
    nativeCompiler: selected.buildOption?.nativeCompiler ?? 'BiSheng',
    ...(targetSdk === undefined ? {} : { targetApiVersion: parseHarmonySdkVersion(targetSdk, 'targetSdkVersion').api }),
    compatibleApiVersion: parseHarmonySdkVersion(selected.compatibleSdkVersion, 'compatibleSdkVersion').api,
    ...(hash ? { nativeLibFilterHash: hash } : {}),
    permissions: [...new Set<string>((module.requestPermissions || []).map(item => item.name))].sort(),
    querySchemes: [...new Set<string>(module.querySchemes || [])].sort(),
    backgroundModes: [...new Set<string>(entry?.backgroundModes || [])].sort(),
    abiFilters: [...(build.buildOption?.externalNativeOptions?.abiFilters || [])].sort(),
  };
}

export function readNativeRuntime(plan: HarmonyBuildPlan) {
  const read = (file: string) => JSON5.parse(fs.readFileSync(file, 'utf8'));
  const app = read(path.join(plan.harmonyRoot, 'AppScope/app.json5')).app;
  const profile = read(plan.projectFiles.projectBuildProfile);
  const module = read(plan.projectFiles.moduleJson).module;
  const build = read(path.join(plan.moduleRoot, 'build-profile.json5'));

  return { app, config: nativeConfig(profile, module, build, plan.productName, plan.abilityName) };
}

export async function evaluateProjectNativeRuntimeAsync(root: string, mode?: EnvMode) {
  const { exp } = getHarmonyProjectConfig(root, { skipSDKVersionRequirement: true, isModdedConfig: true }, mode);
  const config = exp as ExpoConfigWithHarmony;
  let native: ReturnType<typeof readNativeRuntime>;
  let bundle: string;

  if (config.harmony && !isBareHarmonyProject(root)) {
    const settings = normalizeHarmonyConfig(config);
    const evaluated = await compileHarmonyModsAsync(withHarmonyPrebuildConfig(config), {
      projectRoot: root,
      introspect: true,
      ignoreExistingNativeFiles: true,
    });
    const results = evaluated._internal?.modResults?.harmony;
    native = {
      app: results?.appJson?.app,
      config: nativeConfig(
        results?.projectBuildProfile,
        results?.moduleJson?.module,
        results?.entryBuildProfile,
        settings.productName,
        settings.abilityName
      ),
    };
    bundle = settings.bundleName;
  } else {
    const plan = await resolveHarmonyBuildPlanAsync(root);
    native = readNativeRuntime(plan);
    bundle = plan.bundleName;
  }

  const serializable = { ...config };
  delete (serializable as { mods?: unknown }).mods;
  return { config: serializable, bundleName: bundle, native };
}

export async function readProjectRuntimeAsync(root: string, options: {
  mode?: EnvMode;
  modules?: Readonly<HarmonyRuntimeContract['modules']>;
  metro?: HarmonyMetroRuntime;
} = {}) {
  const { mode, modules, metro } = options;
  const { config, bundleName, native } = isBareHarmonyProject(root)
    ? await evaluateProjectNativeRuntimeAsync(root, mode)
    : await readExpoConfigInChildAsync<Awaited<ReturnType<typeof evaluateProjectNativeRuntimeAsync>>>(root, 'native-runtime', mode);

  return {
    config, bundleName, native: native.config,
    runtimeVersion: await resolveRuntimeVersionAsync(root, config, native.app, modules, mode, metro),
  };
}

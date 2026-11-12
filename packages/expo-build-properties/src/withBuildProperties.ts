/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { createRequire } from 'node:module';
import path from 'node:path';

import {
  createRunOncePlugin,
  normalizeHarmonyConfig,
  registerHarmonyConfigPlugin,
  withEntryBuildProfile,
  withModuleJson,
  withProjectBuildProfile,
  type HarmonyConfigPlugin,
  type ExpoConfigWithHarmony,
} from '@expo-harmony/config-plugins';

import {
  applyBuildPropertiesConfig,
  getBuildProperties,
  validatePluginConfig,
  type PluginConfigType,
} from './pluginConfig';
import { mergeBuildProperties, type BuildPropertiesScope, type ReconcileBuildProperties } from './reconcile';

const pkg = createRequire(__filename)('../package.json') as { name: string; version: string };
type Json = Record<string, unknown>;

function optionalRecord(value: unknown): Json | undefined {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Json : undefined;
}

function applyOptionalProperties(
  config: Pick<ExpoConfigWithHarmony, '_internal'>,
  scope: BuildPropertiesScope,
  value: unknown,
  patch: Json
): Json | undefined {
  const current = optionalRecord(value);
  const reconcile: ReconcileBuildProperties | undefined = config._internal?.harmonyReconcileBuildProperties;
  return reconcile ? reconcile(scope, current, patch) : mergeBuildProperties(current, patch);
}

const withMods: HarmonyConfigPlugin = (config) => {
  config = withProjectBuildProfile(config, (mod) => {
    const harmony = normalizeHarmonyConfig(mod.modRawConfig);
    const props = getBuildProperties(mod.modRawConfig) ?? {};
    const app = optionalRecord(mod.modResults.app) ?? {};
    const products: Json[] = Array.isArray(app.products) ? app.products : [];
    const existing = products.find(product => product.name === harmony.productName) ?? { name: harmony.productName };
    const buildOption = applyOptionalProperties(mod, 'product', existing.buildOption,
      props.nativeCompiler === undefined ? {} : { nativeCompiler: props.nativeCompiler });

    const product = {
      ...existing,
      name: harmony.productName,
      compatibleSdkVersion: harmony.compatibleSdkVersionString,
      targetSdkVersion: harmony.targetSdkVersionString,
      buildOption: { nativeCompiler: 'BiSheng', ...buildOption },
    };
    const next = products.map(item => item.name === product.name ? product : item);
    if (!products.some(item => item.name === product.name)) next.push(product);

    mod.modResults.app = { ...app, products: next };

    return mod;
  });

  config = withEntryBuildProfile(config, (mod) => {
    const harmony = normalizeHarmonyConfig(mod.modRawConfig);
    const props = getBuildProperties(mod.modRawConfig) ?? {};
    const filter = props.nativeLib?.filter;
    const build = applyOptionalProperties(mod, 'entry', mod.modResults.buildOption,
      filter && Object.keys(filter).length ? { nativeLib: { filter } } : {});
    mod.modResults.buildOption = {
      ...build,
      externalNativeOptions: { ...optionalRecord(build?.externalNativeOptions), abiFilters: harmony.abiFilters },
    };

    const modes: Json[] = Array.isArray(mod.modResults.buildOptionSet) ? [...mod.modResults.buildOptionSet] : [];
    const releaseIndex = modes.findIndex(item => item.name === 'release');
    const existingRelease = modes[releaseIndex];
    const rules = props.release?.obfuscation;
    const debugSymbol = props.release?.debugSymbol;
    const releasePatch: Json = {};
    if (rules) {
      // ArkGuard resolves keep/namecache paths relative to the source rule file.
      const files = rules.files?.map(file => path.relative(
        path.dirname(mod.modRequest.modFile!),
        path.resolve(mod.modRequest.projectRoot, file)
      ).split(path.sep).join('/'));
      releasePatch.arkOptions = { obfuscation: { ruleOptions: {
        enable: rules.enable,
        ...(files === undefined ? {} : { files }),
      } } };
    }
    if (debugSymbol && Object.keys(debugSymbol).length) releasePatch.nativeLib = { debugSymbol };
    if (Object.keys(releasePatch).length) releasePatch.name = 'release';

    const release = applyOptionalProperties(mod, 'release', existingRelease, releasePatch);
    if (release) {
      const namedRelease = { ...release, name: 'release' };
      if (releaseIndex === -1) modes.push(namedRelease);
      else modes[releaseIndex] = namedRelease;
      mod.modResults.buildOptionSet = modes;
    } else if (releaseIndex !== -1) {
      modes.splice(releaseIndex, 1);
      if (modes.length) mod.modResults.buildOptionSet = modes;
      else delete mod.modResults.buildOptionSet;
    }

    return mod;
  });

  return withModuleJson(config, (mod) => {
    const props = getBuildProperties(mod.modRawConfig) ?? {};
    const patch: Json = {};
    if (props.compressNativeLibs !== undefined) patch.compressNativeLibs = props.compressNativeLibs;
    if (props.extractNativeLibs !== undefined) patch.extractNativeLibs = props.extractNativeLibs;
    const module = applyOptionalProperties(mod, 'module', mod.modResults.module, patch);
    if (module) mod.modResults.module = module;

    return mod;
  });
};

export const withBuildPropertiesDefaults = createRunOncePlugin(withMods, pkg.name, pkg.version);

export const withBuildProperties: HarmonyConfigPlugin<PluginConfigType | void> = (config, options) => {
  if (!config.harmony?.bundleName && !config.platforms?.includes('harmony')) return config;

  const next = validatePluginConfig(options ?? {});
  const previous = getBuildProperties(config);
  const props = { ...previous, ...next };

  if (previous?.nativeLib?.filter && next.nativeLib) {
    props.nativeLib = { filter: { ...previous.nativeLib.filter, ...next.nativeLib.filter } };
  }

  if (previous?.release && next.release) {
    props.release = { ...previous.release, ...next.release };
    if (previous.release.debugSymbol && next.release.debugSymbol) {
      props.release.debugSymbol = { ...previous.release.debugSymbol, ...next.release.debugSymbol };
    }
  }
  config = applyBuildPropertiesConfig(config, props);
  config._internal ??= {};

  config._internal.harmonyBuildProperties = props;
  config = registerHarmonyConfigPlugin(config, pkg.name);

  return withBuildPropertiesDefaults(config);
};

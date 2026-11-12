/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import path from 'node:path';

import {
  atomicWrite, normalizeHarmonyConfig, recordManagedFile, stableHarmonyJson, withHarmonyAutolinking,
} from '@expo-harmony/config-plugins';
import { getHarmonyConfigPlugins, withCngManifest, type ManagedManifestConfig } from '@expo-harmony/config-plugins/internal';
import {
  linkPreparedModulesAsync, ModuleBuildOptionsArtifact, prepareModulesAsync, type LinkOptions,
} from '@expo-harmony/expo-modules-autolinking';

import { HarmonyPrebuildError } from '../errors';
import {
  createHarmonyBuildDescriptor,
  resolveHarmonyBuildPath,
} from '../buildDescriptor';
import { CngManifestPath, createCngManifest } from '../manifest';
import { reconcileDeferredPluginFilesAsync } from '../stale';
import type { HarmonyPrebuildOptions } from '../withHarmonyPrebuildConfig';

function formatAutolinkingDiagnostics(cause) {
  return Array.isArray(cause.diagnostics)
    ? ` ${cause.diagnostics.map(item => `[${item.code}] ${item.message}`).join(' ')}`
    : '';
}

export function withAutolinkingMods(config, options: HarmonyPrebuildOptions) {
  config = withHarmonyAutolinking(config, async (mod) => {
    if (mod.modRequest.introspect) return mod;

    const harmony = normalizeHarmonyConfig(mod.modRawConfig);
    const mode = options.buildType ?? process.env.EXPO_HARMONY_BUILD_TYPE ?? 'debug';
    if (mode !== 'debug' && mode !== 'release') {
      throw new HarmonyPrebuildError(
        'ERR_HARMONY_CONFIG_INVALID', 'EXPO_HARMONY_BUILD_TYPE must be debug or release.', { operation: 'autolinking' }
      );
    }

    try {
      const root = mod.modRequest.projectRoot;
      const project = await fs.promises.realpath(root);

      const build = createHarmonyBuildDescriptor(harmony, mod._internal?.harmonySigningConfig?.name ?? null);
      const platform = resolveHarmonyBuildPath(project, build.harmonyRoot);

      const moduleBuilds = harmony.moduleBuilds || {};
      const moduleBuildSettings = {
        compatibleSdkVersion: harmony.compatibleSdkVersionString,
        targetSdkVersion: harmony.targetSdkVersionString,
        abiFilters: harmony.abiFilters,
      };
      // Keep configured module builds available to subsequent CLI and DevEco relinks.
      const inputs = path.join(root, ModuleBuildOptionsArtifact);

      const linkOptions: LinkOptions = {
        moduleBuilds,
        moduleBuildSettings,
        expoInlineModules: mod.experiments?.inlineModules ?? null,
        projectRoot: project,
        harmonyProjectPath: platform,
        buildType: mode,
      };
      const prepared = await prepareModulesAsync(linkOptions);
      const result = await linkPreparedModulesAsync(linkOptions, prepared);

      recordManagedFile(mod, inputs, 'autolinking');
      mod._internal ??= {};
      mod._internal.harmonyAutolinkingModules = result.modules;

      for (const relative of result.managedArtifacts) {
        const target = path.join(root, ...relative.split('/'));

        if (fs.existsSync(target)) {
          recordManagedFile(mod, target, 'autolinking');
        }
      }

      recordManagedFile(
        mod,
        resolveHarmonyBuildPath(root, build.nativeInputs.manifest),
        'autolinking'
      );

      return mod;
    } catch (cause) {
      throw new HarmonyPrebuildError(
        'ERR_HARMONY_AUTOLINK_FAILED',
        `Harmony autolinking failed: ${cause.message}${formatAutolinkingDiagnostics(cause)}`,
        { cause, operation: 'autolinking' }
      );
    }
  });

  config = withCngManifest(config, async (mod) => {
    if (mod.modRequest.introspect) return mod;

    const harmony = normalizeHarmonyConfig(mod.modRawConfig);
    const retained = await reconcileDeferredPluginFilesAsync(mod);
    const managed = [...(mod._internal?.harmonyManagedFiles || []), ...retained];
    const moduleConfig = mod._internal?.harmonyManagedModuleConfig;
    const pluginChanges: ManagedManifestConfig[] | undefined = mod._internal?.harmonyManagedManifestConfig;

    const manifest = await createCngManifest(
      mod.modRequest.projectRoot,
      harmony,
      managed,
      mod._internal?.harmonyAutolinkingModules || [],
      mod._internal?.harmonySigningConfig?.name ?? null,
      getHarmonyConfigPlugins(mod),
      {
        moduleConfig: pluginChanges?.length ? { ...moduleConfig, pluginChanges } : moduleConfig,
        buildProperties: mod._internal?.harmonyManagedBuildProperties,
      }
    );
    const file = resolveHarmonyBuildPath(mod.modRequest.projectRoot, CngManifestPath);

    await atomicWrite(file, stableHarmonyJson(manifest));
    await mod._internal?.harmonyFinishJsonOwnershipJournal?.();

    mod._internal ??= {};
    mod._internal.harmonyCngManifest = manifest;

    return mod;
  });

  return config;
}

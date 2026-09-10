import fs from 'node:fs';
import path from 'node:path';

import { linkModulesAsync } from '@expo-harmony/expo-modules-autolinking';
import { normalizeHarmonyConfig, recordManagedFile, stableHarmonyJson, withHarmonyAutolinking } from '@expo-harmony/config-plugins';
import { getHarmonyConfigPlugins, withCngManifest } from '@expo-harmony/config-plugins/internal';

import { HarmonyPrebuildError } from '../errors';
import {
  createHarmonyBuildDescriptor,
  resolveHarmonyBuildPath,
} from '../buildDescriptor';
import { CngManifestPath, createCngManifest } from '../manifest';
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

      const result = await linkModulesAsync({
        projectRoot: project,
        harmonyProjectPath: platform,
        buildType: mode,
      });

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
    const managed = mod._internal?.harmonyManagedFiles || [];

    const manifest = await createCngManifest(
      mod.modRequest.projectRoot,
      harmony,
      managed,
      mod._internal?.harmonyAutolinkingModules || [],
      mod._internal?.harmonySigningConfig?.name ?? null,
      getHarmonyConfigPlugins(mod)
    );
    const file = resolveHarmonyBuildPath(mod.modRequest.projectRoot, CngManifestPath);

    await fs.promises.mkdir(path.dirname(file), { recursive: true });
    await fs.promises.writeFile(file, stableHarmonyJson(manifest));

    mod._internal ??= {};
    mod._internal.harmonyCngManifest = manifest;

    return mod;
  });

  return config;
}

import fs from 'node:fs';
import path from 'node:path';

import { linkModulesAsync } from '@expo-harmony/expo-modules-autolinking';
import {
  getHarmonyConfigPlugins,
  recordManagedFile,
  stableHarmonyJson,
  withCngManifest,
  withHarmonyAutolinking,
} from '@expo-harmony/config-plugins';

import { HarmonyPrebuildError } from '../errors';
import {
  createHarmonyBuildDescriptor,
  resolveHarmonyBuildPath,
} from '../buildDescriptor';
import { CngManifestPath, createCngManifest } from '../manifest';

function formatAutolinkingDiagnostics(cause) {
  return Array.isArray(cause.diagnostics)
    ? ` ${cause.diagnostics.map(item => `[${item.code}] ${item.message}`).join(' ')}`
    : '';
}

export function withAutolinkingMods(config, harmony, options) {
  config = withHarmonyAutolinking(config, async (mod) => {
    try {
      const root = mod.modRequest.projectRoot;
      const project = await fs.promises.realpath(root);

      const build = createHarmonyBuildDescriptor(harmony, mod._internal?.harmonySigningConfig?.name ?? null);
      const platform = resolveHarmonyBuildPath(project, build.harmonyRoot);
      const mode = (options.buildType || process.env.EXPO_HARMONY_BUILD_TYPE || 'debug') as 'debug' | 'release';

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

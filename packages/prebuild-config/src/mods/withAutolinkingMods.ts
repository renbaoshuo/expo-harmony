import fs from 'node:fs';
import path from 'node:path';

import { linkModulesAsync } from '@expo-harmony/expo-modules-autolinking';
import { getHarmonyConfigPlugins, recordManagedFile, stableHarmonyJson, withCngManifest, withHarmonyAutolinking } from '@expo-harmony/config-plugins';

import { HarmonyPrebuildError } from '../errors';
import {
  createHarmonyBuildDescriptor,
  resolveHarmonyBuildPath,
} from '../buildDescriptor';
import { writeExpoCmakeWrapperAsync } from '../generatedFiles';
import { CngManifestPath, createCngManifest } from '../manifest';

function formatAutolinkingDiagnostics(cause) {
  return Array.isArray(cause.diagnostics)
    ? ` ${cause.diagnostics.map(item => `[${item.code}] ${item.message}`).join(' ')}`
    : '';
}

export function withAutolinkingMods(config, normalized, options) {
  config = withHarmonyAutolinking(config, async (value) => {
    try {
      const logicalProjectRoot = value.modRequest.projectRoot;
      const physicalProjectRoot = await fs.promises.realpath(logicalProjectRoot);
      const build = createHarmonyBuildDescriptor(normalized, value._internal?.harmonySigningConfig?.name ?? null);
      const physicalHarmonyProjectPath = resolveHarmonyBuildPath(physicalProjectRoot, build.harmonyRoot);
      const buildType = (options.buildType || process.env.EXPO_HARMONY_BUILD_TYPE || 'debug') as 'debug' | 'release';

      const result = await linkModulesAsync({
        projectRoot: physicalProjectRoot,
        harmonyProjectPath: physicalHarmonyProjectPath,
        buildType,
      });
      const cmakeWrapper = await writeExpoCmakeWrapperAsync(logicalProjectRoot, build.projectFiles.cmakeWrapper);

      value._internal ??= {};
      value._internal.harmonyAutolinkingModules = result.modules;
      for (const relative of result.managedArtifacts) {
        const target = path.join(logicalProjectRoot, ...relative.split('/'));
        if (fs.existsSync(target)) {
          recordManagedFile(value, target, 'autolinking');
        }
      }
      recordManagedFile(value, resolveHarmonyBuildPath(logicalProjectRoot, build.nativeInputs.manifest), 'autolinking');
      recordManagedFile(value, cmakeWrapper, 'autolinking');
      return value;
    } catch (cause) {
      throw new HarmonyPrebuildError('ERR_HARMONY_AUTOLINK_FAILED', `Harmony autolinking failed: ${cause.message}${formatAutolinkingDiagnostics(cause)}`, { cause, operation: 'autolinking' });
    }
  });

  config = withCngManifest(config, async (value) => {
    const managed = value._internal?.harmonyManagedFiles || [];
    const manifest = await createCngManifest(
      value.modRequest.projectRoot,
      normalized,
      managed,
      value._internal?.harmonyAutolinkingModules || [],
      value._internal?.harmonySigningConfig?.name ?? null,
      getHarmonyConfigPlugins(value)
    );
    const file = resolveHarmonyBuildPath(value.modRequest.projectRoot, CngManifestPath);

    await fs.promises.mkdir(path.dirname(file), { recursive: true });
    await fs.promises.writeFile(file, stableHarmonyJson(manifest));
    value._internal ??= {};
    value._internal.harmonyCngManifest = manifest;
    return value;
  });

  return config;
}

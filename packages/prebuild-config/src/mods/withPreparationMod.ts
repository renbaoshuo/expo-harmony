import fs from 'node:fs';
import path from 'node:path';

import { resolveModulesAsync } from '@expo-harmony/expo-modules-autolinking';
import {
  getHarmonyConfigPlugins,
  recordManagedFile,
  withHarmonyDangerousMod,
} from '@expo-harmony/config-plugins';

import { HarmonyPrebuildError } from '../errors';
import {
  ensureGitignoreEntryAsync,
  writeExpoConstantsHeaderAsync,
} from '../generatedFiles';
import { readSigningConfigFile } from '../signing';
import {
  findStaleConfigPlugins,
  readPreviousCngManifestAsync,
  removeStalePluginFilesAsync,
} from '../stale';

function formatAutolinkingDiagnostics(cause) {
  return Array.isArray(cause.diagnostics)
    ? ` ${cause.diagnostics.map(item => `[${item.code}] ${item.message}`).join(' ')}`
    : '';
}

function withPreparationMod(config, normalized) {
  return withHarmonyDangerousMod(config, async (value) => {
    const projectRoot = value.modRequest.projectRoot;
    const harmonyRoot = value.modRequest.platformProjectRoot;
    const previousManifest = await readPreviousCngManifestAsync(projectRoot, normalized);
    const currentPlugins = getHarmonyConfigPlugins(value);
    const stalePlugins = findStaleConfigPlugins(previousManifest, currentPlugins);

    value._internal ??= {};
    value._internal.harmonyPreviousSigningConfigName
      = typeof previousManifest?.signingConfigName === 'string'
        ? previousManifest.signingConfigName
        : null;
    value._internal.harmonyPreviousManagedIdentity
      = previousManifest?.managedIdentity && typeof previousManifest.managedIdentity === 'object'
        ? previousManifest.managedIdentity
        : null;
    value._internal.harmonyConfigPlugins = currentPlugins;
    value._internal.harmonyStaleConfigPlugins = stalePlugins;

    await removeStalePluginFilesAsync(projectRoot, previousManifest, stalePlugins);

    const packedGitignore = path.join(harmonyRoot, 'gitignore');
    const gitignore = path.join(harmonyRoot, '.gitignore');
    if (fs.existsSync(packedGitignore)) {
      if (fs.existsSync(gitignore)) {
        const [packed, existing] = await Promise.all([
          fs.promises.readFile(packedGitignore),
          fs.promises.readFile(gitignore),
        ]);
        if (!packed.equals(Uint8Array.from(existing))) {
          throw new HarmonyPrebuildError('ERR_HARMONY_CONFIG_INVALID', 'The packed Harmony gitignore conflicts with an existing harmony/.gitignore.', { file: gitignore, operation: 'restore-gitignore' });
        }
        await fs.promises.rm(packedGitignore);
      } else {
        await fs.promises.rename(packedGitignore, gitignore);
      }
    }
    await ensureGitignoreEntryAsync(gitignore, '/build-profile.json5');
    recordManagedFile(value, gitignore, 'dangerous');

    const constantsHeader = await writeExpoConstantsHeaderAsync(
      projectRoot,
      normalized,
      config
    );
    recordManagedFile(value, constantsHeader, 'dangerous');

    if (normalized.signingConfigFile) {
      const signing = await readSigningConfigFile(
        projectRoot,
        normalized.signingConfigFile
      );
      value._internal.harmonySigningConfig = signing.config;
    }

    try {
      const physicalProjectRoot = await fs.promises.realpath(projectRoot);
      value._internal.harmonyResolvedModules = await resolveModulesAsync({
        projectRoot: physicalProjectRoot,
      });
    } catch (cause) {
      throw new HarmonyPrebuildError('ERR_HARMONY_AUTOLINK_FAILED', `Harmony module resolution failed: ${cause.message}${formatAutolinkingDiagnostics(cause)}`, { cause, operation: 'resolve-autolinking' });
    }
    return value;
  });
}

export { withPreparationMod };

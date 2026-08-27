import fs from 'node:fs';
import path from 'node:path';

import {
  getHarmonyConfigPlugins,
  recordManagedFile,
  withHarmonyDangerousMod,
} from '@expo-harmony/config-plugins';

import { createHarmonyBuildDescriptor } from '../buildDescriptor';
import { HarmonyPrebuildError } from '../errors';
import { ensureGitignoreEntryAsync } from '../generatedFiles';
import { readSigningConfigFile } from '../signing';
import {
  findStaleConfigPlugins,
  readPreviousCngManifestAsync,
  removeStalePluginFilesAsync,
} from '../stale';

function withPreparationMod(config, normalized) {
  return withHarmonyDangerousMod(config, async (value) => {
    const projectRoot = value.modRequest.projectRoot;
    const harmonyRoot = value.modRequest.platformProjectRoot;
    const previousManifest = await readPreviousCngManifestAsync(projectRoot);
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

    const build = createHarmonyBuildDescriptor(normalized, null);
    const profile = path.posix.relative(build.harmonyRoot, build.projectFiles.projectBuildProfile);
    await ensureGitignoreEntryAsync(gitignore, `/${profile}`);
    recordManagedFile(value, gitignore, 'dangerous');

    if (normalized.signingConfigFile) {
      const signing = await readSigningConfigFile(
        projectRoot,
        normalized.signingConfigFile
      );
      value._internal.harmonySigningConfig = signing.config;
    }
    return value;
  });
}

export { withPreparationMod };

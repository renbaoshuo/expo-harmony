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

function withPreparationMod(config, harmony) {
  return withHarmonyDangerousMod(config, async (mod) => {
    const root = mod.modRequest.projectRoot;
    const platform = mod.modRequest.platformProjectRoot;
    const manifest = await readPreviousCngManifestAsync(root);
    const plugins = getHarmonyConfigPlugins(mod);
    const stale = findStaleConfigPlugins(manifest, plugins);

    mod._internal ??= {};
    mod._internal.harmonyPreviousSigningConfigName
      = typeof manifest?.signingConfigName === 'string'
        ? manifest.signingConfigName
        : null;
    mod._internal.harmonyPreviousManagedIdentity
      = manifest?.managedIdentity && typeof manifest.managedIdentity === 'object'
        ? manifest.managedIdentity
        : null;
    mod._internal.harmonyConfigPlugins = plugins;
    mod._internal.harmonyStaleConfigPlugins = stale;

    await removeStalePluginFilesAsync(root, manifest, stale);

    const packed = path.join(platform, 'gitignore');
    const gitignore = path.join(platform, '.gitignore');

    if (fs.existsSync(packed)) {
      if (fs.existsSync(gitignore)) {
        const [source, current] = await Promise.all([
          fs.promises.readFile(packed),
          fs.promises.readFile(gitignore),
        ]);

        if (!source.equals(Uint8Array.from(current))) {
          throw new HarmonyPrebuildError(
            'ERR_HARMONY_CONFIG_INVALID',
            'The packed Harmony gitignore conflicts with an existing harmony/.gitignore.',
            { file: gitignore, operation: 'restore-gitignore' }
          );
        }

        await fs.promises.rm(packed);
      } else {
        await fs.promises.rename(packed, gitignore);
      }
    }

    const build = createHarmonyBuildDescriptor(harmony, null);
    const profile = path.posix.relative(build.harmonyRoot, build.projectFiles.projectBuildProfile);

    await ensureGitignoreEntryAsync(gitignore, `/${profile}`);
    recordManagedFile(mod, gitignore, 'dangerous');

    if (harmony.signingConfigFile) {
      const signing = await readSigningConfigFile(
        root,
        harmony.signingConfigFile
      );

      mod._internal.harmonySigningConfig = signing.config;
    }

    return mod;
  });
}

export { withPreparationMod };

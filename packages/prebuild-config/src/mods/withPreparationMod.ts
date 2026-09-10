import fs from 'node:fs';
import path from 'node:path';

import { normalizeHarmonyConfig, recordManagedFile, withHarmonyDangerousMod } from '@expo-harmony/config-plugins';
import { getHarmonyConfigPlugins, withPreparation } from '@expo-harmony/config-plugins/internal';

import { HarmonyPrebuildError } from '../errors';
import { readSigningConfigFile } from '../signing';
import { resolve as resolveTemplate } from '../template';
import {
  findStaleConfigPlugins,
  readPreviousCngManifestAsync,
  removeStalePluginFilesAsync,
} from '../stale';

function withPreparationMod(config) {
  const prepare = async (mod) => {
    const harmony = normalizeHarmonyConfig(mod.modRawConfig);
    const root = mod.modRequest.projectRoot;
    const platform = mod.modRequest.platformProjectRoot;
    const manifest = mod.modRequest.ignoreExistingNativeFiles ? null : await readPreviousCngManifestAsync(root);
    const plugins = getHarmonyConfigPlugins(mod);
    const stale = findStaleConfigPlugins(manifest, plugins);

    mod._internal ??= {};
    if (mod.modRequest.introspect) mod._internal.harmonyTemplateDirectory = path.join(resolveTemplate().root, 'harmony');
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

    mod._internal.harmonyStalePluginFiles = await removeStalePluginFilesAsync(
      root, manifest, stale, plugins, mod.modRequest.introspect
    );

    if (harmony.signingConfigFile) {
      const signing = await readSigningConfigFile(root, harmony.signingConfigFile);
      mod._internal.harmonySigningConfig = signing.config;
    }

    if (mod.modRequest.introspect) return mod;

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

    recordManagedFile(mod, gitignore, 'dangerous');

    return mod;
  };

  config = withHarmonyDangerousMod(config, prepare);

  return withPreparation(config, mod => mod.modRequest.introspect ? prepare(mod) : mod);
}

export { withPreparationMod };

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import path from 'node:path';

import { normalizeHarmonyConfig, recordManagedFile, withHarmonyDangerousMod } from '@expo-harmony/config-plugins';
import { getHarmonyConfigPlugins, withPreparation } from '@expo-harmony/config-plugins/internal';
import { createBuildPropertiesReconciler } from '@expo-harmony/expo-build-properties/internal';

import { prepareJsonOwnershipJournal } from '../jsonOwnershipJournal';
import { HarmonyPrebuildError } from '../errors';
import { readSigningConfigFile } from '../signing';
import { resolve as resolveTemplate } from '../template';
import {
  findDeferredPluginFiles,
  findStaleConfigPlugins,
  readPreviousCngManifestAsync,
  removeStalePluginFilesAsync,
} from '../stale';

function withPreparationMod(config) {
  const prepare = async (mod) => {
    const harmony = normalizeHarmonyConfig(mod.modRawConfig);
    const root = mod.modRequest.projectRoot;
    const platform = mod.modRequest.platformProjectRoot;

    // Expo copies the template before mods run; use the state captured by the CLI.
    const fresh = process.env.EXPO_HARMONY_PREBUILD_FRESH === '1' || mod.modRequest.ignoreExistingNativeFiles;
    const manifest = fresh
      ? null
      : await readPreviousCngManifestAsync(root);
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

    const { pluginChanges, ...moduleConfig } = manifest?.managedModuleConfig
      ?? { permissions: [], querySchemes: [], skills: [] };
    const ownership = await prepareJsonOwnershipJournal(
      root, platform, {
        buildProperties: manifest?.managedBuildProperties,
        moduleConfig,
        pluginChanges,
      },
      fresh, mod.modRequest.introspect
    );

    mod._internal.harmonyPreviousManagedModuleConfig = ownership.applied.moduleConfig;
    mod._internal.harmonyManagedModuleConfig = ownership.managed.moduleConfig;
    mod._internal.harmonyManagedBuildProperties = ownership.managed.buildProperties;
    mod._internal.harmonyReconcileBuildProperties = createBuildPropertiesReconciler(
      ownership.applied.buildProperties, ownership.managed.buildProperties
    );
    mod._internal.harmonyManagedManifestConfig = ownership.managed.pluginChanges;
    mod._internal.harmonyPreviousManagedManifestConfig = ownership.applied.pluginChanges;
    mod._internal.harmonyBeforeJsonWrite = ownership.beforeWrite;
    mod._internal.harmonyFinishJsonOwnershipJournal = ownership.finish;
    mod._internal.harmonyConfigPlugins = plugins;
    mod._internal.harmonyPreviousConfigPlugins = manifest?.configPlugins ?? [];
    mod._internal.harmonyStaleConfigPlugins = stale;
    mod._internal.harmonyDeferredPluginFiles = findDeferredPluginFiles(manifest, plugins);

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

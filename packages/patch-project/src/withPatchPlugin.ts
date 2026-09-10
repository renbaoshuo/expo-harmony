import fs from 'node:fs/promises';
import path from 'node:path';

import { createRunOncePlugin, HarmonyPaths, recordManagedFile, registerHarmonyConfigPlugin, type HarmonyConfigPlugin } from '@expo-harmony/config-plugins';
import { withProjectPatch } from '@expo-harmony/config-plugins/internal';
import { WarningAggregator, type ModPlatform } from '@expo/config-plugins';

import { HarmonyPatchError } from './errors';
import { applyPatchAsync, getPatchChangedLinesAsync } from './gitPatch';
import { getPatchFilesAsync } from './patches';

export interface PatchPluginProps {
  patchRoot?: string;
  changedLinesLimit?: number;
}

const owner = '@expo-harmony/patch-project';

const withPatchPlugin: HarmonyConfigPlugin<PatchPluginProps | void> = (config, props) => {
  const options = props || {};
  const limit = options.changedLinesLimit ?? 300;
  if ((options.patchRoot !== undefined && (typeof options.patchRoot !== 'string' || !options.patchRoot.trim()))
    || !Number.isFinite(limit) || limit < 0) {
    throw new HarmonyPatchError('ERR_HARMONY_CONFIG_INVALID', 'patchRoot must be a non-empty directory path and changedLinesLimit must be a non-negative number.');
  }

  registerHarmonyConfigPlugin(config, owner);

  return withProjectPatch(config, async (mod) => {
    if (mod.modRequest.introspect || process.env.EXPO_HARMONY_SKIP_PATCHES === '1') return mod;

    const root = mod.modRequest.projectRoot;
    const directory = await HarmonyPaths.resolveHarmonyPath(root, options.patchRoot ?? 'cng-patches');
    const files = await getPatchFilesAsync(directory);
    if (!files.length) return mod;

    const checksum = mod._internal?.templateChecksum;
    const name = `harmony+${checksum}.patch`;
    if (!checksum || !files.includes(name)) {
      WarningAggregator.addWarningForPlatform('harmony' as ModPlatform, owner, `No patch matches the current template${checksum ? ` (${checksum})` : ''}. Existing Harmony patches were not applied. Review and regenerate them with npx @expo-harmony/patch-project.`);

      return mod;
    }
    if (files.length > 1) {
      WarningAggregator.addWarningForPlatform('harmony' as ModPlatform, owner, `Multiple Harmony patches found; only ${name} will be applied.`);
    }

    const file = await HarmonyPaths.resolveHarmonyPath(directory, name);
    const source = await fs.readFile(file, 'utf8');
    if (!source.trim()) return mod;

    const changed = await getPatchChangedLinesAsync(file);
    if (changed > limit) {
      WarningAggregator.addWarningForPlatform('harmony' as ModPlatform, owner, `${name} has ${changed} changed lines, exceeding the warning limit of ${limit}. Consider a config plugin for larger changes.`);
    }

    const result = await applyPatchAsync(root, source);
    registerHarmonyConfigPlugin(mod, owner, { files: result.created });
    for (const relative of result.files) {
      const file = path.join(mod.modRequest.platformProjectRoot, relative);
      const managed = mod._internal?.harmonyManagedFiles?.find(item => item.path === `harmony/${relative}`);
      recordManagedFile(mod, file, managed?.owner ?? (result.created.includes(relative) ? owner : 'patch'));
    }

    return mod;
  });
};

export default createRunOncePlugin(withPatchPlugin, owner);

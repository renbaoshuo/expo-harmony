/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs/promises';
import path from 'node:path';

import { createRunOncePlugin, HarmonyPaths, recordManagedFile, registerHarmonyConfigPlugin, type HarmonyConfigPlugin } from '@expo-harmony/config-plugins';
import { getHarmonyConfigPlugins, withProjectPatch } from '@expo-harmony/config-plugins/internal';
import { WarningAggregator, type ModPlatform } from '@expo/config-plugins';

import { HarmonyPatchError } from './errors';
import { applyPatchAsync } from './gitPatch';
import { getPatchFilesAsync } from './patches';

export interface PatchPluginProps {
  patchRoot?: string;
  changedLinesLimit?: number;
}

const owner = '@expo-harmony/patch-project';

interface DeferredPluginFile {
  owner: string;
  path: string;
  sha256: string;
}

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
    const files = await getPatchFilesAsync(directory, true);
    if (!files.length) {
      registerHarmonyConfigPlugin(mod, owner, { files: [] });
      return mod;
    }

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
    if (!(await fs.stat(file)).isFile()) {
      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch input must point to a regular file: ${file}.`);
    }

    const source = await fs.readFile(file);
    const managed: readonly { owner: string; path: string }[] = mod._internal?.harmonyManagedFiles ?? [];
    const deferred: readonly DeferredPluginFile[] = mod._internal?.harmonyDeferredPluginFiles ?? [];
    const otherClaims = new Set([
      ...managed.filter(file => file.owner !== owner).map(file => file.path),
      ...getHarmonyConfigPlugins(mod)
        .filter(plugin => plugin.owner !== owner)
        .flatMap(plugin => (plugin.files ?? []).map(file => `harmony/${file}`)),
    ]);
    const previous = new Map(deferred
      .filter(file => file.owner === owner && !otherClaims.has(file.path))
      .map(file => [file.path, file.sha256]));
    const claims = { ...mod, _internal: { ...mod._internal } };
    const result = await applyPatchAsync(root, source, previous, (created) => {
      for (const file of created) {
        if (otherClaims.has(`harmony/${file}`)) {
          throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch cannot claim a managed file: harmony/${file}.`);
        }
      }
      registerHarmonyConfigPlugin(claims, owner, { files: created });
    });
    const changed = result.changedLines;
    if (changed > limit) {
      WarningAggregator.addWarningForPlatform('harmony' as ModPlatform, owner, `${name} has ${changed} changed lines, exceeding the warning limit of ${limit}. Consider a config plugin for larger changes.`);
    }

    mod._internal.harmonyConfigPlugins = claims._internal.harmonyConfigPlugins;
    for (const relative of result.files) {
      const file = path.join(mod.modRequest.platformProjectRoot, relative);
      const entry = managed.find(item => item.path === `harmony/${relative}`);
      recordManagedFile(mod, file, entry?.owner ?? (result.created.includes(relative) ? owner : 'patch'));
    }

    return mod;
  });
};

export default createRunOncePlugin(withPatchPlugin, owner);

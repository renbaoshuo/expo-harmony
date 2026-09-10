import {
  normalizeHarmonyConfig, HarmonyPaths, withArkTSPackageProvider, withCMakeLists, withCppPackageProvider,
  withEntryAbility, withIndexPage, withWorker,
} from '@expo-harmony/config-plugins';

import { readTemplateSource } from '../dependencies';
import * as render from '../renderers';

const SourceMods = [
  [withEntryAbility, HarmonyPaths.HARMONY_PATHS.entryAbility, render.renderEntryAbility],
  [withIndexPage, HarmonyPaths.HARMONY_PATHS.indexPage, render.renderIndexPage],
  [withWorker, HarmonyPaths.HARMONY_PATHS.worker],
  [withArkTSPackageProvider, HarmonyPaths.HARMONY_PATHS.arktsPackageProvider],
  [withCppPackageProvider, HarmonyPaths.HARMONY_PATHS.cppPackageProvider],
  [withCMakeLists, HarmonyPaths.HARMONY_PATHS.cmakeLists],
] as const;

export function withSourceMods(config) {
  for (const [plugin, relative, renderer] of SourceMods) {
    config = plugin(config, async (mod) => {
      const harmony = normalizeHarmonyConfig(mod.modRawConfig);
      const source = await readTemplateSource(relative);

      mod.modResults = renderer
        ? renderer(source, harmony)
        : render.renderCanonical(source, `harmony/${relative}`);

      return mod;
    });
  }

  return config;
}

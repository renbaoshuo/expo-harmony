import {
  normalizeHarmonyConfig, HarmonyPaths, withArkTSPackageProvider, withCMakeLists, withCppPackageProvider,
  withAbilityStage, withEntryAbility, withIndexPage, withWorker,
} from '@expo-harmony/config-plugins';

import { readTemplateSource } from '../dependencies';
import * as render from '../renderers';

const SourceMods = [
  [withAbilityStage, HarmonyPaths.HARMONY_PATHS.abilityStage],
  [withEntryAbility, HarmonyPaths.HARMONY_PATHS.entryAbility, render.renderEntryAbility],
  [withIndexPage, HarmonyPaths.HARMONY_PATHS.indexPage],
  [withWorker, HarmonyPaths.HARMONY_PATHS.worker],
  [withArkTSPackageProvider, HarmonyPaths.HARMONY_PATHS.arktsPackageProvider, render.renderPackageProvider],
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

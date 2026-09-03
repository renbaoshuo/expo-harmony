import {
  HarmonyPaths, withArkTSPackageProvider, withCMakeLists, withCppPackageProvider,
  withEntryAbility, withIndexPage, withWorker,
} from '@expo-harmony/config-plugins';

import { readTemplateSource } from '../dependencies';
import * as render from '../renderers';

const SourceMods = [
  [withEntryAbility, HarmonyPaths.HARMONY_PATHS.entryAbility, render.renderEntryAbility],
  [withIndexPage, HarmonyPaths.HARMONY_PATHS.indexPage, render.renderIndexPage],
  [withWorker, HarmonyPaths.HARMONY_PATHS.worker],
  [withArkTSPackageProvider, HarmonyPaths.HARMONY_PATHS.arktsPackageProvider, render.renderArktsPackageProvider],
  [withCppPackageProvider, HarmonyPaths.HARMONY_PATHS.cppPackageProvider, render.renderCppPackageProvider],
  [withCMakeLists, HarmonyPaths.HARMONY_PATHS.cmakeLists, render.renderCmakeLists],
] as const;

export function withSourceMods(config, harmony) {
  for (const [plugin, relative, renderer] of SourceMods) {
    config = plugin(config, async (mod) => {
      const source = await readTemplateSource(relative);

      mod.modResults = renderer
        ? renderer(source, harmony)
        : render.renderCanonical(source, `harmony/${relative}`);

      return mod;
    });
  }

  return config;
}

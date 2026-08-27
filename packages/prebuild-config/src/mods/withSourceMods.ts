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

export function withSourceMods(config, normalized) {
  for (const [plugin, relative, renderer] of SourceMods) {
    config = plugin(config, async (value) => {
      const source = await readTemplateSource(relative);
      value.modResults = renderer ? renderer(source, normalized) : render.renderCanonical(source, `harmony/${relative}`);
      return value;
    });
  }
  return config;
}

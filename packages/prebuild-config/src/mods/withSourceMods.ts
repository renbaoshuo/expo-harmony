import {
  withArkTSPackageProvider, withCMakeLists, withCppPackageProvider,
  withEntryAbility, withIndexPage, withWorker,
} from '@expo-harmony/config-plugins';

import { readTemplateSource } from '../dependencies';
import * as render from '../renderers';

const SourceMods = [
  [withEntryAbility, 'entry/src/main/ets/entryability/EntryAbility.ets', render.renderEntryAbility],
  [withIndexPage, 'entry/src/main/ets/pages/Index.ets', render.renderIndexPage],
  [withWorker, 'entry/src/main/ets/workers/RNOHWorker.ets'],
  [withArkTSPackageProvider, 'entry/src/main/ets/PackageProvider.ets', render.renderArktsPackageProvider],
  [withCppPackageProvider, 'entry/src/main/cpp/PackageProvider.cpp', render.renderCppPackageProvider],
  [withCMakeLists, 'entry/src/main/cpp/CMakeLists.txt', render.renderCmakeLists],
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

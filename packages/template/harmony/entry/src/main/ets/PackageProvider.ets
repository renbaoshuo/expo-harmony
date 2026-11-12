/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModulesPackage, ExpoReactHostFactory } from '@expo-harmony/expo';
import { ExpoRuntimeConfig } from '@expo-harmony/expo-modules-core';
import type { RNInstanceOptions, RNPackage, RNPackageContext } from '@rnoh/react-native-openharmony';
import { createRNOHPackages } from './RNOHPackagesFactory';
import { expoHarmonyHostProvider } from './generated/ExpoHarmonyHostProvider';

export function getRNOHPackages(context: RNPackageContext, runtimeConfig?: ExpoRuntimeConfig): RNPackage[] {
  return [
    new ExpoModulesPackage(context, expoHarmonyHostProvider, runtimeConfig),
    ...createRNOHPackages(context),
  ];
}

export const expoHarmonyWorkerScriptUrl = "__EXPO_HARMONY_MODULE_NAME__" + '/ets/workers/RNOHWorker.ets';

export const expoReactHost = ExpoReactHostFactory.getDefaultReactHost({
  bundlePath: 'hermes_bundle.hbc',
  workerScriptUrl: expoHarmonyWorkerScriptUrl,
  provider: expoHarmonyHostProvider,
  createRNInstanceOptions: (headless: boolean): RNInstanceOptions => ({
    name: "__EXPO_HARMONY_APP_LABEL__",
    createRNPackages: (context: RNPackageContext): RNPackage[] => getRNOHPackages(context, new ExpoRuntimeConfig({ isHeadless: headless })),
    fontResourceByFontFamily: {},
  }),
});

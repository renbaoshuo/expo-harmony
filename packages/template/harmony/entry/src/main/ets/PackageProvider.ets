import { ExpoReactHost, ExpoRuntimeConfig } from '@expo-harmony/expo-modules-core/Autolinking';
import type { RNInstanceOptions, RNPackage, RNPackageContext } from '@rnoh/react-native-openharmony';
import { createRNOHPackages } from './RNOHPackagesFactory';
import { expoHarmonyHostProvider } from './generated/ExpoHarmonyHostProvider';

export function getRNOHPackages(context: RNPackageContext, runtimeConfig?: ExpoRuntimeConfig): RNPackage[] {
  return createRNOHPackages(context, runtimeConfig);
}

export const expoReactHost = new ExpoReactHost({
  bundlePath: 'hermes_bundle.hbc',
  workerScriptUrl: 'entry/ets/workers/RNOHWorker.ets',
  hostState: expoHarmonyHostProvider.hostState,
  createRNInstanceOptions: (headless: boolean): RNInstanceOptions => ({
    name: "__EXPO_HARMONY_APP_LABEL__",
    createRNPackages: (context: RNPackageContext): RNPackage[] => getRNOHPackages(context, new ExpoRuntimeConfig({ isHeadless: headless })),
    fontResourceByFontFamily: {},
  }),
});

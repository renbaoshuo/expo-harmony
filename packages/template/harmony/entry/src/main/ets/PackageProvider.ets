import type { ExpoRuntimeConfig } from '@expo-harmony/expo-modules-core/Autolinking';
import type { RNPackage, RNPackageContext } from '@rnoh/react-native-openharmony';
import { createRNOHPackages } from './RNOHPackagesFactory';

export function getRNOHPackages(context: RNPackageContext, runtimeConfig?: ExpoRuntimeConfig): RNPackage[] {
  return createRNOHPackages(context, runtimeConfig);
}

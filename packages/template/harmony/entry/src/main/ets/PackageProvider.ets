import type { RNPackage, RNPackageContext } from '@rnoh/react-native-openharmony';
import { createRNOHPackages } from './RNOHPackagesFactory';

export function getRNOHPackages(context: RNPackageContext): RNPackage[] {
  return createRNOHPackages(context);
}

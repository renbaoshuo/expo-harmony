import { ExpoAbilityStage } from '@expo-harmony/expo-modules-core/Autolinking';
import type { ExpoHarmonyHostProvider, ExpoReactHost } from '@expo-harmony/expo-modules-core/Autolinking';
import { expoReactHost } from '../PackageProvider';
import { expoHarmonyHostProvider } from '../generated/ExpoHarmonyHostProvider';

export default class EntryAbilityStage extends ExpoAbilityStage {
  protected override getExpoReactHost(): ExpoReactHost {
    return expoReactHost;
  }

  protected override getExpoHarmonyHostProvider(): ExpoHarmonyHostProvider {
    return expoHarmonyHostProvider;
  }
}

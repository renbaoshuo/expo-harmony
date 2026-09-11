import type { ExpoHarmonyHostProvider } from '@expo-harmony/expo-modules-core/Autolinking';
import { ExpoRNAbility } from '@expo-harmony/expo-modules-core/Autolinking';
import { expoHarmonyHostProvider } from '../generated/ExpoHarmonyHostProvider';

export default class EntryAbility extends ExpoRNAbility {
  override getPagePath(): string {
    return 'pages/Index';
  }

  protected override getExpoHarmonyHostProvider(): ExpoHarmonyHostProvider {
    return expoHarmonyHostProvider;
  }

  protected override getExpoHarmonyWorkerScriptUrl(): string {
    return 'entry/ets/workers/RNOHWorker.ets';
  }
}

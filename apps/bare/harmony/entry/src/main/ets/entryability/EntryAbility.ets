/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ExpoHarmonyHostProvider } from '@expo-harmony/expo';
import { ExpoRNAbility } from '@expo-harmony/expo';
import { expoHarmonyWorkerScriptUrl } from '../PackageProvider';
import { expoHarmonyHostProvider } from '../generated/ExpoHarmonyHostProvider';

export default class EntryAbility extends ExpoRNAbility {
  override getPagePath(): string {
    return 'pages/Index';
  }

  protected override getExpoHarmonyHostProvider(): ExpoHarmonyHostProvider {
    return expoHarmonyHostProvider;
  }

  protected override getExpoHarmonyWorkerScriptUrl(): string {
    return expoHarmonyWorkerScriptUrl;
  }
}

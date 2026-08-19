import { common } from '@kit.AbilityKit';
import type { RNInstance } from '@rnoh/react-native-openharmony';
import type { ExpoReactInstanceLifecycleListener } from '@expo-harmony/expo-modules-core';

import { ExpoSystemUILifecycle } from './ExpoSystemUIPackage';

export class ExpoSystemUIReactInstanceLifecycleListener implements ExpoReactInstanceLifecycleListener {
  async onSetUp(context: common.UIAbilityContext, rnInstance: RNInstance): Promise<void> {
    await ExpoSystemUILifecycle.onRNInstanceSetUp(context, rnInstance);
  }
}

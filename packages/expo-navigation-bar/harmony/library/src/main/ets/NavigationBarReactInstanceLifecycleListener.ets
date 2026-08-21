import { common } from '@kit.AbilityKit';
import type { RNInstance } from '@rnoh/react-native-openharmony';
import type { ExpoReactInstanceLifecycleListener } from '@expo-harmony/expo-modules-core';

import { ExpoNavigationBarLifecycle } from './ExpoNavigationBarPackage';

export class ExpoNavigationBarReactInstanceLifecycleListener implements ExpoReactInstanceLifecycleListener {
  async onSetUp(context: common.UIAbilityContext, rnInstance: RNInstance): Promise<void> {
    await ExpoNavigationBarLifecycle.onRNInstanceSetUp(context, rnInstance);
  }
}

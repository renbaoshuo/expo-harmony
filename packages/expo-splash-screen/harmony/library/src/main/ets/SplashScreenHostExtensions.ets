import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import type { RNInstance } from '@rnoh/react-native-openharmony';
import type { ExpoAbilityLifecycleSubscriber, ExpoReactInstanceLifecycleListener } from '@expo-harmony/expo-modules-core';

import { ExpoSplashScreenLifecycle } from './SplashScreenLifecycle';

export class ExpoSplashScreenAbilityLifecycleSubscriber implements ExpoAbilityLifecycleSubscriber {
  async onWindowStageSetup(context: common.UIAbilityContext, windowStage: window.WindowStage): Promise<void> {
    await ExpoSplashScreenLifecycle.onWindowStageSetup(context, windowStage);
  }

  onWindowStageWillDestroy(context: common.UIAbilityContext): void {
    ExpoSplashScreenLifecycle.onWindowStageWillDestroy(context);
  }

  onDestroy(context: common.UIAbilityContext): void {
    ExpoSplashScreenLifecycle.onWindowStageWillDestroy(context);
  }
}

export class ExpoSplashScreenReactInstanceLifecycleListener implements ExpoReactInstanceLifecycleListener {
  async onSetUp(_context: common.UIAbilityContext, instance: RNInstance): Promise<void> {
    await ExpoSplashScreenLifecycle.onRNInstanceSetUp(instance);
  }
}

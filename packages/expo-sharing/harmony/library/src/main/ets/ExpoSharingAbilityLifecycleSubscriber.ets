import type { ExpoAbilityLifecycleSubscriber } from '@expo-harmony/expo-modules-core';
import { AbilityConstant, common } from '@kit.AbilityKit';
import type { Want } from '@kit.AbilityKit';

import { ExpoSharingLifecycle } from './ExpoSharingPackage';

export class ExpoSharingAbilityLifecycleSubscriber implements ExpoAbilityLifecycleSubscriber {
  onCreate(context: common.UIAbilityContext, want: Want, _launchParam: AbilityConstant.LaunchParam | undefined): void {
    ExpoSharingLifecycle.onCreate(context, want);
  }

  onNewWant(context: common.UIAbilityContext, want: Want, _launchParam: AbilityConstant.LaunchParam): boolean {
    return ExpoSharingLifecycle.onNewWant(context, want);
  }

  onDestroy(context: common.UIAbilityContext): void {
    ExpoSharingLifecycle.onDestroy(context);
  }
}

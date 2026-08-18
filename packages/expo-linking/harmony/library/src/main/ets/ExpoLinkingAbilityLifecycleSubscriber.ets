import type { Want } from '@kit.AbilityKit';
import { AbilityConstant, common } from '@kit.AbilityKit';
import type { ExpoAbilityLifecycleSubscriber } from '@expo-harmony/expo-modules-core';

import { ExpoLinkingLifecycle } from './ExpoLinkingPackage';

export class ExpoLinkingAbilityLifecycleSubscriber implements ExpoAbilityLifecycleSubscriber {
  onCreate(context: common.UIAbilityContext, want: Want, _launchParam: AbilityConstant.LaunchParam | undefined): void {
    ExpoLinkingLifecycle.onCreate(context, want);
  }

  onNewWant(context: common.UIAbilityContext, want: Want, _launchParam: AbilityConstant.LaunchParam): boolean {
    return ExpoLinkingLifecycle.shouldDispatchNewWant(context, want);
  }

  onDestroy(context: common.UIAbilityContext): void {
    ExpoLinkingLifecycle.onDestroy(context);
  }
}

import type { Want } from '@kit.AbilityKit';
import { AbilityConstant, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import type { RNInstance } from '@rnoh/react-native-openharmony';

export interface ExpoAbilityLifecycleSubscriber {
  onCreate?(context: common.UIAbilityContext, want: Want, launchParam?: AbilityConstant.LaunchParam): void;
  onNewWant?(context: common.UIAbilityContext, want: Want, launchParam: AbilityConstant.LaunchParam): boolean;
  onWindowStageSetup?(context: common.UIAbilityContext, windowStage: window.WindowStage): Promise<void>;
  onWindowStageWillDestroy?(context: common.UIAbilityContext): void;
  onDestroy?(context: common.UIAbilityContext): void;
}

export interface ExpoReactInstanceLifecycleListener {
  onSetUp(context: common.UIAbilityContext, rnInstance: RNInstance): Promise<void>;
}

export interface ExpoHarmonyHostProvider {
  readonly abilityLifecycleSubscribers: ExpoAbilityLifecycleSubscriber[];
  readonly reactInstanceLifecycleListeners: ExpoReactInstanceLifecycleListener[];
}

export class ExpoReactInstanceLifecycleDispatcher {
  static async onSetUp(provider: ExpoHarmonyHostProvider, context: common.UIAbilityContext, rnInstance: RNInstance): Promise<void> {
    for (const listener of provider.reactInstanceLifecycleListeners) {
      await listener.onSetUp(context, rnInstance);
    }
  }
}

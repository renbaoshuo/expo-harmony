import type { Want } from '@kit.AbilityKit';
import { AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { RNAbility } from '@rnoh/react-native-openharmony';

import type { ExpoHarmonyHostProvider } from './HarmonyHostLifecycle';
import { ExpoLifecycleDispatcher } from './LifecycleDispatcher';

export abstract class ExpoRNAbility extends RNAbility {
  protected abstract getExpoHarmonyHostProvider(): ExpoHarmonyHostProvider;

  override onCreate(want: Want, launchParam?: AbilityConstant.LaunchParam): void {
    for (const subscriber of this.getExpoHarmonyHostProvider().abilityLifecycleSubscribers) {
      subscriber.onCreate?.(this.context, want, launchParam);
    }
    super.onCreate(want, launchParam);
  }

  override onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    let shouldForwardToRNOH: boolean = true;
    for (const subscriber of this.getExpoHarmonyHostProvider().abilityLifecycleSubscribers) {
      if (subscriber.onNewWant?.(this.context, want, launchParam) === false) {
        shouldForwardToRNOH = false;
      }
    }
    if (shouldForwardToRNOH) super.onNewWant(want, launchParam);
    ExpoLifecycleDispatcher.onNewWant(want);
  }

  override onBackground(): void {
    ExpoLifecycleDispatcher.onUserLeavesAbility();
    super.onBackground();
  }

  protected override async onWindowStageSetup(windowStage: window.WindowStage): Promise<void> {
    for (const subscriber of this.getExpoHarmonyHostProvider().abilityLifecycleSubscribers) {
      if (subscriber.onWindowStageSetup !== undefined) {
        await subscriber.onWindowStageSetup(this.context, windowStage);
      }
    }
    await super.onWindowStageSetup(windowStage);
  }

  override onWindowStageWillDestroy(): void {
    for (const subscriber of this.getExpoHarmonyHostProvider().abilityLifecycleSubscribers) {
      subscriber.onWindowStageWillDestroy?.(this.context);
    }
    super.onWindowStageWillDestroy();
  }

  override onDestroy(): void {
    for (const subscriber of this.getExpoHarmonyHostProvider().abilityLifecycleSubscribers) {
      subscriber.onDestroy?.(this.context);
    }
    ExpoLifecycleDispatcher.onAbilityDestroy();
    super.onDestroy();
  }
}

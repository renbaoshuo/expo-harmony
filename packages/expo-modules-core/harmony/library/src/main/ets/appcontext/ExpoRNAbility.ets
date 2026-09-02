import type { Want } from '@kit.AbilityKit';
import { AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { RNAbility } from '@rnoh/react-native-openharmony';

import type { ExpoHarmonyHostProvider } from './HarmonyHostLifecycle';
import {
  EXPO_LIFECYCLE_MEMORY_LEVEL,
  EXPO_LIFECYCLE_NEW_INTENT,
  EXPO_LIFECYCLE_WINDOW_STAGE_SETUP,
  EXPO_LIFECYCLE_WINDOW_STAGE_WILL_DESTROY,
} from '../protocol/Protocol';

export abstract class ExpoRNAbility extends RNAbility {
  protected abstract getExpoHarmonyHostProvider(): ExpoHarmonyHostProvider;

  /** Application-owned RNOH worker entrypoint used by ExpoModuleContext.runInBackground. */
  protected abstract getExpoHarmonyWorkerScriptUrl(): string;

  /** Enables the RNOH worker used by ExpoModuleContext.runInBackground. */
  protected override getRNOHWorkerScriptUrl(): string {
    const workerScriptUrl: string = this.getExpoHarmonyWorkerScriptUrl();
    if (workerScriptUrl.length === 0) {
      throw new Error('ExpoRNAbility requires a non-empty RNOH worker script URL.');
    }
    return workerScriptUrl;
  }

  override onCreate(want: Want, launchParam?: AbilityConstant.LaunchParam): void {
    const provider = this.getExpoHarmonyHostProvider();

    provider.hostState.beginAbility(this.context, want);
    super.onCreate(want, launchParam);
  }

  override onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Filter RNOH's invalid Linking event while preserving lifecycle delivery.
    if (want.uri !== undefined && want.uri.length > 0) {
      super.onNewWant(want, launchParam);
    }
    this.getExpoHarmonyHostProvider().hostState.dispatch(this.context, EXPO_LIFECYCLE_NEW_INTENT, want);
  }

  protected override async onWindowStageSetup(windowStage: window.WindowStage): Promise<void> {
    await super.onWindowStageSetup(windowStage);
    this.getExpoHarmonyHostProvider().hostState.dispatch(this.context, EXPO_LIFECYCLE_WINDOW_STAGE_SETUP, windowStage);
  }

  override onWindowStageWillDestroy(): void {
    const provider = this.getExpoHarmonyHostProvider();

    provider.hostState.dispatch(this.context, EXPO_LIFECYCLE_WINDOW_STAGE_WILL_DESTROY);

    super.onWindowStageWillDestroy();
  }

  override onDestroy(): void {
    const provider = this.getExpoHarmonyHostProvider();

    try {
      provider.hostState.finishAbility(this.context);
    } finally {
      super.onDestroy();
    }
  }

  override onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    this.getExpoHarmonyHostProvider().hostState.dispatch(this.context, EXPO_LIFECYCLE_MEMORY_LEVEL, level);
    super.onMemoryLevel(level);
  }
}

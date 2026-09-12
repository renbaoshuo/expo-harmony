import { AbilityStage } from '@kit.AbilityKit';
import type { ExpoReactHost } from './ExpoReactHost';
import type { ExpoHarmonyHostProvider } from './HarmonyHostLifecycle';

export abstract class ExpoAbilityStage extends AbilityStage {
  protected abstract getExpoHarmonyHostProvider(): ExpoHarmonyHostProvider;

  protected getExpoReactHost(): ExpoReactHost | undefined {
    return undefined;
  }

  override onCreate(): void {
    super.onCreate();
    this.getExpoReactHost()?.initialize(this.context);
    this.getExpoHarmonyHostProvider().lifecycle.initializeApplication(this.context.getApplicationContext());
  }
}

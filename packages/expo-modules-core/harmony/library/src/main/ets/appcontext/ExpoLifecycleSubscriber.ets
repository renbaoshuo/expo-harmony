import type { AbilityConstant, Configuration, Want, common } from '@kit.AbilityKit';
import type { window } from '@kit.ArkUI';

export abstract class ExpoAppLifecycleSubscriber {
  readonly context: common.ApplicationContext;

  constructor(context: common.ApplicationContext) {
    this.context = context;
  }

  onCreate(): void {}
  onForeground(): void {}
  onBackground(): void {}
  onConfigurationUpdate(_configuration: Configuration): void {}
  onMemoryLevel(_level: AbilityConstant.MemoryLevel): void {}
}

export abstract class ExpoAbilityLifecycleSubscriber {
  readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  onCreate(_want: Want, _launch?: AbilityConstant.LaunchParam): void {}
  onNewWant(_want: Want, _launch: AbilityConstant.LaunchParam): void {}
  onWillForeground(): void {}
  onForeground(): void {}
  onDidForeground(): void {}
  onWillBackground(): void {}
  onBackground(): void {}
  onDidBackground(): void {}
  onConfigurationUpdate(_configuration: Configuration): void {}
  onMemoryLevel(_level: AbilityConstant.MemoryLevel): void {}
  onWindowStageCreate(_stage: window.WindowStage): void {}
  onWindowStageRestore(_stage: window.WindowStage): void {}
  onWindowStageSetup(_stage: window.WindowStage): void | Promise<void> {}
  onWindowStageReady(_stage: window.WindowStage): void | Promise<void> {}
  onWindowStageWillDestroy(_stage?: window.WindowStage): void {}
  onWindowStageDestroy(): void {}
  onBackPressed(): boolean {
    return false;
  }
  onContinue(_params: Record<string, Object>): AbilityConstant.OnContinueResult | undefined {
    return undefined;
  }
  async onContinueAsync(params: Record<string, Object>): Promise<AbilityConstant.OnContinueResult | undefined> {
    return this.onContinue(params);
  }
  onSaveState(_reason: AbilityConstant.StateType, _params: Record<string, Object>): AbilityConstant.OnSaveResult | undefined {
    return undefined;
  }
  async onSaveStateAsync(reason: AbilityConstant.StateType, params: Record<string, Object>): Promise<AbilityConstant.OnSaveResult | undefined> {
    return this.onSaveState(reason, params);
  }
  onDestroy(): void {}
}

export interface ExpoAppLifecycleSubscriberRegistration {
  readonly registrationId: string;
  readonly create: (context: common.ApplicationContext) => ExpoAppLifecycleSubscriber;
}

export interface ExpoAbilityLifecycleSubscriberRegistration {
  readonly registrationId: string;
  readonly create: (context: common.UIAbilityContext) => ExpoAbilityLifecycleSubscriber;
}

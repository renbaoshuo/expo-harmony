import { common } from '@kit.AbilityKit';

import { attachSystemUIRoot } from './ExpoSystemUIModule';
@Component
export struct ExpoSystemUIRootView {
  private detach: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      console.warn('ExpoSystemUIRootView has no UIAbility context.');
      return;
    }

    this.detach = attachSystemUIRoot(host as common.UIAbilityContext);
  }

  aboutToDisappear(): void {
    const detach = this.detach;
    this.detach = undefined;
    detach?.();
  }

  build(): void {}
}

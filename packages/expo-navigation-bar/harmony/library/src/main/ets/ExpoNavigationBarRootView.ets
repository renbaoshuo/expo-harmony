import { common } from '@kit.AbilityKit';

import { applyNavigationBarStartupConfiguration } from './ExpoNavigationBarModule';
@Component
export struct ExpoNavigationBarRootView {
  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      console.warn('ExpoNavigationBarRootView has no UIAbility context.');
      return;
    }

    applyNavigationBarStartupConfiguration(host as common.UIAbilityContext);
  }

  build(): void {}
}

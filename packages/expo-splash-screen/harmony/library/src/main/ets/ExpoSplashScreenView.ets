import { common } from '@kit.AbilityKit';

import { attachSplashScreenView, ExpoSplashScreenError, SplashScreenRenderState } from './SplashScreenLifecycle';
@Component
export struct ExpoSplashScreenView {
  @State private state: SplashScreenRenderState = SplashScreenRenderState.hidden();
  private detach: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    const ui = this.getUIContext();
    const host = ui.getHostContext();

    if (host === undefined) {
      throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_ABILITY_CONTEXT', 'ExpoSplashScreenView has no UIAbility context.');
    }

    this.detach = attachSplashScreenView(host as common.UIAbilityContext, ui, (state: SplashScreenRenderState): void => {
      this.state = state;
    });
  }

  aboutToDisappear(): void {
    const detach = this.detach;

    this.detach = undefined;
    if (detach !== undefined) detach();
  }

  build(): void {
    if (this.state.visible) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.state.image !== undefined) {
          if (this.state.resizeMode === 'cover') {
            Image(this.state.image)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover);
          } else if (this.state.resizeMode === 'native') {
            Image(this.state.image).objectFit(ImageFit.None);
          } else {
            Image(this.state.image)
              .width(this.state.imageWidth)
              .objectFit(ImageFit.Contain);
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.state.backgroundColor)
      .opacity(this.state.opacity)
      .hitTestBehavior(HitTestMode.Block)
      .zIndex(2147483647);
    }
  }
}

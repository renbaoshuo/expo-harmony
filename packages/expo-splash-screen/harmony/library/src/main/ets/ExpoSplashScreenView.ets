import { common } from '@kit.AbilityKit';

import { attachSplashScreenView, ExpoSplashScreenError, SplashScreenRenderState } from './SplashScreenLifecycle';
@Component
export struct ExpoSplashScreenView {
  @State private renderState: SplashScreenRenderState = SplashScreenRenderState.hidden();
  private detach: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    const ui = this.getUIContext();
    const host = ui.getHostContext();

    if (host === undefined) {
      throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_ABILITY_CONTEXT', 'ExpoSplashScreenView has no UIAbility context.');
    }

    this.detach = attachSplashScreenView(host as common.UIAbilityContext, ui, (state: SplashScreenRenderState): void => {
      this.renderState = state;
    });
  }

  aboutToDisappear(): void {
    const detach = this.detach;

    this.detach = undefined;
    if (detach !== undefined) detach();
  }

  build(): void {
    if (this.renderState.visible) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.renderState.image !== undefined) {
          if (this.renderState.resizeMode === 'cover') {
            Image(this.renderState.image)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover);
          } else if (this.renderState.resizeMode === 'native') {
            Image(this.renderState.image)
              .width(this.renderState.imageWidth)
              .objectFit(ImageFit.None);
          } else {
            Image(this.renderState.image)
              .width(this.renderState.imageWidth)
              .objectFit(ImageFit.Contain);
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.renderState.backgroundColor)
      .opacity(this.renderState.opacity)
      .hitTestBehavior(HitTestMode.Block)
      .zIndex(2147483647);
    }
  }
}

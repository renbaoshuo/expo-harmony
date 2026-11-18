/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { expoLogBoxController, type ExpoLogBoxPresentation } from './ExpoLogBoxController';
import { ExpoLogBoxWebSession, ExpoLogBoxWebView } from './ExpoLogBoxWebView';

@Component
struct ExpoLogBoxOverlay {
  @State private visible: boolean = false;
  @State private generation: number = 0;
  private session?: ExpoLogBoxWebSession;
  private unsubscribe?: () => void;

  aboutToAppear(): void {
    const name = this.getUIContext().getWindowName();
    if (name === undefined) return;

    this.unsubscribe = expoLogBoxController.subscribe(name, (presentation?: ExpoLogBoxPresentation): void =>
      this.show(presentation),
    );
  }

  private show(presentation?: ExpoLogBoxPresentation): void {
    this.session?.dispose();
    this.session = undefined;
    this.visible = false;

    if (presentation === undefined) return;

    try {
      const session: ExpoLogBoxWebSession = new ExpoLogBoxWebSession(
        presentation.initialProps,
        presentation.devServerOrigin,
        (message: string): void => {
          if (this.session !== session) return;

          expoLogBoxController.handleMessage(message, session.web, presentation.id).catch((error: Object): void => {
            console.error(`Expo LogBox native action failed: ${String(error)}`);
          });
        },
        (): void => expoLogBoxController.ready(presentation.id),
        (error: Object): void => expoLogBoxController.fail(presentation.id, error),
      );

      this.session = session;
      this.generation += 1;
      this.visible = true;
    } catch (error) {
      expoLogBoxController.fail(presentation.id, error as Object);
    }
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    this.session?.dispose();
    this.session = undefined;
  }

  build(): void {
    if (this.visible) {
      ForEach(
        [this.generation],
        (_generation: number): void => {
          ExpoLogBoxWebView({ session: this.session });
        },
        (generation: number): string => `${generation}`,
      );
    }
  }
}
@Builder
export function ExpoLogBoxRootView(): void {
  ExpoLogBoxOverlay().width('100%').height('100%').zIndex(2147483647).hitTestBehavior(HitTestMode.Transparent);
}

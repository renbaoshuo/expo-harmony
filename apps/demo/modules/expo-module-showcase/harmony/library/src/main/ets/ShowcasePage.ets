/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ComponentContent, window } from '@kit.ArkUI';
import { ExpoModuleContext, ExpoModuleError } from '@expo-harmony/expo-modules-core';

export class ShowcasePageResult {
  action: string;
  value: number;

  constructor(action: string, value: number) {
    this.action = action;
    this.value = value;
  }
}

@Observed
class PageModel {
  value: number;
  padding: Padding = { top: 16, right: 16, bottom: 16, left: 16 };
  close: (action: string) => void = (_action: string): void => {};
  didDisappear: () => void = (): void => {};

  constructor(value: number) {
    this.value = value;
  }
}

@Component
struct ShowcasePage {
  @State model: PageModel = new PageModel(0);

  aboutToDisappear(): void {
    this.model.didDisappear();
  }

  build(): void {
    Column({ space: 18 }) {
      Row() {
        Button('取消').backgroundColor('#EAF3FF').fontColor('#007AFF').height(44)
          .onClick((): void => { this.model.close('cancel'); })
        Blank()
        Text('原生页面').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#111827')
        Blank()
        Button('完成').backgroundColor('#007AFF').fontColor('#FFFFFF').height(44)
          .onClick((): void => { this.model.close('done'); })
      }.width('100%')
      Scroll() {
        Column({ space: 18 }) {
          Column({ space: 16 }) {
            Text('计数').fontSize(18).fontColor('#111827').fontWeight(FontWeight.Bold)
            Text(`${this.model.value}`).fontSize(36).fontColor('#007AFF').fontWeight(FontWeight.Bold)
            Button('增加 1').type(ButtonType.Normal).borderRadius(10)
              .width('100%').height(44).backgroundColor('#007AFF').fontColor('#FFFFFF')
              .onClick((): void => { this.model.value += 1; })
          }.alignItems(HorizontalAlign.Start).padding(16).width('100%')
            .backgroundColor('#FFFFFF').borderRadius(16)
        }.alignItems(HorizontalAlign.Start).width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.padding(this.model.padding).width('100%').height('100%').backgroundColor('#F2F2F7')
  }
}

@Builder
function buildShowcasePage(model: PageModel): void {
  ShowcasePage({ model });
}

export class ShowcasePagePresenter {
  private active: boolean = false;
  private disposed: boolean = false;
  private close?: () => void;

  async open(context: ExpoModuleContext, initialValue: number): Promise<ShowcasePageResult> {
    if (this.active || this.disposed) {
      throw new ExpoModuleError('ERR_SHOWCASE_PAGE', '原生页面已打开或模块已销毁。');
    }
    this.active = true;
    let removeAvoidAreaListener: (() => void) | undefined;
    let removeWindowListener: (() => void) | undefined;
    let pageContent: ComponentContent<PageModel> | undefined;
    try {
      const nativeWindow = await context.getReactNativeWindow();
      if (this.disposed) throw new ExpoModuleError('ERR_SHOWCASE_PAGE', '模块已销毁。');
      const ui = nativeWindow.getUIContext();
      const prompt = ui.getPromptAction();
      const model = new PageModel(initialValue);
      const updatePadding = (): void => {
        const system = nativeWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const navigation = nativeWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        model.padding = {
          top: 16 + ui.px2vp(system.topRect.height),
          right: 16 + ui.px2vp(Math.max(system.rightRect.width, navigation.rightRect.width)),
          bottom: 16 + ui.px2vp(Math.max(system.bottomRect.height, navigation.bottomRect.height)),
          left: 16 + ui.px2vp(Math.max(system.leftRect.width, navigation.leftRect.width)),
        };
      };
      updatePadding();
      nativeWindow.on('avoidAreaChange', updatePadding);
      removeAvoidAreaListener = (): void => { nativeWindow.off('avoidAreaChange', updatePadding); };
      const content = new ComponentContent(ui, wrapBuilder(buildShowcasePage), model);
      pageContent = content;
      return await new Promise<ShowcasePageResult>((resolve, reject) => {
        let result: ShowcasePageResult | undefined;
        let opened: boolean = false;
        let closing: boolean = false;
        let settled: boolean = false;
        const finish = (error?: Error): void => {
          if (settled) return;
          settled = true;
          if (error !== undefined) reject(error);
          else resolve(result ?? new ShowcasePageResult('cancel', model.value));
        };
        const closeWhenOpened = (): void => {
          if (!opened || result === undefined || closing || settled) return;
          closing = true;
          Promise.resolve().then(async (): Promise<void> => {
            if (!settled) await prompt.closeCustomDialog(content);
          }).catch((error: Error): void => {
            finish(error);
          });
        };
        model.close = (action: string): void => {
          if (result !== undefined || settled) return;
          result = new ShowcasePageResult(action, model.value);
          closeWhenOpened();
        };
        this.close = (): void => model.close('cancel');
        // ArkUI can skip onDidDisappear when navigation interrupts the exit animation.
        model.didDisappear = (): void => finish();
        const onWindowEvent = (event: window.WindowEventType): void => {
          if (event === window.WindowEventType.WINDOW_DESTROYED) finish();
        };
        nativeWindow.on('windowEvent', onWindowEvent);
        removeWindowListener = (): void => { nativeWindow.off('windowEvent', onWindowEvent); };
        prompt.openCustomDialog(content, {
          autoCancel: false,
          alignment: DialogAlignment.Center,
          onWillDismiss: (dismissal: DismissDialogAction): void => {
            result ??= new ShowcasePageResult('cancel', model.value);
            closing = true;
            dismissal.dismiss();
          },
          onDidDisappear: (): void => finish(),
        }).then((): void => {
          opened = true;
          closeWhenOpened();
        }).catch((error: Error): void => {
          finish(error);
        });
      });
    } finally {
      this.close = undefined;
      this.active = false;
      const cleanup: ((() => void) | undefined)[] = [
        removeWindowListener,
        removeAvoidAreaListener,
        (): void => pageContent?.dispose(),
      ];
      for (const release of cleanup) {
        try {
          release?.();
        } catch (error) {
          console.warn(`Unable to clean up the showcase page: ${String(error)}`);
        }
      }
    }
  }

  dispose(): void {
    this.disposed = true;
    this.close?.();
  }
}

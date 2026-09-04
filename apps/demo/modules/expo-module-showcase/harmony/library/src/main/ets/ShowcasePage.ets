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
  action: string = 'cancel';
  padding: Padding = { top: 16, right: 16, bottom: 16, left: 16 };
  close: () => void = (): void => {};

  constructor(value: number) {
    this.value = value;
  }
}

@Component
struct ShowcasePage {
  @State model: PageModel = new PageModel(0);

  build(): void {
    Column({ space: 18 }) {
      Row() {
        Button('取消').backgroundColor('#EAF3FF').fontColor('#007AFF').height(44)
          .onClick((): void => { this.model.close(); })
        Blank()
        Text('原生页面').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#111827')
        Blank()
        Button('完成').backgroundColor('#007AFF').fontColor('#FFFFFF').height(44)
          .onClick((): void => { this.model.action = 'done'; this.model.close(); })
      }.width('100%')
      Scroll() {
        Column({ space: 18 }) {
          Text('Expo Modules').fontSize(12).fontColor('#007AFF').fontWeight(FontWeight.Bold)
          Text('原生页面交互').fontSize(30).fontColor('#111827').fontWeight(FontWeight.Bold)
          Text('在原生页面中修改计数，完成后将结果带回测试页面。')
            .fontSize(15).fontColor('#667085').width('100%')
          Column({ space: 16 }) {
            Text('页面计数器').fontSize(18).fontColor('#111827').fontWeight(FontWeight.Bold)
            Text(`${this.model.value}`).fontSize(36).fontColor('#007AFF').fontWeight(FontWeight.Bold)
            Button('增加计数 +1').type(ButtonType.Normal).borderRadius(10)
              .width('100%').height(44).backgroundColor('#007AFF').fontColor('#FFFFFF')
              .onClick((): void => { this.model.value += 1; })
          }.alignItems(HorizontalAlign.Start).padding(16).width('100%')
            .backgroundColor('#FFFFFF').borderRadius(16)
          Text('取消或系统返回将放弃本次修改。').fontSize(13).fontColor('#667085')
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
    if (this.active || this.close !== undefined || this.disposed) {
      throw new ExpoModuleError('ERR_SHOWCASE_PAGE', '原生页面已打开或模块已销毁。');
    }
    this.active = true;
    let removeAvoidAreaListener: (() => void) | undefined;
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
      return await new Promise<ShowcasePageResult>((resolve, reject) => {
        let closing: boolean = false;
        model.close = (): void => {
          if (closing) return;
          closing = true;
          prompt.closeCustomDialog(content).catch((error: Error): void => {
            closing = false;
            reject(error);
          });
        };
        this.close = model.close;
        prompt.openCustomDialog(content, {
          autoCancel: false,
          alignment: DialogAlignment.Center,
          onWillDismiss: (action: DismissDialogAction): void => {
            if (!closing) model.action = 'cancel';
            action.dismiss();
          },
          onDidDisappear: (): void => {
            this.close = undefined;
            content.dispose();
            resolve(new ShowcasePageResult(model.action, model.value));
          },
        }).catch((error: Error): void => {
          this.close = undefined;
          content.dispose();
          reject(error);
        });
      });
    } finally {
      removeAvoidAreaListener?.();
      this.active = false;
    }
  }

  dispose(): void {
    this.disposed = true;
    this.close?.();
  }
}

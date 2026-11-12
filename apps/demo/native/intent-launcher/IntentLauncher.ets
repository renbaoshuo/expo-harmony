/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common, Want } from '@kit.AbilityKit';

const RESULT_OK: number = 42;
const RESULT_CANCELLED: number = 0;

@Entry({ useSharedStorage: true })
@Component
struct IntentLauncherPage {
  @LocalStorageProp('want') private want: Want = {};
  @State private error: string = '';
  @State private pending: boolean = false;

  onBackPress(): boolean {
    this.finish(true);
    return true;
  }

  private async finish(cancelled: boolean): Promise<void> {
    if (this.pending) return;

    this.pending = true;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const result: common.AbilityResult = { resultCode: cancelled ? RESULT_CANCELLED : RESULT_OK };
    if (!cancelled) {
      result.want = {
        uri: this.want.uri,
        parameters: {
          action: this.want.action ?? '',
          type: this.want.type ?? '',
          entities: this.want.entities ?? [],
          flags: this.want.flags ?? 0,
          received: this.want.parameters ?? {},
        },
      };
    }

    try {
      await context.terminateSelfWithResult(result);
    } catch (error) {
      this.error = String(error);
      this.pending = false;
    }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('收到的启动参数').fontSize(28).fontWeight(FontWeight.Bold)
        Text(JSON.stringify(this.want, null, 2)).fontSize(12).width('100%')
        Button('返回结果').width('100%').backgroundColor('#007AFF').enabled(!this.pending)
          .onClick(() => this.finish(false))
        Button('取消').width('100%').backgroundColor('#EAF3FF').fontColor('#007AFF').enabled(!this.pending)
          .onClick(() => this.finish(true))
        if (this.error) {
          Text(this.error).fontColor('#D70015')
        }
      }.alignItems(HorizontalAlign.Start).padding(24).width('100%')
    }.width('100%').height('100%').backgroundColor('#F2F2F7')
  }
}

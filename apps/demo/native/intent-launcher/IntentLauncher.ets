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
        Text('INTENT LAUNCHER').fontSize(12).fontColor('#667085')
        Text('原生结果回传').fontSize(28).fontWeight(FontWeight.Bold)
        Text('返回结果将原样回传收到的 URI 和参数，结果码为 42；取消只返回结果码 0。')
          .fontSize(14).fontColor('#667085')
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

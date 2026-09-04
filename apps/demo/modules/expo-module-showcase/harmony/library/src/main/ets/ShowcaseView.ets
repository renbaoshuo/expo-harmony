import {
  ExpoFunction, ExpoValueTypes, ExpoView, ExpoViewContext, ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import type { ExpoViewContentContext } from '@expo-harmony/expo-modules-core';

@Observed
class ShowcaseView extends ExpoView {
  label: string = '原生计数器';
  value: number = 1;

  constructor(context: ExpoViewContext) {
    super(context);
  }

  increment(delta: number, source: string): number {
    this.value += delta;
    this.sendEvent('onValueChanged', { label: this.label, value: this.value, source });
    return this.value;
  }
}

@Component
struct ShowcaseViewContent {
  @ObjectLink view: ShowcaseView;

  build(): void {
    Column({ space: 10 }) {
      Text(this.view.label).fontColor('#111827').fontSize(17).fontWeight(FontWeight.Bold)
      Text(`${this.view.value}`).fontColor('#007AFF').fontSize(28).fontWeight(FontWeight.Bold)
      Button('原生按钮 +1')
        .type(ButtonType.Normal).borderRadius(10).height(44).width('100%')
        .backgroundColor('#007AFF').fontColor('#FFFFFF').fontSize(14)
        .onClick((): void => { this.view.increment(1, 'touch'); })
    }
      .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
      .padding(16).width('100%').height('100%').borderRadius(12).backgroundColor('#F7F8FA')
  }
}

@Builder
function buildShowcaseView(context: ExpoViewContentContext): void {
  ShowcaseViewContent({ view: context.nativeView as ShowcaseView });
}

export function showcaseViewDefinition(): ExpoViewDefinition<ShowcaseView> {
  return new ExpoViewDefinition<ShowcaseView>(
    'ShowcaseView',
    (context: ExpoViewContext): ShowcaseView => new ShowcaseView(context),
    wrapBuilder(buildShowcaseView),
  )
    .prop('label', ExpoValueTypes.string(), (view: ShowcaseView, label: string): void => {
      view.label = label;
    }, '原生计数器')
    .prop('value', ExpoValueTypes.number(), (view: ShowcaseView, value: number): void => {
      view.value = value;
    }, 1)
    .events(['onValueChanged'])
    .asyncFunction('increment', ExpoFunction.ownedTyped1(
      ExpoValueTypes.number(),
      async (view: ShowcaseView, delta: number): Promise<number> => view.increment(delta, 'command'),
    ).returns(ExpoValueTypes.number()));
}

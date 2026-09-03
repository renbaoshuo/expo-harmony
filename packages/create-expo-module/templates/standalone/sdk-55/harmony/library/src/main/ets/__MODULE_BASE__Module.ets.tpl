import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoSharedObject,
  ExpoSharedObjectClassDefinition,
  ExpoValueTypes,
  ExpoView,
  ExpoViewContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import type { ExpoViewContentContext } from '@expo-harmony/expo-modules-core';

@Observed
class {{MODULE_BASE}}NativeView extends ExpoView {
  label: string = 'Harmony';
  value: number = 0;

  constructor(context: ExpoViewContext) {
    super(context);
  }

  increment(delta: number): number {
    this.value += delta;
    this.sendEvent('onValueChanged', { value: this.value });
    return this.value;
  }
}

@Component
struct {{MODULE_BASE}}NativeViewContent {
  @ObjectLink view: {{MODULE_BASE}}NativeView;

  build(): void {
    Column({ space: 4 }) {
      Text(this.view.label)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      Text(`value = ${this.view.value}`)
        .fontSize(13)
    }
      .alignItems(HorizontalAlign.Start)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 12, right: 12 })
      .width('100%')
  }
}

@Builder
function build{{MODULE_BASE}}NativeView(context: ExpoViewContentContext): void {
  {{MODULE_BASE}}NativeViewContent({ view: context.nativeView as {{MODULE_BASE}}NativeView });
}

class {{MODULE_BASE}}Counter extends ExpoSharedObject {
  value: number;

  constructor(context: ExpoModuleContext, value: number) {
    super(context);
    this.value = value;
  }

  emitValueChanged(): void {
    this.sendEvent('onValueChanged', { value: this.value });
  }
}

export class {{MODULE_BASE}}Module extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  override definition(): ExpoModuleDefinition {
    const counterClass = new ExpoSharedObjectClassDefinition<{{MODULE_BASE}}Counter>('{{MODULE_BASE}}Counter')
      .construct(ExpoFunction.ownedTyped1(
        ExpoValueTypes.number(),
        (context: ExpoModuleContext, value: number): {{MODULE_BASE}}Counter =>
          new {{MODULE_BASE}}Counter(context, value),
      ))
      .constant('kind', 'arkts-counter')
      .property(
        'value',
        ExpoValueTypes.number(),
        (object: {{MODULE_BASE}}Counter): number => object.value,
        (object: {{MODULE_BASE}}Counter, value: number): void => {
          object.value = value;
        },
      )
      .syncFunction('increment', ExpoFunction.ownedTyped1(
        ExpoValueTypes.number(),
        (object: {{MODULE_BASE}}Counter, delta: number): number => {
          object.value += delta;
          return object.value;
        },
      ).returns(ExpoValueTypes.number()))
      .syncFunction('emitValueChanged', (object: {{MODULE_BASE}}Counter): number => {
        object.emitValueChanged();
        return object.value;
      })
      .staticSyncFunction('add', ExpoFunction.ownedTyped2(
        ExpoValueTypes.number(),
        ExpoValueTypes.number(),
        (_context: ExpoModuleContext, left: number, right: number): number => left + right,
      ).returns(ExpoValueTypes.number()))
      .events(['onValueChanged']);
    const nativeView = new ExpoViewDefinition<{{MODULE_BASE}}NativeView>(
      '{{MODULE_BASE}}View',
      (context: ExpoViewContext): {{MODULE_BASE}}NativeView => new {{MODULE_BASE}}NativeView(context),
      wrapBuilder(build{{MODULE_BASE}}NativeView),
    )
      .prop('label', ExpoValueTypes.string(), (view: {{MODULE_BASE}}NativeView, value: string): void => {
        view.label = value;
      }, 'Harmony')
      .prop('value', ExpoValueTypes.number(), (view: {{MODULE_BASE}}NativeView, value: number): void => {
        view.value = value;
      }, 0)
      .events(['onValueChanged'])
      .asyncFunction('increment', ExpoFunction.ownedTyped1(
        ExpoValueTypes.number(),
        async (view: {{MODULE_BASE}}NativeView, delta: number): Promise<number> => view.increment(delta),
      ).returns(ExpoValueTypes.number()));

    return new ExpoModuleDefinition()
      .name('{{MODULE_NAME}}')
      .constant('platform', 'harmony')
      .sharedObjectClass(counterClass)
      .view(nativeView)
      .syncFunction('echo', ExpoFunction.typed1(
        ExpoValueTypes.string(),
        (value: string): string => value,
      ).returns(ExpoValueTypes.string()))
      .asyncFunction('echoAsync', ExpoFunction.typed1(
        ExpoValueTypes.string(),
        async (value: string): Promise<string> => value,
      ).returns(ExpoValueTypes.string()))
      .syncFunction('createCounter', ExpoFunction.typed1(
        ExpoValueTypes.number(),
        (value: number): {{MODULE_BASE}}Counter =>
          counterClass.instance(new {{MODULE_BASE}}Counter(this.appContext, value)),
      ));
  }
}

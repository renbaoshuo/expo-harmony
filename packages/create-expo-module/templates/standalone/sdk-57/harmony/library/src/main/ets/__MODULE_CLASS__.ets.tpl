/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModule, ExpoModuleContext, ExpoModuleDefinition{{NATIVE_IMPORTS}} } from '@expo-harmony/expo-modules-core';
{{#View}}import type { ExpoViewContentContext } from '@expo-harmony/expo-modules-core';
{{/View}}
{{#View}}@Observed
class {{MODULE_BASE}}NativeView extends ExpoView {
  label: string = 'Harmony';
  value: number = 0;

  constructor(context: ExpoViewContext) {
    super(context);
  }

  increment(delta: number): number {
    this.value += delta;
{{#ViewEvent}}    this.sendEvent('onValueChanged', { value: this.value });{{/ViewEvent}}
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

{{/View}}{{#SharedObject}}class {{MODULE_BASE}}Counter extends ExpoSharedObject {
  value: number;

  constructor(context: ExpoModuleContext, value: number) {
    super(context);
    this.value = value;
  }

  emitValueChanged(): void {
    this.sendEvent('onValueChanged', { value: this.value });
  }
}

{{/SharedObject}}export class {{MODULE_CLASS}} extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  override definition(): ExpoModuleDefinition {
{{#SharedObject}}    const counterClass = new ExpoSharedObjectClassDefinition<{{MODULE_BASE}}Counter>('{{MODULE_BASE}}Counter')
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
{{/SharedObject}}{{#View}}    const nativeView = new ExpoViewDefinition<{{MODULE_BASE}}NativeView>(
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
{{#ViewEvent}}      .events(['onValueChanged']){{/ViewEvent}}
      .asyncFunction('increment', ExpoFunction.ownedTyped1(
        ExpoValueTypes.number(),
        async (view: {{MODULE_BASE}}NativeView, delta: number): Promise<number> => view.increment(delta),
      ).returns(ExpoValueTypes.number()));
{{/View}}
    return new ExpoModuleDefinition()
      .name({{MODULE_NAME_JSON}})
{{#Constant}}      .constant('platform', 'harmony')
{{/Constant}}{{#SharedObject}}      .sharedObjectClass(counterClass)
{{/SharedObject}}{{#View}}      .view(nativeView)
{{/View}}{{#Function}}      .syncFunction('echo', ExpoFunction.typed1(
        ExpoValueTypes.string(),
        (value: string): string => value,
      ).returns(ExpoValueTypes.string()))
{{/Function}}{{#AsyncFunction}}      .asyncFunction('echoAsync', ExpoFunction.typed1(
        ExpoValueTypes.string(),
        async (value: string): Promise<string> => value,
      ).returns(ExpoValueTypes.string()))
{{/AsyncFunction}}{{#Event}}      .events(['onChange'])
      .syncFunction('emitChange', ExpoFunction.typed1(
        ExpoValueTypes.string(),
        (value: string): void => { this.sendEvent('onChange', { value }); },
      ))
{{/Event}}{{#SharedObject}}      .syncFunction('createCounter', ExpoFunction.typed1(
        ExpoValueTypes.number(),
        (value: number): {{MODULE_BASE}}Counter =>
          counterClass.instance(new {{MODULE_BASE}}Counter(this.appContext, value)),
      ))
{{/SharedObject}}      ;
  }
}

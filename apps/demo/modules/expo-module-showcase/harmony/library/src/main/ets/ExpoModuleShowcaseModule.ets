import {
  ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError,
  ExpoSharedObjectClassDefinition, ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { ShowcaseCounter, ShowcaseTextRef } from './ShowcaseObjects';
import { ShowcasePagePresenter, ShowcasePageResult } from './ShowcasePage';
import { showcaseViewDefinition } from './ShowcaseView';

class ShowcaseLifecycleSnapshot {
  created: number;
  foregrounded: number;
  backgrounded: number;
  startObserving: number;
  stopObserving: number;

  constructor(created: number, foregrounded: number, backgrounded: number, startObserving: number, stopObserving: number) {
    this.created = created;
    this.foregrounded = foregrounded;
    this.backgrounded = backgrounded;
    this.startObserving = startObserving;
    this.stopObserving = stopObserving;
  }
}

export class ExpoModuleShowcaseModule extends ExpoModule {
  private created: number = 0;
  private foregrounded: number = 0;
  private backgrounded: number = 0;
  private startObserving: number = 0;
  private stopObserving: number = 0;
  private sequence: number = 0;
  private readonly page: ShowcasePagePresenter = new ShowcasePagePresenter();

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  override definition(): ExpoModuleDefinition {
    const counter = new ExpoSharedObjectClassDefinition<ShowcaseCounter>('ShowcaseSharedCounter')
      .construct(ExpoFunction.ownedTyped1(ExpoValueTypes.number(),
        (context: ExpoModuleContext, value: number): ShowcaseCounter => new ShowcaseCounter(context, value)))
      .property('value', ExpoValueTypes.number(),
        (object: ShowcaseCounter): number => object.value,
        (object: ShowcaseCounter, value: number): void => { object.value = value; })
      .syncFunction('increment', ExpoFunction.ownedTyped1(ExpoValueTypes.number(),
        (object: ShowcaseCounter, delta: number): number => object.increment(delta)))
      .asyncFunction('incrementAsync', ExpoFunction.ownedTyped1(ExpoValueTypes.number(),
        async (object: ShowcaseCounter, delta: number): Promise<number> => object.increment(delta)))
      .syncFunction('emitValueChanged', (object: ShowcaseCounter): void => object.emitValueChanged())
      .event('onValueChanged', ExpoValueTypes.record(ExpoValueTypes.number()));
    const textRef = new ExpoSharedObjectClassDefinition<ShowcaseTextRef>('ShowcaseTextRef')
      .sharedRef('expo-module-showcase.text')
      .property('value', ExpoValueTypes.string(), (object: ShowcaseTextRef): string => object.value);

    return new ExpoModuleDefinition()
      .name('ExpoModuleShowcase')
      .constant('platform', 'harmony')
      .constant('nativeLanguage', 'ArkTS')
      .events(['onShowcaseEvent'])
      .sharedObjectClass(counter)
      .sharedObjectClass(textRef)
      .view(showcaseViewDefinition())
      .syncFunction('echo', ExpoFunction.typed1(ExpoValueTypes.string(), (value: string): string => value))
      .asyncFunction('echoAsync', ExpoFunction.typed1(ExpoValueTypes.string(), async (value: string): Promise<string> => value))
      .asyncFunction('failAsync', async (): Promise<void> => {
        throw new ExpoModuleError('ERR_SHOWCASE', '这是用于测试的原生错误。');
      })
      .syncFunction('emitEvent', ExpoFunction.typed1(ExpoValueTypes.string(), (value: string): void => {
        this.sequence += 1;
        this.sendEvent('onShowcaseEvent', { value, sequence: this.sequence, platform: 'harmony' });
      }))
      .syncFunction('returnSameSharedCounter', ExpoFunction.typed1(counter.valueType(),
        (object: ShowcaseCounter): ShowcaseCounter => object).returns(counter.valueType()))
      .syncFunction('createSharedTextRef', ExpoFunction.typed1(ExpoValueTypes.string(),
        (value: string): ShowcaseTextRef => textRef.instance(new ShowcaseTextRef(this.context, value)))
        .returns(textRef.valueType()))
      .asyncFunction('openNativePage', ExpoFunction.typed1(ExpoValueTypes.number(),
        async (value: number): Promise<ShowcasePageResult> =>
          this.context.runOnUIQueue((): Promise<ShowcasePageResult> => this.page.open(this.context, value))))
      .syncFunction('getLifecycleSnapshot', (): ShowcaseLifecycleSnapshot => new ShowcaseLifecycleSnapshot(
        this.created, this.foregrounded, this.backgrounded, this.startObserving, this.stopObserving,
      ))
      .onCreate((): void => { this.created += 1; })
      .onForeground((): void => { this.foregrounded += 1; })
      .onBackground((): void => { this.backgrounded += 1; })
      .onStartObserving((_event: string): void => { this.startObserving += 1; })
      .onStopObserving((_event: string): void => { this.stopObserving += 1; })
      .onDestroy((): void => { this.page.dispose(); });
  }
}

import {
  ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoSharedObjectTypes, ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { ShowcaseCounter, ShowcaseTextRef } from './ShowcaseObjects';

export class ExpoModuleShowcaseConsumerModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  override definition(): ExpoModuleDefinition {
    const counter = ExpoSharedObjectTypes.named<ShowcaseCounter>('ExpoModuleShowcase', 'ShowcaseSharedCounter');
    const textRef = ExpoSharedObjectTypes.sharedRef<ShowcaseTextRef>('expo-module-showcase.text');
    return new ExpoModuleDefinition()
      .name('ExpoModuleShowcaseConsumer')
      .syncFunction('readSharedCounter', ExpoFunction.typed1(counter,
        (object: ShowcaseCounter): number => object.value).returns(ExpoValueTypes.number()))
      .syncFunction('forwardSharedCounter', ExpoFunction.typed1(counter,
        (object: ShowcaseCounter): ShowcaseCounter => object).returns(counter))
      .syncFunction('readSharedTextRef', ExpoFunction.typed1(textRef,
        (object: ShowcaseTextRef): string => object.value).returns(ExpoValueTypes.string()))
      .syncFunction('forwardSharedTextRef', ExpoFunction.typed1(textRef,
        (object: ShowcaseTextRef): ShowcaseTextRef => object).returns(textRef));
  }
}

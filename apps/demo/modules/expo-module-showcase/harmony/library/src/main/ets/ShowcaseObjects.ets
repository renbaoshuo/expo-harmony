import { ExpoModuleContext, ExpoSharedObject, ExpoSharedRef } from '@expo-harmony/expo-modules-core';

export class ShowcaseCounter extends ExpoSharedObject {
  value: number;

  constructor(context: ExpoModuleContext, value: number) {
    super(context);
    this.value = value;
  }

  increment(delta: number): number {
    this.value += delta;
    return this.value;
  }

  emitValueChanged(): void {
    this.sendEvent('onValueChanged', { value: this.value });
  }
}

export class ShowcaseTextRef extends ExpoSharedRef<string> {
  constructor(context: ExpoModuleContext, value: string) {
    super(context, 'expo-module-showcase.text', value);
  }
}

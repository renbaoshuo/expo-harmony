import type { NativeModule, SharedObject, SharedRef } from 'expo-modules-core';
import type { Ref } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type ShowcasePlatform = 'android' | 'ios' | 'harmony';
export type ShowcaseEvent = { value: string; sequence: number; platform: ShowcasePlatform };
export type CounterEvent = { value: number };
export type NativePageResult = { action: 'done' | 'cancel'; value: number };
export type LifecycleSnapshot = {
  created: number;
  foregrounded: number;
  backgrounded: number;
  startObserving: number;
  stopObserving: number;
};

export declare class ShowcaseSharedCounter extends SharedObject<{
  onValueChanged: (event: CounterEvent) => void;
}> {
  constructor(initialValue: number);
  value: number;
  increment(delta: number): number;
  incrementAsync(delta: number): Promise<number>;
  emitValueChanged(): void;
}

export declare class ShowcaseTextRef extends SharedRef<'expo-module-showcase.text'> {
  readonly value: string;
}

export type ShowcaseViewEvent = { label: string; value: number; source: 'touch' | 'command' };
export type ShowcaseViewRef = { increment(delta: number): Promise<number> };
export type ShowcaseViewProps = Omit<ViewProps, 'ref'> & {
  label: string;
  value: number;
  onValueChanged?: (event: NativeSyntheticEvent<ShowcaseViewEvent>) => void;
  ref?: Ref<ShowcaseViewRef>;
};

export declare class ShowcaseNativeModule extends NativeModule<{
  onShowcaseEvent: (event: ShowcaseEvent) => void;
}> {
  readonly platform: ShowcasePlatform;
  readonly nativeLanguage: 'Kotlin' | 'Swift' | 'ArkTS';
  readonly ShowcaseSharedCounter: typeof ShowcaseSharedCounter;
  echo(value: string): string;
  echoAsync(value: string): Promise<string>;
  failAsync(): Promise<never>;
  emitEvent(value: string): void;
  getLifecycleSnapshot(): LifecycleSnapshot;
  returnSameSharedCounter(counter: ShowcaseSharedCounter): ShowcaseSharedCounter;
  createSharedTextRef(value: string): ShowcaseTextRef;
  openNativePage(initialValue: number): Promise<NativePageResult>;
}

export declare class ShowcaseConsumerModule extends NativeModule {
  readSharedCounter(counter: ShowcaseSharedCounter): number;
  forwardSharedCounter(counter: ShowcaseSharedCounter): ShowcaseSharedCounter;
  readSharedTextRef(ref: ShowcaseTextRef): string;
  forwardSharedTextRef(ref: ShowcaseTextRef): ShowcaseTextRef;
}

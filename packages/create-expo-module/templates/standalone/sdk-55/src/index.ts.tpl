import { requireNativeModule, requireNativeViewManager, SharedObject } from 'expo-modules-core';
import type { Ref } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type {{MODULE_BASE}}CounterEvents = {
  onValueChanged(payload: { value: number }): void;
};

export declare class {{MODULE_BASE}}CounterInstance extends SharedObject<{{MODULE_BASE}}CounterEvents> {
  readonly kind: 'arkts-counter';
  value: number;
  increment(delta: number): number;
  emitValueChanged(): number;
}

export type {{MODULE_BASE}}Counter = {{MODULE_BASE}}CounterInstance;

export interface {{MODULE_BASE}}CounterConstructor {
  new(initialValue: number): {{MODULE_BASE}}Counter;
  add(left: number, right: number): number;
}

export interface {{MODULE_BASE}}NativeModule {
  readonly platform: 'harmony';
  readonly {{MODULE_BASE}}Counter: {{MODULE_BASE}}CounterConstructor;
  echo(value: string): string;
  echoAsync(value: string): Promise<string>;
  createCounter(initialValue: number): {{MODULE_BASE}}Counter;
}

export interface {{MODULE_BASE}}ViewEvent {
  value: number;
}

export interface {{MODULE_BASE}}ViewRef {
  increment(delta: number): Promise<number>;
}

export type {{MODULE_BASE}}ViewProps = Omit<ViewProps, 'ref'> & {
  label?: string | null;
  onValueChanged?: (event: NativeSyntheticEvent<{{MODULE_BASE}}ViewEvent>) => void;
  ref?: Ref<{{MODULE_BASE}}ViewRef>;
  value?: number | null;
};

const nativeModule = requireNativeModule<{{MODULE_BASE}}NativeModule>('{{MODULE_NAME}}');

export const platform = nativeModule.platform;
export const {{MODULE_BASE}}Counter = nativeModule.{{MODULE_BASE}}Counter;
export const {{MODULE_BASE}}View = requireNativeViewManager<{{MODULE_BASE}}ViewProps>(
  '{{MODULE_NAME}}'
);
export const echo = (value: string): string => nativeModule.echo(value);
export const echoAsync = (value: string): Promise<string> => nativeModule.echoAsync(value);
export const createCounter = (initialValue: number): {{MODULE_BASE}}Counter =>
  nativeModule.createCounter(initialValue);

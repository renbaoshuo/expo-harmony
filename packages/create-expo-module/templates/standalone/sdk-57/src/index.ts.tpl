/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { requireNativeModule{{FACADE_IMPORTS}}, type NativeModule{{#SharedObject}}, type SharedObject{{/SharedObject}} } from 'expo-modules-core';
{{#View}}import type { Ref } from 'react';
import type { {{#ViewEvent}}NativeSyntheticEvent, {{/ViewEvent}}ViewProps } from 'react-native';
{{/View}}
{{#SharedObject}}export type {{MODULE_BASE}}CounterEvents = {
  onValueChanged(payload: { value: number }): void;
};

export interface {{MODULE_BASE}}CounterInstance extends InstanceType<typeof SharedObject<{{MODULE_BASE}}CounterEvents>> {
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

{{/SharedObject}}export type {{MODULE_BASE}}ModuleEvents = {
{{#Event}}  onChange(payload: { value: string }): void;
{{/Event}}};

export interface {{MODULE_BASE}}NativeModule extends InstanceType<typeof NativeModule<{{MODULE_BASE}}ModuleEvents>> {
{{#Constant}}  readonly platform: 'harmony';
{{/Constant}}{{#Function}}  echo(value: string): string;
{{/Function}}{{#AsyncFunction}}  echoAsync(value: string): Promise<string>;
{{/AsyncFunction}}{{#Event}}  emitChange(value: string): void;
{{/Event}}{{#SharedObject}}  readonly {{MODULE_BASE}}Counter: {{MODULE_BASE}}CounterConstructor;
  createCounter(initialValue: number): {{MODULE_BASE}}Counter;
{{/SharedObject}}}

{{#View}}{{#ViewEvent}}export interface {{MODULE_BASE}}ViewEvent {
  value: number;
}

{{/ViewEvent}}export interface {{MODULE_BASE}}ViewRef {
  increment(delta: number): Promise<number>;
}

export type {{MODULE_BASE}}ViewProps = Omit<ViewProps, 'ref'> & {
  label?: string | null;
{{#ViewEvent}}  onValueChanged?: (event: NativeSyntheticEvent<{{MODULE_BASE}}ViewEvent>) => void;{{/ViewEvent}}
  ref?: Ref<{{MODULE_BASE}}ViewRef>;
  value?: number | null;
};

{{/View}}const nativeModule = requireNativeModule<{{MODULE_BASE}}NativeModule>('{{MODULE_NAME}}');
export default nativeModule;

{{#Constant}}export const platform = nativeModule.platform;
{{/Constant}}{{#Function}}export const echo = (value: string): string => nativeModule.echo(value);
{{/Function}}{{#AsyncFunction}}export const echoAsync = (value: string): Promise<string> => nativeModule.echoAsync(value);
{{/AsyncFunction}}{{#Event}}export const emitChange = (value: string): void => nativeModule.emitChange(value);
{{/Event}}{{#SharedObject}}export const {{MODULE_BASE}}Counter = nativeModule.{{MODULE_BASE}}Counter;
export const createCounter = (initialValue: number): {{MODULE_BASE}}Counter => nativeModule.createCounter(initialValue);
{{/SharedObject}}{{#View}}export const {{MODULE_BASE}}View = requireNativeViewManager<{{MODULE_BASE}}ViewProps>('{{MODULE_NAME}}');
{{/View}}

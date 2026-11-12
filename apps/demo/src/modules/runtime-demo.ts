/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { requireOptionalNativeModule, type NativeModule } from 'expo-modules-core';

type Events = { onUpdatesStateChange: (value: { event: string }) => void };

export declare class RuntimeDemoModule extends NativeModule<Events> {
  readImage(uri: string, editing: boolean, callback: boolean): Promise<string>;
  readManifest(input: string, method: string, pluginName: string): string;
  readJSON(input: string, key: string, type: 'hasValue' | 'raw' | 'string' | 'number' | 'boolean' | 'array' | 'object', nullable: boolean): string;
  parseHeader(method: string, input: string, multipleLines: boolean): string;
  serializeHeader(format: 'dictionary' | 'list' | 'item', input: string): string;
  readUpdates(property: string): string;
}

export const runtimeDemo = requireOptionalNativeModule<RuntimeDemoModule>('RuntimeDemo');

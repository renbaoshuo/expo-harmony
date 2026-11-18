/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { UpdatesConfiguration } from './UpdatesConfiguration';
import { UpdatesState } from './UpdatesState';
import { Headers, Json, UpdateRecord } from './UpdatesProtocol';

export interface IUpdatesController {
  readonly state: UpdatesState;
  readonly configuration: UpdatesConfiguration;
  readonly ready: Promise<void>;
  readonly enabled: boolean;
  readonly active: boolean;
  readonly path: string | null;
  readonly launched?: UpdateRecord;
  readonly embedded?: UpdateRecord;

  start(): void;
  constants(id?: number): Json;
  attach(id: number, reload: (reason: string) => Promise<void>, owner: Object): () => void;
  loaded(id: number): void;
  contentAppeared(id: number): void;
  hasAsset(id: number, path: string): boolean;
  onReactInstanceException(id: number, error: Error): void;
  reload(id: number, reload: (reason: string) => Promise<void>): Promise<void>;
  checkForUpdateAsync(): Promise<Json>;
  fetchUpdateAsync(): Promise<Json>;
  extra(): Promise<Headers>;
  setExtra(key: string, value: string | null): Promise<void>;
  override(value: Json | null): void;
  overrideHeaders(headers: Headers | null): void;
}

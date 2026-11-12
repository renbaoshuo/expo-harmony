/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Json } from './UpdatesProtocol';

export type UpdatesStateValue = 'idle' | 'checking' | 'downloading' | 'restarting';

export type UpdatesStateEvent =
  | { type: 'startStartup' | 'endStartup' | 'check' | 'checkCompleteUnavailable' | 'download' | 'downloadComplete' | 'restart' }
  | { type: 'checkCompleteWithUpdate' | 'downloadCompleteWithUpdate'; manifest: Json }
  | { type: 'checkCompleteWithRollback' | 'downloadCompleteWithRollback'; commitTime: number }
  | { type: 'checkError' | 'downloadError'; errorMessage: string }
  | { type: 'downloadProgress'; progress: number };

export function nativeEvent(event: UpdatesStateEvent): Json {
  if (event.type === 'checkCompleteWithRollback') return { type: event.type };
  if (event.type === 'downloadCompleteWithRollback') return { type: 'downloadComplete' };

  return JSON.parse(JSON.stringify(event));
}

export function destination(event: UpdatesStateEvent): UpdatesStateValue {
  if (event.type === 'check') return 'checking';
  if (event.type === 'download' || event.type === 'downloadProgress') return 'downloading';
  if (event.type === 'restart') return 'restarting';

  return 'idle';
}

export function allowed(state: UpdatesStateValue, event: UpdatesStateEvent): boolean {
  if (state === 'idle') return ['startStartup', 'endStartup', 'check', 'download', 'restart'].includes(event.type);
  if (state === 'checking') return ['checkCompleteWithUpdate', 'checkCompleteWithRollback', 'checkCompleteUnavailable', 'checkError'].includes(event.type);
  if (state === 'downloading') return ['downloadProgress', 'downloadComplete', 'downloadCompleteWithUpdate', 'downloadCompleteWithRollback', 'downloadError'].includes(event.type);

  return false;
}

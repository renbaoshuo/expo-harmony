/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { File, Paths } from 'expo-file-system';
import { Platform } from 'react-native';

export type BackgroundExecution = {
  count: number;
  error: string | null;
  eventId: string;
  occurredAt: string;
};

export function readExecution(task: string): BackgroundExecution | null {
  if (Platform.OS === 'web') return null;
  const file = new File(Paths.document, `${task}.json`);
  if (!file.exists) return null;

  return JSON.parse(file.textSync()) as BackgroundExecution;
}

export function recordExecution(task: string, eventId: string, error: string | null): BackgroundExecution {
  const previous = readExecution(task);
  const value = {
    count: (previous?.count ?? 0) + 1,
    error,
    eventId,
    occurredAt: new Date().toISOString(),
  };

  new File(Paths.document, `${task}.json`).write(JSON.stringify(value));

  return value;
}

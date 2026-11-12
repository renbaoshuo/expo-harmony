/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { requireRecord, requireDate } from './CalendarRecords';

export const CALENDAR_RECORD = ExpoValueTypes.custom<Record<string, ESObject>>(
  'calendar details',
  (value: ESObject): Record<string, ESObject> => requireRecord(value, 'details'),
  (value: Record<string, ESObject>): ESObject => value,
);

export const CALENDAR_DATE = ExpoValueTypes.custom<number>(
  'ISO-8601 date or timestamp',
  (value: ESObject, path: string): number => requireDate(value, path),
  (value: number): ESObject => value,
);

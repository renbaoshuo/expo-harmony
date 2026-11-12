/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ConfigPlugin } from 'expo/config-plugins';

declare const withHarmonyCalendar: ConfigPlugin<{
  calendarPermission?: string;
  readCalendarPermission?: string;
  writeCalendarPermission?: string;
} | void>;

export = withHarmonyCalendar;

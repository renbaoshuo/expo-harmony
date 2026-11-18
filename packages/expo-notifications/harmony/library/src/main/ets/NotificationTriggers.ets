/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { integer, record } from './NotificationTypes';

const MAX_DATE = 8640000000000000;
const MILLISECONDS_PER_SECOND = 1000;
const MIN_REPEAT_INTERVAL_SECONDS = 24 * 60 * 60;
const MONTHS_IN_YEAR = 12;
const MAX_LEAP_DAY_GAP_YEARS = 8;

export function validateTrigger(value: ESObject): Record<string, ESObject> | null {
  if (value === null) return null;

  const trigger = record(value, 'trigger');

  switch (trigger.type) {
    case 'date':
      integer(trigger.timestamp, 'timestamp (milliseconds)', 0, MAX_DATE);
      break;
    case 'timeInterval':
      integer(trigger.seconds, 'seconds', 1, Math.floor(MAX_DATE / MILLISECONDS_PER_SECOND));
      if (trigger.repeats !== undefined && typeof trigger.repeats !== 'boolean') {
        throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', 'repeats must be a boolean.');
      }
      break;
    case 'daily':
    case 'weekly':
    case 'monthly':
    case 'yearly':
      integer(trigger.hour, 'hour', 0, 23);
      integer(trigger.minute, 'minute', 0, 59);
      if (trigger.type === 'weekly') integer(trigger.weekday, 'weekday', 1, 7);
      if (trigger.type === 'monthly' || trigger.type === 'yearly') integer(trigger.day, 'day', 1, 31);
      if (trigger.type === 'yearly') {
        integer(trigger.month, 'month', 0, 11);
        if (trigger.day > new Date(2000, trigger.month + 1, 0).getDate()) {
          throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', 'The requested day does not exist in that month.');
        }
      }
      break;
    case 'calendar':
      throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'iOS calendar pattern triggers are not supported on HarmonyOS.');
    default:
      throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', `Unknown notification trigger: ${String(trigger.type)}.`);
  }

  return trigger;
}

export function nextTriggerDate(trigger: Record<string, ESObject> | null, now: number = Date.now()): number | null {
  if (trigger === null) return null;
  if (trigger.type === 'date') return trigger.timestamp >= now ? trigger.timestamp : null;

  if (trigger.type === 'timeInterval') {
    const timestamp = now + trigger.seconds * MILLISECONDS_PER_SECOND;
    if (timestamp > MAX_DATE) {
      throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', 'The trigger date is outside the supported Date range.');
    }

    return timestamp;
  }

  const date = new Date(now);
  if (trigger.type === 'daily') {
    const today = new Date(date.getFullYear(), date.getMonth(), date.getDate(), trigger.hour as number, trigger.minute as number);

    return today.getTime() >= now
      ? today.getTime()
      : new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1, trigger.hour as number, trigger.minute as number).getTime();
  }

  if (trigger.type === 'weekly') {
    const offset: number = (trigger.weekday - 1 - date.getDay() + 7) % 7;
    const current = new Date(date.getFullYear(), date.getMonth(), date.getDate() + offset, trigger.hour as number, trigger.minute as number);

    return current.getTime() >= now
      ? current.getTime()
      : new Date(date.getFullYear(), date.getMonth(), date.getDate() + offset + 7, trigger.hour as number, trigger.minute as number).getTime();
  }

  const yearly = trigger.type === 'yearly';
  // Consecutive months cannot both lack day 31. A skipped leap century can
  // increase the gap between leap days to eight years.
  const lastOffset = yearly ? MAX_LEAP_DAY_GAP_YEARS : 2;
  const startMonth: number = yearly ? trigger.month : date.getMonth();
  const step = yearly ? MONTHS_IN_YEAR : 1;

  for (let offset = 0; offset <= lastOffset; offset++) {
    const month = new Date(date.getFullYear(), startMonth + offset * step, 1);
    const candidate = new Date(month.getFullYear(), month.getMonth(), trigger.day as number, trigger.hour as number, trigger.minute as number);
    if (candidate.getMonth() === month.getMonth() && candidate.getTime() >= now) return candidate.getTime();
  }

  return null;
}

export function reminderTrigger(trigger: Record<string, ESObject>, timestamp: number): reminderAgentManager.ReminderRequest {
  if (trigger.type === 'timeInterval') {
    const timer: reminderAgentManager.ReminderRequestTimer = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
      triggerTimeInSeconds: trigger.seconds as number,
    };

    if (trigger.repeats !== true) return timer;

    if (timer.triggerTimeInSeconds >= MIN_REPEAT_INTERVAL_SECONDS && typeof deviceInfo.apiAvailable === 'function') {
      if (deviceInfo.apiAvailable('26.0.0')) {
        timer.repeatInterval = timer.triggerTimeInSeconds;
        timer.repeatCount = 0;
        return timer;
      }
    }

    throw new ExpoModuleError(
      'ERR_NOTIFICATIONS_UNSUPPORTED',
      'Repeating interval reminders require HarmonyOS API 26 and an interval of at least 24 hours.',
    );
  }

  // Agent reminders have second resolution. Round up, never deliver early.
  const date = new Date(Math.ceil(timestamp / MILLISECONDS_PER_SECOND) * MILLISECONDS_PER_SECOND);
  const request: reminderAgentManager.ReminderRequestCalendar = {
    reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
    dateTime: {
      year: date.getFullYear(),
      month: date.getMonth() + 1,
      day: date.getDate(),
      hour: trigger.type === 'date' ? date.getHours() : trigger.hour as number,
      minute: trigger.type === 'date' ? date.getMinutes() : trigger.minute as number,
      second: date.getSeconds(),
    },
  };

  if (trigger.type === 'daily') request.daysOfWeek = [1, 2, 3, 4, 5, 6, 7];
  if (trigger.type === 'weekly') request.daysOfWeek = [trigger.weekday === 1 ? 7 : trigger.weekday - 1];
  if (trigger.type === 'monthly' || trigger.type === 'yearly') {
    request.repeatMonths = trigger.type === 'yearly' ? [trigger.month + 1] : [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    request.repeatDays = [trigger.day as number];
  }

  return request;
}

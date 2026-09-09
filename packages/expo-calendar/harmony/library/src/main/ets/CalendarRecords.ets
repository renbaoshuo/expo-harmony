import { calendarManager } from '@kit.CalendarKit';
import { ExpoModuleError } from '@expo-harmony/expo-modules-core';

const ENTITY_EVENT: string = 'event';
const ENTITY_REMINDER: string = 'reminder';
const AVAILABILITY_UNSUPPORTED: string = 'notSupported';
const STATUS_NONE: string = 'none';
const DEFAULT_COLOR: string = '#000000';
// Calendar Kit's native reader returns NORULE for an empty RRULE, even though the ArkTS enum omits it.
const NO_RECURRENCE: number = -1;
// Calendar Kit anchors all-day alarms at 09:00; Expo offsets start at midnight.
const ALL_DAY_ALARM_ANCHOR_MINUTES: number = 9 * 60;

export class ExpoCalendarError extends ExpoModuleError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoCalendarError';
  }
}

export class ExpoCalendarSource {
  type: string;
  name: string;
  isLocalAccount: boolean;

  constructor(account: calendarManager.CalendarAccount) {
    this.type = account.type === calendarManager.CalendarType.BIRTHDAY ? 'birthdays' : account.type;
    this.name = account.name;
    this.isLocalAccount = account.type === calendarManager.CalendarType.LOCAL;
  }
}

export class ExpoCalendarRecord {
  id: string;
  title: string;
  source: ExpoCalendarSource;
  type: string;
  color: string;
  entityType: string = ENTITY_EVENT;
  allowsModifications: boolean = true;
  allowedAvailabilities: string[] = [];
  isPrimary: boolean;
  name: string;
  ownerAccount: string;

  constructor(
    calendar: calendarManager.Calendar,
    account: calendarManager.CalendarAccount,
    config: calendarManager.CalendarConfig,
    primaryId?: number,
  ) {
    this.id = String(calendar.id);
    this.title = account.displayName || account.name;
    this.source = new ExpoCalendarSource(account);
    this.type = expoCalendarType(account.type);
    this.color = expoColor(config.color);
    this.isPrimary = calendar.id === primaryId;
    this.name = account.name;
    this.ownerAccount = account.name;
  }
}

export class ExpoAlarmRecord {
  relativeOffset: number;
  method: string = 'alert';

  constructor(minutes: number, allDay: boolean) {
    this.relativeOffset = (allDay ? ALL_DAY_ALARM_ANCHOR_MINUTES : 0) - minutes;
  }
}

export class ExpoWeekdayRecord {
  dayOfTheWeek: number;
  weekNumber?: number;

  constructor(dayOfTheWeek: number, weekNumber?: number) {
    this.dayOfTheWeek = dayOfTheWeek;
    this.weekNumber = weekNumber;
  }
}

export class ExpoRecurrenceRuleRecord {
  frequency: string;
  interval?: number;
  endDate?: string;
  occurrence?: number;
  daysOfTheWeek?: ExpoWeekdayRecord[];
  daysOfTheMonth?: number[];
  monthsOfTheYear?: number[];
  weeksOfTheYear?: number[];
  daysOfTheYear?: number[];

  constructor(rule: calendarManager.RecurrenceRule) {
    this.frequency = expoFrequency(rule.recurrenceFrequency);
    this.interval = rule.interval === undefined || rule.interval <= 0 ? undefined : Math.floor(rule.interval);
    this.endDate = rule.expire === undefined ? undefined : isoDate(rule.expire);
    this.occurrence = rule.expire === undefined && rule.count !== undefined && rule.count > 0 ? Math.floor(rule.count) : undefined;
    this.daysOfTheWeek = expoWeekdays(rule.daysOfWeek, rule.weeksOfMonth);
    this.daysOfTheMonth = uniqueNumbers(rule.daysOfMonth);
    this.monthsOfTheYear = uniqueNumbers(rule.monthsOfYear);
    this.weeksOfTheYear = nonEmptyNumbers(rule.weeksOfYear);
    this.daysOfTheYear = nonEmptyNumbers(rule.daysOfYear);
  }
}

export class ExpoEventRecord {
  id: string;
  calendarId: string;
  title: string;
  location: string | null;
  timeZone: string;
  notes: string;
  alarms: ExpoAlarmRecord[];
  recurrenceRule: ExpoRecurrenceRuleRecord | null;
  startDate: string;
  endDate: string;
  allDay: boolean;
  availability: string = AVAILABILITY_UNSUPPORTED;
  status: string = STATUS_NONE;

  constructor(event: calendarManager.Event, calendarId: string) {
    const rule = eventRecurrence(event);
    if (event.id === undefined) {
      throw new ExpoCalendarError('ERR_CALENDAR_INVALID_NATIVE_EVENT', 'HarmonyOS returned an event without an ID.');
    }
    if (event.isLunar && rule !== undefined) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Expo recurrence rules cannot represent a lunar calendar schedule.');
    }

    this.id = String(event.id);
    this.calendarId = calendarId;
    this.title = event.title ?? '';

    const location = event.location?.location;
    this.location = location === undefined || location.length === 0 ? null : location;
    this.timeZone = event.timeZone ?? '';
    this.notes = event.description ?? '';
    this.alarms = (event.reminderTime ?? []).map((minutes: number): ExpoAlarmRecord => new ExpoAlarmRecord(minutes, event.isAllDay ?? false));
    this.recurrenceRule = rule === undefined ? null : new ExpoRecurrenceRuleRecord(rule);

    this.startDate = isoDate(event.instanceStartTime ?? event.startTime);
    this.endDate = isoDate(event.instanceEndTime ?? event.endTime);
    this.allDay = event.isAllDay ?? false;
  }
}

export class ExpoAttendeeRecord {
  name: string;
  role: string;
  status: string;
  type: string;
  email?: string;

  constructor(attendee: calendarManager.Attendee) {
    this.name = attendee.name;
    this.role = expoAttendeeRole(attendee);
    this.status = expoAttendeeStatus(attendee.status);
    this.type = expoAttendeeType(attendee.type);
    this.email = attendee.email.length > 0 ? attendee.email : undefined;
  }
}

export class ExpoDialogResult {
  action: string;
  id: string | null;

  constructor(id: number) {
    if (!Number.isSafeInteger(id) || id === 0) {
      throw new ExpoCalendarError('ERR_CALENDAR_DIALOG', 'Calendar Kit returned an invalid event creation result.');
    }
    this.action = id > 0 ? 'saved' : 'canceled';
    this.id = id > 0 ? String(id) : null;
  }
}

function optionalRecord(value: ESObject): Record<string, ESObject> | undefined {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  return value as Record<string, ESObject>;
}

export function requireRecord(value: ESObject, name: string): Record<string, ESObject> {
  const record = optionalRecord(value);
  if (record === undefined) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ARGUMENT', `'${name}' must be an object.`);
  }

  return record;
}

export function requireCalendarId(value: ESObject, name: string = 'calendarId'): number {
  return requireNativeId(value, name);
}

export function requireEventId(value: ESObject, name: string = 'eventId'): number {
  return requireNativeId(value, name);
}

export function requireDate(value: ESObject, name: string): number {
  let time: number;
  if (typeof value === 'number') time = value;
  else if (typeof value === 'string' && value.length > 0) time = Date.parse(value);
  else time = Number.NaN;

  if (!Number.isFinite(time) || !Number.isFinite(new Date(time).getTime())) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_DATE', `'${name}' must be a valid ISO-8601 date or timestamp.`);
  }

  return time;
}

export function calendarAccountFromDetails(data: Record<string, ESObject>): calendarManager.CalendarAccount {
  validateEntityType(data['entityType']);
  const title = requireNonEmptyString(data['title'], 'title');
  let source: Record<string, ESObject> | undefined = undefined;
  if (has(data, 'source') && data['source'] !== undefined && data['source'] !== null) {
    source = requireRecord(data['source'], 'source');
  }

  const type =
    optionalNamedString(source?.['type'], 'source.type') ?? optionalNamedString(data['type'], 'type') ?? calendarManager.CalendarType.LOCAL;

  return {
    name: optionalNamedString(data['name'], 'name') ?? optionalNamedString(source?.['name'], 'source.name') ?? title,
    displayName: title,
    type: nativeCalendarType(type),
  };
}

export function calendarConfigFromDetails(data: Record<string, ESObject>, current?: calendarManager.CalendarConfig): calendarManager.CalendarConfig {
  const unsupported: string[] = ['sourceId', 'timeZone', 'isVisible', 'isSynced'];
  for (const field of unsupported) {
    if (has(data, field)) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', `Calendar Kit cannot write the calendar field '${field}'.`);
    }
  }

  const config: calendarManager.CalendarConfig = {
    enableReminder: current?.enableReminder ?? true,
    color: current?.color,
  };

  if (has(data, 'color')) {
    const color: ESObject = data['color'];
    if (color === undefined) return config;

    if (color === null) {
      config.color = undefined;
    } else if (typeof color === 'number' && Number.isFinite(color) && Number.isInteger(color)) {
      config.color = color;
    } else if (typeof color === 'string' && color.length > 0) {
      config.color = color;
    } else {
      throw new ExpoCalendarError('ERR_CALENDAR_INVALID_COLOR', "'color' must be a valid processed color value.");
    }
  }

  return config;
}

export function validateCalendarUpdate(data: Record<string, ESObject>, account: calendarManager.CalendarAccount): void {
  if (has(data, 'title') && requireNonEmptyString(data['title'], 'title') !== (account.displayName || account.name)) {
    throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'HarmonyOS Calendar Kit does not support renaming an existing calendar.');
  }

  if (has(data, 'name') && requireNonEmptyString(data['name'], 'name') !== account.name) {
    throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'HarmonyOS Calendar Kit does not support changing an existing calendar account name.');
  }

  const hasSource = has(data, 'source') && data['source'] !== undefined && data['source'] !== null;
  const hasType = has(data, 'type') && data['type'] !== undefined && data['type'] !== null;
  if (hasSource || hasType) {
    throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'HarmonyOS Calendar Kit does not support moving an existing calendar to another source.');
  }
}

export function validateEntityType(value: ESObject): void {
  if (value === undefined || value === null || value === ENTITY_EVENT) return;

  if (value === ENTITY_REMINDER) {
    throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Reminder calendars are not supported by HarmonyOS Calendar Kit.');
  }

  throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ENTITY', `Unsupported calendar entity type '${String(value)}'.`);
}

export function eventFromDetails(data: Record<string, ESObject>, current?: calendarManager.Event): calendarManager.Event {
  validateUnsupportedEventFields(data);

  const start = has(data, 'startDate') ? requireDate(data['startDate'], 'startDate') : current?.startTime;
  const end = has(data, 'endDate') ? requireDate(data['endDate'], 'endDate') : current?.endTime;
  if (start === undefined || end === undefined) {
    throw new ExpoCalendarError('ERR_CALENDAR_MISSING_DATE', "'startDate' and 'endDate' are required when creating an event.");
  }
  if (end < start) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_DATE_RANGE', "'endDate' must not be earlier than 'startDate'.");
  }

  const title = has(data, 'title') ? clearableString(data['title'], 'title') : current?.title;
  const location = has(data, 'location') ? nativeLocation(data['location']) : current?.location;
  const allDay = has(data, 'allDay') ? clearableBoolean(data['allDay'], 'allDay') : current?.isAllDay;
  const timeZone = has(data, 'timeZone') ? clearableString(data['timeZone'], 'timeZone') : current?.timeZone;
  let alarms = has(data, 'alarms') ? nativeAlarms(data['alarms'], allDay ?? false) : current?.reminderTime;
  if (!has(data, 'alarms') && current !== undefined && (allDay ?? false) !== (current.isAllDay ?? false)) {
    const shift = (allDay ? ALL_DAY_ALARM_ANCHOR_MINUTES : 0) - (current.isAllDay ? ALL_DAY_ALARM_ANCHOR_MINUTES : 0);
    alarms = alarms?.map((minutes: number): number => minutes + shift);
  }

  const recurrence = nativeRecurrence(data, current);
  const notes = has(data, 'notes') ? clearableString(data['notes'], 'notes') : current?.description;

  const event: calendarManager.Event = {
    type: current?.type ?? calendarManager.EventType.NORMAL,
    startTime: start,
    endTime: end,
  };
  if (current?.id !== undefined) event.id = current.id;
  if (title !== undefined) event.title = title;
  if (location !== undefined) event.location = location;
  if (allDay !== undefined) event.isAllDay = allDay;
  if (current?.attendee !== undefined) event.attendee = current.attendee;
  if (timeZone !== undefined) event.timeZone = timeZone;
  if (alarms !== undefined) event.reminderTime = alarms;
  if (recurrence !== undefined) event.recurrenceRule = recurrence;
  if (notes !== undefined) event.description = notes;
  if (current?.service !== undefined) event.service = current.service;
  if (current?.identifier !== undefined) event.identifier = current.identifier;
  if (current?.isLunar !== undefined) event.isLunar = current.isLunar;

  return event;
}

export function eventCalendarId(data: Record<string, ESObject>): number | undefined {
  if (!has(data, 'calendarId') || data['calendarId'] === undefined) return undefined;
  return requireCalendarId(data['calendarId']);
}

export function eventInstanceRequested(data: Record<string, ESObject>, options?: Record<string, ESObject>): boolean {
  const future: ESObject = options?.['futureEvents'];
  if (future !== undefined && future !== null && typeof future !== 'boolean') {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ARGUMENT', "'futureEvents' must be a boolean.");
  }

  return (data['instanceStartDate'] !== undefined && data['instanceStartDate'] !== null) || future === true;
}

export function expoAttendees(event: calendarManager.Event): ExpoAttendeeRecord[] {
  return (event.attendee ?? []).map((attendee: calendarManager.Attendee): ExpoAttendeeRecord => new ExpoAttendeeRecord(attendee));
}

function requireNativeId(value: ESObject, name: string): number {
  if (typeof value !== 'string' || !/^[0-9]+$/.test(value)) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ID', `'${name}' must be a non-empty native ID string.`);
  }

  const id = Number(value);
  if (!Number.isSafeInteger(id) || id <= 0) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ID', `'${name}' is not a valid HarmonyOS calendar ID.`);
  }

  return id;
}

function has(record: Record<string, ESObject>, key: string): boolean {
  return Object.keys(record).includes(key) && record[key] !== undefined;
}

function optionalString(value: ESObject): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function optionalNamedString(value: ESObject, name: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  const result = optionalString(value);
  if (result === undefined) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ARGUMENT', `'${name}' must be a non-empty string.`);
  }

  return result;
}

function requireNonEmptyString(value: ESObject, name: string): string {
  const result = optionalString(value);
  if (result === undefined) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ARGUMENT', `'${name}' must be a non-empty string.`);
  }

  return result;
}

function clearableString(value: ESObject, name: string): string | undefined {
  if (value === undefined) return undefined;
  if (value === null) return '';
  if (typeof value !== 'string') {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ARGUMENT', `'${name}' must be a string or null.`);
  }

  return value;
}

function clearableBoolean(value: ESObject, name: string): boolean | undefined {
  if (value === undefined) return undefined;
  if (value === null) return false;
  if (typeof value !== 'boolean') {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ARGUMENT', `'${name}' must be a boolean or null.`);
  }

  return value;
}

function nativeLocation(value: ESObject): calendarManager.Location | undefined {
  const location = clearableString(value, 'location');
  return location === undefined ? undefined : { location };
}

function nativeAlarms(value: ESObject, allDay: boolean): number[] | undefined {
  if (value === undefined) return undefined;
  if (value === null) return [];
  if (!Array.isArray(value)) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ALARMS', "'alarms' must be an array or null.");
  }

  const reminders: number[] = [];
  value.forEach((entry: ESObject): void => {
    const alarm = requireRecord(entry, 'alarm');

    if (alarm['absoluteDate'] !== undefined && alarm['absoluteDate'] !== null) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'HarmonyOS Calendar Kit only supports event-relative alarms.');
    }
    if (alarm['structuredLocation'] !== undefined && alarm['structuredLocation'] !== null) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'HarmonyOS Calendar Kit does not support location-based calendar alarms.');
    }

    const method: ESObject = alarm['method'];
    if (method !== undefined && method !== null && method !== 'alert' && method !== 'default') {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', `HarmonyOS Calendar Kit does not support the '${String(method)}' alarm method.`);
    }

    const offset: ESObject = alarm['relativeOffset'];
    if (typeof offset !== 'number' || !Number.isFinite(offset) || !Number.isInteger(offset)) {
      throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ALARM', "An alarm's 'relativeOffset' must be an integer number of minutes.");
    }

    reminders.push((allDay ? ALL_DAY_ALARM_ANCHOR_MINUTES : 0) - offset);
  });

  return reminders;
}

function nativeRecurrence(data: Record<string, ESObject>, current?: calendarManager.Event): calendarManager.RecurrenceRule | undefined {
  // Omission preserves the stored RRULE/EXDATE in Calendar Kit's update API.
  // Re-serializing a fetched rule would lose native selectors not exposed by its reader.
  if (!has(data, 'recurrenceRule')) return undefined;

  const previous = eventRecurrence(current);
  const value: ESObject = data['recurrenceRule'];
  if (value === undefined || value === null) {
    if (previous !== undefined) {
      throw new ExpoCalendarError(
        'ERR_CALENDAR_UNSUPPORTED',
        'HarmonyOS Calendar Kit cannot remove a recurrence rule from an existing event; delete and recreate the event instead.',
      );
    }

    return undefined;
  }

  const record = requireRecord(value, 'recurrenceRule');
  if (current?.isLunar) {
    throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Expo recurrence rules cannot modify a lunar calendar schedule.');
  }

  const endDate: ESObject = record['endDate'];
  const expire = endDate === undefined || endDate === null ? undefined : requireDate(endDate, 'recurrenceRule.endDate');
  const count = expire === undefined ? optionalPositiveInteger(record['occurrence'], 'recurrenceRule.occurrence') : undefined;
  const interval = optionalPositiveInteger(record['interval'], 'recurrenceRule.interval');
  const weekdays = nativeWeekdays(record['daysOfTheWeek']);
  const monthDays = nativeMonthDays(record['daysOfTheMonth'], record['monthsOfTheYear']);
  const setPositions = numberArray(record['setPositions'], 'recurrenceRule.setPositions', -366, 366, true);

  if (setPositions !== undefined && setPositions.length > 0) {
    throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', "HarmonyOS Calendar Kit does not support recurrence 'setPositions'.");
  }

  const rule: calendarManager.RecurrenceRule = {
    recurrenceFrequency: nativeFrequency(requireNonEmptyString(record['frequency'], 'recurrenceRule.frequency')),
  };
  const yearWeeks = numberArray(record['weeksOfTheYear'], 'recurrenceRule.weeksOfTheYear', 1, 53);
  const yearDays = numberArray(record['daysOfTheYear'], 'recurrenceRule.daysOfTheYear', 1, 366);

  // Calendar Kit silently ignores or overwrites selectors unsupported by the frequency.
  validateRecurrenceSelectors(rule.recurrenceFrequency, weekdays, monthDays, yearWeeks, yearDays);
  if (expire !== undefined && expire <= 0) {
    throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Calendar Kit requires recurrence endDate to be after the Unix epoch.');
  }

  if (expire !== undefined) rule.expire = expire;
  if (count !== undefined) rule.count = count;
  if (interval !== undefined) rule.interval = interval;
  if (previous?.excludedDates !== undefined) rule.excludedDates = previous.excludedDates;
  if (weekdays.days !== undefined) rule.daysOfWeek = weekdays.days;
  if (weekdays.weeks !== undefined) rule.weeksOfMonth = weekdays.weeks;
  if (monthDays.days !== undefined) rule.daysOfMonth = monthDays.days;
  if (monthDays.months !== undefined) rule.monthsOfYear = monthDays.months;
  if (yearWeeks !== undefined) rule.weeksOfYear = yearWeeks;
  if (yearDays !== undefined) rule.daysOfYear = yearDays;

  return rule;
}

class NativeWeekdays {
  days?: number[];
  weeks?: number[];
}

class MonthDays {
  days?: number[];
  months?: number[];
}

function validateRecurrenceSelectors(
  frequency: calendarManager.RecurrenceFrequency,
  weekdays: NativeWeekdays,
  monthDays: MonthDays,
  yearWeeks?: number[],
  yearDays?: number[],
): void {
  const week = weekdays.days !== undefined;
  const ordinal = weekdays.weeks !== undefined;
  const day = monthDays.days !== undefined;
  const month = monthDays.months !== undefined;
  const yearWeek = yearWeeks !== undefined;
  const yearDay = yearDays !== undefined;
  if (!week && !ordinal && !day && !month && !yearWeek && !yearDay) return;

  let supported: boolean = false;
  switch (frequency) {
    case calendarManager.RecurrenceFrequency.WEEKLY:
      supported = week && !ordinal && !day && !month && !yearWeek && !yearDay;
      break;
    case calendarManager.RecurrenceFrequency.MONTHLY:
      supported = (!week || ordinal) && !month && !yearWeek && !yearDay;
      break;
    case calendarManager.RecurrenceFrequency.YEARLY:
      supported =
        (yearDay && !week && !day && !month && !yearWeek) ||
        (yearWeek && week && !ordinal && !day && !month && !yearDay) ||
        (month && day && !week && !yearWeek && !yearDay) ||
        (month && week && ordinal && !day && !yearWeek && !yearDay);
      break;
  }

  if (!supported) {
    throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Calendar Kit cannot represent this combination of recurrence selectors.');
  }
}

function nativeMonthDays(days: ESObject, months: ESObject): MonthDays {
  const result = new MonthDays();
  result.days = numberArray(days, 'recurrenceRule.daysOfTheMonth', 1, 31);
  result.months = numberArray(months, 'recurrenceRule.monthsOfTheYear', 1, 12);
  return result;
}

function nativeWeekdays(value: ESObject): NativeWeekdays {
  if (value === undefined || value === null) return new NativeWeekdays();
  if (!Array.isArray(value)) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_RECURRENCE', "'recurrenceRule.daysOfTheWeek' must be an array.");
  }

  const days: number[] = [];
  const weeks: number[] = [];
  let ordinal: boolean = false;
  let plain: boolean = false;
  value.forEach((entry: ESObject): void => {
    const record = requireRecord(entry, 'recurrenceRule.daysOfTheWeek entry');
    const day = requireInteger(record['dayOfTheWeek'], 'recurrenceRule.daysOfTheWeek.dayOfTheWeek', 1, 7);
    const weekday = day === 1 ? 7 : day - 1;
    const week = optionalInteger(record['weekNumber'], 'recurrenceRule.daysOfTheWeek.weekNumber', 1, 5);

    if (week === undefined) {
      plain = true;
      if (!days.includes(weekday)) days.push(weekday);

      return;
    }

    ordinal = true;
    const duplicate = days.some((day: number, index: number): boolean => day === weekday && weeks[index] === week);
    if (!duplicate) {
      days.push(weekday);
      weeks.push(week);
    }
  });

  if (ordinal && plain) {
    throw new ExpoCalendarError(
      'ERR_CALENDAR_UNSUPPORTED',
      'HarmonyOS Calendar Kit cannot combine weekdays with and without a month-week selector in one recurrence rule.',
    );
  }

  const result = new NativeWeekdays();
  result.days = days.length === 0 ? undefined : days;
  result.weeks = weeks.length === 0 ? undefined : weeks;

  return result;
}

function numberArray(value: ESObject, name: string, min: number, max: number, excludeZero: boolean = false): number[] | undefined {
  if (value === undefined || value === null) return undefined;
  if (!Array.isArray(value)) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_RECURRENCE', `'${name}' must be an array.`);
  }

  const result: number[] = [];
  value.forEach((entry: ESObject): void => {
    const number = requireInteger(entry, name, min, max);
    if (excludeZero && number === 0) {
      throw new ExpoCalendarError('ERR_CALENDAR_INVALID_RECURRENCE', `'${name}' cannot contain zero.`);
    }

    if (!result.includes(number)) result.push(number);
  });

  return result.length === 0 ? undefined : result;
}

function requireInteger(value: ESObject, name: string, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_RECURRENCE', `'${name}' must contain integers from ${min} through ${max}.`);
  }

  return value;
}

function optionalInteger(value: ESObject, name: string, min: number, max: number): number | undefined {
  if (value === undefined || value === null || value === 0) return undefined;
  return requireInteger(value, name, min, max);
}

function optionalPositiveInteger(value: ESObject, name: string): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'number' || !Number.isSafeInteger(value)) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_RECURRENCE', `'${name}' must be an integer.`);
  }

  return value > 0 ? value : undefined;
}

function validateUnsupportedEventFields(data: Record<string, ESObject>): void {
  if (
    has(data, 'availability') &&
    data['availability'] !== undefined &&
    data['availability'] !== null &&
    data['availability'] !== AVAILABILITY_UNSUPPORTED
  ) {
    throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', "HarmonyOS Calendar Kit does not expose an event 'availability' field.");
  }

  if (has(data, 'status') && data['status'] !== undefined && data['status'] !== null && data['status'] !== STATUS_NONE) {
    throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', "HarmonyOS Calendar Kit does not expose an event 'status' field.");
  }

  const fields: string[] = [
    'url',
    'endTimeZone',
    'creationDate',
    'lastModifiedDate',
    'originalStartDate',
    'isDetached',
    'organizer',
    'organizerEmail',
    'accessLevel',
    'guestsCanModify',
    'guestsCanInviteOthers',
    'guestsCanSeeGuests',
    'originalId',
    'instanceId',
  ];
  const supplied = fields.filter((field: string): boolean => {
    return has(data, field) && data[field] !== undefined && data[field] !== null;
  });

  if (supplied.length > 0) {
    throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', `HarmonyOS Calendar Kit cannot write Expo event field(s): ${supplied.join(', ')}.`);
  }
}

function nativeFrequency(value: string): calendarManager.RecurrenceFrequency {
  if (value === 'daily') return calendarManager.RecurrenceFrequency.DAILY;
  if (value === 'weekly') return calendarManager.RecurrenceFrequency.WEEKLY;
  if (value === 'monthly') return calendarManager.RecurrenceFrequency.MONTHLY;
  if (value === 'yearly') return calendarManager.RecurrenceFrequency.YEARLY;

  throw new ExpoCalendarError('ERR_CALENDAR_INVALID_RECURRENCE', `Unsupported recurrence frequency '${value}'.`);
}

function expoFrequency(value: calendarManager.RecurrenceFrequency): string {
  if (value === calendarManager.RecurrenceFrequency.DAILY) return 'daily';
  if (value === calendarManager.RecurrenceFrequency.WEEKLY) return 'weekly';
  if (value === calendarManager.RecurrenceFrequency.MONTHLY) return 'monthly';
  if (value === calendarManager.RecurrenceFrequency.YEARLY) return 'yearly';

  throw new ExpoCalendarError('ERR_CALENDAR_INVALID_NATIVE_EVENT', `HarmonyOS returned an unknown recurrence frequency '${value}'.`);
}

function eventRecurrence(event?: calendarManager.Event): calendarManager.RecurrenceRule | undefined {
  const rule = event?.recurrenceRule;
  return rule?.recurrenceFrequency === NO_RECURRENCE ? undefined : rule;
}

function nativeCalendarType(value: string): calendarManager.CalendarType {
  if (value === calendarManager.CalendarType.LOCAL) return calendarManager.CalendarType.LOCAL;
  if (value === calendarManager.CalendarType.EMAIL) return calendarManager.CalendarType.EMAIL;
  if (value === calendarManager.CalendarType.BIRTHDAY || value === 'birthdays') return calendarManager.CalendarType.BIRTHDAY;
  if (value === calendarManager.CalendarType.CALDAV) return calendarManager.CalendarType.CALDAV;
  if (value === calendarManager.CalendarType.SUBSCRIBED) return calendarManager.CalendarType.SUBSCRIBED;

  throw new ExpoCalendarError('ERR_CALENDAR_INVALID_SOURCE', `Unsupported HarmonyOS calendar source type '${value}'.`);
}

function expoCalendarType(value: calendarManager.CalendarType): string {
  if (value === calendarManager.CalendarType.BIRTHDAY) return 'birthdays';
  if (value === calendarManager.CalendarType.EMAIL) return 'unknown';
  return value;
}

function expoColor(value: number | string | undefined): string {
  // Calendar Kit may return #AARRGGBB; Expo serializes calendar colors as #RRGGBB.
  const color = typeof value === 'string' && /^#([0-9a-f]{6}|[0-9a-f]{8})$/i.test(value) ? Number.parseInt(value.slice(1), 16) : value;
  if (typeof color !== 'number' || !Number.isFinite(color)) return DEFAULT_COLOR;

  const rgb = (Math.trunc(color) & 0xffffff) >>> 0;

  return `#${rgb.toString(16).padStart(6, '0').toUpperCase()}`;
}

function expoWeekdays(days?: number[], weeks?: number[]): ExpoWeekdayRecord[] | undefined {
  if (days === undefined || days.length === 0) {
    if (weeks !== undefined && weeks.length > 0) {
      throw new ExpoCalendarError(
        'ERR_CALENDAR_INVALID_NATIVE_EVENT',
        'HarmonyOS returned a recurrence rule with month-week selectors but no weekdays.',
      );
    }

    return undefined;
  }

  if (weeks !== undefined && weeks.length > 0 && weeks.length !== days.length) {
    throw new ExpoCalendarError(
      'ERR_CALENDAR_INVALID_NATIVE_EVENT',
      'HarmonyOS returned a recurrence rule with mismatched weekday and month-week arrays.',
    );
  }

  const result: ExpoWeekdayRecord[] = [];
  days.forEach((day: number, index: number): void => {
    const weekday = day === 7 ? 1 : day + 1;
    result.push(new ExpoWeekdayRecord(weekday, weeks?.[index]));
  });

  return result;
}

function uniqueNumbers(values?: number[]): number[] | undefined {
  if (values === undefined || values.length === 0) return undefined;

  const result: number[] = [];
  values.forEach((value: number): void => {
    if (!result.includes(value)) result.push(value);
  });

  return result;
}

function nonEmptyNumbers(value?: number[]): number[] | undefined {
  return value === undefined || value.length === 0 ? undefined : value.slice();
}

function expoAttendeeRole(attendee: calendarManager.Attendee): string {
  if (attendee.role === calendarManager.AttendeeRole.ORGANIZER) return 'organizer';
  if (attendee.role === calendarManager.AttendeeRole.PARTICIPANT) return 'attendee';
  return 'unknown';
}

function expoAttendeeType(value?: calendarManager.AttendeeType): string {
  if (value === calendarManager.AttendeeType.OPTIONAL) return 'optional';
  if (value === calendarManager.AttendeeType.RESOURCE) return 'resource';
  if (value === calendarManager.AttendeeType.REQUIRED) return 'required';
  return 'unknown';
}

function expoAttendeeStatus(value?: calendarManager.AttendeeStatus): string {
  if (value === calendarManager.AttendeeStatus.TENTATIVE) return 'tentative';
  if (value === calendarManager.AttendeeStatus.ACCEPTED) return 'accepted';
  if (value === calendarManager.AttendeeStatus.DECLINED) return 'declined';
  if (value === calendarManager.AttendeeStatus.UNRESPONSIVE) return 'pending';
  return 'unknown';
}

function isoDate(time: number): string {
  if (!Number.isFinite(time) || !Number.isFinite(new Date(time).getTime())) {
    throw new ExpoCalendarError('ERR_CALENDAR_INVALID_NATIVE_EVENT', 'HarmonyOS returned an invalid event timestamp.');
  }

  return new Date(time).toISOString();
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoService, ExpoServiceContext, ExpoServiceKey } from '@expo-harmony/expo-modules-core';
import { calendarManager } from '@kit.CalendarKit';
import {
  ExpoCalendarError,
  ExpoCalendarRecord,
  ExpoDialogResult,
  ExpoEventRecord,
  calendarAccountFromDetails,
  calendarConfigFromDetails,
  eventCalendarId,
  eventFromDetails,
  eventInstanceRequested,
  requireCalendarId,
  requireDate,
  requireEventId,
  validateCalendarUpdate,
  validateEntityType,
} from './CalendarRecords';
import { CalendarPermissions } from './CalendarPermissions';

const EVENT_FIELDS: (keyof calendarManager.Event)[] = [
  'id',
  'type',
  'title',
  'location',
  'startTime',
  'endTime',
  'isAllDay',
  'attendee',
  'timeZone',
  'reminderTime',
  'recurrenceRule',
  'description',
  'service',
  'identifier',
  'isLunar',
];
const INSTANCE_FIELDS: (keyof calendarManager.Event)[] = [...EVENT_FIELDS, 'instanceStartTime', 'instanceEndTime'];
const DEFAULT_DIALOG_DURATION_MS: number = 60 * 60 * 1000;

export class LocatedEvent {
  calendar: calendarManager.Calendar;
  event: calendarManager.Event;

  constructor(calendar: calendarManager.Calendar, event: calendarManager.Event) {
    this.calendar = calendar;
    this.event = event;
  }
}

class SavedEvent {
  readonly calendar: calendarManager.Calendar;
  readonly id: number;

  constructor(calendar: calendarManager.Calendar, id: number) {
    this.calendar = calendar;
    this.id = id;
  }
}

export class ExpoCalendarStore {
  readonly permissions: CalendarPermissions;
  private pending: boolean = false;
  private mutations: Promise<void> = Promise.resolve();
  private readonly context: ExpoModuleContext;

  constructor(context: ExpoModuleContext) {
    this.context = context;
    this.permissions = new CalendarPermissions(context);
  }

  assertActive(): void {
    if (!this.context.isValid) throw new ExpoCalendarError('ERR_CALENDAR_DESTROYED', 'The Expo Calendar runtime has been destroyed.');
  }

  async calendarRecord(id: string): Promise<ExpoCalendarRecord> {
    const calendar = await this.requireCalendar(requireCalendarId(id));
    return this.calendarRecordFromNative(calendar);
  }

  async calendarRecordFromNative(calendar: calendarManager.Calendar): Promise<ExpoCalendarRecord> {
    const primary = await this.manager().getCalendar();
    this.assertReadable();
    return new ExpoCalendarRecord(calendar, calendar.getAccount(), calendar.getConfig(), primary.id);
  }

  async eventRecord(id: string, calendar?: calendarManager.Calendar): Promise<ExpoEventRecord> {
    const located = await this.requireEvent(requireEventId(id), calendar);
    return new ExpoEventRecord(located.event, String(located.calendar.id));
  }

  private manager(): calendarManager.CalendarManager {
    this.assertActive();
    if (!canIUse('SystemCapability.Applications.CalendarData')) {
      throw new ExpoCalendarError('ERR_UNAVAILABLE', 'Calendar Kit is not available on this device.');
    }
    this.permissions.ensureReadable();
    return calendarManager.getCalendarManager(this.context.uiAbilityContext);
  }

  private assertReadable(): void {
    this.assertActive();
    this.permissions.ensureReadable();
  }

  mutate<Result>(operation: () => Promise<Result>): Promise<Result> {
    // Calendar Kit replaces fields on update; serialize partial updates to avoid lost writes.
    const result = this.mutations.then(async (): Promise<Result> => {
      this.assertActive();
      this.permissions.ensureWritable();

      const value = await operation();
      this.assertActive();
      return value;
    });
    this.mutations = result.then(
      (): void => {},
      (): void => {},
    );

    return result;
  }

  async getCalendars(entity?: string | null): Promise<ExpoCalendarRecord[]> {
    validateEntityType(entity);

    const manager = this.manager();
    const primary = await manager.getCalendar();
    this.assertReadable();
    const calendars = await manager.getAllCalendars();
    this.assertReadable();

    return calendars.map(
      (calendar: calendarManager.Calendar): ExpoCalendarRecord =>
        new ExpoCalendarRecord(calendar, calendar.getAccount(), calendar.getConfig(), primary.id),
    );
  }

  async getDefaultCalendar(): Promise<ExpoCalendarRecord> {
    const calendar = await this.manager().getCalendar();
    this.assertReadable();
    return new ExpoCalendarRecord(calendar, calendar.getAccount(), calendar.getConfig(), calendar.id);
  }

  async saveCalendar(data: Record<string, ESObject>): Promise<calendarManager.Calendar> {
    validateEntityType(data['entityType']);

    const manager = this.manager();

    if (data['id'] === undefined || data['id'] === null) {
      const account = calendarAccountFromDetails(data);
      const config = calendarConfigFromDetails(data);

      const calendar = await manager.createCalendar(account);
      if (!Number.isSafeInteger(calendar.id) || calendar.id <= 0) {
        throw new ExpoCalendarError('ERR_CALENDAR_NOT_SAVED', 'Calendar Kit did not create a valid calendar.');
      }

      try {
        this.assertActive();
        this.permissions.ensureWritable();
        await calendar.setConfig(config);
      } catch (error) {
        try {
          await manager.deleteCalendar(calendar);
        } catch (_) {}

        throw new ExpoCalendarError('ERR_CALENDAR_NOT_SAVED', `Could not configure the calendar: ${(error as Error).message}`);
      }

      return calendar;
    }

    const calendar = await this.requireCalendar(requireCalendarId(data['id'], 'id'));
    validateCalendarUpdate(data, calendar.getAccount());

    const config = calendarConfigFromDetails(data, calendar.getConfig());

    this.assertActive();
    this.permissions.ensureWritable();

    await calendar.setConfig(config);

    return calendar;
  }

  async deleteCalendar(id: string): Promise<void> {
    const calendar = await this.requireCalendar(requireCalendarId(id));
    this.permissions.ensureWritable();
    await this.manager().deleteCalendar(calendar);
  }

  async getEvents(start: number, end: number, ids: string[], emptyMeansAll: boolean = false): Promise<ExpoEventRecord[]> {
    if (end < start) throw new ExpoCalendarError('ERR_CALENDAR_INVALID_DATE_RANGE', 'endDate must not precede startDate.');
    if (ids.length === 0 && !emptyMeansAll) throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ARGUMENT', 'calendarIds must not be empty.');

    const selected = ids.map((id: string): number => requireCalendarId(id));
    const calendars = await this.manager().getAllCalendars();
    this.assertReadable();

    const events: ExpoEventRecord[] = [];
    for (const calendar of calendars) {
      if (!(emptyMeansAll && selected.length === 0) && !selected.includes(calendar.id)) continue;

      const instances = await calendar.queryEventInstances(start, end, undefined, INSTANCE_FIELDS);
      this.assertReadable();

      for (const event of instances) events.push(new ExpoEventRecord(event, String(calendar.id)));
    }

    events.sort((left: ExpoEventRecord, right: ExpoEventRecord): number => Date.parse(left.startDate) - Date.parse(right.startDate));

    return events;
  }

  async saveEvent(data: Record<string, ESObject>, options: Record<string, ESObject>): Promise<SavedEvent> {
    if (eventInstanceRequested(data, options)) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Calendar Kit cannot update individual or future recurring instances.');
    }

    if (data['id'] === undefined || data['id'] === null) {
      const calendarId = eventCalendarId(data);
      if (calendarId === undefined) throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ARGUMENT', 'calendarId is required.');

      const calendar = await this.requireCalendar(calendarId);
      const event = eventFromDetails(data);

      this.assertActive();
      this.permissions.ensureWritable();

      const id = await calendar.addEvent(event);
      if (!Number.isSafeInteger(id) || id <= 0) throw new ExpoCalendarError('ERR_EVENT_NOT_SAVED', 'Calendar Kit did not create a valid event.');

      return new SavedEvent(calendar, id);
    }

    const id = requireEventId(data['id'], 'id');
    const located = await this.requireEvent(id);
    const calendarId = eventCalendarId(data);
    if (calendarId !== undefined && calendarId !== located.calendar.id) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Calendar Kit cannot move an event between calendars.');
    }

    const event = eventFromDetails(data, located.event);

    this.assertActive();
    this.permissions.ensureWritable();

    await located.calendar.updateEvent(event);

    return new SavedEvent(located.calendar, id);
  }

  async deleteEvent(data: Record<string, ESObject>, options: Record<string, ESObject>): Promise<void> {
    if (eventInstanceRequested(data, options)) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Calendar Kit cannot delete individual or future recurring instances.');
    }

    const id = requireEventId(data['id'], 'id');
    const located = await this.requireEvent(id);

    this.assertActive();
    this.permissions.ensureWritable();

    await located.calendar.deleteEvent(id);
  }

  async createEventInCalendar(data: Record<string, ESObject>): Promise<ExpoDialogResult> {
    this.assertActive();
    if (!canIUse('SystemCapability.Applications.CalendarData')) {
      throw new ExpoCalendarError('ERR_UNAVAILABLE', 'Calendar Kit is not available on this device.');
    }
    if (this.pending) throw new ExpoCalendarError('ERR_CALENDAR_DIALOG_PENDING', 'A calendar dialog is already open.');
    if (data['timeZone'] !== undefined && data['timeZone'] !== null) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Calendar Kit cannot set timeZone on the system creation page.');
    }
    if (data['calendarId'] !== undefined && data['calendarId'] !== null) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'The system creation page chooses its own calendar.');
    }

    const start = data['startDate'] == null ? Date.now() : requireDate(data['startDate'], 'startDate');
    const end = data['endDate'] == null ? start + DEFAULT_DIALOG_DURATION_MS : requireDate(data['endDate'], 'endDate');

    const input: Record<string, ESObject> = {};
    Object.keys(data).forEach((key: string): void => {
      input[key] = data[key];
    });
    input['startDate'] = start;
    input['endDate'] = end;
    const event = eventFromDetails(input);

    this.pending = true;

    try {
      const manager = calendarManager.getCalendarManager(this.context.uiAbilityContext);
      const id = await manager.editEvent(event);
      this.assertActive();

      return new ExpoDialogResult(id);
    } finally {
      this.pending = false;
    }
  }

  async requireCalendar(id: number): Promise<calendarManager.Calendar> {
    const calendar = (await this.manager().getAllCalendars()).find((value: calendarManager.Calendar): boolean => value.id === id);
    this.assertReadable();
    if (calendar === undefined) throw new ExpoCalendarError('ERR_CALENDAR_NOT_FOUND', `No accessible calendar has ID '${id}'.`);
    return calendar;
  }

  async requireEvent(id: number, knownCalendar?: calendarManager.Calendar): Promise<LocatedEvent> {
    const manager = this.manager();
    const calendars = knownCalendar === undefined ? await manager.getAllCalendars() : [knownCalendar];
    this.assertReadable();

    for (const calendar of calendars) {
      const events = await calendar.getEvents(calendarManager.EventFilter.filterById([id]), EVENT_FIELDS);
      this.assertReadable();

      const event = events.find((value: calendarManager.Event): boolean => value.id === id);
      if (event !== undefined) return new LocatedEvent(calendar, event);
    }

    throw new ExpoCalendarError('ERR_CALENDAR_EVENT_NOT_FOUND', `No accessible event has ID '${id}'.`);
  }
}

export class ExpoCalendarService extends ExpoService {
  static readonly key = new ExpoServiceKey<ExpoCalendarService>('ExpoCalendarService');
  readonly identity = ExpoCalendarService.key.bind(this);
  private store?: ExpoCalendarStore;

  constructor(context?: ExpoServiceContext) {
    super(context);
  }

  get(context: ExpoModuleContext): ExpoCalendarStore {
    if (this.store === undefined) this.store = new ExpoCalendarStore(context);
    return this.store;
  }
}

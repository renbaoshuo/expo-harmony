/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoService, ExpoServiceContext, ExpoServiceKey } from '@expo-harmony/expo-modules-core';
import { deviceInfo } from '@kit.BasicServicesKit';
import { calendarManager } from '@kit.CalendarKit';
import {
  ExpoCalendarError,
  ExpoCalendarRecord,
  ExpoDialogResult,
  ExpoOpenDialogResult,
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
import { CalendarPermissionResponse, CalendarPermissions } from './CalendarPermissions';

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

class PermissionRequest {
  readonly epoch: string;
  readonly result: Promise<CalendarPermissionResponse>;

  constructor(epoch: string, result: Promise<CalendarPermissionResponse>) {
    this.epoch = epoch;
    this.result = result;
  }
}

export class ExpoCalendarStore {
  readonly permissions: CalendarPermissions;
  private readonly context: ExpoModuleContext;
  private readonly service: ExpoCalendarService;

  constructor(context: ExpoModuleContext, service: ExpoCalendarService) {
    this.context = context;
    this.service = service;
    this.permissions = new CalendarPermissions(context);
  }

  assertActive(): void {
    if (!this.context.isValid) throw new ExpoCalendarError('ERR_CALENDAR_DESTROYED', 'The Expo Calendar runtime has been destroyed.');
  }

  requestPermissions(): Promise<CalendarPermissionResponse> {
    return this.service.requestPermissions(this.context.runtimeEpoch, (): Promise<CalendarPermissionResponse> => this.permissions.request());
  }

  async calendarRecord(id: string): Promise<ExpoCalendarRecord> {
    const calendar = await this.requireCalendar(requireCalendarId(id));
    return this.calendarRecordFromNative(calendar);
  }

  async calendarRecordFromNative(calendar: calendarManager.Calendar): Promise<ExpoCalendarRecord> {
    const primary = await this.manager().getCalendar();
    this.assertReadable();

    return this.serializeCalendar(calendar, primary.id, this.permissions.hasWriteAccess());
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
    return this.service.mutate(async (): Promise<Result> => {
      this.assertActive();
      this.permissions.ensureWritable();

      const result = await operation();
      this.assertActive();

      return result;
    });
  }

  async getCalendars(entity?: string | null): Promise<ExpoCalendarRecord[]> {
    validateEntityType(entity);

    const manager = this.manager();
    const primary = await manager.getCalendar();
    this.assertReadable();
    const calendars = await manager.getAllCalendars();
    this.assertReadable();

    const writable = this.permissions.hasWriteAccess();
    return calendars.map(
      (calendar: calendarManager.Calendar): ExpoCalendarRecord =>
        this.serializeCalendar(calendar, primary.id, writable),
    );
  }

  async getDefaultCalendar(): Promise<ExpoCalendarRecord> {
    const calendar = await this.manager().getCalendar();
    this.assertReadable();

    if (!Number.isSafeInteger(calendar.id) || calendar.id <= 0) {
      throw new ExpoCalendarError('ERR_CALENDAR_NOT_FOUND', 'Calendar Kit did not return a default calendar.');
    }

    return this.serializeCalendar(calendar, calendar.id, this.permissions.hasWriteAccess());
  }

  private serializeCalendar(calendar: calendarManager.Calendar, primary: number, writable: boolean): ExpoCalendarRecord {
    return new ExpoCalendarRecord(calendar, calendar.getAccount(), calendar.getConfig(), primary, writable);
  }

  async saveCalendar(data: Record<string, ESObject>): Promise<calendarManager.Calendar> {
    validateEntityType(data['entityType']);

    const manager = this.manager();

    if (data['id'] === undefined || data['id'] === null) {
      const account = calendarAccountFromDetails(data);
      const config = calendarConfigFromDetails(data);

      // Calendar Kit can reuse an account with the same name and type.
      const calendars = await manager.getAllCalendars();
      this.assertActive();
      this.permissions.ensureWritable();

      for (const existing of calendars) {
        const current = existing.getAccount();

        if (current.name === account.name && current.type === account.type) {
          throw new ExpoCalendarError('ERR_CALENDAR_NOT_SAVED', 'A calendar account with this name and type already exists.');
        }
      }

      const calendar = await manager.createCalendar(account);

      if (!Number.isSafeInteger(calendar.id) || calendar.id <= 0) {
        throw new ExpoCalendarError('ERR_CALENDAR_NOT_SAVED', 'Calendar Kit did not create a valid calendar.');
      }
      if (calendars.some((existing: calendarManager.Calendar): boolean => existing.id === calendar.id)) {
        throw new ExpoCalendarError('ERR_CALENDAR_NOT_SAVED', 'Calendar Kit returned an existing calendar account.');
      }

      if (config === undefined) return calendar;

      try {
        this.assertActive();
        this.permissions.ensureWritable();
        await calendar.setConfig(config);
      } catch (error) {
        // The create and configure operations cannot be made atomic. Avoid
        // deleting the account because Calendar Kit can return an existing ID.
        throw new ExpoCalendarError('ERR_CALENDAR_NOT_SAVED', `Could not configure calendar '${calendar.id}': ${(error as Error).message}`);
      }

      return calendar;
    }

    const calendar = await this.requireCalendar(requireCalendarId(data['id'], 'id'));
    validateCalendarUpdate(data, calendar.getAccount());

    const config = calendarConfigFromDetails(data);
    if (config === undefined) return calendar;

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

    const selected = new Set(ids.map((id: string): number => requireCalendarId(id)));
    const calendars = await this.manager().getAllCalendars();
    this.assertReadable();

    const events: ExpoEventRecord[] = [];

    for (const calendar of calendars) {
      if (selected.size !== 0 && !selected.has(calendar.id)) continue;

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
    if (this.context.isHeadless) throw new ExpoCalendarError('ERR_UNAVAILABLE', 'A foreground runtime is required to present the calendar.');
    if (!canIUse('SystemCapability.Applications.CalendarData')) {
      throw new ExpoCalendarError('ERR_UNAVAILABLE', 'Calendar Kit is not available on this device.');
    }
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
      if (key !== 'timeZone') input[key] = data[key];
    });
    input['startDate'] = start;
    input['endDate'] = end;

    const event = eventFromDetails(input);
    const rule = event.recurrenceRule;
    if (rule !== undefined && (
      (rule.interval ?? 1) !== 1 || rule.expire !== undefined || rule.count !== undefined ||
      rule.daysOfWeek !== undefined || rule.daysOfMonth !== undefined || rule.daysOfYear !== undefined ||
      rule.weeksOfMonth !== undefined || rule.weeksOfYear !== undefined || rule.monthsOfYear !== undefined
    )) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'The system creation page cannot set a custom recurrence rule.');
    }

    return this.service.present(async (): Promise<ExpoDialogResult> => {
      const manager = calendarManager.getCalendarManager(this.context.uiAbilityContext);
      const id = await manager.editEvent(event);
      this.assertActive();

      return new ExpoDialogResult(id);
    });
  }

  async openEventInCalendar(id: ESObject, options?: Record<string, ESObject> | null): Promise<ExpoOpenDialogResult> {
    this.assertActive();
    if (this.context.isHeadless) throw new ExpoCalendarError('ERR_UNAVAILABLE', 'A foreground runtime is required to present the calendar.');
    if (options?.['instanceStartDate'] != null) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Calendar Kit cannot open individual recurring instances.');
    }

    if (typeof deviceInfo.apiAvailable === 'function') {
      if (deviceInfo.apiAvailable('26.0.0')) {
        const eventId = requireEventId(id);
        return this.service.present(async (): Promise<ExpoOpenDialogResult> => {
          const event = await this.requireEvent(eventId);
          await event.calendar.openEventEditPage(eventId);
          this.assertActive();

          return new ExpoOpenDialogResult();
        });
      }
    }

    throw new ExpoCalendarError('ERR_UNAVAILABLE', 'Opening an existing event requires HarmonyOS API 26.0.0.');
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
  private pendingDialog: boolean = false;
  private mutations: Promise<void> = Promise.resolve();
  private permissionRequest?: PermissionRequest;

  constructor(context?: ExpoServiceContext) {
    super(context);
  }

  get(context: ExpoModuleContext): ExpoCalendarStore {
    return new ExpoCalendarStore(context, this);
  }

  async requestPermissions(epoch: string, request: () => Promise<CalendarPermissionResponse>): Promise<CalendarPermissionResponse> {
    const pending = this.permissionRequest;
    if (pending !== undefined) {
      if (pending.epoch === epoch) return pending.result;
      await pending.result.catch((): void => {});
      return this.requestPermissions(epoch, request);
    }

    const next = new PermissionRequest(epoch, request());
    this.permissionRequest = next;

    try {
      return await next.result;
    } finally {
      this.permissionRequest = undefined;
    }
  }

  mutate<Result>(operation: () => Promise<Result>): Promise<Result> {
    // Calendar Kit replaces fields on update; serialize partial updates to avoid lost writes.
    const result = this.mutations.then(operation);
    this.mutations = result.then(
      (): void => {},
      (): void => {},
    );

    return result;
  }

  async present<Result>(operation: () => Promise<Result>): Promise<Result> {
    if (this.pendingDialog) throw new ExpoCalendarError('ERR_CALENDAR_DIALOG_PENDING', 'A calendar dialog is already open.');

    this.pendingDialog = true;
    try {
      return await operation();
    } finally {
      this.pendingDialog = false;
    }
  }
}

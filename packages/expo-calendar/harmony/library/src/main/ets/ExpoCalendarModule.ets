import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { calendarManager } from '@kit.CalendarKit';
import {
  ExpoAttendeeRecord,
  ExpoCalendarError,
  ExpoCalendarRecord,
  ExpoDialogResult,
  ExpoEventRecord,
  calendarAccountFromDetails,
  calendarConfigFromDetails,
  eventCalendarId,
  eventFromDetails,
  eventInstanceRequested,
  expoAttendees,
  requireCalendarId,
  requireDate,
  requireEventId,
  requireRecord,
  validateCalendarUpdate,
  validateEntityType,
} from './CalendarRecords';
import { CalendarPermissions, CalendarPermissionResponse } from './CalendarPermissions';

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
const RECORD = ExpoValueTypes.custom<Record<string, ESObject>>(
  'calendar details',
  (value: ESObject): Record<string, ESObject> => requireRecord(value, 'details'),
  (value: Record<string, ESObject>): ESObject => value,
);
const DATE = ExpoValueTypes.custom<number>(
  'ISO-8601 date or timestamp',
  (value: ESObject, path: string): number => requireDate(value, path),
  (value: number): ESObject => value,
);
const DEFAULT_DIALOG_DURATION_MS: number = 60 * 60 * 1000;

class LocatedEvent {
  calendar: calendarManager.Calendar;
  event: calendarManager.Event;

  constructor(calendar: calendarManager.Calendar, event: calendarManager.Event) {
    this.calendar = calendar;
    this.event = event;
  }
}

export class ExpoCalendarModule extends ExpoModule {
  private permissions: CalendarPermissions;
  private dialogPending: boolean = false;
  private mutations: Promise<void> = Promise.resolve();

  constructor(context: ExpoModuleContext) {
    super(context);
    this.permissions = new CalendarPermissions(context);
  }

  definition(): ExpoModuleDefinition {
    const definition = new ExpoModuleDefinition()
      .name('ExpoCalendar')
      .asyncFunction('getCalendarPermissionsAsync', async (): Promise<CalendarPermissionResponse> => await this.permissions.get())
      .asyncFunction('requestCalendarPermissionsAsync', async (): Promise<CalendarPermissionResponse> => await this.permissions.request());

    // Upstream isAvailableAsync checks for getCalendarsAsync on the native module.
    if (!canIUse('SystemCapability.Applications.CalendarData')) return definition;

    return definition
      .asyncFunction(
        'getCalendarsAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.string().nullable().optional(),
          async (entity?: string | null): Promise<ExpoCalendarRecord[]> => await this.getCalendars(entity),
        ),
      )
      .asyncFunction('getDefaultCalendarAsync', async (): Promise<ExpoCalendarRecord> => await this.getDefaultCalendar())
      .asyncFunction(
        'saveCalendarAsync',
        ExpoFunction.typed1(
          RECORD,
          async (data: Record<string, ESObject>): Promise<string> => await this.mutate(async (): Promise<string> => await this.saveCalendar(data)),
        ),
      )
      .asyncFunction(
        'deleteCalendarAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.string(),
          async (id: string): Promise<void> => await this.mutate(async (): Promise<void> => await this.deleteCalendar(id)),
        ),
      )
      .asyncFunction(
        'getEventsAsync',
        ExpoFunction.typed3(
          DATE,
          DATE,
          ExpoValueTypes.array(ExpoValueTypes.string()),
          async (start: number, end: number, ids: string[]): Promise<ExpoEventRecord[]> => await this.getEvents(start, end, ids),
        ),
      )
      .asyncFunction(
        'getEventByIdAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (id: string): Promise<ExpoEventRecord> => {
          const located = await this.requireEvent(requireEventId(id));
          return new ExpoEventRecord(located.event, String(located.calendar.id));
        }),
      )
      .asyncFunction(
        'saveEventAsync',
        ExpoFunction.typed2(
          RECORD,
          RECORD.defaulted({}),
          async (data: Record<string, ESObject>, options: Record<string, ESObject>): Promise<string> =>
            await this.mutate(async (): Promise<string> => await this.saveEvent(data, options)),
        ),
      )
      .asyncFunction(
        'deleteEventAsync',
        ExpoFunction.typed2(
          RECORD,
          RECORD.defaulted({}),
          async (data: Record<string, ESObject>, options: Record<string, ESObject>): Promise<void> =>
            await this.mutate(async (): Promise<void> => await this.deleteEvent(data, options)),
        ),
      )
      .asyncFunction(
        'getAttendeesForEventAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.string(),
          async (id: string): Promise<ExpoAttendeeRecord[]> => expoAttendees((await this.requireEvent(requireEventId(id))).event),
        ),
      )
      .asyncFunction(
        'createEventInCalendarAsync',
        ExpoFunction.typed1(
          RECORD.defaulted({}),
          async (data: Record<string, ESObject>): Promise<ExpoDialogResult> => await this.createEventInCalendar(data),
        ),
      );
  }

  private manager(): calendarManager.CalendarManager {
    this.permissions.ensureGranted();
    return calendarManager.getCalendarManager(this.context.uiAbilityContext);
  }

  private mutate<Result>(operation: () => Promise<Result>): Promise<Result> {
    // Calendar Kit replaces fields on update; serialize partial updates to avoid lost writes.
    const result = this.mutations.then(operation);
    this.mutations = result.then(
      (): void => {},
      (): void => {},
    );

    return result;
  }

  private async getCalendars(entity?: string | null): Promise<ExpoCalendarRecord[]> {
    validateEntityType(entity);

    const manager = this.manager();
    const primary = await manager.getCalendar();

    return (await manager.getAllCalendars()).map(
      (calendar: calendarManager.Calendar): ExpoCalendarRecord =>
        new ExpoCalendarRecord(calendar, calendar.getAccount(), calendar.getConfig(), primary.id),
    );
  }

  private async getDefaultCalendar(): Promise<ExpoCalendarRecord> {
    const calendar = await this.manager().getCalendar();
    return new ExpoCalendarRecord(calendar, calendar.getAccount(), calendar.getConfig(), calendar.id);
  }

  private async saveCalendar(data: Record<string, ESObject>): Promise<string> {
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
        await calendar.setConfig(config);
      } catch (error) {
        try {
          await manager.deleteCalendar(calendar);
        } catch (_) {
          // Preserve the configuration failure even if rollback fails.
        }

        throw new ExpoCalendarError('ERR_CALENDAR_NOT_SAVED', `Could not configure the calendar: ${(error as Error).message}`);
      }

      return String(calendar.id);
    }

    const calendar = await this.requireCalendar(requireCalendarId(data['id'], 'id'));
    validateCalendarUpdate(data, calendar.getAccount());

    await calendar.setConfig(calendarConfigFromDetails(data, calendar.getConfig()));

    return String(calendar.id);
  }

  private async deleteCalendar(id: string): Promise<void> {
    const calendar = await this.requireCalendar(requireCalendarId(id));
    await this.manager().deleteCalendar(calendar);
  }

  private async getEvents(start: number, end: number, ids: string[]): Promise<ExpoEventRecord[]> {
    if (end < start) throw new ExpoCalendarError('ERR_CALENDAR_INVALID_DATE_RANGE', 'endDate must not precede startDate.');
    if (ids.length === 0) throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ARGUMENT', 'calendarIds must not be empty.');
    const selected = ids.map((id: string): number => requireCalendarId(id));

    const events: ExpoEventRecord[] = [];
    for (const calendar of await this.manager().getAllCalendars()) {
      if (!selected.includes(calendar.id)) continue;

      const instances = await calendar.queryEventInstances(start, end, undefined, INSTANCE_FIELDS);
      for (const event of instances) events.push(new ExpoEventRecord(event, String(calendar.id)));
    }

    events.sort((left: ExpoEventRecord, right: ExpoEventRecord): number => Date.parse(left.startDate) - Date.parse(right.startDate));

    return events;
  }

  private async saveEvent(data: Record<string, ESObject>, options: Record<string, ESObject>): Promise<string> {
    if (eventInstanceRequested(data, options)) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Calendar Kit cannot update individual or future recurring instances.');
    }

    if (data['id'] === undefined || data['id'] === null) {
      const calendarId = eventCalendarId(data);
      if (calendarId === undefined) throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ARGUMENT', 'calendarId is required.');

      const calendar = await this.requireCalendar(calendarId);
      const event = eventFromDetails(data);

      const id = await calendar.addEvent(event);
      if (!Number.isSafeInteger(id) || id <= 0) throw new ExpoCalendarError('ERR_EVENT_NOT_SAVED', 'Calendar Kit did not create a valid event.');

      return String(id);
    }

    const located = await this.requireEvent(requireEventId(data['id'], 'id'));
    const calendarId = eventCalendarId(data);
    if (calendarId !== undefined && calendarId !== located.calendar.id) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Calendar Kit cannot move an event between calendars.');
    }

    await located.calendar.updateEvent(eventFromDetails(data, located.event));

    return String(located.event.id);
  }

  private async deleteEvent(data: Record<string, ESObject>, options: Record<string, ESObject>): Promise<void> {
    if (eventInstanceRequested(data, options)) {
      throw new ExpoCalendarError('ERR_CALENDAR_UNSUPPORTED', 'Calendar Kit cannot delete individual or future recurring instances.');
    }

    const id = requireEventId(data['id'], 'id');
    const located = await this.requireEvent(id);

    await located.calendar.deleteEvent(id);
  }

  private async createEventInCalendar(data: Record<string, ESObject>): Promise<ExpoDialogResult> {
    if (this.dialogPending) throw new ExpoCalendarError('ERR_CALENDAR_DIALOG_PENDING', 'A calendar dialog is already open.');
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

    this.dialogPending = true;
    try {
      return new ExpoDialogResult(await calendarManager.getCalendarManager(this.context.uiAbilityContext).editEvent(event));
    } finally {
      this.dialogPending = false;
    }
  }

  private async requireCalendar(id: number): Promise<calendarManager.Calendar> {
    const calendar = (await this.manager().getAllCalendars()).find((value: calendarManager.Calendar): boolean => value.id === id);
    if (calendar === undefined) throw new ExpoCalendarError('ERR_CALENDAR_NOT_FOUND', `No accessible calendar has ID '${id}'.`);
    return calendar;
  }

  private async requireEvent(id: number): Promise<LocatedEvent> {
    for (const calendar of await this.manager().getAllCalendars()) {
      const events = await calendar.getEvents(calendarManager.EventFilter.filterById([id]), EVENT_FIELDS);
      const event = events.find((value: calendarManager.Event): boolean => value.id === id);
      if (event !== undefined) return new LocatedEvent(calendar, event);
    }

    throw new ExpoCalendarError('ERR_CALENDAR_EVENT_NOT_FOUND', `No accessible event has ID '${id}'.`);
  }
}

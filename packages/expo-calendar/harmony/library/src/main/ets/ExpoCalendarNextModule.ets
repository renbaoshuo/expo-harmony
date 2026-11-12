/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoSharedObject,
  ExpoSharedObjectClassDefinition,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import {
  ExpoAttendeeRecord,
  ExpoCalendarError,
  ExpoCalendarRecord,
  ExpoEventRecord,
  eventInstanceRequested,
  expoAttendees,
  requireDate,
  requireEventId,
} from './CalendarRecords';
import { ExpoCalendarService, ExpoCalendarStore } from './ExpoCalendarStore';
import { CalendarPermissionResponse } from './CalendarPermissions';
import { CALENDAR_DATE, CALENDAR_RECORD } from './CalendarValues';

function updateDetails(details: Record<string, ESObject>, nullableFields: string[]): Record<string, ESObject> {
  const result: Record<string, ESObject> = {};
  Object.keys(details).forEach((name: string): void => {
    result[name] = details[name];
  });
  nullableFields.forEach((name: string): void => {
    result[name] = null;
  });
  return result;
}

class CalendarObject extends ExpoSharedObject {
  readonly store: ExpoCalendarStore;
  value?: ExpoCalendarRecord;

  constructor(context: ExpoModuleContext, store: ExpoCalendarStore, value: ExpoCalendarRecord) {
    super(context);
    this.store = store;
    this.value = value;
  }

  private id(): string {
    this.store.assertActive();
    if (this.value === undefined) throw new ExpoCalendarError('ERR_CALENDAR_NOT_FOUND', 'This calendar has been deleted.');
    return this.value.id;
  }

  async update(details: Record<string, ESObject>): Promise<void> {
    const id = this.id();
    const input = updateDetails(details, []);
    input['id'] = id;
    await this.store.mutate(async (): Promise<void> => {
      const calendar = await this.store.saveCalendar(input);
      this.value = await this.store.calendarRecordFromNative(calendar);
    });
  }

  async delete(): Promise<void> {
    const id = this.id();
    await this.store.mutate(async (): Promise<void> => {
      await this.store.deleteCalendar(id);
      this.value = undefined;
    });
  }

  async listEvents(start: number, end: number): Promise<CalendarEventObject[]> {
    const events = await this.store.getEvents(start, end, [this.id()]);
    return events.map((event: ExpoEventRecord): CalendarEventObject => new CalendarEventObject(this.context, this.store, event));
  }

  async createEvent(details: Record<string, ESObject>): Promise<CalendarEventObject> {
    const calendarId = this.id();
    const input = updateDetails(details, []);
    input['id'] = null;
    input['calendarId'] = calendarId;
    return this.store.mutate(async (): Promise<CalendarEventObject> => {
      const saved = await this.store.saveEvent(input, {});
      return new CalendarEventObject(this.context, this.store, await this.store.eventRecord(String(saved.id), saved.calendar));
    });
  }
}

class CalendarEventObject extends ExpoSharedObject {
  readonly store: ExpoCalendarStore;
  value?: ExpoEventRecord;

  constructor(context: ExpoModuleContext, store: ExpoCalendarStore, value: ExpoEventRecord) {
    super(context);
    this.store = store;
    this.value = value;
  }

  private id(): string {
    this.store.assertActive();
    if (this.value === undefined) throw new ExpoCalendarError('ERR_CALENDAR_EVENT_NOT_FOUND', 'This event has been deleted.');
    return this.value.id;
  }

  async update(details: Record<string, ESObject>, nullableFields: string[]): Promise<void> {
    const id = this.id();
    const input = updateDetails(details, nullableFields);
    input['id'] = id;
    await this.store.mutate(async (): Promise<void> => {
      const saved = await this.store.saveEvent(input, {});
      this.value = await this.store.eventRecord(id, saved.calendar);
    });
  }

  async delete(): Promise<void> {
    const id = this.id();
    await this.store.mutate(async (): Promise<void> => {
      await this.store.deleteEvent({ 'id': id }, {});
      this.value = undefined;
    });
  }

  getOccurrence(options: Record<string, ESObject>): CalendarEventObject {
    this.id();
    this.store.permissions.ensureReadable();

    if (options['instanceStartDate'] !== undefined && options['instanceStartDate'] !== null) {
      requireDate(options['instanceStartDate'], 'instanceStartDate');
    }
    if (eventInstanceRequested(options, options)) {
      // Calendar Kit only exposes asynchronous instance queries and whole-series mutations.
      throw new ExpoCalendarError('ERR_UNAVAILABLE', 'ExpoCalendarEvent.getOccurrenceSync with recurring event options is not available in HarmonyOS Calendar Kit.');
    }
    return this;
  }

  async getAttendees(): Promise<CalendarAttendeeObject[]> {
    const located = await this.store.requireEvent(requireEventId(this.id()));
    return expoAttendees(located.event).map(
      (attendee: ExpoAttendeeRecord): CalendarAttendeeObject => new CalendarAttendeeObject(this.context, attendee),
    );
  }
}

class CalendarAttendeeObject extends ExpoSharedObject {
  readonly value: ExpoAttendeeRecord;

  constructor(context: ExpoModuleContext, value: ExpoAttendeeRecord) {
    super(context);
    this.value = value;
  }
}

// The JS entry point extends this class on every platform, before its iOS guards run.
class CalendarReminderObject extends ExpoSharedObject {}

export class ExpoCalendarNextModule extends ExpoModule {
  private readonly store: ExpoCalendarStore;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.store = context.services.require(ExpoCalendarService.key).get(context);
  }

  definition(): ExpoModuleDefinition {
    const calendars = new ExpoSharedObjectClassDefinition<CalendarObject>('ExpoCalendar');
    const events = new ExpoSharedObjectClassDefinition<CalendarEventObject>('ExpoCalendarEvent');
    const attendees = new ExpoSharedObjectClassDefinition<CalendarAttendeeObject>('ExpoCalendarAttendee');
    const reminders = new ExpoSharedObjectClassDefinition<CalendarReminderObject>('ExpoCalendarReminder');
    const calendarType = calendars.valueType();
    const eventType = events.valueType();
    const attendeeType = attendees.valueType();

    calendars
      .construct(ExpoFunction.ownedTyped0((_context: ExpoModuleContext): CalendarObject => {
        throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ARGUMENT', 'Use getCalendars, createCalendar or ExpoCalendar.get to retrieve a calendar.');
      }))
      .property('id', (calendar: CalendarObject): string | undefined => calendar.value?.id)
      .property('title', (calendar: CalendarObject): string | undefined => calendar.value?.title)
      .property('source', (calendar: CalendarObject): ESObject => calendar.value?.source)
      .property('type', (calendar: CalendarObject): string | undefined => calendar.value?.type)
      .property('color', (calendar: CalendarObject): string | undefined => calendar.value?.color)
      .property('entityType', (calendar: CalendarObject): string | undefined => calendar.value?.entityType)
      .property('name', (calendar: CalendarObject): string | undefined => calendar.value?.name)
      .property('ownerAccount', (calendar: CalendarObject): string | undefined => calendar.value?.ownerAccount)
      .property('isPrimary', (calendar: CalendarObject): boolean | undefined => calendar.value?.isPrimary)
      .property('allowsModifications', (calendar: CalendarObject): boolean => calendar.value?.allowsModifications ?? false)
      .property('allowedAvailabilities', (calendar: CalendarObject): string[] => calendar.value?.allowedAvailabilities ?? [])
      .asyncFunction('listEvents', ExpoFunction.ownedTyped2(
        CALENDAR_DATE,
        CALENDAR_DATE,
        async (calendar: CalendarObject, start: number, end: number): Promise<CalendarEventObject[]> =>
          (await calendar.listEvents(start, end)).map((event: CalendarEventObject): CalendarEventObject => events.instance(event)),
      ).returns(ExpoValueTypes.array(eventType)))
      .asyncFunction('createEvent', ExpoFunction.ownedTyped1(
        CALENDAR_RECORD,
        async (calendar: CalendarObject, data: Record<string, ESObject>): Promise<CalendarEventObject> => events.instance(await calendar.createEvent(data)),
      ).returns(eventType))
      .asyncFunction('update', ExpoFunction.ownedTyped1(
        CALENDAR_RECORD,
        async (calendar: CalendarObject, data: Record<string, ESObject>): Promise<void> => calendar.update(data),
      ))
      .asyncFunction('delete', ExpoFunction.ownedTyped0(async (calendar: CalendarObject): Promise<void> => calendar.delete()));

    events
      .construct(ExpoFunction.ownedTyped0((_context: ExpoModuleContext): CalendarEventObject => {
        throw new ExpoCalendarError('ERR_CALENDAR_INVALID_ARGUMENT', 'Use listEvents, createEvent or ExpoCalendarEvent.get to retrieve an event.');
      }))
      .property('id', (event: CalendarEventObject): string | undefined => event.value?.id)
      .property('calendarId', (event: CalendarEventObject): string | undefined => event.value?.calendarId)
      .property('title', (event: CalendarEventObject): string | undefined => event.value?.title)
      .property('location', (event: CalendarEventObject): string | null | undefined => event.value?.location)
      .property('timeZone', (event: CalendarEventObject): string | undefined => event.value?.timeZone)
      .property('organizerEmail', (event: CalendarEventObject): string | undefined => event.value?.organizerEmail)
      .property('notes', (event: CalendarEventObject): string | undefined => event.value?.notes)
      .property('alarms', (event: CalendarEventObject): ESObject => event.value?.alarms)
      .property('recurrenceRule', (event: CalendarEventObject): ESObject => event.value?.recurrenceRule)
      .property('startDate', (event: CalendarEventObject): string | undefined => event.value?.startDate)
      .property('endDate', (event: CalendarEventObject): string | undefined => event.value?.endDate)
      .property('allDay', (event: CalendarEventObject): boolean | undefined => event.value?.allDay)
      .property('availability', (event: CalendarEventObject): string | undefined => event.value?.availability)
      .property('status', (event: CalendarEventObject): string | undefined => event.value?.status)
      .asyncFunction('update', ExpoFunction.ownedTyped2(
        CALENDAR_RECORD,
        ExpoValueTypes.array(ExpoValueTypes.string()).nullable().optional(),
        async (event: CalendarEventObject, data: Record<string, ESObject>, nullableFields?: string[] | null): Promise<void> =>
          event.update(data, nullableFields ?? []),
      ))
      .asyncFunction('delete', ExpoFunction.ownedTyped0(async (event: CalendarEventObject): Promise<void> => event.delete()))
      .asyncFunction('getAttendees', ExpoFunction.ownedTyped0(
        async (event: CalendarEventObject): Promise<CalendarAttendeeObject[]> =>
          (await event.getAttendees()).map((attendee: CalendarAttendeeObject): CalendarAttendeeObject => attendees.instance(attendee)),
      ).returns(ExpoValueTypes.array(attendeeType)))
      .syncFunction('getOccurrenceSync', ExpoFunction.ownedTyped1(
        CALENDAR_RECORD.defaulted({}),
        (event: CalendarEventObject, options: Record<string, ESObject>): CalendarEventObject => events.instance(event.getOccurrence(options)),
      ).returns(eventType))
      .asyncFunction('openInCalendar', ExpoFunction.ownedTyped1(
        CALENDAR_RECORD.nullable().optional(),
        async (_event: CalendarEventObject, _options?: Record<string, ESObject> | null): Promise<void> => {
          throw new ExpoCalendarError('ERR_UNAVAILABLE', 'ExpoCalendarEvent.openInCalendar is not available in HarmonyOS Calendar Kit.');
        },
      ))
      .asyncFunction('editInCalendar', ExpoFunction.ownedTyped1(
        CALENDAR_RECORD.nullable().optional(),
        async (_event: CalendarEventObject, _options?: Record<string, ESObject> | null): Promise<void> => {
          throw new ExpoCalendarError('ERR_UNAVAILABLE', 'ExpoCalendarEvent.editInCalendar is not available in HarmonyOS Calendar Kit.');
        },
      ));

    attendees
      .construct(ExpoFunction.ownedTyped0((_context: ExpoModuleContext): CalendarAttendeeObject => {
        throw new ExpoCalendarError('ERR_UNAVAILABLE', 'Constructing ExpoCalendarAttendee directly is not available in HarmonyOS Calendar Kit.');
      }))
      .property('name', (attendee: CalendarAttendeeObject): string => attendee.value.name)
      .property('email', (attendee: CalendarAttendeeObject): string | undefined => attendee.value.email)
      .property('role', (attendee: CalendarAttendeeObject): string => attendee.value.role)
      .property('status', (attendee: CalendarAttendeeObject): string => attendee.value.status)
      .property('type', (attendee: CalendarAttendeeObject): string => attendee.value.type);

    reminders.construct(ExpoFunction.ownedTyped0((_context: ExpoModuleContext): CalendarReminderObject => {
      throw new ExpoCalendarError('ERR_UNAVAILABLE', 'ExpoCalendarReminder is not available in HarmonyOS Calendar Kit.');
    }));

    return new ExpoModuleDefinition()
      .name('CalendarNext')
      .sharedObjectClass(calendars)
      .sharedObjectClass(events)
      .sharedObjectClass(attendees)
      .sharedObjectClass(reminders)
      .asyncFunction('getCalendarPermissions', ExpoFunction.typed1(
        ExpoValueTypes.boolean().nullable().optional(),
        async (_writeOnly?: boolean | null): Promise<CalendarPermissionResponse> => this.store.permissions.get(),
      ))
      .asyncFunction('requestCalendarPermissions', ExpoFunction.typed1(
        ExpoValueTypes.boolean().nullable().optional(),
        async (_writeOnly?: boolean | null): Promise<CalendarPermissionResponse> => this.store.permissions.request(),
      ))
      .asyncFunction('getCalendars', ExpoFunction.typed1(
        ExpoValueTypes.string().nullable().optional(),
        async (entity?: string | null): Promise<CalendarObject[]> =>
          (await this.store.getCalendars(entity)).map(
            (record: ExpoCalendarRecord): CalendarObject => calendars.instance(new CalendarObject(this.context, this.store, record)),
          ),
      ).returns(ExpoValueTypes.array(calendarType)))
      .asyncFunction('getCalendarById', ExpoFunction.typed1(
        ExpoValueTypes.string(),
        async (id: string): Promise<CalendarObject> =>
          calendars.instance(new CalendarObject(this.context, this.store, await this.store.calendarRecord(id))),
      ).returns(calendarType))
      .asyncFunction('createCalendar', ExpoFunction.typed1(
        CALENDAR_RECORD,
        async (details: Record<string, ESObject>): Promise<CalendarObject> => {
          const input = updateDetails(details, []);
          input['id'] = null;
          return this.store.mutate(async (): Promise<CalendarObject> => {
            const calendar = await this.store.saveCalendar(input);
            const record = await this.store.calendarRecordFromNative(calendar);
            return calendars.instance(new CalendarObject(this.context, this.store, record));
          });
        },
      ).returns(calendarType))
      .asyncFunction('listEvents', ExpoFunction.typed3(
        ExpoValueTypes.array(ExpoValueTypes.string()),
        CALENDAR_DATE,
        CALENDAR_DATE,
        async (ids: string[], start: number, end: number): Promise<CalendarEventObject[]> =>
          (await this.store.getEvents(start, end, ids, true)).map(
            (record: ExpoEventRecord): CalendarEventObject => events.instance(new CalendarEventObject(this.context, this.store, record)),
          ),
      ).returns(ExpoValueTypes.array(eventType)))
      .asyncFunction('getEventById', ExpoFunction.typed1(
        ExpoValueTypes.string(),
        async (id: string): Promise<CalendarEventObject> =>
          events.instance(new CalendarEventObject(this.context, this.store, await this.store.eventRecord(id))),
      ).returns(eventType));
  }
}

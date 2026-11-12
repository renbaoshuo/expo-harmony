/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { ExpoCalendarRecord, ExpoEventRecord, ExpoAttendeeRecord, ExpoDialogResult, expoAttendees, requireEventId } from './CalendarRecords';
import { CalendarPermissionResponse } from './CalendarPermissions';
import { ExpoCalendarService, ExpoCalendarStore } from './ExpoCalendarStore';
import { CALENDAR_RECORD, CALENDAR_DATE } from './CalendarValues';

export class ExpoCalendarModule extends ExpoModule {
  private readonly store: ExpoCalendarStore;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.store = context.services.require(ExpoCalendarService.key).get(context);
  }

  definition(): ExpoModuleDefinition {
    const definition = new ExpoModuleDefinition()
      .name('ExpoCalendar')
      .asyncFunction('getCalendarPermissionsAsync', async (): Promise<CalendarPermissionResponse> => await this.store.permissions.get())
      .asyncFunction('requestCalendarPermissionsAsync', async (): Promise<CalendarPermissionResponse> => await this.store.permissions.request());

    // Upstream isAvailableAsync checks for getCalendarsAsync on the native module.
    if (!canIUse('SystemCapability.Applications.CalendarData')) return definition;

    return definition
      .asyncFunction(
        'getCalendarsAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.string().nullable().optional(),
          async (entity?: string | null): Promise<ExpoCalendarRecord[]> => await this.store.getCalendars(entity),
        ),
      )
      .asyncFunction('getDefaultCalendarAsync', async (): Promise<ExpoCalendarRecord> => await this.store.getDefaultCalendar())
      .asyncFunction(
        'saveCalendarAsync',
        ExpoFunction.typed1(
          CALENDAR_RECORD,
          (data: Record<string, ESObject>): Promise<string> => this.store.mutate(async (): Promise<string> => String((await this.store.saveCalendar(data)).id)),
        ),
      )
      .asyncFunction(
        'deleteCalendarAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.string(),
          async (id: string): Promise<void> => await this.store.mutate(async (): Promise<void> => await this.store.deleteCalendar(id)),
        ),
      )
      .asyncFunction(
        'getEventsAsync',
        ExpoFunction.typed3(
          CALENDAR_DATE,
          CALENDAR_DATE,
          ExpoValueTypes.array(ExpoValueTypes.string()),
          async (start: number, end: number, ids: string[]): Promise<ExpoEventRecord[]> => await this.store.getEvents(start, end, ids),
        ),
      )
      .asyncFunction(
        'getEventByIdAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), (id: string): Promise<ExpoEventRecord> => this.store.eventRecord(id)),
      )
      .asyncFunction(
        'saveEventAsync',
        ExpoFunction.typed2(
          CALENDAR_RECORD,
          CALENDAR_RECORD.defaulted({}),
          (data: Record<string, ESObject>, options: Record<string, ESObject>): Promise<string> =>
            this.store.mutate(async (): Promise<string> => String((await this.store.saveEvent(data, options)).id)),
        ),
      )
      .asyncFunction(
        'deleteEventAsync',
        ExpoFunction.typed2(
          CALENDAR_RECORD,
          CALENDAR_RECORD.defaulted({}),
          async (data: Record<string, ESObject>, options: Record<string, ESObject>): Promise<void> =>
            await this.store.mutate(async (): Promise<void> => await this.store.deleteEvent(data, options)),
        ),
      )
      .asyncFunction(
        'getAttendeesForEventAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.string(),
          async (id: string): Promise<ExpoAttendeeRecord[]> => expoAttendees((await this.store.requireEvent(requireEventId(id))).event),
        ),
      )
      .asyncFunction(
        'createEventInCalendarAsync',
        ExpoFunction.typed1(
          CALENDAR_RECORD.defaulted({}),
          async (data: Record<string, ESObject>): Promise<ExpoDialogResult> => await this.store.createEventInCalendar(data),
        ),
      );
  }
}

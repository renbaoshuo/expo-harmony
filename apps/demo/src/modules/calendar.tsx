/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Calendar from 'expo-calendar';
import * as Legacy from 'expo-calendar/legacy';
import { useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
type PermissionHookMode = 'manual' | 'query' | 'request';
const permissionHookModes: [PermissionHookMode, string][] = [
  ['manual', '手动调用'],
  ['query', '挂载时查询'],
  ['request', '挂载时申请'],
];

function calendarData(value: Calendar.ExpoCalendar) {
  return {
    id: value.id,
    title: value.title,
    name: value.name,
    color: value.color,
    entityType: value.entityType,
    type: value.type,
    source: value.source,
    ownerAccount: value.ownerAccount,
    isPrimary: value.isPrimary,
    allowsModifications: value.allowsModifications,
    allowedAvailabilities: value.allowedAvailabilities,
  };
}

function eventData(value: Calendar.ExpoCalendarEvent) {
  return {
    id: value.id,
    calendarId: value.calendarId,
    title: value.title,
    startDate: value.startDate,
    endDate: value.endDate,
    allDay: value.allDay,
    location: value.location,
    timeZone: value.timeZone,
    notes: value.notes,
    alarms: value.alarms,
    recurrenceRule: value.recurrenceRule,
    availability: value.availability,
    status: value.status,
    organizerEmail: value.organizerEmail,
  };
}

function CalendarPermissionHook({ busy, legacy, mode, run, writeOnly }: {
  busy: boolean;
  legacy: boolean;
  mode: PermissionHookMode;
  run: (operation: () => Promise<unknown>) => () => void;
  writeOnly: boolean;
}) {
  const [permission, request, get] = Calendar.useCalendarPermissions({
    get: !legacy && mode === 'query',
    request: !legacy && mode === 'request',
    writeOnly,
  });
  const [legacyPermission, requestLegacy, getLegacy] = Legacy.useCalendarPermissions({
    get: legacy && mode === 'query',
    request: legacy && mode === 'request',
  });

  return (
    <>
      <DataRow label="useCalendarPermissions" value={(legacy ? legacyPermission : permission)?.status ?? '尚未查询'} />
      <ActionRow>
        <ActionButton disabled={busy} label="通过 Hook 查询" tone="secondary" onPress={run(legacy ? getLegacy : get)} />
        <ActionButton disabled={busy} label="通过 Hook 申请" tone="secondary" onPress={run(legacy ? requestLegacy : request)} />
      </ActionRow>
    </>
  );
}

function CalendarPermissions({ legacy }: { legacy: boolean }) {
  const [mode, setMode] = useState<PermissionHookMode>('manual');
  const [writeOnly, setWriteOnly] = useState(false);
  const result = useAsyncResult();
  const busy = result.state.phase === 'running';
  const run = (operation: () => Promise<unknown>) => () => void result.run(async () => json(await operation()));

  return (
    <Panel title="日历权限">
      {!legacy && Platform.OS === 'ios'
        ? (
            <ActionButton
              disabled={busy}
              label={writeOnly ? '仅写入权限' : '读写权限'}
              tone="secondary"
              onPress={() => {
                setWriteOnly(value => !value);
                setMode('manual');
              }}
            />
          )
        : null}
      <ActionRow>
        <ActionButton disabled={busy} label="检查可用性" tone="secondary" onPress={run(Legacy.isAvailableAsync)} />
        <ActionButton disabled={busy} label="查询权限" tone="secondary" onPress={run(legacy ? Legacy.getCalendarPermissionsAsync : () => Calendar.getCalendarPermissions(writeOnly))} />
        <ActionButton disabled={busy} label="申请权限" onPress={run(legacy ? Legacy.requestCalendarPermissionsAsync : () => Calendar.requestCalendarPermissions(writeOnly))} />
        {legacy ? <ActionButton disabled={busy} label="申请权限（旧接口）" tone="secondary" onPress={run(Legacy.requestPermissionsAsync)} /> : null}
      </ActionRow>
      <ActionRow>
        {permissionHookModes.map(([value, label]) => (
          <ActionButton
            key={value}
            disabled={busy}
            label={label}
            tone={mode === value ? 'primary' : 'secondary'}
            onPress={() => setMode(value)}
          />
        ))}
      </ActionRow>
      <CalendarPermissionHook key={`${mode}:${writeOnly}`} busy={busy} legacy={legacy} mode={mode} run={run} writeOnly={writeOnly} />
      <ResultPanel state={result.state} />
    </Panel>
  );
}

const recurrenceExamples: [string, Calendar.RecurrenceRule | undefined][] = [
  ['省略重复规则', undefined],
  ['每天', { frequency: Calendar.Frequency.DAILY, interval: 1, occurrence: 3 }],
  ['每周', { frequency: Calendar.Frequency.WEEKLY, interval: 1, daysOfTheWeek: [{ dayOfTheWeek: Calendar.DayOfTheWeek.Monday }], occurrence: 3 }],
  ['每月指定日期', { frequency: Calendar.Frequency.MONTHLY, daysOfTheMonth: [10, 20], occurrence: 3 }],
  ['每月指定星期', { frequency: Calendar.Frequency.MONTHLY, daysOfTheWeek: [{ dayOfTheWeek: Calendar.DayOfTheWeek.Monday, weekNumber: 2 }], occurrence: 3 }],
  ['每年指定日期', { frequency: Calendar.Frequency.YEARLY, monthsOfTheYear: [1, 3], daysOfTheMonth: [10, 20], occurrence: 3 }],
  ['每年第几天', { frequency: Calendar.Frequency.YEARLY, daysOfTheYear: [30], occurrence: 3 }],
  ['每年第几周', { frequency: Calendar.Frequency.YEARLY, weeksOfTheYear: [2], daysOfTheWeek: [{ dayOfTheWeek: Calendar.DayOfTheWeek.Monday }], occurrence: 3 }],
];

export function CalendarDemo() {
  const [legacy, setLegacy] = useState(false);
  const [calendarId, setCalendarId] = useState('');
  const [eventId, setEventId] = useState('');
  const [createdCalendar, setCreatedCalendar] = useState('');
  const [createdEvent, setCreatedEvent] = useState<{ id: string; calendarId: string }>();
  const [entityType, setEntityType] = useState<Calendar.EntityTypes>();
  const [calendarDetails, setCalendarDetails] = useState(() => json({
    title: 'Expo 日历',
    name: 'Expo Calendar',
    color: '#007AFF',
    entityType: Calendar.EntityTypes.EVENT,
    ownerAccount: 'Expo Calendar',
    source: { name: 'Expo Calendar', type: 'local', isLocalAccount: true },
  }));
  const [color, setColor] = useState('#32ADE6');
  const [calendarIds, setCalendarIds] = useState('');
  const [queryObjects, setQueryObjects] = useState(false);
  const [start, setStart] = useState(() => new Date(Date.now() - DAY).toISOString());
  const [end, setEnd] = useState(() => new Date(Date.now() + 7 * DAY).toISOString());
  const [details, setDetails] = useState(() => json({
    title: 'Expo 日程',
    startDate: new Date(Date.now() + DAY).toISOString(),
    endDate: new Date(Date.now() + DAY + HOUR).toISOString(),
    location: '会议室',
    timeZone: 'UTC',
    allDay: false,
    notes: '准备讨论议题',
    alarms: [{ relativeOffset: -15, method: Calendar.AlarmMethod.ALERT }],
  }));
  const [recurrence, setRecurrence] = useState('');
  const [systemDetails, setSystemDetails] = useState(() => json({
    title: 'Expo 日程',
    location: '会议室',
    allDay: false,
    startDate: new Date(Date.now() + HOUR).toISOString(),
    endDate: new Date(Date.now() + 2 * HOUR).toISOString(),
    notes: '准备讨论议题',
    alarms: [{ relativeOffset: -15, method: Calendar.AlarmMethod.ALERT }],
  }));
  const calendars = useAsyncResult();
  const events = useAsyncResult();
  const dialog = useAsyncResult();
  const busy = [calendars, events, dialog].some(value => value.state.phase === 'running');
  const canEditCalendar = !!createdCalendar && calendarId === createdCalendar;
  const canEditEvent = !!createdEvent && eventId === createdEvent.id;
  const platform = String(Platform.OS);
  const calendar = () => Calendar.ExpoCalendar.get(calendarId);
  const event = () => Calendar.ExpoCalendarEvent.get(eventId);
  const ids = () => calendarIds.split(',').map(id => id.trim()).filter(Boolean);
  const eventDetails = () => {
    const data = JSON.parse(details) as Partial<Legacy.Event>;
    if (recurrence.trim()) data.recurrenceRule = JSON.parse(recurrence);
    return data;
  };

  const createCalendar = () => calendars.run(async () => {
    const data = JSON.parse(calendarDetails) as Partial<Legacy.Calendar>;
    if (legacy) {
      const id = await Legacy.createCalendarAsync(data);
      setCreatedCalendar(id);
      setCalendarId(id);
      setCalendarIds(id);
      return id;
    }
    const value = await Calendar.createCalendar(data);
    setCreatedCalendar(value.id);
    setCalendarId(value.id);
    setCalendarIds(value.id);
    return json(calendarData(value));
  });

  const deleteCalendar = () => calendars.run(async () => {
    if (legacy) await Legacy.deleteCalendarAsync(calendarId);
    else await (await calendar()).delete();
    setCreatedCalendar('');
    setCalendarId('');
    if (calendarIds === calendarId) setCalendarIds('');
    if (createdEvent?.calendarId === calendarId) {
      setCreatedEvent(undefined);
      if (eventId === createdEvent.id) setEventId('');
    }
    return `已删除日历 ${calendarId}`;
  });

  const createEvent = () => events.run(async () => {
    const data = eventDetails();
    if (legacy) {
      const id = await Legacy.createEventAsync(calendarId, data);
      setCreatedEvent({ id, calendarId });
      setEventId(id);
      return id;
    }
    const value = await (await calendar()).createEvent(data);
    setCreatedEvent({ id: value.id, calendarId });
    setEventId(value.id);
    return json(eventData(value));
  });
  const queryEvents = () => events.run(async () => {
    const range = [new Date(start), new Date(end)] as const;
    const queryIds = ids();
    if (legacy) return json(await Legacy.getEventsAsync(queryIds, ...range));

    const input = queryObjects ? await Promise.all(queryIds.map(id => Calendar.ExpoCalendar.get(id))) : queryIds;
    return json((await Calendar.listEvents(input, ...range)).map(eventData));
  });

  return (
    <>
      <ActionRow>
        <ActionButton disabled={busy} label="对象 API" tone={legacy ? 'secondary' : 'primary'} onPress={() => setLegacy(false)} />
        <ActionButton disabled={busy} label="旧版 API" tone={legacy ? 'primary' : 'secondary'} onPress={() => setLegacy(true)} />
      </ActionRow>
      <CalendarPermissions key={String(legacy)} legacy={legacy} />

      <Panel title="日历">
        <ActionRow>
          <ActionButton label={entityType ? '日程类型' : '默认类型'} tone="secondary" onPress={() => setEntityType(value => value ? undefined : Calendar.EntityTypes.EVENT)} />
          <ActionButton disabled={busy} label="列出日历" onPress={() => void calendars.run(async () => json(legacy ? await Legacy.getCalendarsAsync(entityType) : (await Calendar.getCalendars(entityType)).map(calendarData)))} />
          {platform === 'harmony' || platform === 'ios'
            ? (
                <ActionButton disabled={busy} label="读取默认日历" tone="secondary" onPress={() => void calendars.run(async () => json(await Legacy.getDefaultCalendarAsync()))} />
              )
            : null}
        </ActionRow>
        <Field label="新日历属性（JSON）" multiline value={calendarDetails} onChangeText={setCalendarDetails} />
        <ActionButton disabled={busy || !!createdCalendar} label="创建演示日历" onPress={() => void createCalendar()} />
        <Field label="日历 ID" value={calendarId} onChangeText={setCalendarId} />
        <Field label="更新颜色" value={color} onChangeText={setColor} />
        <ActionRow>
          {!legacy ? <ActionButton disabled={busy || !calendarId} label="按 ID 读取日历" tone="secondary" onPress={() => void calendars.run(async () => json(calendarData(await calendar())))} /> : null}
          <ActionButton
            disabled={busy || !canEditCalendar || !color.trim()}
            label="更新演示日历颜色"
            tone="secondary"
            onPress={() => void calendars.run(async () => {
              if (legacy) return await Legacy.updateCalendarAsync(calendarId, { color });
              const value = await calendar();
              await value.update({ color });
              return json(calendarData(value));
            })}
          />
          <ActionButton disabled={busy || !canEditCalendar} label="删除演示日历" tone="danger" onPress={() => void deleteCalendar()} />
        </ActionRow>
        <ResultPanel state={calendars.state} />
      </Panel>

      <Panel title="日程">
        <Field label="查询日历 ID（逗号分隔）" value={calendarIds} onChangeText={setCalendarIds} />
        <Field label="查询起始时间（ISO 8601）" value={start} onChangeText={setStart} />
        <Field label="查询结束时间（ISO 8601）" value={end} onChangeText={setEnd} />
        <ActionRow>
          {!legacy ? <ActionButton disabled={busy} label={queryObjects ? '使用日历对象' : '使用日历 ID'} tone="secondary" onPress={() => setQueryObjects(value => !value)} /> : null}
          <ActionButton disabled={busy || (legacy && !ids().length)} label="查询时间范围内的日程" tone="secondary" onPress={() => void queryEvents()} />
          {!legacy
            ? (
                <ActionButton disabled={busy || !calendarId} label="查询所选日历的日程" tone="secondary" onPress={() => void events.run(async () => json((await (await calendar()).listEvents(new Date(start), new Date(end))).map(eventData)))} />
              )
            : null}
        </ActionRow>
        <Field label="日程属性（JSON）" multiline value={details} onChangeText={setDetails} />
        <ActionRow>
          {recurrenceExamples.map(([label, value]) => (
            <ActionButton key={label} label={label} tone="secondary" onPress={() => setRecurrence(value ? json(value) : '')} />
          ))}
          <ActionButton
            label="每天重复至指定日期"
            tone="secondary"
            onPress={() => setRecurrence(json({
              frequency: Calendar.Frequency.DAILY,
              endDate: new Date(Date.now() + 30 * DAY).toISOString(),
            }))}
          />
        </ActionRow>
        <Field label="重复规则（JSON）" multiline value={recurrence} onChangeText={setRecurrence} placeholder='{"frequency":"daily","interval":1,"occurrence":3}' />
        <ActionButton disabled={busy || !canEditCalendar || !!createdEvent} label="创建演示日程" onPress={() => void createEvent()} />
        <Field label="日程 ID" value={eventId} onChangeText={setEventId} />
        <ActionRow>
          <ActionButton disabled={busy || !eventId} label="按 ID 读取日程" tone="secondary" onPress={() => void events.run(async () => json(legacy ? await Legacy.getEventAsync(eventId) : eventData(await event())))} />
          {!legacy ? <ActionButton disabled={busy || !eventId} label="读取当前重复实例" tone="secondary" onPress={() => void events.run(async () => json(eventData((await event()).getOccurrenceSync())))} /> : null}
          <ActionButton
            disabled={busy || !eventId}
            label="读取参与者"
            tone="secondary"
            onPress={() => void events.run(async () => {
              if (legacy) return json(await Legacy.getAttendeesForEventAsync(eventId));
              const attendees = await (await event()).getAttendees();
              const records = attendees.map(({ name, email, role, status, type }) => ({
                name, email, role, status, type,
              }));
              return json(records);
            })}
          />
          <ActionButton
            disabled={busy || !canEditEvent}
            label="更新演示日程"
            tone="secondary"
            onPress={() => void events.run(async () => {
              if (legacy) return await Legacy.updateEventAsync(eventId, eventDetails());
              const value = await event();
              await value.update(eventDetails() as Partial<Calendar.ModifiableEventProperties>);
              return json(eventData(value));
            })}
          />
          <ActionButton
            disabled={busy || !canEditEvent}
            label="删除演示日程"
            tone="danger"
            onPress={() => void events.run(async () => {
              if (legacy) await Legacy.deleteEventAsync(eventId);
              else await (await event()).delete();
              setCreatedEvent(undefined);
              setEventId('');
              return `已删除日程 ${eventId}`;
            })}
          />
        </ActionRow>
        <ResultPanel state={events.state} />
      </Panel>

      <Panel title="系统新建日程">
        <Field label="预填日程属性（JSON）" multiline value={systemDetails} onChangeText={setSystemDetails} />
        <ActionButton disabled={busy} label="打开新建表单" onPress={() => void dialog.run(async () => json(await Legacy.createEventInCalendarAsync(systemDetails.trim() ? JSON.parse(systemDetails) : undefined)))} />
        <ResultPanel state={dialog.state} />
      </Panel>
    </>
  );
}

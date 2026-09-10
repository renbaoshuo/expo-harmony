import * as Calendar from 'expo-calendar';
import { useState } from 'react';
import { Platform } from 'react-native';

import { ActionButton, ActionRow, DataRow, Note, Panel, ResultPanel, useAsyncResult } from '../ui';

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

async function verify() {
  const permission = await Calendar.getCalendarPermissionsAsync();
  if (!permission.granted) throw new Error('请先授予日历读写权限。');

  const start = new Date();
  start.setUTCHours(12, 0, 0, 0);
  start.setUTCDate(start.getUTCDate() + 1);
  const end = new Date(start.getTime() + HOUR);
  const finish = new Date(start.getTime() + 7 * DAY);
  const checks: string[] = [];
  const calendar = await Calendar.createCalendarAsync({
    title: `Expo Calendar 验证 ${Date.now()}`,
    name: 'Expo Calendar Demo',
    color: '#007AFF',
    entityType: Calendar.EntityTypes.EVENT,
    ownerAccount: 'Expo Calendar Demo',
    accessLevel: Calendar.CalendarAccessLevel.OWNER,
    source: { isLocalAccount: true, name: 'Expo Calendar Demo', type: 'local' },
  });

  try {
    await Calendar.updateCalendarAsync(calendar, { color: '#32ADE6' });
    const calendars = await Calendar.getCalendarsAsync(Calendar.EntityTypes.EVENT);
    const saved = calendars.find(value => value.id === calendar);
    if (saved?.color.toUpperCase() !== '#32ADE6') {
      throw new Error(`日历创建或颜色更新未正确保存：${JSON.stringify(saved)}。`);
    }
    checks.push('日历创建、读取、颜色更新');

    const id = await Calendar.createEventAsync(calendar, {
      title: 'Expo Calendar 日程',
      location: '会议室',
      notes: '初始说明',
      startDate: start,
      endDate: end,
      timeZone: 'UTC',
      alarms: [{ relativeOffset: -15 }],
    });
    const event = await Calendar.getEventAsync(id);
    if (event.calendarId !== calendar || event.title !== 'Expo Calendar 日程'
      || new Date(event.startDate).getTime() !== start.getTime()
      || new Date(event.endDate).getTime() !== end.getTime()
      || event.alarms?.[0]?.relativeOffset !== -15) {
      throw new Error('日程字段或提醒往返结果不一致。');
    }
    checks.push('日程创建、日期与提醒往返');

    await Promise.all([
      Calendar.updateEventAsync(id, { title: '已更新标题' }),
      Calendar.updateEventAsync(id, { notes: '并发更新说明' }),
    ]);
    const updated = await Calendar.getEventAsync(id);
    if (updated.title !== '已更新标题' || updated.notes !== '并发更新说明'
      || updated.location !== '会议室' || updated.alarms?.[0]?.relativeOffset !== -15) {
      throw new Error('局部或并发更新丢失了日程字段。');
    }
    const attendees = await Calendar.getAttendeesForEventAsync(id);
    if (!Array.isArray(attendees) || attendees.length !== 0) throw new Error('新建日程应返回空的参与者列表。');
    checks.push('并发局部更新、未修改字段保留、参与者读取');

    const midnight = new Date(start);
    midnight.setUTCHours(0, 0, 0, 0);
    await Calendar.updateEventAsync(id, {
      allDay: true,
      startDate: midnight,
      endDate: new Date(midnight.getTime() + DAY),
    });
    const allDay = await Calendar.getEventAsync(id);
    if (!allDay.allDay || allDay.alarms?.[0]?.relativeOffset !== -15) {
      throw new Error('切换全天日程后提醒偏移发生变化。');
    }
    await Calendar.updateEventAsync(id, { allDay: false, startDate: start, endDate: end, alarms: [] });
    const cleared = await Calendar.getEventAsync(id);
    if (cleared.allDay || cleared.alarms?.length !== 0) throw new Error('全天标记或提醒未清除。');
    checks.push('全天提醒转换、提醒清空');

    const series = await Calendar.createEventAsync(calendar, {
      title: '重复日程',
      startDate: start,
      endDate: end,
      timeZone: 'UTC',
      recurrenceRule: { frequency: Calendar.Frequency.DAILY, occurrence: 3 },
    });
    const before = (await Calendar.getEventsAsync([calendar], midnight, finish)).filter(value => value.id === series);
    if (before.length !== 3 || new Set(before.map(value => String(value.startDate))).size !== 3) {
      throw new Error(`应展开 3 次独立的重复实例，实际得到 ${before.length} 次。`);
    }
    await Calendar.updateEventAsync(series, { notes: '保留重复规则' });
    const after = (await Calendar.getEventsAsync([calendar], midnight, finish)).filter(value => value.id === series);
    if (after.length !== 3
      || after.some((value, index) => String(value.startDate) !== String(before[index]?.startDate))) {
      throw new Error('局部更新改变了重复规则或实例日期。');
    }
    checks.push('重复实例展开、局部更新保留规则');

    if ((Platform.OS as string) === 'harmony') {
      const cases = [
        { name: '反向时间区间', code: 'ERR_CALENDAR_INVALID_DATE_RANGE', run: () => Calendar.getEventsAsync([calendar], end, start) },
        { name: '非法原生 ID', code: 'ERR_CALENDAR_INVALID_ID', run: () => Calendar.getEventAsync('invalid') },
        { name: '重复实例修改', code: 'ERR_CALENDAR_UNSUPPORTED', run: () => Calendar.updateEventAsync(series, { title: '单次修改' }, { instanceStartDate: start }) },
        { name: '绝对日期提醒', code: 'ERR_CALENDAR_UNSUPPORTED', run: () => Calendar.updateEventAsync(id, { alarms: [{ absoluteDate: start.toISOString() }] }) },
      ];
      for (const test of cases) {
        let code: unknown;
        try {
          await test.run();
        } catch (error) {
          code = (error as { code?: unknown }).code;
        }
        if (code !== test.code) throw new Error(`${test.name}：预期 ${test.code}，实际 ${String(code)}。`);
      }
      checks.push('非法参数与不支持能力的错误码');
    }

    await Calendar.deleteEventAsync(id);
    await Calendar.deleteEventAsync(series);
    const remaining = await Calendar.getEventsAsync([calendar], midnight, finish);
    if (remaining.length !== 0) throw new Error('删除日程后仍能查询到记录。');
    checks.push('普通日程与重复系列删除');
  } finally {
    await Calendar.deleteCalendarAsync(calendar);
  }

  const remaining = await Calendar.getCalendarsAsync(Calendar.EntityTypes.EVENT);
  if (remaining.some(value => value.id === calendar)) throw new Error('临时日历未清理。');
  checks.push('临时日历清理');

  return JSON.stringify({ passed: true, checks }, null, 2);
}

export function CalendarDemo() {
  const [permission, request, get] = Calendar.useCalendarPermissions();
  const [available, setAvailable] = useState<boolean>();
  const [calendars, setCalendars] = useState<Calendar.Calendar[]>();
  const [primary, setPrimary] = useState<Calendar.Calendar>();
  const access = useAsyncResult();
  const query = useAsyncResult();
  const checks = useAsyncResult();
  const dialog = useAsyncResult();
  const busy = [access, query, checks, dialog].some(value => value.state.phase === 'running');

  const inspect = () => query.run(async () => {
    const supported = await Calendar.isAvailableAsync();
    setAvailable(supported);
    if (!supported) throw new Error('当前系统不提供日历能力。');

    const [list, calendar] = await Promise.all([
      Calendar.getCalendarsAsync(Calendar.EntityTypes.EVENT),
      Calendar.getDefaultCalendarAsync(),
    ]);
    setCalendars(list);
    setPrimary(calendar);

    return JSON.stringify(list.map(value => ({ id: value.id, title: value.title, color: value.color })), null, 2);
  });

  return (
    <>
      <Panel eyebrow="权限" title="检查与申请日历权限">
        <DataRow label="useCalendarPermissions 状态" value={permission?.status ?? '加载中'} />
        <DataRow label="已授权" value={permission ? String(permission.granted) : '加载中'} />
        <DataRow label="可再次询问" value={permission ? String(permission.canAskAgain) : '加载中'} />
        <ActionRow>
          <ActionButton disabled={busy} label="检查权限" onPress={() => void access.run(async () => JSON.stringify(await get(), null, 2))} testID="calendar-permissions-get" tone="secondary" />
          <ActionButton disabled={busy} label="请求权限" onPress={() => void access.run(async () => JSON.stringify(await request(), null, 2))} testID="calendar-permissions-request" />
        </ActionRow>
        <ResultPanel state={access.state} />
      </Panel>

      <Panel eyebrow="日历" title="读取可访问的日历">
        <DataRow label="系统日历能力" value={available === undefined ? '尚未查询' : String(available)} />
        <DataRow label="日历数量" value={calendars === undefined ? '尚未查询' : String(calendars.length)} />
        <DataRow label="默认日历" value={primary ? `${primary.title} (${primary.id})` : '尚未查询'} />
        <ActionButton disabled={busy} label="查询日历" onPress={() => void inspect()} testID="calendar-read" />
        <Note>普通日历权限仅允许访问系统默认日历和当前应用的数据，列表不代表设备中的全部日程。</Note>
        <ResultPanel state={query.state} />
      </Panel>

      <Panel eyebrow="读写校验" title="验证日历与日程的完整流程">
        <Note>创建临时日历，验证颜色、日程读写、并发局部更新、全天提醒、重复实例和错误码。完成或失败后自动删除本次创建的日历及日程。</Note>
        <ActionButton disabled={busy || !permission?.granted} label="运行读写校验" onPress={() => void checks.run(verify)} testID="calendar-verify" />
        <ResultPanel state={checks.state} />
      </Panel>

      <Panel eyebrow="系统页面" title="新建日程">
        <ActionButton disabled={busy} label="打开系统新建页" onPress={() => void dialog.run(async () => JSON.stringify(await Calendar.createEventInCalendarAsync({ title: 'Expo Calendar 系统页面验证' }), null, 2))} testID="calendar-dialog" />
        <Note>可取消或保存，结果显示在下方。此操作无需读写权限；保存的日程由系统管理，不会自动清理。</Note>
        <ResultPanel state={dialog.state} />
      </Panel>
    </>
  );
}

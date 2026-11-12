/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Notifications from 'expo-notifications';
import { useEffect, useState } from 'react';
import { Platform, Switch } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const CATEGORY = 'expo-demo-actions';
const Trigger = Notifications.SchedulableTriggerInputTypes;
const TRIGGERS = [
  [Trigger.TIME_INTERVAL, '倒计时'],
  [Trigger.DATE, '指定日期'],
  [Trigger.DAILY, '每天'],
  [Trigger.WEEKLY, '每周'],
  [Trigger.MONTHLY, '每月'],
  [Trigger.YEARLY, '每年'],
  [Trigger.CALENDAR, '日历条件'],
] as const;

function numeric(text: string, name: string) {
  if (!text.trim() || !Number.isSafeInteger(Number(text))) throw new Error(`${name}须为整数`);
  return Number(text);
}

function PermissionsCard() {
  const [permissions, setPermissions] = useState(() => json({
    ios: { allowAlert: true, allowBadge: true, allowSound: true },
  } satisfies Notifications.NotificationPermissionsRequest));
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="通知权限">
      {Platform.OS === 'ios' ? <Field label="申请选项（JSON）" value={permissions} onChangeText={setPermissions} multiline /> : null}
      <ActionRow>
        <ActionButton disabled={busy} label="读取通知权限" onPress={() => void action.run(async () => json(await Notifications.getPermissionsAsync()))} testID="notifications-permissions-get" tone="secondary" />
        <ActionButton
          disabled={busy}
          label="申请通知权限"
          onPress={() => void action.run(async () => json(await Notifications.requestPermissionsAsync(
            Platform.OS === 'ios' ? JSON.parse(permissions) as Notifications.NotificationPermissionsRequest : undefined
          )))}
          testID="notifications-permissions-request"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function ForegroundCard() {
  const [enabled, setEnabled] = useState(true);
  const [banner, setBanner] = useState(true);
  const [list, setList] = useState(true);
  const [sound, setSound] = useState(false);
  const [badge, setBadge] = useState(false);
  const [handled, setHandled] = useState<string>();

  useEffect(() => {
    if (!enabled) return;
    Notifications.setNotificationHandler({
      handleNotification: async () => ({
        shouldShowBanner: banner,
        shouldShowList: list,
        shouldPlaySound: sound,
        shouldSetBadge: badge,
      }),
      handleSuccess: setHandled,
      handleError: (_id, error) => setHandled(error.message),
    });
    return () => Notifications.setNotificationHandler(null);
  }, [badge, banner, enabled, list, sound]);

  return (
    <Panel title="前台通知展示">
      <DataRow label="前台处理器" value={<Switch value={enabled} onValueChange={setEnabled} accessibilityLabel="前台处理器" />} />
      <DataRow label="显示横幅" value={<Switch value={banner} onValueChange={setBanner} accessibilityLabel="显示横幅" />} />
      <DataRow label="显示在通知中心" value={<Switch value={list} onValueChange={setList} accessibilityLabel="显示在通知中心" />} />
      <DataRow label="播放提示音" value={<Switch value={sound} onValueChange={setSound} accessibilityLabel="播放提示音" />} />
      <DataRow label="更新角标" value={<Switch value={badge} onValueChange={setBadge} accessibilityLabel="更新角标" />} />
      {handled ? <DataRow label="最近一次处理结果" value={handled} /> : null}
    </Panel>
  );
}

function ImmediateNotificationCard() {
  const [identifier, setIdentifier] = useState('expo-demo-notification');
  const [title, setTitle] = useState('Expo 通知');
  const [body, setBody] = useState('点击查看通知响应');
  const [subtitle, setSubtitle] = useState('');
  const [data, setData] = useState('{"source":"notifications-demo"}');
  const [badge, setBadge] = useState('');
  const [category, setCategory] = useState('');
  const [sound, setSound] = useState(false);
  const [autoDismiss, setAutoDismiss] = useState(true);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="即时通知">
      <Field label="通知 ID" value={identifier} onChangeText={setIdentifier} />
      <Field label="标题" value={title} onChangeText={setTitle} />
      <Field label="正文" value={body} onChangeText={setBody} />
      <Field label="副标题" value={subtitle} onChangeText={setSubtitle} />
      <Field label="附加数据（JSON）" value={data} onChangeText={setData} multiline />
      <Field label="角标数字" value={badge} onChangeText={setBadge} keyboardType="number-pad" />
      <Field label="类别 ID" value={category} onChangeText={setCategory} placeholder={CATEGORY} />
      <DataRow label="播放默认提示音" value={<Switch value={sound} onValueChange={setSound} accessibilityLabel="播放默认提示音" />} />
      <DataRow label="点击后清除通知" value={<Switch value={autoDismiss} onValueChange={setAutoDismiss} accessibilityLabel="点击后清除通知" />} />
      <ActionRow>
        <ActionButton
          disabled={busy}
          label="发送即时通知"
          testID="notifications-send"
          onPress={() => void action.run(async () => {
            const id = await Notifications.scheduleNotificationAsync({
              identifier: identifier || undefined,
              trigger: null,
              content: {
                title,
                body,
                subtitle: subtitle || undefined,
                data: data.trim() ? JSON.parse(data) as Record<string, unknown> : undefined,
                badge: badge.trim() ? numeric(badge, '角标') : undefined,
                categoryIdentifier: category || undefined,
                sound: sound ? 'default' : false,
                autoDismiss,
              },
            });
            setIdentifier(id);
            return id;
          })}
        />
        <ActionButton disabled={busy} label="列出已展示通知" testID="notifications-presented" tone="secondary" onPress={() => void action.run(async () => json(await Notifications.getPresentedNotificationsAsync()))} />
        <ActionButton
          disabled={busy || !identifier}
          label="清除指定通知"
          testID="notifications-dismiss"
          tone="secondary"
          onPress={() => void action.run(async () => {
            await Notifications.dismissNotificationAsync(identifier);
            return '已清除指定通知';
          })}
        />
        <ActionButton
          disabled={busy}
          label="清除全部已展示通知"
          tone="secondary"
          onPress={() => void action.run(async () => {
            await Notifications.dismissAllNotificationsAsync();
            return '已清除全部已展示通知';
          })}
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function ScheduleCard() {
  const [identifier, setIdentifier] = useState('expo-demo-reminder');
  const [title, setTitle] = useState('Expo 提醒');
  const [body, setBody] = useState('到时间了');
  const [trigger, setTrigger] = useState<(typeof TRIGGERS)[number][0]>(Trigger.TIME_INTERVAL);
  const [seconds, setSeconds] = useState('15');
  const [date, setDate] = useState(() => new Date(Date.now() + 3600000).toISOString());
  const [hour, setHour] = useState('9');
  const [minute, setMinute] = useState('0');
  const [weekday, setWeekday] = useState('2');
  const [day, setDay] = useState('1');
  const [month, setMonth] = useState('0');
  const [repeats, setRepeats] = useState(false);
  const [calendar, setCalendar] = useState('{"hour":9,"minute":0,"repeats":true}');
  const [channelId, setChannelId] = useState('');
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const timeOfDay = trigger !== Trigger.TIME_INTERVAL && trigger !== Trigger.DATE && trigger !== Trigger.CALENDAR;

  const triggerInput = (): Notifications.SchedulableNotificationTriggerInput => {
    const channel = channelId ? { channelId } : {};
    if (trigger === Trigger.TIME_INTERVAL) return { ...channel, type: trigger, seconds: numeric(seconds, '秒数'), repeats };
    if (trigger === Trigger.DATE) {
      const timestamp = Date.parse(date);
      if (!Number.isFinite(timestamp)) throw new Error('请输入有效的触发时间');
      return { ...channel, type: trigger, date: timestamp };
    }
    if (trigger === Trigger.CALENDAR) {
      return { ...JSON.parse(calendar) as Notifications.CalendarTriggerInput, type: trigger };
    }
    const time = { ...channel, hour: numeric(hour, '小时'), minute: numeric(minute, '分钟') };
    if (trigger === Trigger.DAILY) return { ...time, type: trigger };
    if (trigger === Trigger.WEEKLY) return { ...time, type: trigger, weekday: numeric(weekday, '星期') };
    const dateOfMonth = { ...time, day: numeric(day, '日期') };
    if (trigger === Trigger.MONTHLY) return { ...dateOfMonth, type: trigger };
    return { ...dateOfMonth, type: trigger, month: numeric(month, '月份') };
  };

  return (
    <Panel title="定时通知">
      <Field label="通知 ID" value={identifier} onChangeText={setIdentifier} />
      <Field label="标题" value={title} onChangeText={setTitle} />
      <Field label="正文" value={body} onChangeText={setBody} />
      <ActionRow>
        {TRIGGERS.filter(([value]) => value !== Trigger.CALENDAR || Platform.OS === 'ios').map(([value, label]) => (
          <ActionButton key={value} label={label} onPress={() => setTrigger(value)} tone={value === trigger ? 'primary' : 'secondary'} />
        ))}
      </ActionRow>
      {trigger === Trigger.TIME_INTERVAL ? <Field label="间隔（秒）" value={seconds} onChangeText={setSeconds} keyboardType="number-pad" /> : null}
      {trigger === Trigger.TIME_INTERVAL && (Platform.OS === 'ios' || Platform.OS === 'android')
        ? (
            <DataRow label="重复提醒" value={<Switch value={repeats} onValueChange={setRepeats} accessibilityLabel="重复提醒" />} />
          )
        : null}
      {trigger === Trigger.DATE ? <Field label="触发时间（ISO 8601）" value={date} onChangeText={setDate} /> : null}
      {trigger === Trigger.CALENDAR ? <Field label="日历条件（JSON）" multiline value={calendar} onChangeText={setCalendar} /> : null}
      {timeOfDay
        ? (
            <>
              <Field label="小时（0–23）" value={hour} onChangeText={setHour} keyboardType="number-pad" />
              <Field label="分钟（0–59）" value={minute} onChangeText={setMinute} keyboardType="number-pad" />
            </>
          )
        : null}
      {trigger === Trigger.WEEKLY ? <Field label="星期（1 为周日）" value={weekday} onChangeText={setWeekday} keyboardType="number-pad" /> : null}
      {trigger === Trigger.MONTHLY || trigger === Trigger.YEARLY ? <Field label="日期（1–31）" value={day} onChangeText={setDay} keyboardType="number-pad" /> : null}
      {trigger === Trigger.YEARLY ? <Field label="月份（0 为一月）" value={month} onChangeText={setMonth} keyboardType="number-pad" /> : null}
      {Platform.OS === 'android' ? <Field label="通知渠道 ID" value={channelId} onChangeText={setChannelId} /> : null}
      <ActionRow>
        <ActionButton
          disabled={busy}
          label="创建定时通知"
          testID="notifications-schedule"
          onPress={() => void action.run(async () => {
            const id = await Notifications.scheduleNotificationAsync({
              identifier: identifier || undefined,
              content: { title, body },
              trigger: triggerInput(),
            });
            setIdentifier(id);
            return id;
          })}
        />
        <ActionButton
          disabled={busy}
          label="计算下次触发时间"
          tone="secondary"
          onPress={() => void action.run(async () => {
            const timestamp = await Notifications.getNextTriggerDateAsync(triggerInput());
            return json({ timestamp, date: timestamp === null ? null : new Date(timestamp).toISOString() });
          })}
        />
        <ActionButton disabled={busy} label="列出定时通知" testID="notifications-scheduled" tone="secondary" onPress={() => void action.run(async () => json(await Notifications.getAllScheduledNotificationsAsync()))} />
        <ActionButton
          disabled={busy || !identifier}
          label="取消指定通知"
          testID="notifications-cancel"
          tone="secondary"
          onPress={() => void action.run(async () => {
            await Notifications.cancelScheduledNotificationAsync(identifier);
            return '已取消指定通知';
          })}
        />
        <ActionButton
          disabled={busy}
          label="取消全部定时通知"
          tone="secondary"
          onPress={() => void action.run(async () => {
            await Notifications.cancelAllScheduledNotificationsAsync();
            return '已取消全部定时通知';
          })}
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function CategoryCard() {
  const [identifier, setIdentifier] = useState(CATEGORY);
  const [actions, setActions] = useState(() => json([{ identifier: 'open', buttonTitle: '打开' }] satisfies Notifications.NotificationAction[]));
  const [options, setOptions] = useState('{}');
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="通知类别">
      <Field label="类别 ID" value={identifier} onChangeText={setIdentifier} />
      <Field label="操作按钮（JSON）" value={actions} onChangeText={setActions} multiline />
      {Platform.OS === 'ios' ? <Field label="类别选项（JSON）" value={options} onChangeText={setOptions} multiline /> : null}
      <ActionRow>
        <ActionButton
          disabled={busy || !identifier}
          label="保存类别"
          onPress={() => void action.run(async () => json(await Notifications.setNotificationCategoryAsync(
            identifier,
            JSON.parse(actions) as Notifications.NotificationAction[],
            Platform.OS === 'ios' ? JSON.parse(options) as Notifications.NotificationCategoryOptions : undefined
          )))}
        />
        <ActionButton disabled={busy} label="列出类别" tone="secondary" onPress={() => void action.run(async () => json(await Notifications.getNotificationCategoriesAsync()))} />
        <ActionButton disabled={busy || !identifier} label="删除类别" tone="secondary" onPress={() => void action.run(async () => json(await Notifications.deleteNotificationCategoryAsync(identifier)))} />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function EventCard() {
  const response = Notifications.useLastNotificationResponse();
  const [received, setReceived] = useState<Notifications.Notification>();
  const [clicked, setClicked] = useState<Notifications.NotificationResponse>();
  const [listenReceived, setListenReceived] = useState(true);
  const [listenClicked, setListenClicked] = useState(true);
  const [listenCleared, setListenCleared] = useState(true);
  const [cleared, setCleared] = useState<number>();
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  useEffect(() => {
    if (!listenReceived) return;
    const subscription = Notifications.addNotificationReceivedListener(setReceived);
    return () => subscription.remove();
  }, [listenReceived]);
  useEffect(() => {
    if (!listenClicked) return;
    const subscription = Notifications.addNotificationResponseReceivedListener(setClicked);
    return () => subscription.remove();
  }, [listenClicked]);
  useEffect(() => {
    if (!listenCleared) return;
    const subscription = Notifications.addNotificationResponseClearedListener(() => setCleared(Date.now()));
    return () => subscription.remove();
  }, [listenCleared]);

  return (
    <Panel title="通知事件">
      <DataRow label="监听通知接收" value={<Switch value={listenReceived} onValueChange={setListenReceived} accessibilityLabel="监听通知接收" />} />
      <DataRow label="监听通知点击" value={<Switch value={listenClicked} onValueChange={setListenClicked} accessibilityLabel="监听通知点击" />} />
      <DataRow label="监听点击记录清除" value={<Switch value={listenCleared} onValueChange={setListenCleared} accessibilityLabel="监听点击记录清除" />} />
      {received ? <DataRow label="最近一次接收" value={json(received)} /> : null}
      {clicked ? <DataRow label="最近一次点击" value={json(clicked)} /> : null}
      {cleared ? <DataRow label="最近一次清除时间" value={new Date(cleared).toISOString()} /> : null}
      <DataRow label="useLastNotificationResponse" value={response === undefined ? '加载中' : json(response)} />
      <DataRow label="正文点击的操作 ID" value={Notifications.DEFAULT_ACTION_IDENTIFIER} />
      <ActionRow>
        <ActionButton disabled={busy} label="读取点击记录" onPress={() => void action.run(() => json(Notifications.getLastNotificationResponse()))} tone="secondary" />
        <ActionButton disabled={busy} label="异步读取点击记录" onPress={() => void action.run(async () => json(await Notifications.getLastNotificationResponseAsync()))} tone="secondary" />
        <ActionButton
          disabled={busy}
          label="清除点击记录"
          testID="notifications-response-clear"
          onPress={() => void action.run(() => {
            Notifications.clearLastNotificationResponse();
            return '已清除点击记录';
          })}
        />
        <ActionButton
          disabled={busy}
          label="异步清除点击记录"
          onPress={() => void action.run(async () => {
            await Notifications.clearLastNotificationResponseAsync();
            return '已清除点击记录';
          })}
          tone="secondary"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function BadgeCard() {
  const [badge, setBadge] = useState('3');
  const [options, setOptions] = useState('{}');
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="应用角标">
      <Field label="角标数字" value={badge} onChangeText={setBadge} keyboardType="number-pad" />
      {Platform.OS === 'web' ? <Field label="角标选项（JSON）" multiline value={options} onChangeText={setOptions} /> : null}
      <ActionRow>
        <ActionButton disabled={busy} label="读取角标" testID="notifications-badge-get" tone="secondary" onPress={() => void action.run(async () => json(await Notifications.getBadgeCountAsync()))} />
        <ActionButton
          disabled={busy}
          label="设置角标"
          testID="notifications-badge-set"
          onPress={() => void action.run(async () => json(await Notifications.setBadgeCountAsync(
            numeric(badge, '角标'),
            Platform.OS === 'web' ? JSON.parse(options) as Parameters<typeof Notifications.setBadgeCountAsync>[1] : undefined
          )))}
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function PushCard() {
  const [listenToken, setListenToken] = useState(false);
  const [token, setToken] = useState<Notifications.DevicePushToken>();
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  useEffect(() => {
    if (!listenToken) return;
    const subscription = Notifications.addPushTokenListener(setToken);
    return () => subscription.remove();
  }, [listenToken]);

  return (
    <Panel title="设备推送">
      <DataRow label="监听设备令牌变化" value={<Switch value={listenToken} onValueChange={setListenToken} accessibilityLabel="监听设备令牌变化" />} />
      {token ? <DataRow label="最近一次令牌更新" value={json(token)} /> : null}
      <ActionRow>
        <ActionButton disabled={busy} label="读取设备推送令牌" testID="notifications-token" onPress={() => void action.run(async () => json(await Notifications.getDevicePushTokenAsync()))} />
        <ActionButton
          disabled={busy}
          label="注销设备推送"
          testID="notifications-unregister"
          tone="secondary"
          onPress={() => void action.run(async () => {
            await Notifications.unregisterForNotificationsAsync();
            return '已注销设备推送';
          })}
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

export function NotificationsDemo() {
  return (
    <>
      <PermissionsCard />
      <ForegroundCard />
      <ImmediateNotificationCard />
      <ScheduleCard />
      <CategoryCard />
      <EventCard />
      <BadgeCard />
      <PushCard />
    </>
  );
}

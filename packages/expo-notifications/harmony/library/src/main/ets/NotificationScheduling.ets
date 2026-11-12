/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoAppLifecycleState, ExpoModuleContext, ExpoModuleError, ExpoPermissionStatus } from '@expo-harmony/expo-modules-core';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NotificationsStore } from './NotificationsStore';
import {
  notificationContent,
  identifier,
  REMINDER_PERMISSION,
  Notification,
  NotificationRequest,
  ScheduledNotification,
  ExpoNotificationError,
  notificationSlot,
} from './NotificationTypes';
import { validateTrigger, reminderTrigger, nextTriggerDate } from './NotificationTriggers';
import { publishNotification, responseParameters } from './NotificationPresentation';

const REMINDER_NOT_FOUND = 1700003;
const REMINDER_LIMIT_EXCEEDED = 1700002;

async function cancelSystemReminder(id: number): Promise<void> {
  try {
    await reminderAgentManager.cancelReminder(id);
  } catch (error) {
    if ((error as BusinessError).code !== REMINDER_NOT_FOUND) {
      if (error instanceof ExpoModuleError) throw error;
      throw new ExpoNotificationError('ERR_NOTIFICATIONS_SCHEDULE', error as Object);
    }
  }
}

export async function schedule(context: ExpoModuleContext, store: NotificationsStore, id: string, input: ESObject, value: ESObject): Promise<string> {
  identifier(id);

  const content = notificationContent(input);
  const trigger = validateTrigger(value);

  const output = trigger === null ? null : recordTrigger(trigger);
  const request: NotificationRequest = { identifier: id, content, trigger: output };
  const notification: Notification = { date: Date.now(), request };

  if (trigger === null) {
    if (context.appLifecycleState === ExpoAppLifecycleState.FOREGROUND) store.receive(context.uiAbilityContext, notification);
    else await publishNotification(context.uiAbilityContext, store, notification);

    return id;
  }

  if (context.systemPermissionStatus(REMINDER_PERMISSION) !== ExpoPermissionStatus.GRANTED) {
    throw new ExpoModuleError(
      'ERR_NOTIFICATIONS_REMINDER_PERMISSION',
      'Scheduled notifications require ohos.permission.PUBLISH_AGENT_REMINDER. The app owner must obtain the Agent-Powered Reminder capability where required and declare the permission in the application manifest.',
    );
  }
  if (content.sound !== 'default') {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Silent agent reminders are not supported on HarmonyOS; use the default sound.');
  }
  if (content.badge !== undefined || content.categoryIdentifier || content.sticky || content.subtitle) {
    throw new ExpoModuleError(
      'ERR_NOTIFICATIONS_UNSUPPORTED',
      'Badge, category, sticky, or subtitle fields on agent reminders are not supported on HarmonyOS.',
    );
  }

  const reminder = reminderTrigger(trigger, notification.date);
  notification.date = nextTriggerDate(trigger, notification.date) as number;
  if (trigger.type === 'date' && output !== null) output['value'] = notification.date;

  const pending = await store.validSchedules();
  const old = pending.find((entry: ScheduledNotification): boolean => entry.request.identifier === id);
  const records = store.schedules();
  const shown = old !== undefined && (await notificationManager.getActiveNotifications()).some(
    (entry: notificationManager.NotificationRequest): boolean => entry.id === old.notificationId,
  );
  const native = old !== undefined && !shown ? old.notificationId : await store.allocateId();

  reminder.notificationId = native;
  reminder.title = content.title ?? '';
  reminder.content = content.body ?? '';
  reminder.expiredContent = content.body ?? '';
  reminder.ringDuration = 0;
  reminder.snoozeTimes = 0;
  reminder.tapDismissed = content.autoDismiss !== false;
  reminder.slotType = notificationSlot(context.uiAbilityContext);
  reminder.wantAgent = {
    pkgName: context.uiAbilityContext.abilityInfo.bundleName,
    abilityName: context.uiAbilityContext.abilityInfo.name,
    parameters: responseParameters(notification),
  };

  if (old !== undefined && !shown) {
    // The system updates a pending reminder in place, including when its quota is full.
    const replacement: ScheduledNotification = { reminderId: old.reminderId, notificationId: native, request };
    await store.write('scheduled', records.map((entry: ScheduledNotification): ScheduledNotification =>
      entry.reminderId === old.reminderId ? replacement : entry,
    ));

    try {
      await reminderAgentManager.updateReminder(old.reminderId, reminder);
    } catch (error) {
      await store.write('scheduled', records);

      if (error instanceof ExpoModuleError) throw error;
      throw new ExpoNotificationError('ERR_NOTIFICATIONS_SCHEDULE', error as Object);
    }

    return id;
  }

  // A reminder whose card is displayed cannot be updated. Publish first so a
  // failed replacement leaves the previous reminder in the system.
  let handle: number;

  try {
    handle = await reminderAgentManager.publishReminder(reminder);
  } catch (error) {
    if (Number((error as BusinessError).code) === REMINDER_LIMIT_EXCEEDED) {
      throw new ExpoModuleError(
        String(REMINDER_LIMIT_EXCEEDED),
        'HarmonyOS rejected the reminder because its quota was exceeded or this app has no Agent-Powered Reminder capability. Check the app’s AppGallery Connect capability and signing profile.',
        error as Object,
      );
    }

    if (error instanceof ExpoModuleError) throw error;
    throw new ExpoNotificationError('ERR_NOTIFICATIONS_SCHEDULE', error as Object);
  }

  const entry: ScheduledNotification = { reminderId: handle, notificationId: native, request };

  try {
    await store.write('scheduled', records.concat([entry]));
    if (old !== undefined) await cancelSystemReminder(old.reminderId);
  } catch (error) {
    try {
      await cancelSystemReminder(handle);
    } catch (rollback) {
      throw new ExpoModuleError(
        'ERR_NOTIFICATIONS_SCHEDULE_ROLLBACK',
        `Could not complete scheduling or cancel reminder ${handle}; retry cancellation with the Expo identifier.`,
        rollback as Object,
      );
    }

    if (error instanceof ExpoModuleError) throw error;
    throw new ExpoNotificationError('ERR_NOTIFICATIONS_STORAGE', error as Object);
  }

  return id;
}

export async function cancelScheduled(store: NotificationsStore, id?: string): Promise<void> {
  if (id !== undefined) identifier(id);

  // validSchedules retains display metadata separately from still-pending reminders.
  for (const entry of await store.validSchedules(true)) {
    if (id === undefined || entry.request.identifier === id) await cancelSystemReminder(entry.reminderId);
  }
}

function recordTrigger(trigger: Record<string, ESObject>): Record<string, ESObject> {
  if (trigger.type === 'date') {
    const result: Record<string, ESObject> = {};
    result['type'] = 'date';
    result['value'] = trigger.timestamp;
    result['repeats'] = false;

    return result;
  }

  return JSON.parse(JSON.stringify(trigger)) as Record<string, ESObject>;
}

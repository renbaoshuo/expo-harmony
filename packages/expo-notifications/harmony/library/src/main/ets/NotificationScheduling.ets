/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoAppLifecycleState, ExpoModuleContext, ExpoModuleError, ExpoPermissionStatus } from '@expo-harmony/expo-modules-core';
import { common } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';
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
import { publishNotification, responseWantParameters } from './NotificationPresentation';

const REMINDER_NOT_FOUND = 1700003;
const REMINDER_LIMIT_EXCEEDED = 1700002;
const MAX_RING_SECONDS = 1800;

async function ringtoneDuration(context: common.UIAbilityContext, file: string): Promise<number> {
  const resources = context.resourceManager;
  const source = await resources.getRawFd(file);

  try {
    const extractor = await media.createAVMetadataExtractor();

    try {
      extractor.fdSrc = source;
      const metadata = await extractor.fetchMetadata();

      const seconds = Math.ceil(Number(metadata.duration) / 1000);
      if (!Number.isSafeInteger(seconds) || seconds <= 0 || seconds > MAX_RING_SECONDS) {
        throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', 'An agent reminder ringtone must have a duration of 1 to 1800 seconds.');
      }

      return seconds;
    } finally {
      await extractor.release();
    }
  } finally {
    await resources.closeRawFd(file);
  }
}

async function cancelSystemReminder(id: number): Promise<void> {
  try {
    await reminderAgentManager.cancelReminder(id);
  } catch (error) {
    if ((error as BusinessError).code !== REMINDER_NOT_FOUND) {
      throw new ExpoNotificationError('ERR_NOTIFICATIONS_SCHEDULE', error as Object);
    }
  }
}

export async function schedule(context: ExpoModuleContext, store: NotificationsStore, id: string, input: ESObject, value: ESObject): Promise<string> {
  identifier(id);

  const content = notificationContent(input);
  const customSound: string | undefined = content.sound === 'custom' ? (input as Record<string, ESObject>)['sound'] : undefined;
  const trigger = validateTrigger(value);

  const fields = trigger === null ? null : recordTrigger(trigger);
  const request: NotificationRequest = { identifier: id, content, trigger: fields };
  const notification: Notification = { date: Date.now(), request };

  if (trigger === null) {
    if (context.appLifecycleState === ExpoAppLifecycleState.FOREGROUND) store.receive(context.uiAbilityContext, notification, customSound);
    else await publishNotification(context.uiAbilityContext, store, notification, customSound);

    return id;
  }

  if (context.systemPermissionStatus(REMINDER_PERMISSION) !== ExpoPermissionStatus.GRANTED) {
    throw new ExpoModuleError(
      'ERR_NOTIFICATIONS_REMINDER_PERMISSION',
      'Scheduled notifications require ohos.permission.PUBLISH_AGENT_REMINDER. The app owner must obtain the Agent-Powered Reminder capability where required and declare the permission in the application manifest.',
    );
  }
  if (content.sound === null) {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Agent reminders do not support silent notifications.');
  }
  if (content.badge !== undefined || content.categoryIdentifier !== null || content.subtitle !== null) {
    throw new ExpoModuleError(
      'ERR_NOTIFICATIONS_UNSUPPORTED',
      'Badge, category, or subtitle fields on agent reminders are not supported on HarmonyOS.',
    );
  }

  const ability = context.uiAbilityContext;
  const seconds = customSound === undefined ? 0 : await ringtoneDuration(ability, customSound);
  const pending = await store.validSchedules();
  const old = pending.find((entry: ScheduledNotification): boolean => entry.request.identifier === id);
  const records = store.schedules();
  const shown = old !== undefined && (await notificationManager.getActiveNotifications()).some(
    (entry: notificationManager.NotificationRequest): boolean => entry.id === old.notificationId,
  );
  let native = old !== undefined && !shown ? old.notificationId : await store.allocateId();

  const next = nextTriggerDate(trigger);
  if (next === null) {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', 'Cannot schedule a notification in the past.');
  }

  const reminder = reminderTrigger(trigger, next);
  notification.date = next;

  reminder.notificationId = native;
  reminder.title = content.title ?? '';
  reminder.content = content.body ?? '';
  reminder.expiredContent = content.body ?? '';
  reminder.ringDuration = seconds;

  if (customSound !== undefined) {
    reminder.customRingUri = customSound;
    reminder.ringChannel = reminderAgentManager.RingChannel.RING_CHANNEL_NOTIFICATION;
  }

  reminder.snoozeTimes = 0;
  reminder.tapDismissed = content.autoDismiss !== false;
  reminder.slotType = notificationSlot(ability);
  reminder.wantAgent = {
    pkgName: ability.abilityInfo.bundleName,
    abilityName: ability.abilityInfo.name,
    parameters: await responseWantParameters(store, notification),
  };

  if (old !== undefined && !shown) {
    // Updating in place also works when the reminder quota is full.
    const replacement: ScheduledNotification = { reminderId: old.reminderId, notificationId: native, request };

    await store.write('scheduled', records.map((entry: ScheduledNotification): ScheduledNotification =>
      entry.reminderId === old.reminderId ? replacement : entry,
    ));

    try {
      await reminderAgentManager.updateReminder(old.reminderId, reminder);

      return id;
    } catch (error) {
      await store.write('scheduled', records);

      if ((error as BusinessError).code !== REMINDER_NOT_FOUND) {
        throw new ExpoNotificationError('ERR_NOTIFICATIONS_SCHEDULE', error as Object);
      }
    }

    // The previous reminder can fire or be removed between querying and updating.
    native = await store.allocateId();
    reminder.notificationId = native;
  }

  // Displayed reminders cannot be updated. Publish before canceling the old reminder.
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

    throw new ExpoNotificationError('ERR_NOTIFICATIONS_SCHEDULE', error as Object);
  }

  const entry: ScheduledNotification = { reminderId: handle, notificationId: native, request };
  let saved = false;

  try {
    await store.write('scheduled', records.concat([entry]));
    saved = true;
    if (old !== undefined) await cancelSystemReminder(old.reminderId);
  } catch (error) {
    try {
      await cancelSystemReminder(handle);
      if (saved) await store.write('scheduled', records);
    } catch (rollback) {
      throw new ExpoModuleError(
        'ERR_NOTIFICATIONS_SCHEDULE_ROLLBACK',
        `Could not restore the previous state after scheduling reminder ${handle}.`,
        rollback as Object,
      );
    }

    throw new ExpoNotificationError('ERR_NOTIFICATIONS_STORAGE', error as Object);
  }

  return id;
}

export async function cancelScheduled(store: NotificationsStore, id?: string): Promise<void> {
  if (id !== undefined) identifier(id);

  for (const entry of await store.validSchedules(true)) {
    if (id === undefined || entry.request.identifier === id) await cancelSystemReminder(entry.reminderId);
  }
}

function recordTrigger(trigger: Record<string, ESObject>): Record<string, ESObject> {
  const result: Record<string, ESObject> = { 'type': trigger.type };

  if (trigger.type === 'date') {
    result['value'] = trigger.timestamp;
    result['repeats'] = false;
  } else if (trigger.type === 'timeInterval') {
    result['seconds'] = trigger.seconds;
    result['repeats'] = trigger.repeats ?? false;
  } else {
    result['hour'] = trigger.hour;
    result['minute'] = trigger.minute;
    if (trigger.type === 'weekly') result['weekday'] = trigger.weekday;
    if (trigger.type === 'monthly' || trigger.type === 'yearly') result['day'] = trigger.day;
    if (trigger.type === 'yearly') result['month'] = trigger.month;
  }

  return result;
}

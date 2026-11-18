/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { NotificationsStore } from './NotificationsStore';
import {
  DEFAULT_ACTION,
  RESPONSE_KEY,
  RESPONSE_SIGNATURE_KEY,
  MAX_ACTION_BUTTONS,
  MAX_NOTIFICATION_ID,
  Notification,
  NotificationResponse,
  NotificationAction,
  NotificationCategory,
  ScheduledNotification,
  pushNotification,
  notificationSlot,
  parseResponse,
  record,
  repeats,
  ExpoNotificationError,
} from './NotificationTypes';

// NotificationFlagStatus is an SDK type but is not re-exported by NotificationKit.
const FLAG_DEFAULT = 0;
const FLAG_DISABLED = 2;
const CAPABILITY_UNSUPPORTED = 801;
const NOTIFICATION_NOT_FOUND = 1600007;
const REMINDER_NOT_FOUND = 1700003;

export async function setNotificationBadge(count: number): Promise<boolean> {
  try {
    if (!(await notificationManager.isNotificationEnabled())) return false;
    if (typeof deviceInfo.apiAvailable === 'function') {
      if (deviceInfo.apiAvailable('26.0.0')) {
        if ((await notificationManager.getNotificationSetting()).badgeNumberEnabled === false) return false;
      }
    }

    await notificationManager.setBadgeNumber(count);

    return true;
  } catch (error) {
    if ((error as BusinessError).code === CAPABILITY_UNSUPPORTED) return false;

    throw new ExpoNotificationError('ERR_NOTIFICATIONS_BADGE', error as Object);
  }
}

function responseParameters(notification: Notification, action: string = DEFAULT_ACTION): Record<string, Object> {
  const response: NotificationResponse = { actionIdentifier: action, notification };
  const params: Record<string, Object> = {};
  params[RESPONSE_KEY] = JSON.stringify(response);

  return params;
}

export async function responseWantParameters(
  store: NotificationsStore,
  notification: Notification,
  action: string = DEFAULT_ACTION,
): Promise<Record<string, Object>> {
  const params = responseParameters(notification, action);
  const signature = await store.signResponse(params[RESPONSE_KEY] as string);

  params[RESPONSE_SIGNATURE_KEY] = signature;
  return params;
}

async function clickAgent(
  context: common.UIAbilityContext,
  store: NotificationsStore,
  notification: Notification,
  id: number,
  action: string,
  index: number,
): Promise<WantAgent> {
  return wantAgent.getWantAgent({
    wants: [
      {
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name,
        action,
        parameters: await responseWantParameters(store, notification, action),
      },
    ],
    operationType: wantAgent.OperationType.START_ABILITY,
    requestCode: id * (MAX_ACTION_BUTTONS + 1) + index,
    wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
  });
}

export function validateBehavior(value: Record<string, ESObject>): void {
  for (const key of ['shouldShowBanner', 'shouldShowList', 'shouldShowAlert', 'shouldPlaySound', 'shouldSetBadge']) {
    if (value[key] !== undefined && typeof value[key] !== 'boolean') {
      throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', `${key} must be a boolean.`);
    }
  }

  if (value.priority !== undefined) {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Android notification priority is not supported on HarmonyOS.');
  }

  if (showsBanner(value) && !showsList(value)) {
    throw new ExpoModuleError(
      'ERR_NOTIFICATIONS_UNSUPPORTED',
      'Banner-only notifications without a notification-center entry are not supported on HarmonyOS.',
    );
  }
}

function showsBanner(behavior: Record<string, ESObject>): boolean {
  return behavior.shouldShowBanner === true || behavior.shouldShowAlert === true;
}

function showsList(behavior: Record<string, ESObject>): boolean {
  return behavior.shouldShowList === true || behavior.shouldShowAlert === true;
}

function notificationText(context: common.UIAbilityContext, content: Record<string, ESObject>): notificationManager.NotificationBasicContent {
  const title: string | null = content.title;
  const body: string | null = content.body;
  const subtitle: string | null = content.subtitle;

  if (title && body) return { title, text: body, additionalText: subtitle ?? undefined };

  // Notification Kit requires both a title and text.
  const text = body || title || subtitle;
  if (!text) {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', 'Displaying a notification requires a title, body, or subtitle.');
  }

  const app = context.applicationInfo;
  let label = app.name;
  if (app.labelId !== 0) {
    try {
      label = context.resourceManager.getStringSync(app.labelId) || label;
    } catch (_) {
      // App resources can be unavailable during an Ability transition.
    }
  }

  return { title: label, text, additionalText: subtitle === text ? undefined : subtitle ?? undefined };
}

export async function publishNotification(
  context: common.UIAbilityContext,
  store: NotificationsStore,
  notification: Notification,
  customSound?: string,
  behavior?: Record<string, ESObject>,
): Promise<void> {
  const content = notification.request.content;
  const updateBadge = content.badge !== undefined && (behavior === undefined || behavior.shouldSetBadge === true);
  if (behavior !== undefined && !showsBanner(behavior) && !showsList(behavior)) {
    if (updateBadge) {
      await setNotificationBadge(content.badge as number);
    }

    return;
  }

  const normal = notificationText(context, content);
  const muted = content.sound === null || (behavior !== undefined && behavior.shouldPlaySound !== true);

  const active = await notificationManager.getActiveNotifications();
  const previous = active.find((entry: notificationManager.NotificationRequest): boolean =>
    entry.label === notification.request.identifier &&
    typeof entry.extraInfo?.[RESPONSE_KEY] === 'string' &&
    entry.id !== undefined && entry.id > 0 && entry.id <= MAX_NOTIFICATION_ID,
  );
  const id = previous?.id ?? (await store.allocateId());
  const category = store.categories().find((entry: NotificationCategory): boolean => entry.identifier === content.categoryIdentifier);

  const buttons: notificationManager.NotificationActionButton[] = [];
  for (const action of category?.actions ?? []) {
    buttons.push({ title: action.buttonTitle, wantAgent: await clickAgent(context, store, notification, id, action.identifier, buttons.length + 1) });
  }

  const request: notificationManager.NotificationRequest = {
    id,
    label: notification.request.identifier,
    notificationSlotType: notificationSlot(context),
    content: {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal,
    },
    tapDismissed: content.autoDismiss !== false,
    wantAgent: await clickAgent(context, store, notification, id, DEFAULT_ACTION, 0),
    actionButtons: buttons,
    sound: muted ? undefined : customSound,
    extraInfo: responseParameters(notification),
    notificationFlags: {
      soundEnabled: muted ? FLAG_DISABLED : FLAG_DEFAULT,
      bannerEnabled: behavior !== undefined && !showsBanner(behavior) ? FLAG_DISABLED : FLAG_DEFAULT,
    },
  };

  await notificationManager.publish(request);
  if (updateBadge) await setNotificationBadge(content.badge as number);
}

export function presentedNotification(request: notificationManager.NotificationRequest, schedules: ScheduledNotification[]): Notification {
  const serialized: ESObject = request.extraInfo?.[RESPONSE_KEY];
  if (typeof serialized === 'string') {
    try {
      const notification = parseResponse(serialized).notification;
      if (request.deliveryTime !== undefined) notification.date = request.deliveryTime;

      return notification;
    } catch (_) {
      /* Notifications from other publishers need not use our metadata. */
    }
  }

  const scheduled = schedules.find((entry: ScheduledNotification): boolean => entry.notificationId === request.id);
  if (scheduled !== undefined) return { date: request.deliveryTime ?? Date.now(), request: scheduled.request };

  const normal = request.content.normal ?? request.content.longText ?? request.content.multiLine;
  // System Push Kit notifications do not expose clickAction.data through this API.
  const data: Record<string, ESObject> = {};
  const notification = pushNotification(
    request.label || String(request.id),
    normal?.title ?? null,
    normal?.text ?? null,
    data,
    request.deliveryTime ?? Date.now(),
  );
  notification.request.content['subtitle'] = normal?.additionalText ?? null;
  notification.request.content['sound'] = null;

  return notification;
}

export async function dismissPresentedNotification(
  request: notificationManager.NotificationRequest,
  schedules: ScheduledNotification[],
): Promise<void> {
  if (request.id === undefined) return;

  const reminder = schedules.find((entry: ScheduledNotification): boolean => entry.notificationId === request.id);
  if (reminder !== undefined) {
    try {
      if (repeats(reminder.request)) {
        await reminderAgentManager.cancelReminderOnDisplay(reminder.reminderId);
      } else {
        await reminderAgentManager.cancelReminder(reminder.reminderId);
      }
      return;
    } catch (error) {
      if ((error as BusinessError).code !== REMINDER_NOT_FOUND) {
        throw new ExpoNotificationError('ERR_NOTIFICATIONS_DISMISS', error as Object);
      }
    }
  }

  try {
    await notificationManager.cancel(request.id, request.label);
  } catch (error) {
    if ((error as BusinessError).code !== NOTIFICATION_NOT_FOUND) {
      throw new ExpoNotificationError('ERR_NOTIFICATIONS_DISMISS', error as Object);
    }
  }
}

export function validateActions(actions: NotificationAction[], options?: Record<string, ESObject>): void {
  if (!Array.isArray(actions) || actions.length > MAX_ACTION_BUTTONS) {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', 'HarmonyOS supports at most two notification action buttons.');
  }

  const ids = new Set<string>();

  for (const action of actions) {
    if (!action || typeof action.identifier !== 'string' || !action.identifier || !action.buttonTitle || typeof action.buttonTitle !== 'string') {
      throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', 'Notification actions require an identifier and buttonTitle.');
    }
    if (ids.has(action.identifier) || action.identifier === DEFAULT_ACTION) {
      throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', 'Notification action identifiers must be unique and not reserved.');
    }
    if (action.textInput !== undefined) {
      throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Text input notification actions are not supported on HarmonyOS.');
    }

    if (action.options !== undefined) {
      const fields = record(action.options, 'action.options');
      for (const key of ['opensAppToForeground', 'isAuthenticationRequired', 'isDestructive']) {
        if (fields[key] !== undefined && typeof fields[key] !== 'boolean') {
          throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', `action.options.${key} must be a boolean.`);
        }
      }
    }
    if (
      action.options?.opensAppToForeground === false ||
      action.options?.isAuthenticationRequired === true ||
      action.options?.isDestructive === true
    ) {
      throw new ExpoModuleError(
        'ERR_NOTIFICATIONS_UNSUPPORTED',
        'Background, authenticated, or destructive notification actions are not supported on HarmonyOS.',
      );
    }

    ids.add(action.identifier);
  }

  if (options !== undefined && Object.keys(options).some((key: string): boolean => options[key] !== undefined)) {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'iOS notification category options are not supported on HarmonyOS.');
  }
}

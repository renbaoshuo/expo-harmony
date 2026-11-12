/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';

export const DEFAULT_ACTION = 'expo.modules.notifications.actions.DEFAULT';
export const RESPONSE_KEY = 'expo.modules.notifications.response';
export const PUSH_LISTENER_ACTION = 'action.ohos.push.listener';
export const SLOT_METADATA = 'expo.modules.notifications.defaultSlotType';
export const HANDLER_TIMEOUT_MS = 3000;
export const MAX_ACTION_BUTTONS = 2;
export const MAX_NOTIFICATION_ID = Math.floor((2147483647 - MAX_ACTION_BUTTONS) / (MAX_ACTION_BUTTONS + 1));
export const REMINDER_PERMISSION = 'ohos.permission.PUBLISH_AGENT_REMINDER';
export const EXPO_SERVICE_ERROR = 'ERR_NOTIFICATIONS_EXPO_PUSH_SERVICE_UNSUPPORTED';

export class ExpoNotificationError extends ExpoModuleError {
  constructor(fallback: string, error: Object) {
    super(String((error as BusinessError).code ?? fallback), (error as Error).message, error);
  }
}

export function notificationSlot(context: common.UIAbilityContext): notificationManager.SlotType {
  const value = context.abilityInfo.metadata?.find((entry): boolean => entry.name === SLOT_METADATA)?.value ?? 'service';

  switch (value) {
    case 'service':
      return notificationManager.SlotType.SERVICE_INFORMATION;
    case 'social':
      return notificationManager.SlotType.SOCIAL_COMMUNICATION;
    case 'content':
      return notificationManager.SlotType.CONTENT_INFORMATION;
    case 'other':
      return notificationManager.SlotType.OTHER_TYPES;
    default:
      throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', `Invalid defaultSlotType: ${value}.`);
  }
}

export interface NotificationRequest {
  identifier: string;
  content: Record<string, ESObject>;
  trigger: Record<string, ESObject> | null;
}

export interface Notification {
  date: number;
  request: NotificationRequest;
}

export interface NotificationResponse {
  actionIdentifier: string;
  notification: Notification;
}

export function parseResponse(serialized: string): NotificationResponse {
  const response = record(JSON.parse(serialized), 'notification response') as NotificationResponse;

  identifier(response.actionIdentifier);
  if (!Number.isFinite(response.notification?.date)) {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', 'Notification date must be finite.');
  }
  identifier(response.notification?.request?.identifier);
  record(response.notification.request.content, 'notification content');
  if (response.notification.request.trigger !== null) record(response.notification.request.trigger, 'notification trigger');

  return response;
}

export function pushNotification(id: string, title: string | null, body: string | null, data: Record<string, ESObject>, date: number): Notification {
  const content: Record<string, ESObject> = {};
  content['title'] = title;
  content['subtitle'] = null;
  content['body'] = body;
  content['data'] = data;
  content['sound'] = 'default';

  const trigger: Record<string, ESObject> = {};
  trigger['type'] = 'push';
  const request: NotificationRequest = { identifier: id, content, trigger };

  return { date, request };
}

export interface ScheduledNotification {
  reminderId: number;
  notificationId: number;
  request: NotificationRequest;
}

export interface NotificationAction {
  identifier: string;
  buttonTitle: string;
  options?: Record<string, ESObject>;
  textInput?: Record<string, ESObject>;
}

export interface NotificationCategory {
  identifier: string;
  actions: NotificationAction[];
}

export function record(value: ESObject, name: string): Record<string, ESObject> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', `${name} must be an object.`);
  }

  return value as Record<string, ESObject>;
}

export function identifier(value: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', 'An identifier must be a nonempty string.');
  }

  return value;
}

export function integer(value: ESObject, name: string, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < min || value > max) {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', `${name} must be an integer between ${min} and ${max}.`);
  }

  return value as number;
}

export function notificationContent(input: ESObject): Record<string, ESObject> {
  const content = record(input, 'content');

  for (const name of ['title', 'subtitle', 'body', 'categoryIdentifier']) {
    if (content[name] !== undefined && content[name] !== null && typeof content[name] !== 'string') {
      throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', `content.${name} must be a string.`);
    }
  }

  if (content.data !== undefined && content.data !== null) record(content.data, 'content.data');
  if (content.badge !== undefined) integer(content.badge, 'badge', 0, 2147483647);
  if (content.sound !== undefined && content.sound !== null && typeof content.sound !== 'boolean' && content.sound !== 'default') {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Custom local notification sounds are not supported on HarmonyOS.');
  }

  for (const name of ['autoDismiss', 'sticky']) {
    if (content[name] !== undefined && typeof content[name] !== 'boolean') {
      throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', `content.${name} must be a boolean.`);
    }
  }

  if (content.sticky === true) {
    throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Sticky notifications are not supported on HarmonyOS.');
  }

  for (const name of ['attachments', 'vibrate', 'color', 'priority', 'interruptionLevel', 'launchImageName']) {
    if (content[name] !== undefined) {
      throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', `content.${name} is not supported on HarmonyOS.`);
    }
  }

  const copy = JSON.parse(JSON.stringify(content)) as Record<string, ESObject>;
  copy.title = content.title ?? null;
  copy.subtitle = content.subtitle ?? null;
  copy.body = content.body ?? null;
  copy.data = content.data ?? {};
  // Match upstream Android: omission means the default notification sound.
  copy.sound = content.sound === false || content.sound === null ? null : 'default';

  return copy;
}

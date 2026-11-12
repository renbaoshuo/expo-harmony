/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { notificationManager } from '@kit.NotificationKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  Notification,
  NotificationResponse,
  NotificationCategory,
  ScheduledNotification,
  MAX_NOTIFICATION_ID,
  RESPONSE_KEY,
  parseResponse,
} from './NotificationTypes';

const PERMISSION_DENIED = 201;

export type NotificationReceiver = (notification: Notification) => void;
export type ResponseReceiver = (response: NotificationResponse) => void;
export type TokenReceiver = (token: string) => void;

class OperationQueue {
  private tail: Promise<void> = Promise.resolve();

  run<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.tail.then(operation);
    this.tail = result.then(
      (): void => {},
      (): void => {},
    );

    return result;
  }
}

export class NotificationsStore {
  private static instances: Map<string, NotificationsStore> = new Map();
  private readonly storage: preferences.Preferences;
  private readonly notifications: OperationQueue = new OperationQueue();
  private readonly registration: OperationQueue = new OperationQueue();
  private readonly writes: OperationQueue = new OperationQueue();
  private registrationRevision: number = 0;
  private permission?: Promise<void>;
  private failure?: Object;
  readonly received: Map<common.UIAbilityContext, Set<NotificationReceiver>> = new Map();
  readonly responses: Set<ResponseReceiver> = new Set();
  readonly tokens: Set<TokenReceiver> = new Set();
  lastResponse: NotificationResponse | null = null;

  private constructor(context: common.Context) {
    this.storage = preferences.getPreferencesSync(context, { name: 'expo_notifications' });
  }

  static get(context: common.Context): NotificationsStore {
    const key = context.applicationInfo.name;
    let instance = NotificationsStore.instances.get(key);
    if (instance === undefined) {
      instance = new NotificationsStore(context);
      NotificationsStore.instances.set(key, instance);
    }

    return instance;
  }

  run<T>(operation: () => Promise<T>): Promise<T> {
    return this.notifications.run(operation);
  }

  get tokenRevision(): number {
    return this.registrationRevision;
  }

  runToken<T>(operation: () => Promise<T>, supersedesUpdates: boolean = false): Promise<T> {
    return this.registration.run(async (): Promise<T> => {
      const result = await operation();
      if (supersedesUpdates) this.registrationRevision += 1;
      return result;
    });
  }

  requestPermissions(operation: () => Promise<void>): Promise<void> {
    if (this.permission !== undefined) return this.permission;

    const result = Promise.resolve().then(operation);
    this.permission = result;

    result.then(
      (): void => {
        this.permission = undefined;
      },
      (): void => {
        this.permission = undefined;
      },
    );

    return result;
  }

  read<T>(key: string, fallback: T): T {
    const value = this.storage.getSync(key, '') as string;
    if (value === '') return fallback;

    try {
      return JSON.parse(value) as T;
    } catch (error) {
      throw new ExpoModuleError('ERR_NOTIFICATIONS_STORAGE', `Invalid persisted notifications data (${key}).`, error as Object);
    }
  }

  write<T>(key: string, value: T): Promise<void> {
    // Preferences.flush commits every key, so writes and rollback must share a queue.
    return this.writes.run((): Promise<void> => this.persist(key, value));
  }

  private async persist<T>(key: string, value: T): Promise<void> {
    if (this.failure !== undefined) {
      throw new ExpoModuleError(
        'ERR_NOTIFICATIONS_STORAGE',
        'Notification storage rollback failed; restart the application before retrying.',
        this.failure,
      );
    }

    const previous = this.storage.getSync(key, '');

    this.storage.putSync(key, JSON.stringify(value));

    try {
      await this.storage.flush();
    } catch (error) {
      try {
        this.storage.putSync(key, previous);
        await this.storage.flush();
      } catch (rollback) {
        this.failure = rollback as Object;

        throw new ExpoModuleError(
          'ERR_NOTIFICATIONS_STORAGE',
          `Could not persist or restore notifications data (${key}); restart the application before retrying.`,
          rollback as Object,
        );
      }

      throw new ExpoModuleError('ERR_NOTIFICATIONS_STORAGE', `Could not persist notifications data (${key}).`, error as Object);
    }
  }

  schedules(): ScheduledNotification[] {
    return this.read<ScheduledNotification[]>('scheduled', []);
  }

  categories(): NotificationCategory[] {
    return this.read<NotificationCategory[]>('categories', []);
  }

  async allocateId(): Promise<number> {
    const active = await notificationManager.getActiveNotifications();
    const occupied = new Set<number>(active.map((entry: notificationManager.NotificationRequest): number => entry.id ?? 0));
    this.schedules().forEach((entry: ScheduledNotification): void => {
      occupied.add(entry.notificationId);
    });

    let next = this.read<number>('nextId', 0);
    do {
      next = next >= MAX_NOTIFICATION_ID ? 1 : next + 1;
    } while (occupied.has(next));

    await this.write('nextId', next);

    return next;
  }

  async validSchedules(cancelling: boolean = false): Promise<ScheduledNotification[]> {
    const saved = this.schedules();
    let valid: reminderAgentManager.ReminderInfo[];

    try {
      valid = await reminderAgentManager.getAllValidReminders();
    } catch (error) {
      // cancelReminder itself does not require this query permission. Continue
      // cancelling saved handles when an app update removed the permission.
      if ((error as BusinessError).code === PERMISSION_DENIED && (cancelling || saved.length === 0)) return saved;
      throw new ExpoModuleError(String((error as BusinessError).code ?? 'ERR_NOTIFICATIONS_SCHEDULE'), (error as Error).message, error as Object);
    }

    const ids = new Set<number>(valid.map((entry: reminderAgentManager.ReminderInfo): number => entry.reminderId));
    const active = await notificationManager.getActiveNotifications();
    const displayed = new Set<number>(active.map((entry: notificationManager.NotificationRequest): number => entry.id ?? -1));

    const retained = saved.filter((entry: ScheduledNotification): boolean => ids.has(entry.reminderId) || displayed.has(entry.notificationId));

    // Recover missing records or an interrupted update from the system's Expo payload.
    for (const item of valid) {
      const serialized = item.reminderReq.wantAgent?.parameters?.[RESPONSE_KEY];
      if (typeof serialized !== 'string' || item.reminderReq.notificationId === undefined) continue;

      let response: NotificationResponse;

      try {
        response = parseResponse(serialized);
      } catch (_) {
        continue;
      }

      const entry: ScheduledNotification = {
        reminderId: item.reminderId,
        notificationId: item.reminderReq.notificationId,
        request: response.notification.request,
      };
      const index = retained.findIndex((cached: ScheduledNotification): boolean => cached.reminderId === item.reminderId);
      if (index === -1) retained.push(entry);
      else retained[index] = entry;
    }

    if (JSON.stringify(retained) !== JSON.stringify(saved)) await this.write('scheduled', retained);

    return retained.filter((entry: ScheduledNotification): boolean => ids.has(entry.reminderId));
  }

  receive(context: common.UIAbilityContext, notification: Notification): void {
    const callbacks = this.received.get(context);
    // Snapshot before callbacks, which can register or remove listeners synchronously.
    if (callbacks !== undefined) Array.from(callbacks).forEach((callback: NotificationReceiver): void => callback(notification));
  }

  respond(response: NotificationResponse): void {
    this.lastResponse = response;
    Array.from(this.responses).forEach((callback: ResponseReceiver): void => callback(response));
  }

  get lastToken(): string | undefined {
    return this.read<string | null>('pushToken', null) ?? undefined;
  }

  async clearToken(): Promise<void> {
    await this.write('pushToken', null);
  }

  async updateToken(token: string): Promise<void> {
    if (token.length === 0 || token === this.lastToken) return;

    await this.write('pushToken', token);

    Array.from(this.tokens).forEach((callback: TokenReceiver): void => callback(token));
  }
}

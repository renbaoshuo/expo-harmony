/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModule, ExpoModuleDefinition, ExpoModuleError, ExpoFunction, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { pushService } from '@kit.PushKit';
import { NotificationsStore, NotificationReceiver, ResponseReceiver, TokenReceiver } from './NotificationsStore';
import {
  Notification,
  NotificationResponse,
  NotificationRequest,
  NotificationCategory,
  NotificationAction,
  ScheduledNotification,
  HANDLER_TIMEOUT_MS,
  EXPO_SERVICE_ERROR,
  identifier,
  integer,
  ExpoNotificationError,
  record,
} from './NotificationTypes';
import { validateTrigger, nextTriggerDate } from './NotificationTriggers';
import {
  dismissPresentedNotification,
  presentedNotification,
  publishNotification,
  setNotificationBadge,
  validateActions,
  validateBehavior,
} from './NotificationPresentation';
import { schedule, cancelScheduled } from './NotificationScheduling';

const NotificationRecord = ExpoValueTypes.custom<Record<string, ESObject>>(
  'notification object',
  (value: ESObject): Record<string, ESObject> => record(value, 'notification argument'),
  (value: Record<string, ESObject>): ESObject => value,
);
const NotificationActions = ExpoValueTypes.custom<NotificationAction[]>(
  'notification actions',
  (value: ESObject): NotificationAction[] => {
    if (!Array.isArray(value)) {
      throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', 'actions must be an array.');
    }

    return value as NotificationAction[];
  },
  (value: NotificationAction[]): ESObject => value,
);

const NOTIFICATIONS_DISABLED = 1600004;
const CAPABILITY_UNSUPPORTED = 801;
const PERMISSION_REQUESTED = 'permissionRequested';

abstract class NotificationsModule extends ExpoModule {
  protected get store(): NotificationsStore {
    return NotificationsStore.get(this.context.uiAbilityContext);
  }

  protected queue<T>(operation: () => Promise<T>): Promise<T> {
    return this.store.run((): Promise<T> => {
      this.context.runtimeEpoch;

      return operation();
    });
  }

  protected queueToken<T>(operation: () => Promise<T>): Promise<T> {
    return this.store.runToken((): Promise<T> => {
      this.context.runtimeEpoch;

      return operation();
    }, true);
  }

  protected listen(callback: NotificationReceiver): void {
    let callbacks = this.store.received.get(this.context.uiAbilityContext);
    if (callbacks === undefined) {
      callbacks = new Set<NotificationReceiver>();
      this.store.received.set(this.context.uiAbilityContext, callbacks);
    }

    callbacks.add(callback);
  }

  protected unlisten(callback: NotificationReceiver): void {
    const callbacks = this.store.received.get(this.context.uiAbilityContext);
    callbacks?.delete(callback);
    if (callbacks?.size === 0) this.store.received.delete(this.context.uiAbilityContext);
  }

  protected canSendEvents(): boolean {
    try {
      // The runtime can stop accepting events before its onDestroy hook runs.
      this.context.runtimeEpoch;
      return true;
    } catch (_) {
      return false;
    }
  }
}

export class ExpoPushTokenManager extends NotificationsModule {
  private receiver: TokenReceiver = (token: string): void => {
    if (!this.canSendEvents()) return;

    const payload: Record<string, ESObject> = { 'devicePushToken': token };
    this.sendEvent('onDevicePushToken', payload);
  };

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoPushTokenManager')
      .events(['onDevicePushToken'])
      .onDestroy((): void => {
        this.store.tokens.delete(this.receiver);
      })
      .onStartObserving('onDevicePushToken', (): void => {
        this.store.tokens.add(this.receiver);
        this.refreshToken();
      })
      .onStopObserving('onDevicePushToken', (): void => {
        this.store.tokens.delete(this.receiver);
      })
      .onForeground((): void => {
        this.refreshToken();
      })
      .asyncFunction('getDevicePushTokenAsync', (): Promise<string> => this.token())
      .asyncFunction(
        'unregisterForNotificationsAsync',
        (): Promise<void> =>
          this.queueToken(async (): Promise<void> => {
            // Persist opt-out so late token callbacks cannot re-register.
            await this.store.clearToken();

            try {
              await pushService.deleteToken();
            } catch (error) {
              if (error instanceof ExpoModuleError) throw error;
              throw new ExpoNotificationError('ERR_NOTIFICATIONS_PUSH_TOKEN', error as Object);
            }
          }),
      );
  }

  private refreshToken(): void {
    if (!this.store.tokens.has(this.receiver)) return;

    this.queueToken(async (): Promise<void> => {
      if (this.store.tokens.has(this.receiver) && this.store.lastToken !== undefined) await this.fetchToken(true);
    }).catch((error: Object): void => {
      if (this.canSendEvents()) this.context.logger.warn(`Unable to refresh Push Kit registration (code ${(error as BusinessError).code}).`);
    });
  }

  private token(): Promise<string> {
    return this.queueToken((): Promise<string> => this.fetchToken());
  }

  private async fetchToken(observingOnly: boolean = false): Promise<string> {
    const store = this.store;
    let token: string;

    try {
      token = await pushService.getToken();
    } catch (error) {
      if (error instanceof ExpoModuleError) throw error;
      throw new ExpoNotificationError('ERR_NOTIFICATIONS_PUSH_TOKEN', error as Object);
    }

    if (token.length === 0) {
      throw new ExpoModuleError('ERR_NOTIFICATIONS_PUSH_TOKEN', 'Push Kit returned an empty token.');
    }

    if (!observingOnly || store.tokens.size > 0) await store.updateToken(token);

    return token;
  }
}

export class ExpoNotificationPermissionsModule extends NotificationsModule {
  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoNotificationPermissionsModule')
      .asyncFunction('getPermissionsAsync', (): Promise<Record<string, ESObject>> => this.permissions())
      .asyncFunction(
        'requestPermissionsAsync',
        ExpoFunction.typed1(
          NotificationRecord.optional(),
          async (_options?: ESObject): Promise<Record<string, ESObject>> => {
            this.context.runtimeEpoch;

            const store = this.store;
            const context = this.context.uiAbilityContext;

            // Keep the shared request independent of runtime lifetime.
            await store.requestPermissions(async (): Promise<void> => {
              if (store.read<boolean>(PERMISSION_REQUESTED, false) || await notificationManager.isNotificationEnabled()) return;

              try {
                await notificationManager.requestEnableNotification(context);
              } catch (error) {
                if ((error as BusinessError).code !== NOTIFICATIONS_DISABLED) {
                  if (error instanceof ExpoModuleError) throw error;
                  throw new ExpoNotificationError('ERR_NOTIFICATIONS_PERMISSION', error as Object);
                }
              }

              await store.write(PERMISSION_REQUESTED, true);
            });

            return this.permissions();
          },
        ),
      );
  }

  private async permissions(): Promise<Record<string, ESObject>> {
    this.context.runtimeEpoch;

    const store = this.store;
    const settings = await notificationManager.getNotificationSetting();
    const granted = settings.notificationEnabled ?? await notificationManager.isNotificationEnabled();
    const asked = store.read<boolean>(PERMISSION_REQUESTED, false);

    if (granted && !asked) await store.write(PERMISSION_REQUESTED, true);

    const response: Record<string, ESObject> = {};
    response['status'] = granted ? 'granted' : asked ? 'denied' : 'undetermined';
    response['granted'] = granted;
    response['canAskAgain'] = granted || !asked;
    response['expires'] = 'never';
    response['harmony'] = settings;

    return response;
  }
}

export class ExpoBadgeModule extends NotificationsModule {
  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoBadgeModule')
      .asyncFunction('getBadgeCountAsync', async (): Promise<number> => {
        try {
          return await notificationManager.getBadgeNumber();
        } catch (error) {
          if ((error as BusinessError).code === CAPABILITY_UNSUPPORTED) return 0;
          if (error instanceof ExpoModuleError) throw error;
          throw new ExpoNotificationError('ERR_NOTIFICATIONS_BADGE', error as Object);
        }
      })
      .asyncFunction(
        'setBadgeCountAsync',
        ExpoFunction.typed1(ExpoValueTypes.number(), (count: number): Promise<boolean> =>
          setNotificationBadge(integer(count, 'badgeCount', 0, 2147483647)),
        ),
      );
  }
}

export class ExpoNotificationScheduler extends NotificationsModule {
  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoNotificationScheduler')
      .asyncFunction(
        'scheduleNotificationAsync',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          NotificationRecord,
          NotificationRecord.nullable(),
          (id: string, content: ESObject, trigger: ESObject): Promise<string> =>
            this.queue((): Promise<string> => schedule(this.context, this.store, id, content, trigger)),
        ),
      )
      .asyncFunction(
        'getAllScheduledNotificationsAsync',
        (): Promise<NotificationRequest[]> =>
          this.queue(
            async (): Promise<NotificationRequest[]> =>
              (await this.store.validSchedules()).map((entry: ScheduledNotification): NotificationRequest => entry.request),
          ),
      )
      .asyncFunction(
        'cancelScheduledNotificationAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), (id: string): Promise<void> => this.queue((): Promise<void> => cancelScheduled(this.store, id))),
      )
      .asyncFunction(
        'cancelAllScheduledNotificationsAsync',
        (): Promise<void> => this.queue((): Promise<void> => cancelScheduled(this.store)),
      )
      .asyncFunction(
        'getNextTriggerDateAsync',
        ExpoFunction.typed1(
          NotificationRecord.nullable(),
          async (trigger: ESObject): Promise<number | null> => nextTriggerDate(validateTrigger(trigger)),
        ),
      );
  }
}

export class ExpoNotificationPresenter extends NotificationsModule {
  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoNotificationPresenter')
      .asyncFunction(
        'getPresentedNotificationsAsync',
        (): Promise<Notification[]> => this.queue(async (): Promise<Notification[]> => {
          const scheduled = this.store.schedules();

          return (await notificationManager.getActiveNotifications()).map(
            (request: notificationManager.NotificationRequest): Notification => presentedNotification(request, scheduled),
          );
        }),
      )
      .asyncFunction(
        'dismissNotificationAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), (id: string): Promise<void> =>
          this.queue(async (): Promise<void> => {
            identifier(id);

            const scheduled = this.store.schedules();

            for (const item of await notificationManager.getActiveNotifications()) {
              if (presentedNotification(item, scheduled).request.identifier === id) {
                await dismissPresentedNotification(item, scheduled);
              }
            }
          }),
        ),
      )
      .asyncFunction(
        'dismissAllNotificationsAsync',
        (): Promise<void> => this.queue(async (): Promise<void> => {

          const scheduled = this.store.schedules();

          for (const item of await notificationManager.getActiveNotifications()) {
            await dismissPresentedNotification(item, scheduled);
          }
        }),
      );
  }
}

export class ExpoNotificationsEmitter extends NotificationsModule {
  private observing: boolean = false;
  private delivered?: NotificationResponse;
  private received: NotificationReceiver = (notification: Notification): void => {
    if (!this.canSendEvents()) return;
    this.sendEvent('onDidReceiveNotification', notification);
  };
  private response: ResponseReceiver = (response: NotificationResponse): void => {
    if (!this.observing || !this.canSendEvents()) return;

    this.sendEvent('onDidReceiveNotificationResponse', response);
    this.delivered = response;
  };

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoNotificationsEmitter')
      .events(['onDidReceiveNotification', 'onDidReceiveNotificationResponse', 'onDidClearNotificationResponse', 'onNotificationsDeleted'])
      .onCreate((): void => {
        this.listen(this.received);
        this.store.responses.add(this.response);
      })
      .onDestroy((): void => {
        this.observing = false;
        this.unlisten(this.received);
        this.store.responses.delete(this.response);
      })
      .onStartObserving('onDidReceiveNotificationResponse', (): void => {
        this.observing = true;
        const response = this.store.lastResponse;
        if (response !== null && response !== this.delivered) this.response(response);
      })
      .onStopObserving('onDidReceiveNotificationResponse', (): void => {
        this.observing = false;
      })
      .syncFunction('getLastNotificationResponse', (): NotificationResponse | null => this.store.lastResponse)
      .syncFunction('clearLastNotificationResponse', (): void => {
        this.store.lastResponse = null;
      });
  }
}

class PendingNotification {
  readonly notification: Notification;
  readonly timer: number;

  constructor(notification: Notification, timer: number) {
    this.notification = notification;
    this.timer = timer;
  }
}

export class ExpoNotificationsHandlerModule extends NotificationsModule {
  private pending: Map<string, PendingNotification> = new Map();
  private received: NotificationReceiver = (notification: Notification): void => {
    if (!this.canSendEvents()) return;

    const id = notification.request.identifier;
    const previous = this.pending.get(id);
    if (previous !== undefined) this.expire(id, previous);

    const timer = setTimeout((): void => {
      const current = this.pending.get(id);
      if (current !== undefined) this.expire(id, current);
    }, HANDLER_TIMEOUT_MS);

    this.pending.set(id, new PendingNotification(notification, timer));
    const payload: Record<string, ESObject> = { 'id': id, 'notification': notification };
    this.sendEvent('onHandleNotification', payload);
  };

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoNotificationsHandlerModule')
      .events(['onHandleNotification', 'onHandleNotificationTimeout'])
      .onStartObserving('onHandleNotification', (): void => {
        this.listen(this.received);
      })
      .onStopObserving('onHandleNotification', (): void => {
        this.unlisten(this.received);
      })
      .onDestroy((): void => {
        this.unlisten(this.received);
        this.pending.forEach((entry: PendingNotification): void => clearTimeout(entry.timer));
        this.pending.clear();
      })
      .asyncFunction(
        'handleNotificationAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), NotificationRecord, async (id: string, input: ESObject): Promise<void> => {
          const pending = this.pending.get(id);
          if (pending === undefined) {
            throw new ExpoModuleError('ERR_NOTIFICATION_HANDLED', 'The notification handler expired or already completed.');
          }

          const behavior = record(input, 'behavior');
          validateBehavior(behavior);

          clearTimeout(pending.timer);
          this.pending.delete(id);

          await this.queue((): Promise<void> => publishNotification(this.context.uiAbilityContext, this.store, pending.notification, behavior));
        }),
      );
  }

  private expire(id: string, entry: PendingNotification): void {
    clearTimeout(entry.timer);
    this.pending.delete(id);
    if (!this.canSendEvents()) return;

    const payload: Record<string, ESObject> = { 'id': id, 'notification': entry.notification };
    this.sendEvent('onHandleNotificationTimeout', payload);
  }
}

export class ExpoNotificationCategoriesModule extends NotificationsModule {
  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoNotificationCategoriesModule')
      .asyncFunction('getNotificationCategoriesAsync', async (): Promise<NotificationCategory[]> => this.store.categories())
      .asyncFunction(
        'setNotificationCategoryAsync',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          NotificationActions,
          NotificationRecord.optional(),
          (id: string, actions: NotificationAction[], options?: Record<string, ESObject>): Promise<NotificationCategory> =>
            this.queue(async (): Promise<NotificationCategory> => {
              identifier(id);
              validateActions(actions, options);

              const category: NotificationCategory = { identifier: id, actions };
              const categories = this.store.categories().filter((item: NotificationCategory): boolean => item.identifier !== id);

              await this.store.write('categories', categories.concat([category]));

              return category;
            }),
        ),
      )
      .asyncFunction(
        'deleteNotificationCategoryAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.string(),
          (id: string): Promise<boolean> =>
            this.queue(async (): Promise<boolean> => {
              identifier(id);

              const categories = this.store.categories();
              const remaining = categories.filter((item: NotificationCategory): boolean => item.identifier !== id);
              if (remaining.length === categories.length) return false;

              await this.store.write('categories', remaining);

              return true;
            }),
        ),
      );
  }
}

export class ExpoBackgroundNotificationTasksModule extends NotificationsModule {
  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoBackgroundNotificationTasksModule')
      .asyncFunction(
        'registerTaskAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (_name: string): Promise<void> => {
          throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Background notification tasks are not supported on HarmonyOS.');
        }),
      )
      .asyncFunction(
        'unregisterTaskAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (_name: string): Promise<void> => {
          throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Background notification tasks are not supported on HarmonyOS.');
        }),
      );
  }
}

export class NotificationsServerRegistrationModule extends NotificationsModule {
  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('NotificationsServerRegistrationModule')
      .asyncFunction('getInstallationIdAsync', async (): Promise<string> => {
        throw new ExpoModuleError(EXPO_SERVICE_ERROR, 'Expo Push Service is not supported on HarmonyOS. Use Huawei Push Kit.');
      })
      .asyncFunction('getRegistrationInfoAsync', async (): Promise<string> => {
        throw new ExpoModuleError(EXPO_SERVICE_ERROR, 'Expo Push Service is not supported on HarmonyOS. Use Huawei Push Kit.');
      })
      .asyncFunction(
        'setRegistrationInfoAsync',
        ExpoFunction.typed1(ExpoValueTypes.string().nullable(), async (_info: string | null): Promise<void> => {
          throw new ExpoModuleError(EXPO_SERVICE_ERROR, 'Expo Push Service is not supported on HarmonyOS. Use Huawei Push Kit.');
        }),
      );
  }
}

export class ExpoNotificationChannelManager extends NotificationsModule {
  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoNotificationChannelManager')
      .asyncFunction('getNotificationChannelsAsync', async (): Promise<ESObject> => {
        throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Android notification channels are not supported on HarmonyOS.');
      })
      .asyncFunction(
        'getNotificationChannelAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (_id: string): Promise<ESObject> => {
          throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Android notification channels are not supported on HarmonyOS.');
        }),
      )
      .asyncFunction(
        'setNotificationChannelAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), NotificationRecord, async (_id: string, _value: ESObject): Promise<ESObject> => {
          throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Android notification channels are not supported on HarmonyOS.');
        }),
      )
      .asyncFunction(
        'deleteNotificationChannelAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (_id: string): Promise<void> => {
          throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Android notification channels are not supported on HarmonyOS.');
        }),
      );
  }
}

export class ExpoNotificationChannelGroupManager extends NotificationsModule {
  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoNotificationChannelGroupManager')
      .asyncFunction('getNotificationChannelGroupsAsync', async (): Promise<ESObject> => {
        throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Android notification channel groups are not supported on HarmonyOS.');
      })
      .asyncFunction(
        'getNotificationChannelGroupAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (_id: string): Promise<ESObject> => {
          throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Android notification channel groups are not supported on HarmonyOS.');
        }),
      )
      .asyncFunction(
        'setNotificationChannelGroupAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), NotificationRecord, async (_id: string, _value: ESObject): Promise<ESObject> => {
          throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Android notification channel groups are not supported on HarmonyOS.');
        }),
      )
      .asyncFunction(
        'deleteNotificationChannelGroupAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (_id: string): Promise<void> => {
          throw new ExpoModuleError('ERR_NOTIFICATIONS_UNSUPPORTED', 'Android notification channel groups are not supported on HarmonyOS.');
        }),
      );
  }
}

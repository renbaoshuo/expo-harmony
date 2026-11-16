/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { requireNativeModule } from 'expo-modules-core';
import {
  NotificationTimeoutError,
  setNotificationHandler as setUpstreamNotificationHandler,
  type NotificationHandler,
} from 'expo-notifications/build/NotificationsHandler';

export * from 'expo-notifications/build/NotificationsHandler';

const nativeHandler = requireNativeModule<{ enableHandlerTaskIds?: () => void }>('ExpoNotificationsHandlerModule');

function notificationIdentifier(taskId: string): string {
  // The native task ID contains a UUID followed by the complete Expo identifier.
  return taskId.slice(taskId.indexOf(':') + 1);
}

export function setNotificationHandler(handler: NotificationHandler | null): void {
  if (!handler || !nativeHandler.enableHandlerTaskIds) {
    setUpstreamNotificationHandler(handler);
    return;
  }

  nativeHandler.enableHandlerTaskIds();
  setUpstreamNotificationHandler({
    handleNotification: notification => handler.handleNotification(notification),
    handleSuccess: taskId => handler.handleSuccess?.(notificationIdentifier(taskId)),
    handleError: (taskId, error) => {
      const id = notificationIdentifier(taskId);
      const reported = error instanceof NotificationTimeoutError && error.info.id === taskId
        ? new NotificationTimeoutError(id, error.info.notification)
        : error;

      handler.handleError?.(id, reported);
    },
  });
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type withNotifications from './withNotifications';

export type NotificationsPluginProps = Exclude<Parameters<typeof withNotifications>[1], void>;

declare const notifications: (props?: NotificationsPluginProps) => [
  '@expo-harmony/expo-notifications',
  NotificationsPluginProps,
];

export default notifications;

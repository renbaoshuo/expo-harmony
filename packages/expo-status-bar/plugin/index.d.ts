/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export type StatusBarPluginProps = {
  /** Determines whether the status bar starts hidden. */
  hidden?: boolean;
  /** Determines the initial status bar text and icon color. */
  style?: 'light' | 'dark';
};

export default function statusBar(props?: StatusBarPluginProps): [string, StatusBarPluginProps];

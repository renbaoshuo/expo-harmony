/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

/** @deprecated This will be removed in a future Expo release. */
export type NavigationBarVisibility = 'visible' | 'hidden';

/** @deprecated This will be removed in a future Expo release. */
export type NavigationBarVisibilityEvent = {
  visibility: NavigationBarVisibility;
  /** Harmony uses 2 for hidden and 0 for visible, not Android's full system UI bitmask. */
  rawVisibility: number;
};

/** `light` and `dark` describe the buttons, while `auto` and `inverted` resolve against the app theme. */
export type NavigationBarStyle = 'auto' | 'inverted' | 'light' | 'dark';

export type NavigationBarProps = {
  /** Button color. `auto` selects light buttons in dark mode and dark buttons in light mode. */
  style?: NavigationBarStyle;
  /** Whether to hide the navigation bar and gesture indicator. */
  hidden?: boolean;
};

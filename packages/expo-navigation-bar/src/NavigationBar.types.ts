export type NavigationBarButtonStyle = 'light' | 'dark';

export type NavigationBarVisibility = 'visible' | 'hidden';

/** @deprecated This will be removed in a future Expo release. */
export type NavigationBarBehavior = 'overlay-swipe' | 'inset-swipe' | 'inset-touch';

/** @deprecated This will be removed in a future Expo release. */
export type NavigationBarPosition = 'relative' | 'absolute';

export type NavigationBarVisibilityEvent = {
  visibility: NavigationBarVisibility;
  /**
   * Android emits the native system UI bitmask. Harmony emits a compatibility projection in
   * which bit 2 represents a hidden navigation bar and 0 represents a visible navigation bar.
   */
  rawVisibility: number;
};

export type NavigationBarStyle = 'auto' | 'inverted' | 'light' | 'dark';

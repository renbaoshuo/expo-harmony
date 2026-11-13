/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { type EventSubscription, requireNativeModule } from 'expo-modules-core';
import type {
  NavigationBarProps,
  NavigationBarStyle,
  NavigationBarVisibility,
  NavigationBarVisibilityEvent,
} from 'expo-navigation-bar';
import { useEffect, useRef, useState } from 'react';
import { Appearance, useColorScheme } from 'react-native';

type ResolvedBarStyle = 'light' | 'dark';

const ExpoNavigationBar = requireNativeModule<{
  addListener(event: 'ExpoNavigationBar.didChange', listener: (event: NavigationBarVisibilityEvent) => void): EventSubscription;
  setStyle(style: ResolvedBarStyle): Promise<void>;
  setHidden(hidden: boolean): Promise<void>;
  getVisibilityAsync(): Promise<NavigationBarVisibility>;
}>('ExpoNavigationBar');

function isLightColorScheme() {
  const colorScheme = Appearance?.getColorScheme() ?? 'light';
  return colorScheme === 'light';
}

function resolveStyle(style: NavigationBarStyle): ResolvedBarStyle {
  switch (style) {
    case 'auto':
      return isLightColorScheme() ? 'dark' : 'light';
    case 'inverted':
      return isLightColorScheme() ? 'light' : 'dark';
    default:
      return style;
  }
}

const defaultProps: Required<NavigationBarProps> = {
  style: 'light',
  hidden: false,
};

function mergeEntriesStack() {
  return entriesStack.reduce<Required<NavigationBarProps>>(
    (prev, cur) => ({
      style: cur.style ?? prev.style,
      hidden: cur.hidden ?? prev.hidden,
    }),
    { ...defaultProps }
  );
}

const entriesStack: NavigationBarProps[] = [];

let updateImmediate: ReturnType<typeof setImmediate> | null = null;

let currentStyle: { value: ResolvedBarStyle } | undefined;
let currentHidden: { value: boolean } | undefined;

function reportUpdateFailure(property: 'style' | 'visibility', error: unknown): void {
  // A queued component cleanup can run after Expo has closed its native runtime.
  if (typeof error === 'object' && error !== null && 'code' in error && error.code === 'ERR_RUNTIME_DESTROYED') return;
  console.warn(`Unable to set the HarmonyOS navigation bar ${property}: ${String(error)}`);
}

async function applyStyle(style: NavigationBarStyle): Promise<void> {
  const resolved = resolveStyle(style);

  if (resolved === currentStyle?.value) return;

  const update = { value: resolved };
  try {
    const request = ExpoNavigationBar.setStyle(resolved);
    currentStyle = update;
    await request;
  } catch (error) {
    if (currentStyle === update) currentStyle = undefined;
    reportUpdateFailure('style', error);
  }
}

async function applyHidden(hidden: boolean): Promise<void> {
  if (hidden === currentHidden?.value) return;

  const update = { value: hidden };
  try {
    const request = ExpoNavigationBar.setHidden(hidden);
    currentHidden = update;
    await request;
  } catch (error) {
    if (currentHidden === update) currentHidden = undefined;
    reportUpdateFailure('visibility', error);
  }
}

/** @deprecated Use `NavigationBar.setStyle` instead. */
export function setStyle(style: NavigationBarStyle): void {
  defaultProps.style = style;
  void applyStyle(style);
}

function setHidden(hidden: boolean): void {
  defaultProps.hidden = hidden;
  void applyHidden(hidden);
}

function updateEntriesStack() {
  if (updateImmediate != null) {
    clearImmediate(updateImmediate);
  }

  updateImmediate = setImmediate(() => {
    updateImmediate = null;
    const { style, hidden } = mergeEntriesStack();

    void applyStyle(style);
    void applyHidden(hidden);
  });
}

export function NavigationBar({ style, hidden }: NavigationBarProps) {
  const colorScheme = useColorScheme();
  const entry = useRef<NavigationBarProps>({});

  useEffect(() => {
    const props = entry.current;
    entriesStack.push(props);

    return () => {
      const index = entriesStack.indexOf(props);
      if (index !== -1) entriesStack.splice(index, 1);
      updateEntriesStack();
    };
  }, []);

  useEffect(() => {
    entry.current.style = style;
    entry.current.hidden = hidden;
    updateEntriesStack();
  }, [colorScheme, style, hidden]);

  return null;
}

NavigationBar.setStyle = setStyle;
NavigationBar.setHidden = setHidden;

/** @deprecated This will be removed in a future Expo release. */
export function addVisibilityListener(
  listener: (event: NavigationBarVisibilityEvent) => void
): EventSubscription {
  return ExpoNavigationBar.addListener('ExpoNavigationBar.didChange', listener);
}

/** @deprecated Use `NavigationBar.setHidden` instead. */
export async function setVisibilityAsync(visibility: NavigationBarVisibility): Promise<void> {
  // This direct native request can change the value cached by the component.
  currentHidden = undefined;
  await ExpoNavigationBar.setHidden(visibility === 'hidden');
}

/** @deprecated This will be removed in a future Expo release. */
export async function getVisibilityAsync(): Promise<NavigationBarVisibility> {
  return ExpoNavigationBar.getVisibilityAsync();
}

/** @deprecated This will be removed in a future Expo release. */
export function useVisibility(): NavigationBarVisibility | null {
  const [visibility, setVisibility] = useState<NavigationBarVisibility | null>(null);

  useEffect(() => {
    let mounted = true;
    let updated = false;

    const subscription = addVisibilityListener((event) => {
      if (mounted) {
        updated = true;
        setVisibility(event.visibility);
      }
    });

    getVisibilityAsync().then((next) => {
      // A late initial snapshot must not overwrite a newer event.
      if (mounted && !updated) setVisibility(next);
    }).catch((error: unknown) => {
      if (mounted) console.warn(`Unable to read the HarmonyOS navigation bar visibility: ${String(error)}`);
    });

    return () => {
      mounted = false;
      subscription.remove();
    };
  }, []);

  return visibility;
}

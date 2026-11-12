/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { EventSubscription } from 'expo-modules-core';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Appearance, useColorScheme } from 'react-native';

import ExpoNavigationBar from './ExpoNavigationBar';
import type {
  NavigationBarProps,
  NavigationBarStyle,
  NavigationBarVisibility,
  NavigationBarVisibilityEvent,
} from './NavigationBar.types';

type ResolvedBarStyle = 'light' | 'dark';

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

function mergeEntriesStack(entriesStack: NavigationBarProps[]) {
  return entriesStack.reduce<Required<NavigationBarProps>>(
    (prev, cur) => ({
      style: cur.style ?? prev.style,
      hidden: cur.hidden ?? prev.hidden,
    }),
    { ...defaultProps }
  );
}

function createStackEntry({ style, hidden }: NavigationBarProps): NavigationBarProps {
  return { style, hidden };
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
    const { style, hidden } = mergeEntriesStack(entriesStack);

    void applyStyle(style);
    void applyHidden(hidden);
  });
}

function pushStackEntry(props: NavigationBarProps): NavigationBarProps {
  const entry = createStackEntry(props);
  entriesStack.push(entry);
  updateEntriesStack();
  return entry;
}

function popStackEntry(entry: NavigationBarProps): void {
  const index = entriesStack.indexOf(entry);
  if (index !== -1) {
    entriesStack.splice(index, 1);
  }
  updateEntriesStack();
}

function replaceStackEntry(
  entry: NavigationBarProps,
  props: NavigationBarProps
): NavigationBarProps {
  const newEntry = createStackEntry(props);
  const index = entriesStack.indexOf(entry);
  if (index !== -1) {
    entriesStack[index] = newEntry;
  }
  updateEntriesStack();
  return newEntry;
}

export function NavigationBar({ style, hidden }: NavigationBarProps) {
  const colorScheme = useColorScheme();
  const props = useMemo<NavigationBarProps>(() => ({ style, hidden }), [style, hidden]);
  const entry = useRef<NavigationBarProps | null>(null);

  useEffect(() => {
    entry.current = pushStackEntry(props);

    return () => {
      if (entry.current) {
        popStackEntry(entry.current);
        entry.current = null;
      }
    };
  }, []);

  useEffect(() => {
    if (entry.current) {
      entry.current = replaceStackEntry(entry.current, props);
    }
  }, [colorScheme, props]);

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

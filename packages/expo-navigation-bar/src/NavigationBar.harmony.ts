import { type EventSubscription } from 'expo-modules-core';
import { useEffect, useState } from 'react';
import { Appearance, processColor } from 'react-native';

import ExpoNavigationBar from './ExpoNavigationBar';
import type {
  NavigationBarBehavior,
  NavigationBarButtonStyle,
  NavigationBarPosition,
  NavigationBarStyle,
  NavigationBarVisibility,
  NavigationBarVisibilityEvent,
} from './NavigationBar.types';

function navigationBarStyleToButtonStyle(style: NavigationBarStyle): NavigationBarButtonStyle {
  const light = (Appearance.getColorScheme() ?? 'light') === 'light';

  switch (style) {
    case 'auto':
      return light ? 'dark' : 'light';
    case 'light':
      return 'dark';
    case 'dark':
      return 'light';
    case 'inverted':
      return light ? 'light' : 'dark';
  }
}

export function addVisibilityListener(
  listener: (event: NavigationBarVisibilityEvent) => void
): EventSubscription {
  return ExpoNavigationBar.addListener('ExpoNavigationBar.didChange', listener);
}

export async function setBackgroundColorAsync(color: string): Promise<void> {
  const value = processColor(color);

  if (typeof value !== 'number') {
    throw new TypeError(`Invalid navigation bar color: ${color}`);
  }

  await ExpoNavigationBar.setBackgroundColorAsync(value);
}

export async function getBackgroundColorAsync(): Promise<string> {
  return ExpoNavigationBar.getBackgroundColorAsync();
}

export async function setBorderColorAsync(_color: string): Promise<void> {
  console.warn('HarmonyOS does not expose a navigation bar divider color.');
}

export async function getBorderColorAsync(): Promise<string> {
  return '#00000000';
}

export async function setVisibilityAsync(visibility: NavigationBarVisibility): Promise<void> {
  await ExpoNavigationBar.setVisibilityAsync(visibility);
}

export async function getVisibilityAsync(): Promise<NavigationBarVisibility> {
  return ExpoNavigationBar.getVisibilityAsync();
}

export async function setButtonStyleAsync(style: NavigationBarButtonStyle): Promise<void> {
  await ExpoNavigationBar.setButtonStyleAsync(style);
}

export async function getButtonStyleAsync(): Promise<NavigationBarButtonStyle> {
  return ExpoNavigationBar.getButtonStyleAsync();
}

export async function setPositionAsync(position: NavigationBarPosition): Promise<void> {
  await ExpoNavigationBar.setPositionAsync(position);
}

export async function unstable_getPositionAsync(): Promise<NavigationBarPosition> {
  return ExpoNavigationBar.getPositionAsync();
}

export async function setBehaviorAsync(_behavior: NavigationBarBehavior): Promise<void> {
  console.warn('HarmonyOS does not expose Android navigation bar reveal behavior modes.');
}

export async function getBehaviorAsync(): Promise<NavigationBarBehavior> {
  return 'inset-touch';
}

export function setStyle(style: NavigationBarStyle): void {
  void ExpoNavigationBar.setButtonStyleAsync(navigationBarStyleToButtonStyle(style)).catch((error: unknown) => {
    console.warn(`Unable to set the HarmonyOS navigation bar style: ${String(error)}`);
  });
}

export function useVisibility(): NavigationBarVisibility | null {
  const [visibility, setVisibility] = useState<NavigationBarVisibility | null>(null);

  useEffect(() => {
    let mounted = true;

    getVisibilityAsync().then((next) => {
      if (mounted) setVisibility(next);
    }).catch(() => {});

    const subscription = addVisibilityListener((event) => {
      if (mounted) setVisibility(event.visibility);
    });

    return () => {
      mounted = false;
      subscription.remove();
    };
  }, []);

  return visibility;
}

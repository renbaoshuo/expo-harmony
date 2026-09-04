import { requireNativeModule } from 'expo-modules-core';

export * from 'expo-linking';

type NativeLinking = {
  openURL(url: string): Promise<boolean>;
  canOpenURL(url: string): Promise<boolean>;
  openSettings(): Promise<void>;
};

const native = requireNativeModule<NativeLinking>('ExpoLinking');

export async function openURL(url: string): Promise<true> {
  await native.openURL(url);
  return true;
}

export async function canOpenURL(url: string): Promise<boolean> {
  return native.canOpenURL(url);
}

export async function openSettings(): Promise<void> {
  await native.openSettings();
}

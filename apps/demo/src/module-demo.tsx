import type { ComponentType } from 'react';

import type { ModuleId } from './catalog';
import { AppMetricsDemo } from './modules/app-metrics';
import { ApplicationDemo } from './modules/application';
import { AssetDemo } from './modules/asset';
import { AudioDemo } from './modules/audio';
import { BackgroundFetchDemo } from './modules/background-fetch';
import { BackgroundTaskDemo } from './modules/background-task';
import { BatteryDemo } from './modules/battery';
import { BlobDemo } from './modules/blob';
import { BlurDemo } from './modules/blur';
import { BrightnessDemo } from './modules/brightness';
import { CalendarDemo } from './modules/calendar';
import { CameraDemo } from './modules/camera';
import { CellularDemo } from './modules/cellular';
import { CliDemo } from './modules/cli';
import { ClipboardDemo } from './modules/clipboard';
import { ConfigPluginsDemo } from './modules/config-plugins';
import { ConstantsDemo } from './modules/constants';
import { ContactsDemo } from './modules/contacts';
import { CryptoDemo } from './modules/crypto';
import { DeviceDemo } from './modules/device';
import { ExpoModulesDemo } from './expoModules/ExpoModulesDemo';
import { ModulesAutolinkingDemo } from './modules/expo-modules-autolinking';
import { ModulesCoreDemo } from './modules/expo-modules-core';
import { RouterDemo } from './modules/expo-router';
import { TaskManagerDemo } from './modules/expo-task-manager';
import { FetchDemo } from './modules/fetch';
import { FileSystemDemo } from './modules/file-system';
import { FontDemo } from './modules/font';
import { HapticsDemo } from './modules/haptics';
import { IntentLauncherDemo } from './modules/intent-launcher';
import { KeepAwakeDemo } from './modules/keep-awake';
import { LinearGradientDemo } from './modules/linear-gradient';
import { LinkingDemo } from './modules/linking';
import { LivePhotoDemo } from './modules/live-photo';
import { LocationDemo } from './modules/location';
import { MetroConfigDemo } from './modules/metro-config';
import { NavigationBarDemo } from './modules/navigation-bar';
import { NetworkDemo } from './modules/network';
import { PrebuildConfigDemo } from './modules/prebuild-config';
import { PrintDemo } from './modules/print';
import { SharingDemo } from './modules/sharing';
import { SplashScreenDemo } from './modules/splash-screen';
import { SystemUIDemo } from './modules/system-ui';
import { TemplateDemo } from './modules/template';

const MODULE_DEMOS = {
  'app-metrics': AppMetricsDemo,
  'application': ApplicationDemo,
  'asset': AssetDemo,
  'audio': AudioDemo,
  'background-fetch': BackgroundFetchDemo,
  'background-task': BackgroundTaskDemo,
  'battery': BatteryDemo,
  'blob': BlobDemo,
  'blur': BlurDemo,
  'brightness': BrightnessDemo,
  'calendar': CalendarDemo,
  'camera': CameraDemo,
  'cellular': CellularDemo,
  'cli': CliDemo,
  'clipboard': ClipboardDemo,
  'config-plugins': ConfigPluginsDemo,
  'constants': ConstantsDemo,
  'contacts': ContactsDemo,
  'crypto': CryptoDemo,
  'device': DeviceDemo,
  'expo-module-showcase': ExpoModulesDemo,
  'expo-modules-autolinking': ModulesAutolinkingDemo,
  'expo-modules-core': ModulesCoreDemo,
  'expo-router': RouterDemo,
  'expo-task-manager': TaskManagerDemo,
  'fetch': FetchDemo,
  'file-system': FileSystemDemo,
  'font': FontDemo,
  'haptics': HapticsDemo,
  'intent-launcher': IntentLauncherDemo,
  'keep-awake': KeepAwakeDemo,
  'linear-gradient': LinearGradientDemo,
  'linking': LinkingDemo,
  'live-photo': LivePhotoDemo,
  'location': LocationDemo,
  'metro-config': MetroConfigDemo,
  'navigation-bar': NavigationBarDemo,
  'network': NetworkDemo,
  'prebuild-config': PrebuildConfigDemo,
  'print': PrintDemo,
  'sharing': SharingDemo,
  'splash-screen': SplashScreenDemo,
  'system-ui': SystemUIDemo,
  'template': TemplateDemo,
} satisfies Record<ModuleId, ComponentType>;

export function ModuleDemo({ id }: { id: ModuleId }) {
  const Demo = MODULE_DEMOS[id];
  return <Demo />;
}

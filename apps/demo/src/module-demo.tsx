/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ComponentType } from 'react';

import type { ModuleId } from './catalog';
import { AgeRangeDemo } from './modules/age-range';
import { AppIntegrityDemo } from './modules/app-integrity';
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
import { ClipboardDemo } from './modules/clipboard';
import { ConstantsDemo } from './modules/constants';
import { ContactsDemo } from './modules/contacts';
import { CryptoDemo } from './modules/crypto';
import { DeviceDemo } from './modules/device';
import { DocumentPickerDemo } from './modules/document-picker';
import { ExpoModulesDemo } from './expoModules/ExpoModulesDemo';
import { ModulesCoreDemo } from './modules/expo-modules-core';
import { RouterDemo } from './modules/expo-router';
import { TaskManagerDemo } from './modules/expo-task-manager';
import { FetchDemo } from './modules/fetch';
import { FileSystemDemo } from './modules/file-system';
import { FontDemo } from './modules/font';
import { HapticsDemo } from './modules/haptics';
import { ImageDemo } from './modules/image';
import { ImageLoaderDemo } from './modules/image-loader';
import { ImageManipulatorDemo } from './modules/image-manipulator';
import { ImagePickerDemo } from './modules/image-picker';
import { IntentLauncherDemo } from './modules/intent-launcher';
import { KeepAwakeDemo } from './modules/keep-awake';
import { LinearGradientDemo } from './modules/linear-gradient';
import { LinkingDemo } from './modules/linking';
import { LivePhotoDemo } from './modules/live-photo';
import { LocalAuthenticationDemo } from './modules/local-authentication';
import { LocalizationDemo } from './modules/localization';
import { LocationDemo } from './modules/location';
import { MailComposerDemo } from './modules/mail-composer';
import { MediaLibraryDemo } from './modules/media-library';
import { MeshGradientDemo } from './modules/mesh-gradient';
import { NavigationBarDemo } from './modules/navigation-bar';
import { NetworkDemo } from './modules/network';
import { NotificationsDemo } from './modules/notifications';
import { PrintDemo } from './modules/print';
import { ScreenCaptureDemo } from './modules/screen-capture';
import { ScreenOrientationDemo } from './modules/screen-orientation';
import { SecureStoreDemo } from './modules/secure-store';
import { SensorsDemo } from './modules/sensors';
import { SharingDemo } from './modules/sharing';
import { SMSDemo } from './modules/sms';
import { SpeechDemo } from './modules/speech';
import { SplashScreenDemo } from './modules/splash-screen';
import { SQLiteDemo } from './modules/sqlite';
import { StatusBarDemo } from './modules/status-bar';
import { StoreReviewDemo } from './modules/store-review';
import { VideoDemo } from './modules/video';
import { VideoThumbnailsDemo } from './modules/video-thumbnails';
import { SystemUIDemo } from './modules/system-ui';
import { SymbolsDemo } from './modules/symbols';
import { TrackingTransparencyDemo } from './modules/tracking-transparency';
import { WebBrowserDemo } from './modules/web-browser';

import { UpdatesDemo } from './modules/updates';
import { ExpoDemo } from './modules/expo';
import { EASClientDemo } from './modules/eas-client';
import { ManifestsDemo } from './modules/manifests';
import { JSONUtilsDemo } from './modules/json-utils';
import { StructuredHeadersDemo } from './modules/structured-headers';
import { UpdatesInterfaceDemo } from './modules/updates-interface';
import { DevToolsDemo } from './modules/devtools';
import { DevMenuDemo } from './modules/dev-menu';
import { DomWebViewDemo } from './modules/dom-webview';
import { LogBoxDemo } from './modules/log-box';

const MODULE_DEMOS = {
  'age-range': AgeRangeDemo,
  'app-integrity': AppIntegrityDemo,
  'devtools': DevToolsDemo,
  'dev-menu': DevMenuDemo,
  'dom-webview': DomWebViewDemo,
  'log-box': LogBoxDemo,
  'expo': ExpoDemo,
  'eas-client': EASClientDemo,
  'manifests': ManifestsDemo,
  'json-utils': JSONUtilsDemo,
  'structured-headers': StructuredHeadersDemo,
  'updates-interface': UpdatesInterfaceDemo,
  'updates': UpdatesDemo,
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
  'clipboard': ClipboardDemo,
  'constants': ConstantsDemo,
  'contacts': ContactsDemo,
  'crypto': CryptoDemo,
  'device': DeviceDemo,
  'document-picker': DocumentPickerDemo,
  'expo-module-showcase': ExpoModulesDemo,
  'expo-modules-core': ModulesCoreDemo,
  'expo-router': RouterDemo,
  'expo-task-manager': TaskManagerDemo,
  'fetch': FetchDemo,
  'file-system': FileSystemDemo,
  'font': FontDemo,
  'haptics': HapticsDemo,
  'image': ImageDemo,
  'image-loader': ImageLoaderDemo,
  'image-manipulator': ImageManipulatorDemo,
  'image-picker': ImagePickerDemo,
  'intent-launcher': IntentLauncherDemo,
  'keep-awake': KeepAwakeDemo,
  'linear-gradient': LinearGradientDemo,
  'linking': LinkingDemo,
  'live-photo': LivePhotoDemo,
  'local-authentication': LocalAuthenticationDemo,
  'localization': LocalizationDemo,
  'location': LocationDemo,
  'mail-composer': MailComposerDemo,
  'media-library': MediaLibraryDemo,
  'mesh-gradient': MeshGradientDemo,
  'navigation-bar': NavigationBarDemo,
  'network': NetworkDemo,
  'notifications': NotificationsDemo,
  'print': PrintDemo,
  'screen-capture': ScreenCaptureDemo,
  'screen-orientation': ScreenOrientationDemo,
  'secure-store': SecureStoreDemo,
  'sensors': SensorsDemo,
  'sharing': SharingDemo,
  'sms': SMSDemo,
  'speech': SpeechDemo,
  'splash-screen': SplashScreenDemo,
  'sqlite': SQLiteDemo,
  'status-bar': StatusBarDemo,
  'store-review': StoreReviewDemo,
  'system-ui': SystemUIDemo,
  'video': VideoDemo,
  'video-thumbnails': VideoThumbnailsDemo,
  'symbols': SymbolsDemo,
  'tracking-transparency': TrackingTransparencyDemo,
  'web-browser': WebBrowserDemo,
} satisfies Record<ModuleId, ComponentType>;

export function ModuleDemo({ id }: { id: ModuleId }) {
  const Demo = MODULE_DEMOS[id];
  return <Demo />;
}

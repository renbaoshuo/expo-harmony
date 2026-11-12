/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoConstantsConfig } from './ExpoConstantsConfig';
import { ExpoModuleContext, ExpoService, ExpoServiceContext, ExpoServiceKey, ExpoServicesRegistry } from '@expo-harmony/expo-modules-core';
import { bundleManager } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';

const APP_CONFIG_RAW_FILE: string = 'app.config';
const INVALID_RAW_FILE_PATH: number = 9001005;

class HarmonyPlatformConstants {
  bundleName: string;
  versionName: string;
  versionCode: number;
  deviceType: string;
  apiVersion: number;
  osFullName: string;

  constructor(bundleName: string, versionName: string, versionCode: number, deviceType: string, apiVersion: number, osFullName: string) {
    this.bundleName = bundleName;
    this.versionName = versionName;
    this.versionCode = versionCode;
    this.deviceType = deviceType;
    this.apiVersion = apiVersion;
    this.osFullName = osFullName;
  }
}

class PlatformConstants {
  harmony: HarmonyPlatformConstants;

  constructor(harmony: HarmonyPlatformConstants) {
    this.harmony = harmony;
  }
}

export interface ExpoConstantsProvider {
  constants(context: ExpoModuleContext): Record<string, ESObject>;
}

export const ExpoConstantsKey = new ExpoServiceKey<ExpoConstantsProvider>('ExpoConstants');

class ExpoConstantsRuntime {
  readonly sessionId: string = util.generateRandomUUID();
  embeddedManifest?: string | null;
}

export class ExpoConstantsService extends ExpoService implements ExpoConstantsProvider {
  static readonly key = new ExpoServiceKey<ExpoConstantsService>('ExpoConstantsService');
  readonly identity = ExpoConstantsService.key.bind(this);
  readonly interfaces = [ExpoConstantsKey.bind(this)];
  private readonly config: ExpoConstantsConfig;
  private readonly runtimes = new WeakMap<ExpoServicesRegistry, ExpoConstantsRuntime>();

  constructor(context?: ExpoServiceContext, config: ExpoConstantsConfig = new ExpoConstantsConfig()) {
    super(context);
    this.config = config;
  }

  constants(context: ExpoModuleContext): Record<string, ESObject> {
    const isHeadless = context.isHeadless || this.config.isHeadless;
    const services = context.services;
    const cached = this.runtimes.get(services);
    const runtime = cached ?? new ExpoConstantsRuntime();
    if (cached === undefined) this.runtimes.set(services, runtime);

    return {
      'appOwnership': this.config.appOwnership,
      'debugMode': (): boolean => context.isDebug,
      'deviceName': deviceName(),
      'deviceYearClass': null,
      'executionEnvironment': this.config.executionEnvironment,
      'isHeadless': isHeadless,
      'manifest': (): string | null => this.manifest(context, runtime),
      'linkingUri': this.config.linkingUri ?? null,
      'experienceUrl': this.config.experienceUrl ?? null,
      'manifest2': null,
      'sessionId': runtime.sessionId,
      'statusBarHeight': (): number => isHeadless ? 0 : this.readStatusBarHeight(context),
      'systemFonts': (): string[] => isHeadless ? [] : this.readSystemFonts(context),
      'systemVersion': systemVersion(),
      'platform': (): PlatformConstants | undefined => this.readPlatformConstants(context),
    };
  }

  private manifest(context: ExpoModuleContext, runtime: ExpoConstantsRuntime): string | null {
    if (this.config.manifest !== undefined) return this.config.manifest;
    if (runtime.embeddedManifest === undefined) runtime.embeddedManifest = this.readAppConfig(context);
    return runtime.embeddedManifest;
  }

  private readAppConfig(context: ExpoModuleContext): string | null {
    try {
      const resources = context.uiAbilityContext.resourceManager;
      const bytes = resources.getRawFileContentSync(APP_CONFIG_RAW_FILE);

      const text = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true }).decodeToString(bytes);
      const value: ESObject = JSON.parse(text);
      if (value === null || typeof value !== 'object' || Array.isArray(value)) {
        throw new Error('The embedded Expo app config must be a JSON object.');
      }

      return text;
    } catch (error) {
      if ((error as BusinessError).code !== INVALID_RAW_FILE_PATH) {
        context.logger.warn(`Unable to read the embedded Expo app config; returning null: ${String(error)}`);
      }
      return null;
    }
  }

  private readStatusBarHeight(context: ExpoModuleContext): number {
    try {
      const stage = context.uiAbilityContext.windowStage;
      const mainWindow = stage.getMainWindowSync();
      const area = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const height = mainWindow.getUIContext().px2vp(area.topRect.height);

      return Number.isFinite(height) && height >= 0 ? height : 0;
    } catch (error) {
      context.logger.warn(`Unable to read the HarmonyOS status bar height; using 0: ${String(error)}`);
      return 0;
    }
  }

  private readSystemFonts(context: ExpoModuleContext): string[] {
    try {
      const names = context.uiAbilityContext.windowStage.getMainWindowSync().getUIContext().getFont().getSystemFontList();
      const unique = new Set<string>();
      names.forEach((name: string): void => {
        if (name.length > 0) unique.add(name);
      });

      return Array.from(unique).sort();
    } catch (error) {
      context.logger.warn(`Unable to enumerate HarmonyOS system fonts; returning an empty list: ${String(error)}`);
      return [];
    }
  }

  private readPlatformConstants(context: ExpoModuleContext): PlatformConstants | undefined {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      if (info.name.length === 0 || info.versionName.length === 0 || !Number.isSafeInteger(info.versionCode)) {
        throw new Error('HarmonyOS returned invalid bundle information.');
      }

      return new PlatformConstants(
        new HarmonyPlatformConstants(info.name, info.versionName, info.versionCode, deviceInfo.deviceType, deviceInfo.sdkApiVersion, deviceInfo.osFullName),
      );
    } catch (error) {
      context.logger.warn(`Unable to read HarmonyOS bundle information: ${String(error)}`);
      return undefined;
    }
  }
}

function deviceName(): string {
  if (deviceInfo.marketName.length > 0) return deviceInfo.marketName;
  if (deviceInfo.productModel.length > 0) return deviceInfo.productModel;
  if (deviceInfo.deviceType.length > 0) return `HarmonyOS ${deviceInfo.deviceType}`;
  return 'HarmonyOS device';
}

function systemVersion(): string {
  return deviceInfo.displayVersion;
}

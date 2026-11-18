/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { deviceInfo, systemDateTime } from '@kit.BasicServicesKit';
import lazy { settings } from '@kit.BasicServicesKit';
import lazy { hidebug } from '@kit.PerformanceAnalysisKit';

enum DeviceType {
  UNKNOWN = 0,
  PHONE = 1,
  TABLET = 2,
  DESKTOP = 3,
  TV = 4,
}

const BYTES_PER_KIBIBYTE: number = 1024;
const MEMORY_CAPABILITY = 'SystemCapability.HiviewDFX.HiProfiler.HiDebug';
const SETTINGS_CAPABILITY = 'SystemCapability.Applications.Settings.Core';
// Huawei documents this product model for DevEco Studio's emulator.
const EMULATOR_PRODUCT_MODEL = 'emulator';
const DEFAULT_INCREMENTAL_VERSION = 'default';

export class ExpoDeviceModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoDevice')
      .constant('isDevice', (): boolean => deviceInfo.productModel !== EMULATOR_PRODUCT_MODEL)
      .constant('brand', (): string | null => nonEmptyOrNull(deviceInfo.brand))
      .constant('manufacturer', (): string | null => nonEmptyOrNull(deviceInfo.manufacture))
      .constant('modelName', (): string | null => nonEmptyOrNull(deviceInfo.marketName) ?? nonEmptyOrNull(deviceInfo.productModel))
      .constant('modelId', (): string | null => nonEmptyOrNull(deviceInfo.productModel))
      .constant('designName', (): string | null => nonEmptyOrNull(deviceInfo.hardwareModel))
      .constant('productName', (): string | null => nonEmptyOrNull(deviceInfo.productSeries))
      .constant('deviceYearClass', null)
      .constant('totalMemory', (): number | null => this.totalMemory())
      .constant('deviceType', (): DeviceType => getDeviceType())
      .constant('supportedCpuArchitectures', (): string[] | null => {
        const list = nonEmptyOrNull(deviceInfo.abiList);
        if (list === null) return null;

        const abis = list
          .split(',')
          .map((abi: string): string => abi.trim())
          .filter((abi: string): boolean => abi.length > 0);

        return abis.length > 0 ? abis : null;
      })
      .constant('osName', (): string | null => nonEmptyOrNull(deviceInfo.distributionOSName))
      .constant('osVersion', (): string | null => nonEmptyOrNull(deviceInfo.distributionOSVersion))
      .constant('osBuildId', (): string | null => nonEmptyOrNull(deviceInfo.displayVersion))
      .constant('osInternalBuildId', (): string | null => {
        const version = deviceInfo.incrementalVersion;

        return (version === DEFAULT_INCREMENTAL_VERSION ? null : nonEmptyOrNull(version)) ?? nonEmptyOrNull(deviceInfo.osFullName);
      })
      .constant('osBuildFingerprint', (): string | null => nonEmptyOrNull(deviceInfo.versionId))
      .constant('platformApiLevel', (): number | null => positiveIntegerOrNull(deviceInfo.sdkApiVersion))
      .constant('deviceName', (): string | null => {
        if (!canIUse(SETTINGS_CAPABILITY)) return null;

        try {
          return nonEmptyOrNull(settings.getValueSync(this.context.uiAbilityContext, settings.general.DEVICE_NAME, ''));
        } catch {
          return null;
        }
      })
      .asyncFunction('getDeviceTypeAsync', async (): Promise<DeviceType> => getDeviceType())
      .asyncFunction('getUptimeAsync', async (): Promise<number> => {
        let uptime: number;

        try {
          uptime = systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE, false);
        } catch (error) {
          throw new ExpoModuleError('ERR_DEVICE_UPTIME', `Unable to read the HarmonyOS system uptime: ${String(error)}`, error as Object);
        }

        if (!Number.isSafeInteger(uptime) || uptime < 0) {
          throw new ExpoModuleError('ERR_DEVICE_UPTIME', 'HarmonyOS returned an invalid system uptime.');
        }

        return uptime;
      })
      .asyncFunction('getMaxMemoryAsync', async (): Promise<number> => {
        if (!canIUse(MEMORY_CAPABILITY)) {
          throw new ExpoModuleError('ERR_DEVICE_MAX_MEMORY', 'This HarmonyOS device does not expose the ArkTS heap limit.');
        }

        let limit: bigint;

        try {
          limit = hidebug.getAppMemoryLimit().vmHeapLimit;
        } catch (error) {
          throw new ExpoModuleError('ERR_DEVICE_MAX_MEMORY', 'Unable to read the HarmonyOS ArkTS heap limit.', error as Object);
        }

        const bytes = kibibytesToBytes(limit);
        if (bytes === null) {
          throw new ExpoModuleError('ERR_DEVICE_MAX_MEMORY', 'HarmonyOS returned an invalid ArkTS heap limit.');
        }

        return bytes;
      })
      .asyncFunction('hasPlatformFeatureAsync', ExpoFunction.typed1(
        ExpoValueTypes.string(),
        async (feature: string): Promise<boolean> => feature.length > 0 && canIUse(feature),
      ));
  }

  private totalMemory(): number | null {
    if (!canIUse(MEMORY_CAPABILITY)) return null;

    try {
      return kibibytesToBytes(hidebug.getSystemMemInfo().totalMem);
    } catch (error) {
      this.context.logger.warn(`Unable to read HarmonyOS total memory: ${String(error)}`);

      return null;
    }
  }
}

function positiveIntegerOrNull(value: number): number | null {
  return Number.isSafeInteger(value) && value > 0 ? value : null;
}

function kibibytesToBytes(value: bigint): number | null {
  return positiveIntegerOrNull(Number(value) * BYTES_PER_KIBIBYTE);
}

function nonEmptyOrNull(value: string): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value : null;
}

function getDeviceType(): DeviceType {
  // The SDK's DeviceTypes enum requires API 20; these values also work on API 13.
  switch (deviceInfo.deviceType) {
    case 'phone':
      return DeviceType.PHONE;
    case 'tablet':
      return DeviceType.TABLET;
    case '2in1':
      return DeviceType.DESKTOP;
    case 'tv':
      return DeviceType.TV;
    default:
      return DeviceType.UNKNOWN;
  }
}

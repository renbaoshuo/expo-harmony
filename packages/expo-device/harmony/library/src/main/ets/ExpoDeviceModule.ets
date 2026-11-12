/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { deviceInfo, settings, systemDateTime } from '@kit.BasicServicesKit';
import { hidebug } from '@kit.PerformanceAnalysisKit';

enum DeviceType {
  UNKNOWN = 0,
  PHONE = 1,
  TABLET = 2,
  DESKTOP = 3,
  TV = 4,
}

const BYTES_PER_KIBIBYTE: number = 1024;

export class ExpoDeviceModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoDevice')
      .constant('isDevice', true)
      .constant('brand', (): string | null => nonEmptyOrNull(deviceInfo.brand))
      .constant('manufacturer', (): string | null => nonEmptyOrNull(deviceInfo.manufacture))
      .constant('modelName', (): string | null => {
        return nonEmptyOrNull(deviceInfo.marketName) ?? nonEmptyOrNull(deviceInfo.productModel);
      })
      .constant('modelId', (): string | null => nonEmptyOrNull(deviceInfo.productModel))
      .constant('designName', null)
      .constant('productName', null)
      .constant('deviceYearClass', null)
      .constant('totalMemory', (): number | null => this.totalMemory())
      .constant('deviceType', (): DeviceType => getDeviceType())
      .constant('supportedCpuArchitectures', (): string[] | null => {
        const abis = deviceInfo.abiList
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
        // HarmonyOS can report this placeholder before a commercial release.
        return version === 'default' ? null : nonEmptyOrNull(version);
      })
      .constant('osBuildFingerprint', (): string | null => nonEmptyOrNull(deviceInfo.versionId))
      .constant('platformApiLevel', null)
      .constant('deviceName', (): string | null => {
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
      });
  }

  private totalMemory(): number | null {
    try {
      const memory = hidebug.getSystemMemInfo();

      const bytes = Number(memory.totalMem) * BYTES_PER_KIBIBYTE;

      return Number.isSafeInteger(bytes) && bytes > 0 ? bytes : null;
    } catch (error) {
      this.context.logger.warn(`Unable to read HarmonyOS total memory: ${String(error)}`);

      return null;
    }
  }
}

function nonEmptyOrNull(value: string): string | null {
  return value.length > 0 ? value : null;
}

function getDeviceType(): DeviceType {
  // The SDK's DeviceTypes enum requires API 20; these values also work on API 13.
  switch (deviceInfo.deviceType) {
    case 'default':
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

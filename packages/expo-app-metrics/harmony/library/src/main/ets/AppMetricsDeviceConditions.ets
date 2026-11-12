/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { batteryInfo, deviceInfo, power, thermal } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';

/** Missing readings stay absent; no permission or system failure is reported as a measurement. */
export function readDeviceConditions(warn: (message: string) => void): Record<string, ESObject> {
  const readings: Record<string, ESObject> = {};

  try {
    if (canIUse('SystemCapability.PowerManager.PowerManager.Core')) {
      const mode = power.getPowerMode();
      readings['expo.device.lowPowerMode'] = mode === power.DevicePowerMode.MODE_POWER_SAVE
        || mode === power.DevicePowerMode.MODE_EXTREME_POWER_SAVE
        || (deviceInfo.sdkApiVersion >= 20 && mode === power.DevicePowerMode.MODE_CUSTOM_POWER_SAVE);
    }
  } catch (error) { warn(`Unable to read power mode for Expo App Metrics: ${String(error)}`); }

  try {
    if (canIUse('SystemCapability.PowerManager.BatteryManager.Core')) {
      const level = batteryInfo.batterySOC;
      if (Number.isFinite(level) && level >= 0 && level <= 100) readings['expo.device.batteryLevel'] = level / 100;
      const state = batteryInfo.chargingStatus;
      if (state !== batteryInfo.BatteryChargeState.NONE) {
        readings['expo.device.batteryCharging'] = state === batteryInfo.BatteryChargeState.ENABLE || state === batteryInfo.BatteryChargeState.FULL;
      }
    }
  } catch (error) { warn(`Unable to read battery state for Expo App Metrics: ${String(error)}`); }

  try {
    if (canIUse('SystemCapability.PowerManager.ThermalManager')) {
      readings['expo.device.thermalState'] = thermalState(thermal.getLevel());
    }
  } catch (error) { warn(`Unable to read thermal state for Expo App Metrics: ${String(error)}`); }

  try {
    if (canIUse('SystemCapability.Communication.NetManager.Core')) {
      const handle = connection.getDefaultNetSync();
      if (handle.netId === 0) {
        readings['expo.network.connected'] = false;
        readings['expo.network.type'] = 'none';
      } else if (handle.netId > 0) {
        const caps = connection.getNetCapabilitiesSync(handle);
        const bearers = caps.bearerTypes;
        if (caps.networkCap !== undefined) {
          readings['expo.network.connected'] = caps.networkCap.includes(connection.NetCap.NET_CAPABILITY_INTERNET);
        }
        readings['expo.network.type'] = bearers.includes(connection.NetBearType.BEARER_WIFI) ? 'wifi'
          : bearers.includes(connection.NetBearType.BEARER_CELLULAR) ? 'cellular'
          : bearers.includes(connection.NetBearType.BEARER_ETHERNET) ? 'ethernet' : 'other';
      }
    }
  } catch (error) { warn(`Unable to read network state for Expo App Metrics: ${String(error)}`); }

  return readings;
}

function thermalState(level: thermal.ThermalLevel): string {
  switch (level) {
    case thermal.ThermalLevel.COOL:
    case thermal.ThermalLevel.NORMAL: return 'nominal';
    case thermal.ThermalLevel.WARM: return 'fair';
    case thermal.ThermalLevel.HOT:
    case thermal.ThermalLevel.OVERHEATED: return 'serious';
    case thermal.ThermalLevel.WARNING:
    case thermal.ThermalLevel.EMERGENCY:
    case thermal.ThermalLevel.ESCAPE: return 'critical';
    default: return 'unknown';
  }
}

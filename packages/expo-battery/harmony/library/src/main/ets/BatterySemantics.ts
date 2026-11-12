/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { batteryInfo } from '@kit.BasicServicesKit';

export const UNKNOWN_BATTERY_LEVEL: number = -1;

const BATTERY_PERCENT_SCALE: number = 100;

export class ExpoBatteryState {
  static readonly UNKNOWN: number = 0;
  static readonly UNPLUGGED: number = 1;
  static readonly CHARGING: number = 2;
  static readonly FULL: number = 3;
  static readonly NOT_CHARGING: number = 4;
}

export type ExpoBatteryStateValue = number;

export function batteryLevelFromSoc(soc: number): number {
  if (!Number.isFinite(soc) || soc < 0 || soc > BATTERY_PERCENT_SCALE) {
    return UNKNOWN_BATTERY_LEVEL;
  }

  return soc / BATTERY_PERCENT_SCALE;
}

export function batteryStateFromChargeState(
  state: batteryInfo.BatteryChargeState,
  plugged: batteryInfo.BatteryPluggedType,
): ExpoBatteryStateValue {
  if (state === batteryInfo.BatteryChargeState.NONE) return ExpoBatteryState.UNPLUGGED;
  if (state === batteryInfo.BatteryChargeState.ENABLE) return ExpoBatteryState.CHARGING;

  if (state === batteryInfo.BatteryChargeState.DISABLE) {
    // DISABLE also covers charging paused by battery protection while plugged in.
    if (plugged === batteryInfo.BatteryPluggedType.NONE) return ExpoBatteryState.UNPLUGGED;
    if (plugged === batteryInfo.BatteryPluggedType.AC || plugged === batteryInfo.BatteryPluggedType.USB
      || plugged === batteryInfo.BatteryPluggedType.WIRELESS) return ExpoBatteryState.NOT_CHARGING;

    return ExpoBatteryState.UNKNOWN;
  }

  if (state === batteryInfo.BatteryChargeState.FULL) return ExpoBatteryState.FULL;

  return ExpoBatteryState.UNKNOWN;
}

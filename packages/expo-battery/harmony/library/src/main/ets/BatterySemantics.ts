import { batteryInfo } from '@kit.BasicServicesKit';

export const UNKNOWN_BATTERY_LEVEL: number = -1;

const BATTERY_PERCENT_SCALE: number = 100;

export class ExpoBatteryState {
  static readonly UNKNOWN: number = 0;
  static readonly UNPLUGGED: number = 1;
  static readonly CHARGING: number = 2;
  static readonly FULL: number = 3;
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
): ExpoBatteryStateValue {
  if (state === batteryInfo.BatteryChargeState.ENABLE) return ExpoBatteryState.CHARGING;
  if (state === batteryInfo.BatteryChargeState.DISABLE) return ExpoBatteryState.UNPLUGGED;
  if (state === batteryInfo.BatteryChargeState.FULL) return ExpoBatteryState.FULL;

  return ExpoBatteryState.UNKNOWN;
}

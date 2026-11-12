/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { BusinessError } from '@kit.BasicServicesKit';
import { call, data, radio, sim, sms } from '@kit.TelephonyKit';

enum CellularGeneration {
  UNKNOWN = 0,
  CELLULAR_2G = 1,
  CELLULAR_3G = 2,
  CELLULAR_4G = 3,
  CELLULAR_5G = 4,
}

enum SimField {
  ISO_COUNTRY_CODE,
  CARRIER_NAME,
  OPERATOR_NUMERIC,
}

const PERMISSION_DENIED: number = 201;
const CAPABILITY_NOT_SUPPORTED: number = 801;
const NO_SIM_CARD: number = 8300004;
const NO_DEFAULT_SLOT: number = -1;
const MOBILE_COUNTRY_CODE_LENGTH: number = 3;
const TELEPHONY_CORE_CAPABILITY: string = 'SystemCapability.Telephony.CoreService';
const CELLULAR_DATA_CAPABILITY: string = 'SystemCapability.Telephony.CellularData';
const CALL_MANAGER_CAPABILITY: string = 'SystemCapability.Telephony.CallManager';
const SMS_CAPABILITY: string = 'SystemCapability.Telephony.SmsMms';

export class ExpoCellularModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoCellular')
      .asyncFunction('getCellularGenerationAsync', async (): Promise<CellularGeneration> => {
        return await this.getCellularGeneration();
      })
      .asyncFunction('allowsVoipAsync', async (): Promise<boolean | null> => {
        return null;
      })
      .asyncFunction('getIsoCountryCodeAsync', async (): Promise<string | null> => {
        const value = await this.readSimValue(SimField.ISO_COUNTRY_CODE);

        return value?.toLowerCase() ?? null;
      })
      .asyncFunction('getCarrierNameAsync', async (): Promise<string | null> => {
        return await this.readSimValue(SimField.CARRIER_NAME);
      })
      .asyncFunction('getMobileCountryCodeAsync', async (): Promise<string | null> => {
        const operator = await this.readSimOperator();

        return operator?.slice(0, MOBILE_COUNTRY_CODE_LENGTH) ?? null;
      })
      .asyncFunction('getMobileNetworkCodeAsync', async (): Promise<string | null> => {
        const operator = await this.readSimOperator();

        return operator?.slice(MOBILE_COUNTRY_CODE_LENGTH) ?? null;
      });
  }

  private async getCellularGeneration(): Promise<CellularGeneration> {
    try {
      if (canIUse(TELEPHONY_CORE_CAPABILITY)) {
        if (canIUse(CELLULAR_DATA_CAPABILITY)) {
          const slot = await data.getDefaultCellularDataSlotId();

          if (!(await this.isSimReady(slot))) return CellularGeneration.UNKNOWN;

          const tech = await radio.getRadioTech(slot);

          switch (tech.psRadioTech) {
            case radio.RadioTechnology.RADIO_TECHNOLOGY_GSM:
            case radio.RadioTechnology.RADIO_TECHNOLOGY_1XRTT:
              return CellularGeneration.CELLULAR_2G;
            case radio.RadioTechnology.RADIO_TECHNOLOGY_WCDMA:
            case radio.RadioTechnology.RADIO_TECHNOLOGY_HSPA:
            case radio.RadioTechnology.RADIO_TECHNOLOGY_HSPAP:
            case radio.RadioTechnology.RADIO_TECHNOLOGY_TD_SCDMA:
            case radio.RadioTechnology.RADIO_TECHNOLOGY_EVDO:
            case radio.RadioTechnology.RADIO_TECHNOLOGY_EHRPD:
              return CellularGeneration.CELLULAR_3G;
            case radio.RadioTechnology.RADIO_TECHNOLOGY_LTE:
            case radio.RadioTechnology.RADIO_TECHNOLOGY_LTE_CA:
              return CellularGeneration.CELLULAR_4G;
            case radio.RadioTechnology.RADIO_TECHNOLOGY_NR:
              return CellularGeneration.CELLULAR_5G;
            default:
              return CellularGeneration.UNKNOWN;
          }
        }
      }

      return CellularGeneration.UNKNOWN;
    } catch (error) {
      const code = (error as BusinessError).code;

      if (code === PERMISSION_DENIED || code === CAPABILITY_NOT_SUPPORTED || code === NO_SIM_CARD) {
        return CellularGeneration.UNKNOWN;
      }

      throw new ExpoModuleError('ERR_CELLULAR_GENERATION', 'Unable to query HarmonyOS cellular radio technology.', error as Object);
    }
  }

  private async readSimValue(field: SimField): Promise<string | null> {
    try {
      if (canIUse(TELEPHONY_CORE_CAPABILITY)) {
        const slot = field === SimField.OPERATOR_NUMERIC
          ? await this.getOperatorSlot()
          : await this.getDefaultSubscriptionSlot();

        if (!(await this.isSimReady(slot))) return null;

        let value: string;

        switch (field) {
          case SimField.ISO_COUNTRY_CODE:
            value = await sim.getISOCountryCodeForSim(slot);
            break;
          case SimField.CARRIER_NAME:
            value = await sim.getSimSpn(slot);
            break;
          case SimField.OPERATOR_NUMERIC:
            value = await sim.getSimOperatorNumeric(slot);
            break;
        }

        return value.length > 0 ? value : null;
      }

      return null;
    } catch (error) {
      const code = (error as BusinessError).code;

      if (code === CAPABILITY_NOT_SUPPORTED || code === NO_SIM_CARD) return null;

      throw new ExpoModuleError('ERR_CELLULAR_SIM', 'Unable to query HarmonyOS SIM information.', error as Object);
    }
  }

  private async readSimOperator(): Promise<string | null> {
    const operator = await this.readSimValue(SimField.OPERATOR_NUMERIC);

    return operator !== null && /^\d{5,6}$/.test(operator) ? operator : null;
  }

  private async getOperatorSlot(): Promise<number> {
    // AOSP resolves PLMN through data/SMS/voice defaults, unlike SPN and country code.
    if (canIUse(TELEPHONY_CORE_CAPABILITY)) {
      const count = sim.getMaxSimCount();

      if (canIUse(CELLULAR_DATA_CAPABILITY)) {
        const slot = await readDefaultSlot(() => data.getDefaultCellularDataSlotId());

        if (isValidSlot(slot, count)) return slot;
      }

      if (canIUse(SMS_CAPABILITY)) {
        const slot = await readDefaultSlot(() => sms.getDefaultSmsSlotId());

        if (isValidSlot(slot, count)) return slot;
      }

      return await readDefaultSlot(() => sim.getDefaultVoiceSlotId());
    }

    return NO_DEFAULT_SLOT;
  }

  private async getDefaultSubscriptionSlot(): Promise<number> {
    if (canIUse(TELEPHONY_CORE_CAPABILITY)) {
      if (canIUse(CALL_MANAGER_CAPABILITY) && call.hasVoiceCapability()) {
        const slot = await readDefaultSlot(() => sim.getDefaultVoiceSlotId());

        if (isValidSlot(slot, sim.getMaxSimCount())) return slot;
      }

      if (canIUse(CELLULAR_DATA_CAPABILITY)) return await data.getDefaultCellularDataSlotId();
    }

    return NO_DEFAULT_SLOT;
  }

  private async isSimReady(slot: number): Promise<boolean> {
    if (canIUse(TELEPHONY_CORE_CAPABILITY) && isValidSlot(slot, sim.getMaxSimCount())) {
      const state = await sim.getSimState(slot);

      return state === sim.SimState.SIM_STATE_READY || state === sim.SimState.SIM_STATE_LOADED;
    }

    return false;
  }
}

async function readDefaultSlot(getSlot: () => Promise<number>): Promise<number> {
  try {
    return await getSlot();
  } catch (error) {
    const code = (error as BusinessError).code;

    // TelephonyKit can reject a default voice or SMS lookup with -1 when no slot is available.
    if (code === NO_DEFAULT_SLOT || code === CAPABILITY_NOT_SUPPORTED || code === NO_SIM_CARD) {
      return NO_DEFAULT_SLOT;
    }

    throw error as Error;
  }
}

function isValidSlot(slot: number, count: number): boolean {
  return Number.isInteger(slot) && slot >= 0 && slot < count;
}

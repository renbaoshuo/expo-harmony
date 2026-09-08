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
const NO_SIM_CARD: number = 8300004;
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
        // Upstream first gates on the default SIM, then reads the data subscription.
        if ((await this.getReadyDefaultSlot()) === null) return CellularGeneration.UNKNOWN;

        if (canIUse(CELLULAR_DATA_CAPABILITY)) {
          const slot = await data.getDefaultCellularDataSlotId();
          if (!isValidSlot(slot, sim.getMaxSimCount())) return CellularGeneration.UNKNOWN;

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
      if (code === PERMISSION_DENIED || code === NO_SIM_CARD) return CellularGeneration.UNKNOWN;

      throw new ExpoModuleError('ERR_CELLULAR_GENERATION', 'Unable to query HarmonyOS cellular radio technology.', error as Object);
    }
  }

  private async readSimValue(field: SimField): Promise<string | null> {
    try {
      if (canIUse(TELEPHONY_CORE_CAPABILITY)) {
        const slot = await this.getReadyDefaultSlot();
        if (slot === null) return null;

        let value: string;
        switch (field) {
          case SimField.ISO_COUNTRY_CODE:
            value = await sim.getISOCountryCodeForSim(slot);
            break;
          case SimField.CARRIER_NAME:
            value = await sim.getSimSpn(slot);
            break;
          case SimField.OPERATOR_NUMERIC:
            value = await sim.getSimOperatorNumeric(await this.getOperatorSlot(slot));
            break;
        }

        return value.length > 0 ? value : null;
      }

      return null;
    } catch (error) {
      if ((error as BusinessError).code === NO_SIM_CARD) return null;

      throw new ExpoModuleError('ERR_CELLULAR_SIM', 'Unable to query HarmonyOS SIM information.', error as Object);
    }
  }

  private async readSimOperator(): Promise<string | null> {
    const operator = await this.readSimValue(SimField.OPERATOR_NUMERIC);

    return operator !== null && /^\d{5,6}$/.test(operator) ? operator : null;
  }

  private async getOperatorSlot(fallback: number): Promise<number> {
    // AOSP getSimOperatorNumeric prefers data, SMS, voice, then the default subscription.
    // This differs from getSimOperatorName / getSimCountryIso on a dual-SIM device.
    if (canIUse(TELEPHONY_CORE_CAPABILITY)) {
      const count = sim.getMaxSimCount();

      if (canIUse(CELLULAR_DATA_CAPABILITY)) {
        const slot = await data.getDefaultCellularDataSlotId();
        if (isValidSlot(slot, count)) return slot;
      }

      if (canIUse(SMS_CAPABILITY)) {
        const slot = await sms.getDefaultSmsSlotId();
        if (isValidSlot(slot, count)) return slot;
      }

      const slot = await sim.getDefaultVoiceSlotId();
      if (isValidSlot(slot, count)) return slot;
    }

    return fallback;
  }

  private async getReadyDefaultSlot(): Promise<number | null> {
    if (canIUse(TELEPHONY_CORE_CAPABILITY)) {
      let voice: boolean = false;
      if (canIUse(CALL_MANAGER_CAPABILITY)) {
        voice = call.hasVoiceCapability();
      }

      // Android's default subscription uses voice on voice-capable devices, data otherwise.
      let slot: number | null = null;
      if (voice) {
        slot = await sim.getDefaultVoiceSlotId();
      } else if (canIUse(CELLULAR_DATA_CAPABILITY)) {
        slot = await data.getDefaultCellularDataSlotId();
      }

      if (slot === null || !isValidSlot(slot, sim.getMaxSimCount())) return null;

      const state = await sim.getSimState(slot);

      return state === sim.SimState.SIM_STATE_READY || state === sim.SimState.SIM_STATE_LOADED ? slot : null;
    }

    return null;
  }
}

function isValidSlot(slot: number, count: number): boolean {
  return Number.isInteger(slot) && slot >= 0 && slot < count;
}

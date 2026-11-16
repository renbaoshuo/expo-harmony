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
  ExpoValueType,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { minorsProtection } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';

interface Response {
  lowerBound: number | null;
  upperBound: number | null;
}

const CAPABILITY: string = 'SystemCapability.AuthenticationServices.HuaweiID.MinorsProtection';

const YOUTH_MODE_AGE_LIMIT: number = 18;

const REQUEST: ExpoValueType<Object> = ExpoValueTypes.custom<Object>(
  'Any',
  (value: ESObject, path: string): Object => {
    if (value === null) {
      throw new ExpoModuleError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected a non-null value.`, undefined, path);
    }
    return value;
  },
  (value: Object): ESObject => value,
);

export class ExpoAgeRangeModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoAgeRange')
      .asyncFunction(
        'requestAgeRangeAsync',
        ExpoFunction.typed1(REQUEST, (_options: Object): Promise<Response> => this.request()),
      )
      // Unknown is different from a confirmed absence of age-assurance obligations.
      .asyncFunction('isEligibleForAgeFeaturesAsync', async (): Promise<boolean | null> => null);
  }

  private async request(): Promise<Response> {
    let supported = false;
    let info: minorsProtection.MinorsProtectionInfo | undefined;
    try {
      supported = canIUse(CAPABILITY) && minorsProtection.supportMinorsMode();
      if (supported) info = await minorsProtection.getMinorsProtectionInfo();
    } catch (error) {
      const failure = error as BusinessError | undefined;
      const code = failure?.code;
      const message = failure?.message;

      throw new ExpoModuleError(
        typeof code === 'number' && Number.isSafeInteger(code) ? String(code) : 'ERR_AGE_RANGE_REQUEST_FAILED',
        typeof message === 'string' && message.length > 0 ? message : 'Failed to request the age range from HarmonyOS.',
        failure,
      );
    }

    if (!supported) {
      throw new ExpoModuleError('ERR_AGE_RANGE_NOT_AVAILABLE', 'The Age Range service is not available');
    }
    if (typeof info?.minorsProtectionMode !== 'boolean') {
      throw new ExpoModuleError('ERR_AGE_RANGE_UNKNOWN_RESPONSE', 'The Age Range service returned invalid youth mode information');
    }

    const group = info.ageGroup;
    if (!info.minorsProtectionMode || group === undefined || group === null) {
      return { lowerBound: null, upperBound: null };
    }

    const lower = group.lowerAge;
    const upper = group.upperAge;
    if (!Number.isInteger(lower) || !Number.isInteger(upper)
      || lower < 0 || upper <= lower || upper > YOUTH_MODE_AGE_LIMIT) {
      throw new ExpoModuleError('ERR_AGE_RANGE_UNKNOWN_RESPONSE', 'The Age Range service returned invalid age bounds');
    }

    // Account Kit reports an exclusive upper bound.
    return { lowerBound: lower, upperBound: upper - 1 };
  }
}

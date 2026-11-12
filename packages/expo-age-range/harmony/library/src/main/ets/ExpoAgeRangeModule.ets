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

const AGE_GROUP_BOUNDARIES: number[] = [0, 3, 8, 12, 16, 18];

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
    if (canIUse(CAPABILITY)) {
      try {
        if (minorsProtection.supportMinorsMode()) {
          const info = await minorsProtection.getMinorsProtectionInfo();
          if (typeof info?.minorsProtectionMode !== 'boolean') {
            throw new ExpoModuleError('ERR_AGE_RANGE_UNKNOWN_RESPONSE', 'The Age Range service returned invalid youth mode information');
          }

          const group = info.ageGroup;
          // Disabled youth mode does not prove adulthood.
          if (!info.minorsProtectionMode || group === undefined || group === null) {
            return { lowerBound: null, upperBound: null };
          }

          const lower = AGE_GROUP_BOUNDARIES.indexOf(group.lowerAge);
          const upper = AGE_GROUP_BOUNDARIES.indexOf(group.upperAge);
          if (lower < 0 || upper !== lower + 1) {
            throw new ExpoModuleError('ERR_AGE_RANGE_UNKNOWN_RESPONSE', 'The Age Range service returned invalid age bounds');
          }

          // Convert Account Kit's exclusive upper age to the last whole year in the group.
          return { lowerBound: group.lowerAge, upperBound: group.upperAge - 1 };
        }
      } catch (error) {
        if (error instanceof ExpoModuleError) throw error;

        const failure = error as BusinessError | undefined;

        throw new ExpoModuleError(
          failure?.code?.toString() || 'ERR_AGE_RANGE_REQUEST_FAILED',
          failure?.message || 'Failed to request the age range from HarmonyOS.',
          failure,
        );
      }
    }

    throw new ExpoModuleError('ERR_AGE_RANGE_NOT_AVAILABLE', 'The Age Range service is not available');
  }
}

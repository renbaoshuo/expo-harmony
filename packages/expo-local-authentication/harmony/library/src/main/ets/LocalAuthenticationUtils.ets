/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { BusinessError } from '@kit.BasicServicesKit';
import { userAuth } from '@kit.UserAuthenticationKit';

const AUTHENTICATION_CAPABILITY: string = 'SystemCapability.UserIAM.UserAuth.Core';
const PERMISSION_DENIED: number = 201;

export enum AuthenticationType {
  FINGERPRINT = 1,
  FACIAL_RECOGNITION = 2,
}

export enum SecurityLevel {
  NONE = 0,
  SECRET = 1,
  BIOMETRIC_WEAK = 2,
  BIOMETRIC_STRONG = 3,
}

export const BIOMETRIC_TYPES: userAuth.UserAuthType[] = [userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.FACE];
export const WEAK_TRUST_LEVEL: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL2;
export const STRONG_TRUST_LEVEL: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL3;

export interface LocalAuthenticationResult {
  success: boolean;
  error?: string;
  warning?: string;
}

export function availability(type: userAuth.UserAuthType, level: userAuth.AuthTrustLevel): userAuth.UserAuthResultCode {
  if (!canIUse(AUTHENTICATION_CAPABILITY)) return userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT;

  try {
    userAuth.getAvailableStatus(type, level);
    return userAuth.UserAuthResultCode.SUCCESS;
  } catch (error) {
    const failure = error as BusinessError;
    const code = failure.code;

    switch (code) {
      case userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT:
      case userAuth.UserAuthResultCode.TRUST_LEVEL_NOT_SUPPORT:
      case userAuth.UserAuthResultCode.NOT_ENROLLED:
      case userAuth.UserAuthResultCode.LOCKED:
      case userAuth.UserAuthResultCode.PIN_EXPIRED:
        return code;
      default:
        throw new ExpoModuleError('ERR_LOCAL_AUTHENTICATION_UNAVAILABLE', `Unable to query authentication capability (${code}).`, failure);
    }
  }
}

export function isEnrolled(status: userAuth.UserAuthResultCode): boolean {
  return status === userAuth.UserAuthResultCode.SUCCESS || status === userAuth.UserAuthResultCode.LOCKED;
}

export function supportedAuthenticationTypes(): AuthenticationType[] {
  const types: AuthenticationType[] = [];

  for (const type of BIOMETRIC_TYPES) {
    const status = availability(type, userAuth.AuthTrustLevel.ATL1);

    if (status !== userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT) {
      types.push(type === userAuth.UserAuthType.FINGERPRINT ? AuthenticationType.FINGERPRINT : AuthenticationType.FACIAL_RECOGNITION);
    }
  }

  return types;
}

export function hasEnrolledBiometrics(level: userAuth.AuthTrustLevel): boolean {
  return BIOMETRIC_TYPES.some((type: userAuth.UserAuthType): boolean => isEnrolled(availability(type, level)));
}

export function authenticationResult(code: number): LocalAuthenticationResult {
  switch (code) {
    case userAuth.UserAuthResultCode.SUCCESS:
      return { success: true };
    case userAuth.UserAuthResultCode.FAIL:
      return { success: false, error: 'authentication_failed' };
    case userAuth.UserAuthResultCode.CANCELED:
    case userAuth.UserAuthResultCode.CANCELED_FROM_WIDGET:
      return { success: false, error: 'user_cancel' };
    case userAuth.UserAuthResultCode.TIMEOUT:
      return { success: false, error: 'timeout' };
    case userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT:
    case userAuth.UserAuthResultCode.TRUST_LEVEL_NOT_SUPPORT:
    case userAuth.UserAuthResultCode.PIN_EXPIRED:
    case PERMISSION_DENIED:
      return { success: false, error: 'not_available' };
    case userAuth.UserAuthResultCode.LOCKED:
      return { success: false, error: 'lockout' };
    case userAuth.UserAuthResultCode.NOT_ENROLLED:
      return { success: false, error: 'not_enrolled' };
    case userAuth.UserAuthResultCode.GENERAL_ERROR:
    case userAuth.UserAuthResultCode.BUSY:
      return { success: false, error: 'unable_to_process' };
    default:
      return { success: false, error: 'unknown', warning: `HarmonyOS authentication error (${code}).` };
  }
}

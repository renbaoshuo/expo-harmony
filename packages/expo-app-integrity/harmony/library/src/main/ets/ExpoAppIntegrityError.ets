/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { BusinessError } from '@kit.BasicServicesKit';
import { huks } from '@kit.UniversalKeystoreKit';

export enum IntegrityErrorCode {
  FEATURE_UNSUPPORTED = 'ERR_APP_INTEGRITY_FEATURE_UNSUPPORTED',
  API_NOT_AVAILABLE = 'ERR_APP_INTEGRITY_API_NOT_AVAILABLE',
  INVALID_INPUT = 'ERR_APP_INTEGRITY_INVALID_INPUT',
  HARDWARE_NOT_SUPPORTED = 'ERR_APP_INTEGRITY_HARDWARE_ATTESTATION_NOT_SUPPORTED',
  KEY_GENERATION_FAILED = 'ERR_APP_INTEGRITY_HARDWARE_ATTESTATION_KEY_GENERATION_FAILED',
  ATTESTATION_FAILED = 'ERR_APP_INTEGRITY_HARDWARE_ATTESTATION_FAILED',
  CERTIFICATE_CHAIN_INVALID = 'ERR_APP_INTEGRITY_HARDWARE_ATTESTATION_CERTIFICATE_CHAIN_INVALID',
}

export class ExpoAppIntegrityError extends ExpoModuleError {
  constructor(code: IntegrityErrorCode, message: string, cause?: Object) {
    let resolved: string = code;

    if (cause instanceof ExpoModuleError) {
      resolved = cause.code;
      message += ` ${cause.message}`;
    } else if (cause !== undefined) {
      const error = cause as BusinessError;
      if (
        error.code === huks.HuksExceptionErrCode.HUKS_ERR_CODE_NOT_SUPPORTED_API ||
        error.code === huks.HuksExceptionErrCode.HUKS_ERR_CODE_FEATURE_NOT_SUPPORTED
      ) {
        resolved = IntegrityErrorCode.HARDWARE_NOT_SUPPORTED;
      }

      if (typeof error.code === 'number') {
        message += ` HarmonyOS error (${error.code}): ${error.message}`;
      } else if (cause instanceof Error) {
        message += ` ${cause.message}`;
      }
    }

    super(resolved, `[ExpoAppIntegrity]: ${message}`, cause);
  }
}

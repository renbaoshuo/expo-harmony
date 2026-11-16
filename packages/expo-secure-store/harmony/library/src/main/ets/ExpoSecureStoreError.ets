/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class ExpoSecureStoreError extends ExpoModuleError {
  constructor(error: Object) {
    if (error instanceof ExpoModuleError) {
      super(error.code, error.message, error.cause, error.path);
      return;
    }

    const code = (error as BusinessError).code;
    if (code === asset.ErrorCode.DUPLICATED) {
      super('ERR_SECURE_STORE_BUSY', 'The SecureStore record changed during the operation. Retry the operation.', error);
      return;
    }

    const detail = typeof code === 'number' ? ` (code ${code})` : '';
    super('ERR_SECURE_STORE_OPERATION_FAILED', `HarmonyOS SecureStore operation failed${detail}.`, error);
  }
}

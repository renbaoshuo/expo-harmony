/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import type { BusinessError } from '@kit.BasicServicesKit';

export class ExpoContactsError extends ExpoModuleError {
  constructor(code: string, message: string, cause?: Object) {
    super(code, message, cause);
  }
}

export class ContactsNativeError extends Error {
  readonly code?: number;
  readonly data?: Object;
  readonly cause: Object;

  constructor(cause: Object) {
    const error = cause as BusinessError<Object> | undefined;
    super(error?.message ?? String(cause));
    this.name = error?.name ?? 'Error';
    this.code = error?.code;
    this.data = error?.data;
    this.cause = cause;
  }
}

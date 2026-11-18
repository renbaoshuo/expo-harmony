/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoAppLifecycleState, ExpoModuleContext, ExpoModuleError, ExpoPermissionStatus } from '@expo-harmony/expo-modules-core';
import { Permissions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';

export const ACTIVITY_MOTION: Permissions = 'ohos.permission.ACTIVITY_MOTION';
const PERMISSION_ERROR_REASONS_API: number = 18;
const SELF_PERMISSION_STATUS_API: number = 20;
const PREFERENCES_NAME: string = 'ExpoSensors';
const DECISION_KEY: string = 'activityMotionDetermined';
const LEGACY_DENIED_KEY: string = 'activityMotionDenied';

enum RequestReason {
  Success = 0,
  InvalidPermission = 1,
  NotDeclared = 2,
  CannotRequest = 5,
  ManualSettings = 6,
}

export class SensorPermissionResponse {
  status: string;
  granted: boolean;
  canAskAgain: boolean;
  expires: string = 'never';

  constructor(status: string, canAskAgain: boolean) {
    this.status = status;
    this.granted = status === 'granted';
    this.canAskAgain = canAskAgain;
  }
}

export class PedometerPermissions {
  private readonly context: ExpoModuleContext;
  private legacyDecision?: Promise<boolean>;
  private pending?: Promise<SensorPermissionResponse>;

  constructor(context: ExpoModuleContext) {
    this.context = context;
  }

  async get(): Promise<SensorPermissionResponse> {
    const response = this.context.getPermissionResponse(ACTIVITY_MOTION);
    const status = response.status;
    if (status === ExpoPermissionStatus.INVALID) {
      throw new ExpoModuleError(
        'ERR_SENSOR_PERMISSION',
        'Invalid activity motion permission. Declare ACTIVITY_MOTION in the application module.json5.',
      );
    }
    if (status === ExpoPermissionStatus.GRANTED) return new SensorPermissionResponse('granted', true);

    if (status === ExpoPermissionStatus.NOT_DETERMINED && deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API) {
      this.legacyDecision ??= this.readLegacyDecision();
      if (await this.legacyDecision) return new SensorPermissionResponse('denied', false);
    }

    return new SensorPermissionResponse(status === ExpoPermissionStatus.NOT_DETERMINED ? 'undetermined' : 'denied', response.canAskAgain);
  }

  async request(): Promise<SensorPermissionResponse> {
    if (this.pending !== undefined) return await this.pending;

    const pending = this.requestOnce();
    this.pending = pending;

    try {
      return await pending;
    } finally {
      if (this.pending === pending) this.pending = undefined;
    }
  }

  private async requestOnce(): Promise<SensorPermissionResponse> {
    const current = await this.get();
    if (current.granted) return current;

    if (this.context.isHeadless || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoModuleError('ERR_SENSOR_PERMISSION', 'Requesting activity motion permission requires a foreground application.');
    }

    const request = await this.context.requestPermissions([ACTIVITY_MOTION]).catch((error: Error) => {
      throw new ExpoModuleError('ERR_SENSOR_PERMISSION', 'The system could not request activity motion permission.', error);
    });

    let blocked = false;

    for (const result of request.systemResults) {
      const index = result.permissions.indexOf(ACTIVITY_MOTION);
      const reason: number = deviceInfo.sdkApiVersion >= PERMISSION_ERROR_REASONS_API
        ? result.errorReasons?.[index] ?? RequestReason.Success
        : RequestReason.Success;

      if (index < 0 || reason === RequestReason.InvalidPermission || reason === RequestReason.NotDeclared) {
        throw new ExpoModuleError(
          'ERR_SENSOR_PERMISSION',
          'Invalid activity motion permission result. Check the ACTIVITY_MOTION declaration in module.json5.',
        );
      }

      const cannotRequest = reason === RequestReason.CannotRequest || reason === RequestReason.ManualSettings;
      if (!cannotRequest && reason !== RequestReason.Success) {
        throw new ExpoModuleError('ERR_SENSOR_PERMISSION', `The system could not request activity motion permission (reason ${reason}).`);
      }

      const status = result.authResults[index];
      if (!cannotRequest && status !== ExpoPermissionStatus.GRANTED && status !== ExpoPermissionStatus.DENIED) {
        throw new ExpoModuleError('ERR_SENSOR_PERMISSION', 'Invalid activity motion permission result. Check the ACTIVITY_MOTION declaration in module.json5.');
      }

      blocked = blocked || cannotRequest;
    }

    const response = await this.get();

    return blocked && !response.granted ? new SensorPermissionResponse('denied', false) : response;
  }

  private async readLegacyDecision(): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: PREFERENCES_NAME });

      return (await store.get(DECISION_KEY, false)) === true || (await store.get(LEGACY_DENIED_KEY, false)) === true;
    } catch (_) {
      return false;
    }
  }
}

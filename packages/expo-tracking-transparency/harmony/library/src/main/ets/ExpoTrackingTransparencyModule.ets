/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError, ExpoPermissionStatus } from '@expo-harmony/expo-modules-core';
import { identifier } from '@kit.AdsKit';
import { TrackingPermissions, TrackingPermissionResponse, TRACKING_PERMISSION } from './TrackingPermissions';

const EMPTY_ADVERTISING_ID: string = '00000000-0000-0000-0000-000000000000';

export class ExpoTrackingTransparencyModule extends ExpoModule {
  private permissions: TrackingPermissions;

  constructor(context: ExpoModuleContext) {
    super(context);

    this.permissions = new TrackingPermissions(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoTrackingTransparency')
      .syncFunction('getAdvertisingId', (): string | null => {
        throw new ExpoModuleError(
          'ERR_UNAVAILABLE',
          'HarmonyOS only provides asynchronous OAID access. Use getAdvertisingIdAsync() from @expo-harmony/expo-tracking-transparency.',
        );
      })
      .asyncFunction('getAdvertisingIdAsync', async (): Promise<string | null> => this.getAdvertisingIdAsync())
      .asyncFunction('getPermissionsAsync', async (): Promise<TrackingPermissionResponse> => this.permissions.get())
      .asyncFunction('requestPermissionsAsync', async (): Promise<TrackingPermissionResponse> => this.permissions.request());
  }

  private async getAdvertisingIdAsync(): Promise<string | null> {
    if (this.context.permissionStatus(TRACKING_PERMISSION) !== ExpoPermissionStatus.GRANTED) return null;

    let id: string;

    try {
      id = await identifier.getOAID();
    } catch (error) {
      if (this.context.permissionStatus(TRACKING_PERMISSION) !== ExpoPermissionStatus.GRANTED) return null;

      throw new ExpoModuleError('ERR_TRACKING_TRANSPARENCY_ADVERTISING_ID', 'Unable to read the HarmonyOS advertising identifier.', error as Object);
    }

    // Permission may be revoked while OAID is being read.
    if (this.context.permissionStatus(TRACKING_PERMISSION) !== ExpoPermissionStatus.GRANTED) return null;

    return id.length === 0 || id === EMPTY_ADVERTISING_ID ? null : id;
  }
}

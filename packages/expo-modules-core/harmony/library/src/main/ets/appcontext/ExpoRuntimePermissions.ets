/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { abilityAccessCtrl, bundleManager } from '@kit.AbilityKit';
import type { common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ExpoServiceKey } from './ExpoServicesRegistry';

export const EXPO_PERMISSION_HISTORY = 'expo.modules.permissions.asked';
const PERMISSION_STATUS_API = 20;
const PERMISSION_REQUEST_REASONS_API = 18;

enum PermissionRequestReason {
  SUCCESS = 0,
  CANNOT_REQUEST = 5,
}

export enum ExpoPermissionStatus {
  DENIED = -1,
  GRANTED = 0,
  NOT_DETERMINED = 1,
  INVALID = 2,
  RESTRICTED = 3,
}

export class ExpoPermissionResponse {
  readonly status: ExpoPermissionStatus;
  readonly canAskAgain: boolean;

  constructor(status: ExpoPermissionStatus) {
    this.status = status;
    this.canAskAgain = status === ExpoPermissionStatus.GRANTED || status === ExpoPermissionStatus.NOT_DETERMINED;
  }
}

export function querySystemPermissionStatus(context: common.Context, permission: Permissions): ExpoPermissionStatus {
  const manager = abilityAccessCtrl.createAtManager();
  if (deviceInfo.sdkApiVersion >= PERMISSION_STATUS_API) {
    return manager.getSelfPermissionStatus(permission) as number as ExpoPermissionStatus;
  }

  const token = context.applicationInfo.accessTokenId;
  return manager.checkAccessTokenSync(token, permission) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
    ? ExpoPermissionStatus.GRANTED
    : ExpoPermissionStatus.DENIED;
}

export function hasSystemPermissionHistory(): boolean {
  return deviceInfo.sdkApiVersion >= PERMISSION_STATUS_API;
}

export function getLegacyDeniedPermissionStatus(context: common.Context, preferencesName: string, permission: Permissions): ExpoPermissionStatus {
  const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION);
  const declared = info.reqPermissionDetails?.some((detail: bundleManager.ReqPermissionDetail): boolean => detail.name === permission);
  if (!declared) return ExpoPermissionStatus.INVALID;

  const store = preferences.getPreferencesSync(context, { name: preferencesName });
  return store.getSync(permission, false) === true ? ExpoPermissionStatus.DENIED : ExpoPermissionStatus.NOT_DETERMINED;
}

export async function recordLegacyPermissionDenials(
  context: common.Context,
  preferencesName: string,
  result: PermissionRequestResult,
): Promise<void> {
  const store = preferences.getPreferencesSync(context, { name: preferencesName });
  let changed = false;

  for (let index = 0; index < result.permissions.length; index += 1) {
    const permission = result.permissions[index];
    const status = result.authResults[index];
    const reason = deviceInfo.sdkApiVersion >= PERMISSION_REQUEST_REASONS_API ? result.errorReasons?.[index] : undefined;
    const shown = result.dialogShownResults?.[index];

    if (status === ExpoPermissionStatus.GRANTED) {
      if (store.hasSync(permission)) {
        store.deleteSync(permission);
        changed = true;
      }
    } else if (
      status === ExpoPermissionStatus.DENIED &&
      (reason === PermissionRequestReason.CANNOT_REQUEST ||
        (reason === PermissionRequestReason.SUCCESS && shown !== undefined) ||
        (reason === undefined && shown === true))
    ) {
      // Without a reason, a suppressed dialog can also indicate an unmet prerequisite.
      if (store.getSync(permission, false) !== true) {
        store.putSync(permission, true);
        changed = true;
      }
    }
  }

  if (changed) await store.flush();
}

export interface ExpoRuntimePermissions {
  getPermissionStatus(permission: Permissions, systemStatus: ExpoPermissionStatus): ExpoPermissionStatus;
  requestPermissions(permissions: Permissions[], requestSystemPermissions: () => Promise<PermissionRequestResult>): Promise<void>;
}

export const ExpoRuntimePermissionsKey = new ExpoServiceKey<ExpoRuntimePermissions>('ExpoRuntimePermissions');

export class ExpoPermissionRequestResult {
  readonly permissions: string[];
  readonly authResults: number[];

  readonly systemResults: PermissionRequestResult[];

  constructor(permissions: string[], authResults: number[], systemResults: PermissionRequestResult[]) {
    this.permissions = permissions;
    this.authResults = authResults;
    this.systemResults = systemResults;
  }
}

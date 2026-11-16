/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { bundleManager } from '@kit.AbilityKit';
import type { common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ExpoServiceKey } from './ExpoServicesRegistry';

export const EXPO_PERMISSION_HISTORY = 'expo.modules.permissions.asked';
export const PERMISSION_STATUS_API = 20;
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

export function getLegacyDeniedPermissionStatus(context: common.Context, preferencesName: string, permission: Permissions): ExpoPermissionStatus {
  const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION);
  if (!info.reqPermissionDetails.some((detail: bundleManager.ReqPermissionDetail): boolean => detail.name === permission)) {
    return ExpoPermissionStatus.INVALID;
  }

  const store = preferences.getPreferencesSync(context, { name: preferencesName });
  return store.getSync(permission, false) === true ? ExpoPermissionStatus.DENIED : ExpoPermissionStatus.NOT_DETERMINED;
}

export async function recordLegacyPermissionDenials(
  context: common.Context,
  preferencesName: string,
  result: PermissionRequestResult,
  api: number,
): Promise<void> {
  const store = preferences.getPreferencesSync(context, { name: preferencesName });
  let changed = false;

  for (let index = 0; index < result.permissions.length; index += 1) {
    const permission = result.permissions[index];
    const auth = result.authResults[index];
    const reason = api >= PERMISSION_REQUEST_REASONS_API ? result.errorReasons?.[index] : undefined;

    if (auth === ExpoPermissionStatus.GRANTED) {
      if (store.hasSync(permission)) {
        store.deleteSync(permission);
        changed = true;
      }
    } else if (
      auth === ExpoPermissionStatus.DENIED &&
      (reason === PermissionRequestReason.CANNOT_REQUEST ||
        ((reason === undefined || reason === PermissionRequestReason.SUCCESS) && result.dialogShownResults?.[index] !== undefined))
    ) {
      // Legacy permission queries cannot distinguish a prior denial from an unseen prompt.
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

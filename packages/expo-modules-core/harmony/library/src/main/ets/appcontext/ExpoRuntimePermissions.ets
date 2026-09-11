import type { PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { ExpoServiceKey } from './ExpoServicesRegistry';

export enum ExpoPermissionStatus {
  DENIED = -1,
  GRANTED = 0,
  NOT_DETERMINED = 1,
  INVALID = 2,
  RESTRICTED = 3,
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

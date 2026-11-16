/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export class PermissionResponse {
  status: string;
  granted: boolean;
  canAskAgain: boolean;
  expires: string = 'never';
  accessPrivileges?: string;

  constructor(status: string, canAskAgain: boolean) {
    this.status = status;
    this.granted = status === 'granted';
    this.canAskAgain = canAskAgain;
  }
}

export function hasCameraPicker(): boolean {
  return canIUse('SystemCapability.Multimedia.Camera.Core');
}

export function cameraPickerPermission(): PermissionResponse {
  // System capture is authorized by the user inside CameraPicker.
  const available = hasCameraPicker();
  return new PermissionResponse(available ? 'granted' : 'denied', available);
}

export function hasPhotoPicker(): boolean {
  return canIUse('SystemCapability.FileManagement.PhotoAccessHelper.Core');
}

export function mediaLibraryPermission(): PermissionResponse {
  // Access covers the system picker only.
  const available = hasPhotoPicker();
  const response = new PermissionResponse(available ? 'granted' : 'denied', available);
  response.accessPrivileges = available ? 'all' : 'none';

  return response;
}

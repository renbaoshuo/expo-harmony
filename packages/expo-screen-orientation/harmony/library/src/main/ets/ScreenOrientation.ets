/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { display, window } from '@kit.ArkUI';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { ExpoModuleError } from '@expo-harmony/expo-modules-core';

export enum Orientation {
  UNKNOWN = 0,
  PORTRAIT_UP = 1,
  PORTRAIT_DOWN = 2,
  LANDSCAPE_LEFT = 3,
  LANDSCAPE_RIGHT = 4,
}

export enum OrientationLock {
  DEFAULT = 0,
  ALL = 1,
  PORTRAIT = 2,
  PORTRAIT_UP = 3,
  PORTRAIT_DOWN = 4,
  LANDSCAPE = 5,
  LANDSCAPE_LEFT = 6,
  LANDSCAPE_RIGHT = 7,
  OTHER = 8,
  UNKNOWN = 9,
}

const LOCKS: Map<number, window.Orientation> = new Map([
  [OrientationLock.DEFAULT, window.Orientation.UNSPECIFIED],
  [OrientationLock.ALL, window.Orientation.AUTO_ROTATION],
  [OrientationLock.PORTRAIT, window.Orientation.AUTO_ROTATION_PORTRAIT],
  [OrientationLock.PORTRAIT_UP, window.Orientation.PORTRAIT],
  [OrientationLock.PORTRAIT_DOWN, window.Orientation.PORTRAIT_INVERTED],
  [OrientationLock.LANDSCAPE, window.Orientation.AUTO_ROTATION_LANDSCAPE],
  // Harmony Window and Display use opposite landscape names.
  [OrientationLock.LANDSCAPE_LEFT, window.Orientation.LANDSCAPE],
  [OrientationLock.LANDSCAPE_RIGHT, window.Orientation.LANDSCAPE_INVERTED],
]);

// Official deviceType value; setPreferredOrientation does not take effect on 2in1.
// Use the string contract because DeviceTypes.TYPE_2IN1 is only available since API 20.
const TWO_IN_ONE_DEVICE_TYPE: string = '2in1';
const ORIENTATION_CONVERSION_API_LEVEL: number = 23;
const CAPABILITY_NOT_SUPPORTED: number = 801;
const INVALID_DISPLAY: number = 1400001;
const DISPLAY_SERVICE_ABNORMAL: number = 1400003;

// convertOrientationAndRotation returns these values, not window.Orientation.
enum WindowDirection {
  PORTRAIT = 0,
  LANDSCAPE_INVERTED = 1,
  PORTRAIT_INVERTED = 2,
  LANDSCAPE = 3,
}

export function supportsOrientationLock(value: number): boolean {
  return deviceInfo.deviceType !== TWO_IN_ONE_DEVICE_TYPE && LOCKS.has(value);
}

export function toPreferredOrientation(value: number): window.Orientation {
  const orientation = LOCKS.get(value);
  if (orientation === undefined) {
    throw new ExpoModuleError('ERR_SCREEN_ORIENTATION_INVALID_LOCK', `Unsupported orientation lock: ${value}.`);
  }

  return orientation;
}

export function fromPreferredOrientation(value: window.Orientation): OrientationLock {
  for (const entry of LOCKS) {
    if (entry[1] === value) return entry[0];
  }

  return OrientationLock.OTHER;
}

export function requirePlatformOrientation(value: number): window.Orientation {
  switch (value) {
    case window.Orientation.UNSPECIFIED:
    case window.Orientation.PORTRAIT:
    case window.Orientation.LANDSCAPE:
    case window.Orientation.PORTRAIT_INVERTED:
    case window.Orientation.LANDSCAPE_INVERTED:
    case window.Orientation.AUTO_ROTATION:
    case window.Orientation.AUTO_ROTATION_PORTRAIT:
    case window.Orientation.AUTO_ROTATION_LANDSCAPE:
    case window.Orientation.AUTO_ROTATION_RESTRICTED:
    case window.Orientation.AUTO_ROTATION_PORTRAIT_RESTRICTED:
    case window.Orientation.AUTO_ROTATION_LANDSCAPE_RESTRICTED:
    case window.Orientation.LOCKED:
    case window.Orientation.AUTO_ROTATION_UNSPECIFIED:
    case window.Orientation.USER_ROTATION_PORTRAIT:
    case window.Orientation.USER_ROTATION_LANDSCAPE:
    case window.Orientation.USER_ROTATION_PORTRAIT_INVERTED:
    case window.Orientation.USER_ROTATION_LANDSCAPE_INVERTED:
    case window.Orientation.FOLLOW_DESKTOP:
      return value;
    default:
      throw new ExpoModuleError('ERR_SCREEN_ORIENTATION_INVALID_PLATFORM_LOCK', `Unsupported HarmonyOS orientation: ${value}.`);
  }
}

export function readOrientation(win: window.Window): Orientation {
  const props = win.getWindowProperties();
  const rect = props.windowRect;

  if (rect.width <= 0 || rect.height <= 0) return Orientation.UNKNOWN;

  let screen: display.Display;

  try {
    screen = props.displayId === undefined ? display.getDefaultDisplaySync() : display.getDisplayByIdSync(props.displayId);
  } catch (error) {
    const code = (error as BusinessError).code;
    // The display can disappear before the window's displayId is updated.
    if (code === (props.displayId === undefined ? INVALID_DISPLAY : DISPLAY_SERVICE_ABNORMAL)) return Orientation.UNKNOWN;

    throw error as Error;
  }

  if (deviceInfo.sdkApiVersion >= ORIENTATION_CONVERSION_API_LEVEL && canIUse('SystemCapability.Window.SessionManager')) {
    try {
      const direction = win.convertOrientationAndRotation(
        window.RotationInfoType.DISPLAY_ORIENTATION,
        window.RotationInfoType.WINDOW_ORIENTATION,
        screen.orientation,
      );

      return fromWindowDirection(direction);
    } catch (error) {
      if ((error as BusinessError).code !== CAPABILITY_NOT_SUPPORTED) {
        throw new ExpoModuleError('ERR_SCREEN_ORIENTATION_CONVERSION', `Unable to convert the current screen orientation: ${String(error)}`, error);
      }
    }
  }

  return fromDisplayOrientation(screen.orientation);
}

function fromWindowDirection(value: number): Orientation {
  switch (value) {
    case WindowDirection.PORTRAIT:
      return Orientation.PORTRAIT_UP;
    case WindowDirection.PORTRAIT_INVERTED:
      return Orientation.PORTRAIT_DOWN;
    case WindowDirection.LANDSCAPE:
      return Orientation.LANDSCAPE_LEFT;
    case WindowDirection.LANDSCAPE_INVERTED:
      return Orientation.LANDSCAPE_RIGHT;
    default:
      return Orientation.UNKNOWN;
  }
}

function fromDisplayOrientation(value: display.Orientation): Orientation {
  // The logical display direction already accounts for the device's natural orientation.
  switch (value) {
    case display.Orientation.PORTRAIT:
      return Orientation.PORTRAIT_UP;
    case display.Orientation.PORTRAIT_INVERTED:
      return Orientation.PORTRAIT_DOWN;
    case display.Orientation.LANDSCAPE:
      return Orientation.LANDSCAPE_RIGHT;
    case display.Orientation.LANDSCAPE_INVERTED:
      return Orientation.LANDSCAPE_LEFT;
    default:
      return Orientation.UNKNOWN;
  }
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoModuleDefinition } from '@expo-harmony/expo-modules-core';
import { display, window } from '@kit.ArkUI';
import { sensor } from '@kit.SensorServiceKit';
import { SensorModule } from './SensorModule';
import {
  DEGREES_PER_RADIAN,
  DeviceMotionMeasurement,
  finite,
  GRAVITY_EARTH,
  NANOSECONDS_PER_SECOND,
  RotationMeasurement,
  VectorMeasurement,
} from './SensorMeasurements';
import { SensorPermissionResponse } from './SensorPermissions';

export class DeviceMotionModule extends SensorModule {
  private acceleration?: VectorMeasurement;
  private total?: VectorMeasurement;
  private gravity?: VectorMeasurement;
  private rotation?: RotationMeasurement;
  private rate?: RotationMeasurement;
  private pending: boolean = false;
  private window?: window.Window;

  constructor(context: ExpoModuleContext) {
    super(context, 'ExponentDeviceMotion', 'deviceMotionDidUpdate', ['ohos.permission.ACCELEROMETER', 'ohos.permission.GYROSCOPE']);
    this.interval = 1000 / 60;

    this.addSensor<sensor.AccelerometerResponse>(
      sensor.SensorId.ACCELEROMETER,
      (callback, options): void => {
        sensor.on(sensor.SensorId.ACCELEROMETER, callback, options);
      },
      (callback): void => {
        sensor.off(sensor.SensorId.ACCELEROMETER, callback);
      },
      (value): void => {
        this.total = new VectorMeasurement(value.x, value.y, value.z, value.timestamp);
        this.publish();
      },
    );

    this.addSensor<sensor.LinearAccelerometerResponse>(
      sensor.SensorId.LINEAR_ACCELEROMETER,
      (callback, options): void => {
        sensor.on(sensor.SensorId.LINEAR_ACCELEROMETER, callback, options);
      },
      (callback): void => {
        sensor.off(sensor.SensorId.LINEAR_ACCELEROMETER, callback);
      },
      (value): void => {
        this.acceleration = new VectorMeasurement(value.x, value.y, value.z, value.timestamp);
        this.publish();
      },
    );

    this.addSensor<sensor.GravityResponse>(
      sensor.SensorId.GRAVITY,
      (callback, options): void => {
        sensor.on(sensor.SensorId.GRAVITY, callback, options);
      },
      (callback): void => {
        sensor.off(sensor.SensorId.GRAVITY, callback);
      },
      (value): void => {
        this.gravity = new VectorMeasurement(value.x, value.y, value.z, value.timestamp);
        this.publish();
      },
    );

    this.addSensor<sensor.GyroscopeResponse>(
      sensor.SensorId.GYROSCOPE,
      (callback, options): void => {
        sensor.on(sensor.SensorId.GYROSCOPE, callback, options);
      },
      (callback): void => {
        sensor.off(sensor.SensorId.GYROSCOPE, callback);
      },
      (value): void => {
        this.rate = new RotationMeasurement(
          value.x * DEGREES_PER_RADIAN,
          value.y * DEGREES_PER_RADIAN,
          value.z * DEGREES_PER_RADIAN,
          value.timestamp,
        );

        this.publish();
      },
    );

    this.addSensor<sensor.RotationVectorResponse>(
      sensor.SensorId.ROTATION_VECTOR,
      (callback, options): void => {
        sensor.on(sensor.SensorId.ROTATION_VECTOR, callback, options);
      },
      (callback): void => {
        sensor.off(sensor.SensorId.ROTATION_VECTOR, callback);
      },
      (value): void => {
        this.updateRotation(value);
      },
    );
  }

  definition(): ExpoModuleDefinition {
    return super
      .definition()
      .constant('Gravity', GRAVITY_EARTH)
      .asyncFunction('getPermissionsAsync', async (): Promise<SensorPermissionResponse> => {
        return this.systemPermissions();
      })
      .asyncFunction('requestPermissionsAsync', async (): Promise<SensorPermissionResponse> => {
        return this.systemPermissions();
      });
  }

  protected didStartObservation(): void {
    const generation = this.generation;

    this.context
      .getReactNativeWindow()
      .then((current: window.Window): void => {
        if (generation === this.generation && this.context.isValid) this.window = current;
      })
      .catch((error: Error): void => {
        if (generation === this.generation) this.warn(`Unable to obtain the React Native window: ${String(error)}`);
      });
  }

  protected clearSamples(): void {
    this.acceleration = undefined;
    this.total = undefined;
    this.gravity = undefined;
    this.rotation = undefined;
    this.rate = undefined;
    this.pending = false;
    this.window = undefined;
  }

  private async updateRotation(value: sensor.RotationVectorResponse): Promise<void> {
    if (this.pending) return;

    this.pending = true;
    const generation = this.generation;
    const timestamp = value.timestamp;

    try {
      const matrix = await sensor.getRotationMatrix([finite(value.x), finite(value.y), finite(value.z), finite(value.w)]);

      if (generation !== this.generation) return;
      if (matrix.length !== 9 || !matrix.every((entry: number): boolean => Number.isFinite(entry))) {
        throw new RangeError('Invalid sensor rotation matrix.');
      }

      // Expo Android uses -azimuth, -pitch, roll in radians.
      this.rotation = new RotationMeasurement(
        -Math.atan2(matrix[1], matrix[4]),
        Math.asin(Math.max(-1, Math.min(1, matrix[7]))),
        Math.atan2(-matrix[6], matrix[8]),
        timestamp,
      );

      this.publish();
    } catch (error) {
      if (generation === this.generation) this.warn(`Unable to calculate device rotation: ${String(error)}`);
    } finally {
      if (generation === this.generation) this.pending = false;
    }
  }

  private publish(): void {
    const total = this.total;
    const gravity = this.gravity;
    const rotation = this.rotation;

    if (total === undefined || gravity === undefined || rotation === undefined) return;

    // Match upstream Android's gravity direction, including its factor of two.
    const combined = new VectorMeasurement(
      total.x - 2 * gravity.x,
      total.y - 2 * gravity.y,
      total.z - 2 * gravity.z,
      total.timestamp * NANOSECONDS_PER_SECOND,
    );

    this.emitMeasurement(new DeviceMotionMeasurement(this.acceleration ?? null, combined, rotation, this.rate ?? null, this.interval, this.orientation()));
  }

  private orientation(): number {
    let rotation: number;

    try {
      const id = this.window?.getWindowProperties().displayId;
      rotation = id === undefined ? display.getDefaultDisplaySync().rotation : display.getDisplayByIdSync(id).rotation;
    } catch (_) {
      // The window or its display may have been removed while observing.
      try {
        rotation = display.getDefaultDisplaySync().rotation;
      } catch (_) {
        return 0;
      }
    }

    switch (rotation) {
      case 1:
        return 90;
      case 2:
        return 180;
      case 3:
        return -90;
      default:
        return 0;
    }
  }
}

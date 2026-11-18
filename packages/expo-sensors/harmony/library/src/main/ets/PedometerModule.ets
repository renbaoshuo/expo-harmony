/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { sensor } from '@kit.SensorServiceKit';
import { SensorModule } from './SensorModule';
import { PedometerMeasurement } from './SensorMeasurements';
import { ACTIVITY_MOTION, PedometerPermissions, SensorPermissionResponse } from './SensorPermissions';

export class PedometerModule extends SensorModule {
  private readonly permissions: PedometerPermissions;
  private previous?: number;
  private previousTimestamp: number = -1;
  private steps: number = 0;

  constructor(context: ExpoModuleContext) {
    super(context, 'ExponentPedometer', 'Exponent.pedometerUpdate', [ACTIVITY_MOTION]);
    this.permissions = new PedometerPermissions(context);

    this.addSensor<sensor.PedometerResponse>(
      sensor.SensorId.PEDOMETER,
      (callback, options): void => {
        sensor.on(sensor.SensorId.PEDOMETER, callback, options);
      },
      (callback): void => {
        sensor.off(sensor.SensorId.PEDOMETER, callback);
      },
      (value): void => {
        this.onSteps(value);
      },
    );
  }

  definition(): ExpoModuleDefinition {
    return super
      .definition()
      .asyncFunction('getPermissionsAsync', async (): Promise<SensorPermissionResponse> => {
        return this.permissions.get();
      })
      .asyncFunction('requestPermissionsAsync', async (): Promise<SensorPermissionResponse> => {
        const response = await this.permissions.request();

        if (response.granted) this.resumeSafely();

        return response;
      })
      .asyncFunction(
        'getStepCountAsync',
        ExpoFunction.typed2(ExpoValueTypes.number(), ExpoValueTypes.number(), async (_start: number, _end: number): Promise<void> => {
          throw new ExpoModuleError('ERR_NOT_SUPPORTED', 'Getting step count for a date range is not supported on HarmonyOS.');
        }),
      );
  }

  protected resetObservation(): void {
    this.previous = undefined;
    this.previousTimestamp = -1;
    this.steps = 0;
  }

  private onSteps(value: sensor.PedometerResponse): void {
    const count = value.steps;
    if (!Number.isSafeInteger(count) || count < 0) throw new RangeError('Invalid pedometer step count.');
    if (value.timestamp <= this.previousTimestamp) return;

    if (this.previous !== undefined && count >= this.previous) {
      this.steps += count - this.previous;
    }

    this.previous = count;
    this.previousTimestamp = value.timestamp;

    this.emitMeasurement(new PedometerMeasurement(this.steps));
  }
}

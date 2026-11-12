/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { sensor } from '@kit.SensorServiceKit';
import { intervalNanoseconds, timestampSeconds } from './SensorMeasurements';

const UNSUBSCRIBE_RETRY_MS: number = 1000;
const MAX_UNSUBSCRIBE_ATTEMPTS: number = 3;

// Native listeners for the same sensor share a sampling period. Preserve the
// fastest request when DeviceMotion and a standalone sensor are both observing.
const activeSamplePeriods = new Map<sensor.SensorId, Map<SensorObserver, number>>();

export interface SensorObserver {
  id: sensor.SensorId;
  start(interval: number): void;
  stop(): void;
}

export class SensorSubscription<T extends sensor.Response> implements SensorObserver {
  readonly id: sensor.SensorId;
  private readonly subscribe: (callback: (value: T) => void, options: sensor.Options) => void;
  private readonly unsubscribe: (callback: (value: T) => void) => void;
  private readonly receive: (value: T) => void;
  private readonly warn: (message: string) => void;
  private readonly failure: (message: string) => void;
  private callback?: (value: T) => void;
  private active: boolean = false;
  private retry: number = -1;
  private attempts: number = 0;

  constructor(
    id: sensor.SensorId,
    subscribe: (callback: (value: T) => void, options: sensor.Options) => void,
    unsubscribe: (callback: (value: T) => void) => void,
    receive: (value: T) => void,
    warn: (message: string) => void,
    failure: (message: string) => void,
  ) {
    this.id = id;
    this.subscribe = subscribe;
    this.unsubscribe = unsubscribe;
    this.receive = receive;
    this.warn = warn;
    this.failure = failure;
  }

  start(interval: number): void {
    this.stop();

    if (this.callback !== undefined) throw new Error(`Sensor ${this.id} still has a pending unsubscription.`);

    const info = sensor.getSingleSensorSync(this.id);

    const minimum = Math.max(1, Number.isFinite(info.minSamplePeriod) ? info.minSamplePeriod : 1);
    const maximum = Number.isFinite(info.maxSamplePeriod) && info.maxSamplePeriod >= minimum ? info.maxSamplePeriod : Number.MAX_SAFE_INTEGER;
    const period = Math.min(maximum, Math.max(minimum, intervalNanoseconds(interval)));

    const callback = (value: T): void => {
      if (!this.active || this.callback !== callback) return;

      try {
        timestampSeconds(value.timestamp);

        this.receive(value);
      } catch (error) {
        this.warn(`Unable to process sensor ${this.id} data: ${String(error)}`);
      }
    };

    this.callback = callback;
    this.active = true;
    this.attempts = 0;

    const periods = activeSamplePeriods.get(this.id) ?? new Map<SensorObserver, number>();
    let sharedPeriod = period;
    periods.forEach((current: number): void => {
      sharedPeriod = Math.min(sharedPeriod, current);
    });

    try {
      this.subscribe(callback, { interval: sharedPeriod });
    } catch (error) {
      this.active = false;
      this.callback = undefined;

      throw new Error(`Unable to subscribe sensor ${this.id}: ${String(error)}`);
    }

    periods.set(this, period);
    activeSamplePeriods.set(this.id, periods);
  }

  stop(): void {
    this.active = false;
    const periods = activeSamplePeriods.get(this.id);
    if (periods !== undefined) {
      periods.delete(this);
      if (periods.size === 0) activeSamplePeriods.delete(this.id);
    }
    if (this.retry >= 0) clearTimeout(this.retry);
    this.retry = -1;

    const callback = this.callback;
    if (callback === undefined) return;

    try {
      this.unsubscribe(callback);

      this.callback = undefined;
      this.attempts = 0;
    } catch (error) {
      this.warn(`Unable to unsubscribe sensor ${this.id}: ${String(error)}`);

      this.attempts += 1;
      if (this.attempts < MAX_UNSUBSCRIBE_ATTEMPTS) {
        this.retry = setTimeout((): void => {
          this.stop();
        }, UNSUBSCRIBE_RETRY_MS);
      } else {
        this.failure(
          `Sensor ${this.id} cleanup failed after ${this.attempts} attempts. Its callback remains quarantined; a later stop/start will retry removal.`,
        );
      }
    }
  }
}

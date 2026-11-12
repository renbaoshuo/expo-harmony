/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export const GRAVITY_EARTH: number = 9.80665;
export const NANOSECONDS_PER_MILLISECOND: number = 1_000_000;
export const NANOSECONDS_PER_SECOND: number = 1_000_000_000;
export const DEGREES_PER_RADIAN: number = 180 / Math.PI;

export function finite(value: number): number {
  if (!Number.isFinite(value)) throw new RangeError('Sensor data must be finite.');

  return value;
}

export function timestampSeconds(timestamp: number): number {
  if (finite(timestamp) < 0) throw new RangeError('Sensor timestamps must be non-negative.');

  return timestamp / NANOSECONDS_PER_SECOND;
}

export function intervalNanoseconds(interval: number): number {
  const nanoseconds = Math.round(interval * NANOSECONDS_PER_MILLISECOND);
  if (!Number.isFinite(interval) || interval < 0 || !Number.isSafeInteger(nanoseconds)) {
    throw new RangeError('Sensor update interval must be a finite, non-negative number of milliseconds within the safe numeric range.');
  }

  return Math.max(1, nanoseconds);
}

export class VectorMeasurement {
  x: number;
  y: number;
  z: number;
  timestamp: number;

  constructor(x: number, y: number, z: number, timestamp: number) {
    this.x = finite(x);
    this.y = finite(y);
    this.z = finite(z);
    this.timestamp = timestampSeconds(timestamp);
  }
}

export class RotationMeasurement {
  alpha: number;
  beta: number;
  gamma: number;
  timestamp: number;

  constructor(alpha: number, beta: number, gamma: number, timestamp: number) {
    this.alpha = finite(alpha);
    this.beta = finite(beta);
    this.gamma = finite(gamma);
    this.timestamp = timestampSeconds(timestamp);
  }
}

export class BarometerMeasurement {
  pressure: number;
  timestamp: number;

  constructor(pressure: number, timestamp: number) {
    this.pressure = finite(pressure);
    this.timestamp = timestampSeconds(timestamp);
  }
}

export class LightMeasurement {
  illuminance: number;
  timestamp: number;

  constructor(illuminance: number, timestamp: number) {
    this.illuminance = finite(illuminance);
    this.timestamp = timestampSeconds(timestamp);
  }
}

export class PedometerMeasurement {
  steps: number;

  constructor(steps: number) {
    this.steps = steps;
  }
}

export class DeviceMotionMeasurement {
  acceleration: VectorMeasurement | null;
  accelerationIncludingGravity: VectorMeasurement;
  rotation: RotationMeasurement;
  rotationRate: RotationMeasurement | null;
  interval: number;
  orientation: number;

  constructor(
    acceleration: VectorMeasurement | null,
    total: VectorMeasurement,
    rotation: RotationMeasurement,
    rate: RotationMeasurement | null,
    interval: number,
    orientation: number,
  ) {
    this.acceleration = acceleration;
    this.accelerationIncludingGravity = total;
    this.rotation = rotation;
    this.rotationRate = rate;
    this.interval = interval;
    this.orientation = orientation;
  }
}

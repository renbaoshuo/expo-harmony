/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoModuleLogger,
  ExpoPermissionStatus,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { Permissions } from '@kit.AbilityKit';
import { systemDateTime } from '@kit.BasicServicesKit';
import { sensor } from '@kit.SensorServiceKit';
import { SensorObserver, SensorSubscription } from './SensorSubscription';
import { intervalNanoseconds } from './SensorMeasurements';
import { SensorPermissionResponse } from './SensorPermissions';

const SUBSCRIBE_RETRY_MS: number = 1000;
const MAX_SUBSCRIBE_RETRIES: number = 3;

export class SensorModule extends ExpoModule {
  protected interval: number = 100;
  protected generation: number = 0;
  private observing: boolean = false;
  private readonly name: string;
  private readonly event: string;
  private readonly subscriptions: SensorObserver[] = [];
  private readonly required: Permissions[];
  private logger?: ExpoModuleLogger;
  private retry: number = -1;
  private retries: number = 0;
  private foreground: boolean;
  private destroyed: boolean = false;
  private running: boolean = false;
  private emitted: number = -1;

  constructor(context: ExpoModuleContext, name: string, event: string, required: Permissions[] = []) {
    super(context);
    this.name = name;
    this.event = event;
    this.required = required;
    this.foreground = context.appLifecycleState === ExpoAppLifecycleState.FOREGROUND;
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name(this.name)
      .events([this.event])
      .onCreate((): void => {
        this.logger = this.context.logger;
      })
      .asyncFunction('isAvailableAsync', async (): Promise<boolean> => {
        return this.subscriptions.every((subscription: SensorObserver): boolean => {
          try {
            sensor.getSingleSensorSync(subscription.id);

            return true;
          } catch (_) {
            return false;
          }
        });
      })
      .asyncFunction(
        'setUpdateInterval',
        ExpoFunction.typed1(ExpoValueTypes.number(), async (interval: number): Promise<void> => {
          try {
            intervalNanoseconds(interval);
          } catch (error) {
            throw new ExpoModuleError('ERR_SENSOR_INTERVAL', String(error));
          }

          this.interval = interval;

          this.pause();
          this.resumeSafely();
        }),
      )
      .onStartObserving((): void => {
        this.observing = true;
        this.resetObservation();
        this.resumeSafely();
      })
      .onStopObserving((): void => {
        this.observing = false;
        this.pause();
        this.resetObservation();
      })
      .onForeground((): void => {
        this.foreground = true;
        this.resumeSafely();
      })
      .onBackground((): void => {
        this.foreground = false;
        this.pause();
      })
      .onPrepareForReload(async (): Promise<void> => {
        this.destroy();
      })
      .onDestroy((): void => {
        this.destroy();
      });
  }

  protected addSensor<T extends sensor.Response>(
    id: sensor.SensorId,
    subscribe: (callback: (value: T) => void, options: sensor.Options) => void,
    unsubscribe: (callback: (value: T) => void) => void,
    receive: (value: T) => void,
  ): void {
    this.subscriptions.push(
      new SensorSubscription<T>(
        id,
        subscribe,
        unsubscribe,
        (value: T): void => {
          if (!this.context.isValid) return;

          if (!this.hasPermissions()) {
            this.pause();

            return;
          }

          receive(value);
        },
        (message: string): void => {
          this.warn(message);
        },
        (message: string): void => {
          this.logger?.error(message);
        },
      ),
    );
  }

  protected emitMeasurement(value: Object): void {
    if (!this.running || !this.context.isValid || !this.hasPermissions()) return;

    const now = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);

    if (this.emitted >= 0 && now - this.emitted < this.interval) return;

    this.sendEvent(this.event, value);
    this.emitted = now;
  }

  protected resetObservation(): void {}
  protected clearSamples(): void {}
  protected didStartObservation(): void {}

  protected systemPermissions(): SensorPermissionResponse {
    const granted = this.hasPermissions();

    return new SensorPermissionResponse(granted ? 'granted' : 'denied', granted);
  }

  protected resumeSafely(reset: boolean = true): void {
    if (reset) this.retries = 0;

    try {
      this.resume();
    } catch (error) {
      this.warn(`Unable to observe ${this.name}: ${String(error)}`);

      if (
        this.context.isValid &&
        this.hasPermissions() &&
        this.observing &&
        this.foreground &&
        !this.destroyed &&
        this.retry < 0 &&
        this.retries < MAX_SUBSCRIBE_RETRIES
      ) {
        this.retries += 1;
        this.retry = setTimeout((): void => {
          this.retry = -1;
          this.resumeSafely(false);
        }, SUBSCRIBE_RETRY_MS);
      }
    }
  }

  protected warn(message: string): void {
    this.logger?.warn(message);
  }

  private resume(): void {
    if (this.destroyed || !this.foreground || !this.observing || this.running) return;
    if (!this.hasPermissions()) throw new ExpoModuleError('ERR_SENSOR_PERMISSION_DENIED', `Permission to observe ${this.name} was not granted.`);

    this.running = true;

    try {
      this.subscriptions.forEach((subscription: SensorObserver): void => {
        subscription.start(this.interval);
      });
    } catch (error) {
      this.pause();

      throw new ExpoModuleError('ERR_SENSOR_SUBSCRIBE', String(error));
    }

    this.didStartObservation();
  }

  private pause(): void {
    if (this.retry >= 0) clearTimeout(this.retry);
    this.retry = -1;

    this.running = false;
    this.generation += 1;
    this.emitted = -1;

    this.subscriptions.forEach((subscription: SensorObserver): void => {
      subscription.stop();
    });

    this.clearSamples();
  }

  private hasPermissions(): boolean {
    return this.required.every((permission: Permissions): boolean => {
      return this.context.permissionStatus(permission) === ExpoPermissionStatus.GRANTED;
    });
  }

  private destroy(): void {
    this.destroyed = true;
    this.observing = false;

    this.pause();
    this.resetObservation();
  }
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoAppLifecycleState, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { batteryInfo, BusinessError, commonEventManager, deviceInfo, power } from '@kit.BasicServicesKit';
import { batteryLevelFromSoc, batteryStateFromChargeState, ExpoBatteryState, UNKNOWN_BATTERY_LEVEL } from './BatterySemantics';
import type { ExpoBatteryStateValue } from './BatterySemantics';

const BATTERY_LEVEL_EVENT_NAME: string = 'Expo.batteryLevelDidChange';
const BATTERY_STATE_EVENT_NAME: string = 'Expo.batteryStateDidChange';
const POWER_MODE_EVENT_NAME: string = 'Expo.powerModeDidChange';
const BATTERY_SYSTEM_EVENT: string = commonEventManager.Support.COMMON_EVENT_BATTERY_CHANGED;
const POWER_MODE_SYSTEM_EVENT: string = commonEventManager.Support.COMMON_EVENT_POWER_SAVE_MODE_CHANGED;
const SUBSCRIBE_TO_EVENT_API_VERSION: number = 20;
const SUBSCRIPTION_RETRY_DELAY_MS: number = 1000;
const UNSUBSCRIPTION_RETRY_DELAY_MS: number = 1000;
const MAX_UNSUBSCRIPTION_ATTEMPTS: number = 3;

class BatteryLevelEvent {
  batteryLevel: number;

  constructor(level: number) {
    this.batteryLevel = level;
  }
}

class BatteryStateEvent {
  batteryState: ExpoBatteryStateValue;

  constructor(state: ExpoBatteryStateValue) {
    this.batteryState = state;
  }
}

class PowerModeEvent {
  lowPowerMode: boolean;

  constructor(enabled: boolean) {
    this.lowPowerMode = enabled;
  }
}

class ExpoBatteryError extends ExpoModuleError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoBatteryError';
  }
}

export class ExpoBatteryModule extends ExpoModule {
  private readonly events: Set<string> = new Set<string>();
  private readonly startingSubscribers: Set<commonEventManager.CommonEventSubscriber> = new Set<commonEventManager.CommonEventSubscriber>();
  private readonly subscribers: Map<string, commonEventManager.CommonEventSubscriber> = new Map<string, commonEventManager.CommonEventSubscriber>();
  private retry: number = -1;
  private foreground: boolean;
  private destroyed: boolean = false;
  private lastBatteryLevel?: number = undefined;
  private lastBatteryState?: ExpoBatteryStateValue = undefined;
  private lastLowPowerMode?: boolean = undefined;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.foreground = context.appLifecycleState === ExpoAppLifecycleState.FOREGROUND;
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoBattery')
      .constant('isSupported', true)
      .events([BATTERY_LEVEL_EVENT_NAME, BATTERY_STATE_EVENT_NAME, POWER_MODE_EVENT_NAME])
      .asyncFunction('getBatteryLevelAsync', async (): Promise<number> => {
        return this.readBatteryLevel();
      })
      .asyncFunction('getBatteryStateAsync', async (): Promise<ExpoBatteryStateValue> => {
        return this.readBatteryState();
      })
      .asyncFunction('isLowPowerModeEnabledAsync', async (): Promise<boolean> => {
        return this.readLowPowerMode();
      })
      .asyncFunction('isBatteryOptimizationEnabledAsync', async (): Promise<boolean> => {
        return false;
      })
      .onStartObserving((name: string): void => {
        this.startObserving(name);
      })
      .onStopObserving((name: string): void => {
        this.stopObserving(name);
      })
      .onPrepareForReload(async (): Promise<void> => {
        this.destroy();
      })
      .onForeground((): void => {
        if (this.destroyed) return;

        this.foreground = true;
        this.updateSystemObservations();
      })
      .onBackground((): void => {
        this.foreground = false;
        this.updateSystemObservations();
      })
      .onDestroy((): void => {
        this.destroy();
      });
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.events.clear();

    this.updateSystemObservations();
  }

  private startObserving(name: string): void {
    if (this.destroyed) return;
    this.requireEventName(name);

    this.events.add(name);
    this.primeSnapshot(name);

    this.updateSystemObservations();
  }

  private stopObserving(name: string): void {
    this.requireEventName(name);

    this.events.delete(name);
    this.updateSystemObservations();
  }

  private updateSystemObservations(): void {
    this.clearRetryTimer();
    const active = !this.destroyed && this.foreground;
    this.updateSystemObservation(
      BATTERY_SYSTEM_EVENT,
      active && (this.events.has(BATTERY_LEVEL_EVENT_NAME) || this.events.has(BATTERY_STATE_EVENT_NAME)),
    );
    this.updateSystemObservation(POWER_MODE_SYSTEM_EVENT, active && this.events.has(POWER_MODE_EVENT_NAME));
  }

  private updateSystemObservation(event: string, enabled: boolean): void {
    if (!enabled) {
      this.stopSystemObservation(event);
      return;
    }
    if (this.subscribers.has(event)) return;

    let subscriber: commonEventManager.CommonEventSubscriber;

    try {
      subscriber = commonEventManager.createSubscriberSync({ events: [event] });
      this.subscribers.set(event, subscriber);
      if (deviceInfo.sdkApiVersion >= SUBSCRIBE_TO_EVENT_API_VERSION) {
        this.subscribeWithAcknowledgement(event, subscriber);
      } else {
        commonEventManager.subscribe(subscriber, (error: BusinessError, data: commonEventManager.CommonEventData): void => {
          if (this.subscribers.get(event) !== subscriber) return;
          if (error !== undefined && error !== null) {
            this.handleSubscriptionFailure(event, error);
            return;
          }

          this.receiveSystemEvent(event, subscriber, data);
        });
        if (this.subscribers.get(event) === subscriber) this.publishSystemEvent(event);
      }
    } catch (error) {
      this.handleSubscriptionFailure(event, error as Object);
    }
  }

  private async subscribeWithAcknowledgement(
    event: string,
    subscriber: commonEventManager.CommonEventSubscriber,
  ): Promise<void> {
    this.startingSubscribers.add(subscriber);
    try {
      await commonEventManager.subscribeToEvent(subscriber, (data: commonEventManager.CommonEventData): void => {
        this.receiveSystemEvent(event, subscriber, data);
      });
    } catch (error) {
      if (this.subscribers.get(event) === subscriber) this.handleSubscriptionFailure(event, error as Object);
      return;
    } finally {
      this.startingSubscribers.delete(subscriber);
    }

    if (this.subscribers.get(event) === subscriber) {
      this.publishSystemEvent(event);
    } else {
      this.attemptUnsubscribe(subscriber);
    }
  }

  private receiveSystemEvent(
    event: string,
    subscriber: commonEventManager.CommonEventSubscriber,
    data: commonEventManager.CommonEventData,
  ): void {
    if (this.subscribers.get(event) !== subscriber) return;
    if (data?.event === event) this.publishSystemEvent(event, data);
  }

  private stopSystemObservation(event: string): void {
    const subscriber = this.subscribers.get(event);
    this.subscribers.delete(event);
    if (subscriber !== undefined && !this.startingSubscribers.has(subscriber)) {
      this.attemptUnsubscribe(subscriber);
    }
  }

  private attemptUnsubscribe(subscriber: commonEventManager.CommonEventSubscriber, attempt: number = 1): void {
    // The legacy API can drop an unsubscribe issued before registration completes without invoking its callback.
    let failure = 'The service did not acknowledge removal.';
    const timeout = setTimeout((): void => {
      if (attempt < MAX_UNSUBSCRIPTION_ATTEMPTS) {
        this.attemptUnsubscribe(subscriber, attempt + 1);
      } else {
        this.warn(`Unable to stop observing HarmonyOS battery events: ${failure}`);
      }
    }, UNSUBSCRIPTION_RETRY_DELAY_MS);

    try {
      commonEventManager.unsubscribe(subscriber, (error: BusinessError): void => {
        if (error !== undefined && error !== null) {
          failure = String(error);
        } else {
          clearTimeout(timeout);
        }
      });
    } catch (error) {
      failure = String(error);
    }
  }

  private handleSubscriptionFailure(event: string, error: Object): void {
    this.warn(`Unable to observe HarmonyOS event '${event}': ${String(error)}`);
    this.subscribers.delete(event);
    this.scheduleSubscriptionRetry();
  }

  private scheduleSubscriptionRetry(): void {
    if (this.destroyed || !this.foreground || this.events.size === 0 || this.retry >= 0) return;

    this.retry = setTimeout((): void => {
      this.retry = -1;
      this.updateSystemObservations();
    }, SUBSCRIPTION_RETRY_DELAY_MS);
  }

  private clearRetryTimer(): void {
    if (this.retry < 0) return;

    clearTimeout(this.retry);
    this.retry = -1;
  }

  private publishSystemEvent(event: string, data?: commonEventManager.CommonEventData): void {
    if (event === BATTERY_SYSTEM_EVENT) {
      this.publishBatteryLevelIfChanged(data);
      this.publishBatteryStateIfChanged(data);
      return;
    }

    this.publishPowerModeIfChanged();
  }

  private primeSnapshot(name: string): void {
    try {
      if (name === BATTERY_LEVEL_EVENT_NAME) this.lastBatteryLevel = this.readBatteryLevel();
    } catch (error) {
      this.warn(`Unable to initialize the battery level observer: ${String(error)}`);
    }

    try {
      if (name === BATTERY_STATE_EVENT_NAME) this.lastBatteryState = this.readBatteryState();
    } catch (error) {
      this.warn(`Unable to initialize the battery state observer: ${String(error)}`);
    }

    try {
      if (name === POWER_MODE_EVENT_NAME) this.lastLowPowerMode = this.readLowPowerMode();
    } catch (error) {
      this.warn(`Unable to initialize the power mode observer: ${String(error)}`);
    }
  }

  private publishBatteryLevelIfChanged(data?: commonEventManager.CommonEventData): void {
    if (!this.events.has(BATTERY_LEVEL_EVENT_NAME)) return;

    try {
      const value = this.readBatteryLevel(data);
      if (value === this.lastBatteryLevel) return;

      this.sendEvent(BATTERY_LEVEL_EVENT_NAME, new BatteryLevelEvent(value));
      this.lastBatteryLevel = value;
    } catch (error) {
      this.warn(`Unable to publish the Expo Battery level event: ${String(error)}`);
    }
  }

  private publishBatteryStateIfChanged(data?: commonEventManager.CommonEventData): void {
    if (!this.events.has(BATTERY_STATE_EVENT_NAME)) return;

    try {
      const value = this.readBatteryState(data);
      if (value === this.lastBatteryState) return;

      this.sendEvent(BATTERY_STATE_EVENT_NAME, new BatteryStateEvent(value));
      this.lastBatteryState = value;
    } catch (error) {
      this.warn(`Unable to publish the Expo Battery state event: ${String(error)}`);
    }
  }

  private publishPowerModeIfChanged(): void {
    if (!this.events.has(POWER_MODE_EVENT_NAME)) return;

    try {
      const value = this.readLowPowerMode();
      if (value === this.lastLowPowerMode) return;

      this.sendEvent(POWER_MODE_EVENT_NAME, new PowerModeEvent(value));
      this.lastLowPowerMode = value;
    } catch (error) {
      this.warn(`Unable to publish the Expo Battery power mode event: ${String(error)}`);
    }
  }

  private warn(message: string): void {
    if (this.destroyed || !this.context.isValid) return;
    this.context.logger.warn(message);
  }

  private readBatteryLevel(data?: commonEventManager.CommonEventData): number {
    try {
      const present: boolean | undefined = data?.parameters?.[batteryInfo.CommonEventBatteryChangedKey.EXTRA_PRESENT];
      const soc: number | undefined = data?.parameters?.[batteryInfo.CommonEventBatteryChangedKey.EXTRA_SOC];
      if (!(typeof present === 'boolean' ? present : batteryInfo.isBatteryPresent)) return UNKNOWN_BATTERY_LEVEL;
      return batteryLevelFromSoc(typeof soc === 'number' ? soc : batteryInfo.batterySOC);
    } catch (error) {
      throw new ExpoBatteryError('ERR_BATTERY_LEVEL', `Unable to read the HarmonyOS battery level: ${String(error)}`);
    }
  }

  private readBatteryState(data?: commonEventManager.CommonEventData): ExpoBatteryStateValue {
    try {
      const present: boolean | undefined = data?.parameters?.[batteryInfo.CommonEventBatteryChangedKey.EXTRA_PRESENT];
      const state: number | undefined = data?.parameters?.[batteryInfo.CommonEventBatteryChangedKey.EXTRA_CHARGE_STATE];
      const plugged: number | undefined = data?.parameters?.[batteryInfo.CommonEventBatteryChangedKey.EXTRA_PLUGGED_TYPE];
      if (!(typeof present === 'boolean' ? present : batteryInfo.isBatteryPresent)) return ExpoBatteryState.UNKNOWN;
      if (typeof state === 'number' && typeof plugged === 'number') return batteryStateFromChargeState(state, plugged);
      return batteryStateFromChargeState(batteryInfo.chargingStatus, batteryInfo.pluggedType);
    } catch (error) {
      throw new ExpoBatteryError('ERR_BATTERY_STATE', `Unable to read the HarmonyOS battery state: ${String(error)}`);
    }
  }

  private readLowPowerMode(): boolean {
    try {
      const mode = power.getPowerMode();

      return (
        mode === power.DevicePowerMode.MODE_POWER_SAVE ||
        mode === power.DevicePowerMode.MODE_EXTREME_POWER_SAVE ||
        (deviceInfo.sdkApiVersion >= 20 && mode === power.DevicePowerMode.MODE_CUSTOM_POWER_SAVE)
      );
    } catch (error) {
      throw new ExpoBatteryError('ERR_BATTERY_POWER_MODE', `Unable to read the HarmonyOS power mode: ${String(error)}`);
    }
  }

  private requireEventName(value: string): void {
    if (value !== BATTERY_LEVEL_EVENT_NAME && value !== BATTERY_STATE_EVENT_NAME && value !== POWER_MODE_EVENT_NAME) {
      throw new ExpoBatteryError('ERR_BATTERY_EVENT_NAME', `Expo Battery received an unsupported event name '${value}'.`);
    }
  }
}

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
const CUSTOM_POWER_SAVE_API_VERSION: number = 20;
const SUBSCRIPTION_RETRY_DELAY_MS: number = 1000;
const MAX_SUBSCRIPTION_RETRY_DELAY_MS: number = 60000;
const UNSUBSCRIPTION_RETRY_DELAY_MS: number = 1000;
const MAX_UNSUBSCRIPTION_ATTEMPTS: number = 3;
const CAPABILITY_UNSUPPORTED: number = 801;

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
  constructor(code: string, message: string, cause?: Object) {
    super(code, message, cause);
    this.name = 'ExpoBatteryError';
  }
}

interface SystemObservation {
  readonly subscriber: commonEventManager.CommonEventSubscriber;
  pending: boolean;
}

export class ExpoBatteryModule extends ExpoModule {
  private readonly events: Set<string> = new Set<string>();
  private readonly observations: Map<string, SystemObservation> = new Map<string, SystemObservation>();
  private readonly supportsBattery: boolean = canIUse('SystemCapability.PowerManager.BatteryManager.Core');
  private readonly supportsPower: boolean = canIUse('SystemCapability.PowerManager.PowerManager.Core');
  private readonly supportsCommonEvents: boolean = canIUse('SystemCapability.Notification.CommonEvent');
  private retry: number = -1;
  private retryDelay: number = SUBSCRIPTION_RETRY_DELAY_MS;
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
      .constant('isSupported', this.supportsBattery)
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
    if (this.events.has(name)) return;

    this.events.add(name);
    this.primeSnapshot(name);

    this.updateSystemObservations();
  }

  private stopObserving(name: string): void {
    this.requireEventName(name);

    this.events.delete(name);
    this.updateSystemObservations();
  }

  private updateSystemObservations(resetRetry: boolean = true): void {
    if (resetRetry) {
      this.clearRetryTimer();
      this.retryDelay = SUBSCRIPTION_RETRY_DELAY_MS;
    }

    const active = !this.destroyed && this.foreground && this.supportsCommonEvents;
    this.updateSystemObservation(
      BATTERY_SYSTEM_EVENT,
      active && this.supportsBattery && (this.events.has(BATTERY_LEVEL_EVENT_NAME) || this.events.has(BATTERY_STATE_EVENT_NAME)),
    );
    this.updateSystemObservation(POWER_MODE_SYSTEM_EVENT, active && this.supportsPower && this.events.has(POWER_MODE_EVENT_NAME));
  }

  private updateSystemObservation(event: string, enabled: boolean): void {
    if (!enabled) {
      this.stopSystemObservation(event);
      return;
    }
    if (this.observations.has(event)) return;

    try {
      const subscriber = commonEventManager.createSubscriberSync({ events: [event] });
      const observation: SystemObservation = {
        subscriber,
        pending: deviceInfo.sdkApiVersion >= SUBSCRIBE_TO_EVENT_API_VERSION,
      };
      this.observations.set(event, observation);

      if (observation.pending) {
        this.subscribeWithAcknowledgement(event, observation);
      } else {
        commonEventManager.subscribe(subscriber, (error: BusinessError, data: commonEventManager.CommonEventData): void => {
          if (this.observations.get(event) !== observation) return;
          if (error !== undefined && error !== null) {
            this.handleSubscriptionFailure(event, error);
            return;
          }

          this.receiveSystemEvent(event, observation, data);
        });

        if (this.observations.get(event) === observation) this.publishSystemEvent(event);
      }
    } catch (error) {
      this.handleSubscriptionFailure(event, error as Object);
    }
  }

  private async subscribeWithAcknowledgement(
    event: string,
    observation: SystemObservation,
  ): Promise<void> {
    try {
      await commonEventManager.subscribeToEvent(observation.subscriber, (data: commonEventManager.CommonEventData): void => {
        this.receiveSystemEvent(event, observation, data);
      });
    } catch (error) {
      if (this.observations.get(event) === observation) this.handleSubscriptionFailure(event, error as Object);
      return;
    } finally {
      observation.pending = false;
    }

    if (this.observations.get(event) === observation) {
      this.publishSystemEvent(event);
    } else {
      this.unsubscribe(observation.subscriber);
    }
  }

  private receiveSystemEvent(
    event: string,
    observation: SystemObservation,
    data: commonEventManager.CommonEventData,
  ): void {
    if (this.observations.get(event) !== observation) return;

    // A queued event may predate the snapshot taken after subscription or resume.
    if (data?.event === event) this.publishSystemEvent(event);
  }

  private stopSystemObservation(event: string): void {
    const observation = this.observations.get(event);
    this.observations.delete(event);
    if (observation !== undefined && !observation.pending) this.unsubscribe(observation.subscriber);
  }

  private unsubscribe(subscriber: commonEventManager.CommonEventSubscriber): void {
    // The legacy API can drop an unsubscribe issued before registration completes without invoking its callback.
    let attempts = 0;
    let timeout = -1;
    let removed = false;
    let failure = 'The service did not acknowledge removal.';

    const attempt = (): void => {
      attempts += 1;
      timeout = setTimeout((): void => {
        if (removed) return;
        if (attempts < MAX_UNSUBSCRIPTION_ATTEMPTS) {
          attempt();
        } else {
          this.warn(`Unable to stop observing HarmonyOS battery events: ${failure}`);
        }
      }, UNSUBSCRIPTION_RETRY_DELAY_MS);

      try {
        commonEventManager.unsubscribe(subscriber, (error: BusinessError): void => {
          if (error !== undefined && error !== null) {
            failure = String(error);
          } else {
            removed = true;
            clearTimeout(timeout);
          }
        });
      } catch (error) {
        failure = String(error);
      }
    };

    attempt();
  }

  private handleSubscriptionFailure(event: string, error: Object): void {
    this.warn(`Unable to observe HarmonyOS event '${event}': ${String(error)}`);
    this.observations.delete(event);

    if ((error as BusinessError)?.code !== CAPABILITY_UNSUPPORTED) this.scheduleSubscriptionRetry();
  }

  private scheduleSubscriptionRetry(): void {
    if (this.destroyed || !this.foreground || this.events.size === 0 || this.retry >= 0) return;

    this.retry = setTimeout((): void => {
      this.retry = -1;
      this.updateSystemObservations(false);
    }, this.retryDelay);

    this.retryDelay = Math.min(this.retryDelay * 2, MAX_SUBSCRIPTION_RETRY_DELAY_MS);
  }

  private clearRetryTimer(): void {
    if (this.retry < 0) return;

    clearTimeout(this.retry);
    this.retry = -1;
  }

  private publishSystemEvent(event: string): void {
    if (event === BATTERY_SYSTEM_EVENT) {
      this.publishBatteryLevelIfChanged();
      this.publishBatteryStateIfChanged();

      return;
    }

    this.publishPowerModeIfChanged();
  }

  private primeSnapshot(name: string): void {
    try {
      if (name === BATTERY_LEVEL_EVENT_NAME) this.lastBatteryLevel = this.readBatteryLevel();
      else if (name === BATTERY_STATE_EVENT_NAME) this.lastBatteryState = this.readBatteryState();
      else this.lastLowPowerMode = this.readLowPowerMode();
    } catch (error) {
      if (name === BATTERY_LEVEL_EVENT_NAME) this.lastBatteryLevel = undefined;
      else if (name === BATTERY_STATE_EVENT_NAME) this.lastBatteryState = undefined;
      else this.lastLowPowerMode = undefined;

      this.warn(`Unable to initialize the '${name}' observer: ${String(error)}`);
    }
  }

  private publishBatteryLevelIfChanged(): void {
    if (!this.events.has(BATTERY_LEVEL_EVENT_NAME)) return;

    try {
      const level = this.readBatteryLevel();
      if (level === this.lastBatteryLevel) return;

      this.sendEvent(BATTERY_LEVEL_EVENT_NAME, new BatteryLevelEvent(level));
      this.lastBatteryLevel = level;
    } catch (error) {
      this.warn(`Unable to publish the Expo Battery level event: ${String(error)}`);
    }
  }

  private publishBatteryStateIfChanged(): void {
    if (!this.events.has(BATTERY_STATE_EVENT_NAME)) return;

    try {
      const state = this.readBatteryState();
      if (state === this.lastBatteryState) return;

      this.sendEvent(BATTERY_STATE_EVENT_NAME, new BatteryStateEvent(state));
      this.lastBatteryState = state;
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

  private readBatteryLevel(): number {
    if (!this.supportsBattery) return UNKNOWN_BATTERY_LEVEL;

    try {
      if (!batteryInfo.isBatteryPresent) return UNKNOWN_BATTERY_LEVEL;
      return batteryLevelFromSoc(batteryInfo.batterySOC);
    } catch (error) {
      throw new ExpoBatteryError('ERR_BATTERY_LEVEL', 'Unable to read the HarmonyOS battery level.', error as Object);
    }
  }

  private readBatteryState(): ExpoBatteryStateValue {
    if (!this.supportsBattery) return ExpoBatteryState.UNKNOWN;

    try {
      if (!batteryInfo.isBatteryPresent) return ExpoBatteryState.UNKNOWN;
      return batteryStateFromChargeState(batteryInfo.chargingStatus, batteryInfo.pluggedType);
    } catch (error) {
      throw new ExpoBatteryError('ERR_BATTERY_STATE', 'Unable to read the HarmonyOS battery state.', error as Object);
    }
  }

  private readLowPowerMode(): boolean {
    if (!this.supportsPower) return false;

    try {
      const mode = power.getPowerMode();

      return (
        mode === power.DevicePowerMode.MODE_POWER_SAVE ||
        mode === power.DevicePowerMode.MODE_EXTREME_POWER_SAVE ||
        (deviceInfo.sdkApiVersion >= CUSTOM_POWER_SAVE_API_VERSION && mode === power.DevicePowerMode.MODE_CUSTOM_POWER_SAVE)
      );
    } catch (error) {
      throw new ExpoBatteryError('ERR_BATTERY_POWER_MODE', 'Unable to read the HarmonyOS power mode.', error as Object);
    }
  }

  private requireEventName(value: string): void {
    if (value !== BATTERY_LEVEL_EVENT_NAME && value !== BATTERY_STATE_EVENT_NAME && value !== POWER_MODE_EVENT_NAME) {
      throw new ExpoBatteryError('ERR_BATTERY_EVENT_NAME', `Expo Battery received an unsupported event name '${value}'.`);
    }
  }
}

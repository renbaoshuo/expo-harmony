import { ExpoAppLifecycleState, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { batteryInfo, BusinessError, commonEventManager, power } from '@kit.BasicServicesKit';
import { batteryLevelFromSoc, batteryStateFromChargeState, ExpoBatteryState, UNKNOWN_BATTERY_LEVEL } from './BatterySemantics';
import type { ExpoBatteryStateValue } from './BatterySemantics';

const BATTERY_LEVEL_EVENT_NAME: string = 'Expo.batteryLevelDidChange';
const BATTERY_STATE_EVENT_NAME: string = 'Expo.batteryStateDidChange';
const POWER_MODE_EVENT_NAME: string = 'Expo.powerModeDidChange';
const SUBSCRIPTION_RETRY_DELAY_MS: number = 1000;
const UNSUBSCRIPTION_RETRY_DELAY_MS: number = 1000;
const MAX_UNSUBSCRIPTION_ATTEMPTS: number = 3;

class BatteryLevelEvent {
  batteryLevel: number;

  constructor(batteryLevel: number) {
    this.batteryLevel = batteryLevel;
  }
}

class BatteryStateEvent {
  batteryState: ExpoBatteryStateValue;

  constructor(batteryState: ExpoBatteryStateValue) {
    this.batteryState = batteryState;
  }
}

class PowerModeEvent {
  lowPowerMode: boolean;

  constructor(lowPowerMode: boolean) {
    this.lowPowerMode = lowPowerMode;
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
  private readonly pending: Map<commonEventManager.CommonEventSubscriber, number> = new Map<commonEventManager.CommonEventSubscriber, number>();
  private readonly unsubscribing: Set<commonEventManager.CommonEventSubscriber> = new Set<commonEventManager.CommonEventSubscriber>();
  private readonly quarantine: Set<commonEventManager.CommonEventSubscriber> = new Set<commonEventManager.CommonEventSubscriber>();
  private subscriber?: commonEventManager.CommonEventSubscriber = undefined;
  private retry: number = -1;
  private unsubscribeRetry: number = -1;
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
        // Android's per-application battery optimization allowlist has no
        // HarmonyOS equivalent exposed to applications.
        return false;
      })
      .onStartObserving((eventName: string): void => {
        this.startObserving(eventName);
      })
      .onStopObserving((eventName: string): void => {
        this.stopObserving(eventName);
      })
      .onPrepareForReload(async (): Promise<void> => {
        this.destroy();
      })
      .onForeground((): void => {
        if (this.destroyed) return;
        this.foreground = true;
        this.retryQuarantinedUnsubscriptions();
        this.startSystemObservation();
      })
      .onBackground((): void => {
        this.foreground = false;
        this.stopSystemObservation();
      })
      .onDestroy((): void => {
        this.destroy();
      });
  }

  private destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.events.clear();
    this.clearRetryTimer();
    this.clearUnsubscriptionRetryTimer();
    this.stopSystemObservation();
    this.releasePendingSubscriptionsOnDestroy();
  }

  private startObserving(name: string): void {
    if (this.destroyed) return;
    this.requireEventName(name);
    this.events.add(name);
    this.retryQuarantinedUnsubscriptions();
    this.startSystemObservation();
  }

  private stopObserving(name: string): void {
    this.requireEventName(name);
    this.events.delete(name);
    if (this.events.size === 0) this.stopSystemObservation();
  }

  private startSystemObservation(): void {
    if (this.destroyed || !this.foreground || this.events.size === 0 || this.subscriber !== undefined) {
      return;
    }
    this.clearRetryTimer();

    let created: commonEventManager.CommonEventSubscriber | undefined = undefined;
    try {
      const subscriber = commonEventManager.createSubscriberSync({
        events: [commonEventManager.Support.COMMON_EVENT_BATTERY_CHANGED, commonEventManager.Support.COMMON_EVENT_POWER_SAVE_MODE_CHANGED],
      });
      created = subscriber;
      this.subscriber = subscriber;
      this.primeSnapshots();

      commonEventManager.subscribe(subscriber, (error: BusinessError, data: commonEventManager.CommonEventData): void => {
        if (this.destroyed || this.subscriber !== subscriber) return;
        if (error !== undefined && error !== null) {
          this.handleSubscriptionFailure(subscriber, error);
          return;
        }
        if (data === undefined || data === null) {
          this.warn('HarmonyOS battery event callback returned no event data.');
          return;
        }
        this.handleSystemEvent(data);
      });
    } catch (error) {
      this.subscriber = undefined;
      if (created !== undefined) this.queueUnsubscribe(created);
      this.warn(`Unable to observe HarmonyOS battery events: ${String(error)}`);
      this.scheduleSubscriptionRetry();
    }
  }

  private stopSystemObservation(): void {
    this.clearRetryTimer();
    const subscriber = this.subscriber;
    this.subscriber = undefined;
    if (subscriber !== undefined) this.queueUnsubscribe(subscriber);
  }

  private queueUnsubscribe(subscriber: commonEventManager.CommonEventSubscriber): void {
    if (!this.pending.has(subscriber)) this.pending.set(subscriber, 0);
    this.attemptUnsubscribe(subscriber);
  }

  private attemptUnsubscribe(subscriber: commonEventManager.CommonEventSubscriber): void {
    if (!this.pending.has(subscriber) || this.unsubscribing.has(subscriber) || this.quarantine.has(subscriber)) {
      return;
    }
    const attempt = (this.pending.get(subscriber) ?? 0) + 1;
    this.pending.set(subscriber, attempt);
    this.unsubscribing.add(subscriber);

    try {
      commonEventManager.unsubscribe(subscriber, (error: BusinessError): void => {
        this.unsubscribing.delete(subscriber);
        if (!this.pending.has(subscriber)) return;
        if (error === undefined || error === null) {
          this.finishUnsubscribe(subscriber);
          return;
        }
        this.handleUnsubscribeFailure(subscriber, attempt, error);
      });
    } catch (error) {
      this.unsubscribing.delete(subscriber);
      this.handleUnsubscribeFailure(subscriber, attempt, error);
    }
  }

  private handleUnsubscribeFailure(subscriber: commonEventManager.CommonEventSubscriber, attempt: number, error: Object): void {
    this.warn(`Unable to stop observing HarmonyOS battery events (attempt ${attempt}): ${String(error)}`);
    if (attempt >= MAX_UNSUBSCRIPTION_ATTEMPTS) {
      this.warn('HarmonyOS rejected the battery event unsubscription; the stale callback has been isolated.');
      this.quarantine.add(subscriber);
      this.pending.delete(subscriber);
      this.unsubscribing.delete(subscriber);
      return;
    }
    this.scheduleUnsubscriptionRetry();
  }

  private finishUnsubscribe(subscriber: commonEventManager.CommonEventSubscriber): void {
    this.pending.delete(subscriber);
    this.unsubscribing.delete(subscriber);
    this.quarantine.delete(subscriber);
    if (this.pending.size === 0) this.clearUnsubscriptionRetryTimer();
  }

  private scheduleUnsubscriptionRetry(): void {
    if (this.unsubscribeRetry >= 0 || this.pending.size === 0) return;
    this.unsubscribeRetry = setTimeout((): void => {
      this.unsubscribeRetry = -1;
      Array.from(this.pending.keys()).forEach((subscriber: commonEventManager.CommonEventSubscriber): void => {
        this.attemptUnsubscribe(subscriber);
      });
    }, UNSUBSCRIPTION_RETRY_DELAY_MS);
  }

  private clearUnsubscriptionRetryTimer(): void {
    if (this.unsubscribeRetry < 0) return;
    clearTimeout(this.unsubscribeRetry);
    this.unsubscribeRetry = -1;
  }

  private retryQuarantinedUnsubscriptions(): void {
    if (this.destroyed || this.quarantine.size === 0) return;
    Array.from(this.quarantine).forEach((subscriber: commonEventManager.CommonEventSubscriber): void => {
      this.quarantine.delete(subscriber);
      if (!this.pending.has(subscriber)) this.pending.set(subscriber, 0);
      this.attemptUnsubscribe(subscriber);
    });
  }

  private releasePendingSubscriptionsOnDestroy(): void {
    this.quarantine.clear();
    Array.from(this.pending.keys()).forEach((subscriber: commonEventManager.CommonEventSubscriber): void => {
      if (this.unsubscribing.has(subscriber)) return;
      this.pending.set(subscriber, 0);
      this.attemptUnsubscribe(subscriber);
    });
  }

  private handleSubscriptionFailure(subscriber: commonEventManager.CommonEventSubscriber, error: BusinessError): void {
    if (this.subscriber !== subscriber) return;
    this.subscriber = undefined;
    this.warn(`HarmonyOS battery event observation failed: ${String(error)}`);
    this.queueUnsubscribe(subscriber);
    this.scheduleSubscriptionRetry();
  }

  private scheduleSubscriptionRetry(): void {
    if (this.destroyed || !this.foreground || this.events.size === 0 || this.retry >= 0) return;
    this.retry = setTimeout((): void => {
      this.retry = -1;
      this.startSystemObservation();
    }, SUBSCRIPTION_RETRY_DELAY_MS);
  }

  private clearRetryTimer(): void {
    if (this.retry < 0) return;
    clearTimeout(this.retry);
    this.retry = -1;
  }

  private handleSystemEvent(data: commonEventManager.CommonEventData): void {
    if (data.event === commonEventManager.Support.COMMON_EVENT_BATTERY_CHANGED) {
      this.publishBatteryLevelIfChanged();
      this.publishBatteryStateIfChanged();
      return;
    }
    if (data.event === commonEventManager.Support.COMMON_EVENT_POWER_SAVE_MODE_CHANGED) {
      this.publishPowerModeIfChanged();
    }
  }

  private primeSnapshots(): void {
    try {
      if (this.events.has(BATTERY_LEVEL_EVENT_NAME)) this.lastBatteryLevel = this.readBatteryLevel();
    } catch (error) {
      this.warn(`Unable to initialize the battery level observer: ${String(error)}`);
    }
    try {
      if (this.events.has(BATTERY_STATE_EVENT_NAME)) this.lastBatteryState = this.readBatteryState();
    } catch (error) {
      this.warn(`Unable to initialize the battery state observer: ${String(error)}`);
    }
    try {
      if (this.events.has(POWER_MODE_EVENT_NAME)) this.lastLowPowerMode = this.readLowPowerMode();
    } catch (error) {
      this.warn(`Unable to initialize the power mode observer: ${String(error)}`);
    }
  }

  private publishBatteryLevelIfChanged(): void {
    if (!this.events.has(BATTERY_LEVEL_EVENT_NAME)) return;
    try {
      const value = this.readBatteryLevel();
      if (value === this.lastBatteryLevel) return;
      this.sendEvent(BATTERY_LEVEL_EVENT_NAME, new BatteryLevelEvent(value));
      this.lastBatteryLevel = value;
    } catch (error) {
      this.warn(`Unable to publish the Expo Battery level event: ${String(error)}`);
    }
  }

  private publishBatteryStateIfChanged(): void {
    if (!this.events.has(BATTERY_STATE_EVENT_NAME)) return;
    try {
      const value = this.readBatteryState();
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

  private readBatteryLevel(): number {
    try {
      if (!batteryInfo.isBatteryPresent) return UNKNOWN_BATTERY_LEVEL;
      return batteryLevelFromSoc(batteryInfo.batterySOC);
    } catch (error) {
      throw new ExpoBatteryError('ERR_BATTERY_LEVEL', `Unable to read the HarmonyOS battery level: ${String(error)}`);
    }
  }

  private readBatteryState(): ExpoBatteryStateValue {
    try {
      if (!batteryInfo.isBatteryPresent) return ExpoBatteryState.UNKNOWN;
      return batteryStateFromChargeState(batteryInfo.chargingStatus);
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
        mode === power.DevicePowerMode.MODE_CUSTOM_POWER_SAVE
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

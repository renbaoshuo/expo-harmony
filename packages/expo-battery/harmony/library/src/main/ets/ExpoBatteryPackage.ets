import { LifecycleState, RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { EXPO_MODULE_EVENT, ExpoPlatformServiceError, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import { batteryInfo, BusinessError, commonEventManager, power } from '@kit.BasicServicesKit';
import { batteryLevelFromSoc, batteryStateFromChargeState, ExpoBatteryState, UNKNOWN_BATTERY_LEVEL } from './BatterySemantics';
import type { ExpoBatteryStateValue } from './BatterySemantics';

const SERVICE_NAME: string = 'ExpoBatteryService';
const MODULE_NAME: string = 'ExpoBattery';
const GET_BATTERY_LEVEL_METHOD: string = 'getBatteryLevelAsync';
const GET_BATTERY_STATE_METHOD: string = 'getBatteryStateAsync';
const GET_LOW_POWER_MODE_METHOD: string = 'isLowPowerModeEnabledAsync';
const START_OBSERVING_METHOD: string = 'startObserving';
const STOP_OBSERVING_METHOD: string = 'stopObserving';
const BATTERY_LEVEL_EVENT_NAME: string = 'Expo.batteryLevelDidChange';
const BATTERY_STATE_EVENT_NAME: string = 'Expo.batteryStateDidChange';
const POWER_MODE_EVENT_NAME: string = 'Expo.powerModeDidChange';
const SUBSCRIPTION_RETRY_DELAY_MS: number = 1000;
const UNSUBSCRIPTION_RETRY_DELAY_MS: number = 1000;
const MAX_UNSUBSCRIPTION_ATTEMPTS: number = 3;
let registered: boolean = false;

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

class BatteryLevelEventMessage {
  moduleName: string = MODULE_NAME;
  eventName: string = BATTERY_LEVEL_EVENT_NAME;
  arguments: BatteryLevelEvent[];

  constructor(batteryLevel: number) {
    this.arguments = [new BatteryLevelEvent(batteryLevel)];
  }
}

class BatteryStateEventMessage {
  moduleName: string = MODULE_NAME;
  eventName: string = BATTERY_STATE_EVENT_NAME;
  arguments: BatteryStateEvent[];

  constructor(batteryState: ExpoBatteryStateValue) {
    this.arguments = [new BatteryStateEvent(batteryState)];
  }
}

class PowerModeEventMessage {
  moduleName: string = MODULE_NAME;
  eventName: string = POWER_MODE_EVENT_NAME;
  arguments: PowerModeEvent[];

  constructor(lowPowerMode: boolean) {
    this.arguments = [new PowerModeEvent(lowPowerMode)];
  }
}

class ExpoBatteryError extends ExpoPlatformServiceError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoBatteryError';
  }
}

class ExpoBatteryService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;
  private readonly events: Set<string> = new Set();
  private readonly cleanups: Array<() => void> = [];
  private readonly pending: Map<commonEventManager.CommonEventSubscriber, number> = new Map();
  private readonly unsubscribing: Set<commonEventManager.CommonEventSubscriber> = new Set();
  private readonly quarantine: Set<commonEventManager.CommonEventSubscriber> = new Set();
  private subscriber?: commonEventManager.CommonEventSubscriber;
  private retry: number = -1;
  private unsubscribeRetry: number = -1;
  private foreground: boolean;
  private destroyed: boolean = false;

  constructor(context: UITurboModuleContext) {
    this.context = context;
    this.foreground = context.rnInstance.getLifecycleState() === LifecycleState.READY;

    this.cleanups.push(
      context.rnInstance.subscribeToLifecycleEvents('JS_BUNDLE_EXECUTION_FINISH', (): void => {
        this.foreground = true;
        this.retryQuarantinedUnsubscriptions();
        this.startSystemObservation();
      }),
      context.rnInstance.subscribeToLifecycleEvents('FOREGROUND', (): void => {
        this.foreground = true;
        this.retryQuarantinedUnsubscriptions();
        this.startSystemObservation();
      }),
      context.rnInstance.subscribeToLifecycleEvents('BACKGROUND', (): void => {
        this.foreground = false;
        this.stopSystemObservation();
      }),
    );
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (method === GET_BATTERY_LEVEL_METHOD) return this.readBatteryLevel();
    if (method === GET_BATTERY_STATE_METHOD) return this.readBatteryState();
    if (method === GET_LOW_POWER_MODE_METHOD) return this.readLowPowerMode();

    if (method === START_OBSERVING_METHOD) {
      this.startObserving(requireEventName(args[0]));

      return null;
    }

    if (method === STOP_OBSERVING_METHOD) {
      this.stopObserving(requireEventName(args[0]));

      return null;
    }

    throw new ExpoBatteryError('ERR_BATTERY_UNKNOWN_METHOD', `Unknown Expo Battery Harmony method '${method}'.`);
  }

  invokeSync(method: string, _: ESObject[]): ESObject {
    throw new ExpoBatteryError('ERR_BATTERY_ASYNC_METHOD', `Expo Battery Harmony method '${method}' is asynchronous.`);
  }

  onDestroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.events.clear();

    this.clearRetryTimer();
    this.clearUnsubscriptionRetryTimer();
    this.stopSystemObservation();
    this.releasePendingSubscriptionsOnDestroy();
    this.cleanups.forEach((cleanup: () => void): void => cleanup());
    this.cleanups.length = 0;
  }

  private startObserving(name: string): void {
    if (this.destroyed) return;

    this.events.add(name);

    this.retryQuarantinedUnsubscriptions();
    this.startSystemObservation();
  }

  private stopObserving(name: string): void {
    this.events.delete(name);

    if (this.events.size === 0) this.stopSystemObservation();
  }

  private startSystemObservation(): void {
    if (this.destroyed || !this.foreground || this.events.size === 0 || this.subscriber !== undefined || this.pending.size > 0) return;

    this.clearRetryTimer();

    let created: commonEventManager.CommonEventSubscriber | undefined = undefined;
    try {
      const subscriber = commonEventManager.createSubscriberSync({
        events: [commonEventManager.Support.COMMON_EVENT_BATTERY_CHANGED, commonEventManager.Support.COMMON_EVENT_POWER_SAVE_MODE_CHANGED],
      });
      created = subscriber;
      this.subscriber = subscriber;

      commonEventManager.subscribe(subscriber, (error: BusinessError, data: commonEventManager.CommonEventData): void => {
        if (this.destroyed || this.subscriber !== subscriber) return;

        if (error !== undefined && error !== null) {
          this.handleSubscriptionFailure(subscriber, error);

          return;
        }

        if (data === undefined || data === null) {
          this.context.logger.warn('HarmonyOS battery event callback returned no event data.');

          return;
        }

        this.handleSystemEvent(data);
      });
    } catch (error) {
      this.subscriber = undefined;
      if (created !== undefined) this.queueUnsubscribe(created);

      this.context.logger.warn(`Unable to observe HarmonyOS battery events: ${String(error)}`);
      this.scheduleSubscriptionRetry();
    }
  }

  private stopSystemObservation(): void {
    this.clearRetryTimer();

    const subscriber = this.subscriber;
    this.subscriber = undefined;

    if (subscriber === undefined) return;

    this.queueUnsubscribe(subscriber);
  }

  private queueUnsubscribe(subscriber: commonEventManager.CommonEventSubscriber): void {
    if (!this.pending.has(subscriber)) this.pending.set(subscriber, 0);

    this.attemptUnsubscribe(subscriber);
  }

  private attemptUnsubscribe(subscriber: commonEventManager.CommonEventSubscriber): void {
    if (!this.pending.has(subscriber) || this.unsubscribing.has(subscriber) || this.quarantine.has(subscriber)) return;

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
    this.context.logger.warn(`Unable to stop observing HarmonyOS battery events (attempt ${attempt}): ${String(error)}`);

    if (attempt >= MAX_UNSUBSCRIPTION_ATTEMPTS) {
      this.context.logger.warn('HarmonyOS battery observation is paused until the failed subscriber can be released.');
      this.quarantine.add(subscriber);

      return;
    }

    this.scheduleUnsubscriptionRetry();
  }

  private finishUnsubscribe(subscriber: commonEventManager.CommonEventSubscriber): void {
    this.pending.delete(subscriber);
    this.unsubscribing.delete(subscriber);
    this.quarantine.delete(subscriber);

    if (this.pending.size === 0) {
      this.clearUnsubscriptionRetryTimer();

      if (!this.destroyed) this.startSystemObservation();
    }
  }

  private scheduleUnsubscriptionRetry(): void {
    if (this.unsubscribeRetry >= 0 || this.pending.size === 0) return;

    this.unsubscribeRetry = setTimeout((): void => {
      this.unsubscribeRetry = -1;

      const subscribers = Array.from(this.pending.keys());

      subscribers.forEach((subscriber: commonEventManager.CommonEventSubscriber): void => {
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

    const subscribers = Array.from(this.quarantine);

    subscribers.forEach((subscriber: commonEventManager.CommonEventSubscriber): void => {
      this.quarantine.delete(subscriber);
      this.pending.set(subscriber, 0);

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

    this.context.logger.warn(`HarmonyOS battery event observation failed: ${String(error)}`);

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
    try {
      const event = data.event;

      if (event === commonEventManager.Support.COMMON_EVENT_BATTERY_CHANGED) {
        if (this.events.has(BATTERY_LEVEL_EVENT_NAME)) {
          this.context.rnInstance.postMessageToCpp(EXPO_MODULE_EVENT, new BatteryLevelEventMessage(this.readBatteryLevel()));
        }

        if (this.events.has(BATTERY_STATE_EVENT_NAME)) {
          this.context.rnInstance.postMessageToCpp(EXPO_MODULE_EVENT, new BatteryStateEventMessage(this.readBatteryState()));
        }

        return;
      }

      if (event === commonEventManager.Support.COMMON_EVENT_POWER_SAVE_MODE_CHANGED && this.events.has(POWER_MODE_EVENT_NAME)) {
        this.context.rnInstance.postMessageToCpp(EXPO_MODULE_EVENT, new PowerModeEventMessage(this.readLowPowerMode()));
      }
    } catch (error) {
      this.context.logger.warn(`Unable to publish an Expo Battery event: ${String(error)}`);
    }
  }

  private readBatteryLevel(): number {
    try {
      if (!batteryInfo.isBatteryPresent) return UNKNOWN_BATTERY_LEVEL;

      const soc = batteryInfo.batterySOC;

      return batteryLevelFromSoc(soc);
    } catch (error) {
      throw new ExpoBatteryError('ERR_BATTERY_LEVEL', `Unable to read the HarmonyOS battery level: ${String(error)}`);
    }
  }

  private readBatteryState(): ExpoBatteryStateValue {
    try {
      if (!batteryInfo.isBatteryPresent) return ExpoBatteryState.UNKNOWN;

      const status = batteryInfo.chargingStatus;

      return batteryStateFromChargeState(status);
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
}

function requireEventName(value: ESObject): string {
  if (typeof value !== 'string' || !isBatteryEventName(value)) {
    throw new ExpoBatteryError('ERR_BATTERY_EVENT_NAME', 'Expo Battery received an unsupported event name.');
  }

  return value;
}

function isBatteryEventName(value: string): boolean {
  return value === BATTERY_LEVEL_EVENT_NAME || value === BATTERY_STATE_EVENT_NAME || value === POWER_MODE_EVENT_NAME;
}

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new ExpoBatteryService(context),
  });

  registered = true;
}

export class ExpoBatteryPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerService();
    super(context);
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-battery';
  }
}

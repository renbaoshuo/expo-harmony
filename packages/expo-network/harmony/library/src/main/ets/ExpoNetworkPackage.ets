import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { EXPO_MODULE_EVENT, ExpoPlatformServiceError, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import { connection } from '@kit.NetworkKit';
import { BusinessError, settings } from '@kit.BasicServicesKit';

const SERVICE_NAME: string = 'ExpoNetworkService';
const MODULE_NAME: string = 'ExpoNetwork';
const NETWORK_STATE_EVENT_NAME: string = 'onNetworkStateChanged';
const NETWORK_CHANGE_DELAY_MS: number = 250;
const NETWORK_OBSERVER_RETRY_DELAY_MS: number = 1000;
const FALLBACK_IP_ADDRESS: string = '0.0.0.0';
const AIRPLANE_MODE_STATUS_KEY: string = 'settings.telephony.airplanemode';
// Kept for devices that still expose the legacy Settings key.
const LEGACY_AIRPLANE_MODE_STATUS_KEY: string = 'settings.general.airplane_mode_status';
let registered: boolean = false;

enum NetworkStateType {
  NONE = 'NONE',
  UNKNOWN = 'UNKNOWN',
  CELLULAR = 'CELLULAR',
  WIFI = 'WIFI',
  BLUETOOTH = 'BLUETOOTH',
  ETHERNET = 'ETHERNET',
  VPN = 'VPN',
}

class ExpoNetworkError extends ExpoPlatformServiceError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoNetworkError';
  }
}

class NetworkState {
  type: NetworkStateType;
  isConnected: boolean;
  isInternetReachable: boolean;

  constructor(type: NetworkStateType, isConnected: boolean, isInternetReachable: boolean) {
    this.type = type;
    this.isConnected = isConnected;
    this.isInternetReachable = isInternetReachable;
  }
}

class ModuleEventMessage {
  moduleName: string = MODULE_NAME;
  eventName: string = NETWORK_STATE_EVENT_NAME;
  arguments: NetworkState[];

  constructor(state: NetworkState) {
    this.arguments = [state];
  }
}

class ExpoNetworkService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;
  private observer?: connection.NetConnection;
  private timer: number = -1;
  private retryTimer: number = -1;
  private observing: boolean = false;
  private destroyed: boolean = false;
  private eventRevision: number = 0;

  constructor(context: UITurboModuleContext) {
    this.context = context;
  }

  async invoke(method: string, _: ESObject[]): Promise<ESObject> {
    if (method === 'getNetworkStateAsync') return await this.readNetworkState();
    if (method === 'getIpAddressAsync') return await this.readIpAddress();
    if (method === 'isAirplaneModeEnabledAsync') return await this.readAirplaneMode();
    if (method === 'startObserving') {
      this.startObserving();
      return null;
    }
    if (method === 'stopObserving') {
      this.stopObserving();
      return null;
    }

    throw new ExpoNetworkError('ERR_NETWORK_UNKNOWN_METHOD', `Unknown ExpoNetwork Harmony method '${method}'.`);
  }

  invokeSync(method: string, _: ESObject[]): ESObject {
    throw new ExpoNetworkError('ERR_NETWORK_ASYNC_METHOD', `ExpoNetwork Harmony method '${method}' is asynchronous.`);
  }

  onDestroy(): void {
    this.destroy();
  }

  private startObserving(): void {
    if (this.destroyed || this.observing) return;

    this.observing = true;
    this.registerObserver();
  }

  private registerObserver(): void {
    if (this.destroyed || !this.observing || this.observer !== undefined) return;

    try {
      const observer = connection.createNetConnection();

      observer.on('netAvailable', (_: connection.NetHandle): void => this.scheduleNetworkStateEvent());
      observer.on('netLost', (_: connection.NetHandle): void => this.scheduleNetworkStateEvent());
      observer.on('netUnavailable', (): void => this.scheduleNetworkStateEvent());
      observer.on('netCapabilitiesChange', (_: connection.NetCapabilityInfo): void => this.scheduleNetworkStateEvent());

      this.observer = observer;
      observer.register((error: BusinessError): void => {
        if (error !== undefined && error !== null) {
          if (this.observer !== observer) return;

          this.observer = undefined;
          this.context.logger.warn(`Unable to observe Expo Network state changes: ${String(error)}`);

          this.scheduleObserverRetry();
          return;
        }

        if (this.destroyed || !this.observing || this.observer !== observer) {
          this.unregisterObserver(observer);
          return;
        }

        this.scheduleNetworkStateEvent();
      });
    } catch (error) {
      this.observer = undefined;
      this.context.logger.warn(`Unable to initialize the Expo Network observer: ${String(error)}`);

      this.scheduleObserverRetry();
    }
  }

  private scheduleObserverRetry(): void {
    if (this.destroyed || !this.observing || this.retryTimer >= 0) return;

    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.registerObserver();
    }, NETWORK_OBSERVER_RETRY_DELAY_MS);
  }

  private unregisterObserver(observer: connection.NetConnection): void {
    try {
      observer.unregister((error: BusinessError): void => {
        if (error !== undefined && error !== null) {
          this.context.logger.warn(`Unable to stop the Expo Network observer: ${String(error)}`);
        }
      });
    } catch (error) {
      this.context.logger.warn(`Unable to stop the Expo Network observer: ${String(error)}`);
    }
  }

  private stopObserving(): void {
    this.observing = false;
    this.eventRevision += 1;
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }

    const observer = this.observer;
    this.observer = undefined;
    if (observer === undefined) return;

    this.unregisterObserver(observer);
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.stopObserving();
  }

  private scheduleNetworkStateEvent(): void {
    if (this.destroyed || !this.observing) return;
    if (this.timer >= 0) clearTimeout(this.timer);
    const revision = ++this.eventRevision;

    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.publishNetworkState(revision).catch((error: Object): void => {
        this.context.logger.warn(`Unable to publish an Expo Network state change: ${String(error)}`);
      });
    }, NETWORK_CHANGE_DELAY_MS);
  }

  private async publishNetworkState(revision: number): Promise<void> {
    if (this.destroyed || !this.observing || revision !== this.eventRevision) return;

    const state = await this.readNetworkState();
    if (this.destroyed || !this.observing) return;

    this.context.rnInstance.postMessageToCpp(EXPO_MODULE_EVENT, new ModuleEventMessage(state));
  }

  private async readNetworkState(): Promise<NetworkState> {
    let handle: connection.NetHandle;
    try {
      handle = await connection.getDefaultNet();
    } catch (_) {
      return disconnectedState();
    }
    if (handle.netId <= 0) return disconnectedState();

    try {
      const caps = await connection.getNetCapabilities(handle);
      const type = networkType(caps.bearerTypes);
      const isConnected = type !== NetworkStateType.NONE && type !== NetworkStateType.UNKNOWN;
      // Match the Android API 29+ contract: an active default network is reachable.
      const isInternetReachable = handle.netId > 0;

      return new NetworkState(type, isConnected, isInternetReachable);
    } catch (_) {
      // The default network still exists even when its capabilities cannot be read.
      return new NetworkState(NetworkStateType.UNKNOWN, false, true);
    }
  }

  private async readIpAddress(): Promise<string> {
    try {
      const handle = await connection.getDefaultNet();
      if (handle.netId <= 0) return FALLBACK_IP_ADDRESS;

      const properties = await connection.getConnectionProperties(handle);

      for (let index = 0; index < properties.linkAddresses.length; ++index) {
        const address = properties.linkAddresses[index].address;
        if (isUsableIpv4Address(address)) return address.address;
      }
    } catch (_) {}

    return FALLBACK_IP_ADDRESS;
  }

  private async readAirplaneMode(): Promise<boolean> {
    const keys: string[] = [AIRPLANE_MODE_STATUS_KEY, LEGACY_AIRPLANE_MODE_STATUS_KEY];
    for (const key of keys) {
      try {
        const value = settings.getValueSync(this.context.uiAbilityContext, key, '');
        const result = parseAirplaneMode(value);
        if (result !== undefined) return result;
      } catch (error) {
        this.context.logger.warn(`Unable to read the HarmonyOS airplane mode setting '${key}': ${String(error)}`);
      }
    }

    this.context.logger.warn('HarmonyOS did not expose a readable airplane mode setting; returning false.');
    return false;
  }
}

function parseAirplaneMode(value: string): boolean | undefined {
  const mode = value.trim().toLowerCase();
  if (mode === 'true') return true;
  if (mode === 'false') return false;
  if (!/^[+-]?\d+$/.test(mode)) return undefined;

  const number = Number(mode);
  return Number.isSafeInteger(number) ? number !== 0 : undefined;
}

function disconnectedState(): NetworkState {
  return new NetworkState(NetworkStateType.NONE, false, false);
}

function networkType(bearers: connection.NetBearType[]): NetworkStateType {
  if (bearers.includes(connection.NetBearType.BEARER_CELLULAR)) return NetworkStateType.CELLULAR;
  if (bearers.includes(connection.NetBearType.BEARER_WIFI)) return NetworkStateType.WIFI;
  if (bearers.includes(connection.NetBearType.BEARER_BLUETOOTH)) return NetworkStateType.BLUETOOTH;
  if (bearers.includes(connection.NetBearType.BEARER_ETHERNET)) return NetworkStateType.ETHERNET;
  if (bearers.includes(connection.NetBearType.BEARER_VPN)) return NetworkStateType.VPN;
  return NetworkStateType.UNKNOWN;
}

function isUsableIpv4Address(address: connection.NetAddress): boolean {
  const value = address.address;
  if (!/^\d{1,3}(?:\.\d{1,3}){3}$/.test(value)) return false;
  if (value === FALLBACK_IP_ADDRESS || value.startsWith('127.')) return false;

  const octets = value.split('.');

  return octets.every((octet: string): boolean => {
    const number = Number(octet);
    return Number.isInteger(number) && number >= 0 && number <= 255;
  });
}

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new ExpoNetworkService(context),
  });
  registered = true;
}

export class ExpoNetworkPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerService();
    super(context);
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-network';
  }
}

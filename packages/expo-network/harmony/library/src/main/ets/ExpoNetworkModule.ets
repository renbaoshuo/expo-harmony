import { ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { connection } from '@kit.NetworkKit';
import { BusinessError, settings } from '@kit.BasicServicesKit';

const STATE_EVENT: string = 'onNetworkStateChanged';
const CHANGE_DELAY_MS: number = 250;
const RETRY_BASE_DELAY_MS: number = 500;
const RETRY_MAX_DELAY_MS: number = 8000;
const RETRY_LIMIT: number = 5;
const FALLBACK_IP: string = '0.0.0.0';
const MISSING_SETTING: string = '__expo_network_setting_missing__';
const TRANSIENT_ERRORS: Set<number> = new Set<number>([2100002, 2100003]);

enum NetworkStateType {
  NONE = 'NONE',
  UNKNOWN = 'UNKNOWN',
  CELLULAR = 'CELLULAR',
  WIFI = 'WIFI',
  BLUETOOTH = 'BLUETOOTH',
  ETHERNET = 'ETHERNET',
  VPN = 'VPN',
}

class NetworkState {
  type: NetworkStateType;
  isConnected: boolean;
  isInternetReachable: boolean;

  constructor(type: NetworkStateType, connected: boolean, reachable: boolean) {
    this.type = type;
    this.isConnected = connected;
    this.isInternetReachable = reachable;
  }
}

export class ExpoNetworkModule extends ExpoModule {
  private observer?: connection.NetConnection;
  private readonly eventTimers: Set<number> = new Set<number>();
  private readonly pending: Set<connection.NetConnection> = new Set<connection.NetConnection>();
  private retryTimer: number = -1;
  private attempt: number = 0;
  private observing: boolean = false;
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoNetwork')
      .events([STATE_EVENT])
      .asyncFunction('getNetworkStateAsync', async (): Promise<NetworkState> => {
        return await this.readNetworkState();
      })
      .asyncFunction('getIpAddressAsync', async (): Promise<string> => {
        return await this.readIpAddress();
      })
      .asyncFunction('isAirplaneModeEnabledAsync', async (): Promise<boolean> => {
        return await this.readAirplaneMode();
      })
      .onStartObserving(STATE_EVENT, (): void => this.startObserving())
      .onStopObserving(STATE_EVENT, (): void => this.stopObserving())
      .onAbilityDestroy((): void => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private startObserving(): void {
    if (this.destroyed || this.observing) return;

    this.observing = true;
    this.attempt = 0;
    this.registerObserver();
  }

  private registerObserver(): void {
    if (this.destroyed || !this.observing || this.observer !== undefined) return;

    let observer: connection.NetConnection | undefined;
    try {
      const current = connection.createNetConnection();
      observer = current;

      current.on('netAvailable', (_: connection.NetHandle): void => this.scheduleNetworkStateEvent(current));
      current.on('netLost', (_: connection.NetHandle): void => this.scheduleNetworkStateEvent(current));
      current.on('netUnavailable', (): void => this.scheduleNetworkStateEvent(current));
      current.on('netCapabilitiesChange', (_: connection.NetCapabilityInfo): void => this.scheduleNetworkStateEvent(current));

      this.observer = current;
      current.register((error: BusinessError): void => {
        if (error !== undefined && error !== null) {
          if (this.observer !== current) return;

          this.observer = undefined;
          if (!this.destroyed) {
            this.context.logger.warn(`Unable to observe Expo Network state changes: ${String(error)}`);
          }

          this.unregisterObserver(current);
          this.scheduleObserverRetry(error);
          return;
        }

        if (this.destroyed || !this.observing || this.observer !== current) {
          this.unregisterObserver(current);
          return;
        }

        this.attempt = 0;
        this.scheduleNetworkStateEvent(current);
      });
    } catch (error) {
      if (this.observer === observer) this.observer = undefined;
      if (observer !== undefined) this.unregisterObserver(observer);
      if (!this.destroyed) {
        this.context.logger.warn(`Unable to initialize the Expo Network observer: ${String(error)}`);
      }

      this.scheduleObserverRetry(error);
    }
  }

  private scheduleObserverRetry(error: Object): void {
    if (this.destroyed || !this.observing || this.retryTimer >= 0) return;
    if (!isTransientNetworkError(error) || this.attempt >= RETRY_LIMIT) return;

    const delay = Math.min(RETRY_BASE_DELAY_MS * Math.pow(2, this.attempt), RETRY_MAX_DELAY_MS);
    const jitter = Math.floor(Math.random() * RETRY_BASE_DELAY_MS);
    this.attempt += 1;

    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.registerObserver();
    }, delay + jitter);
  }

  private unregisterObserver(observer: connection.NetConnection, attempt: number = 0): void {
    if (this.pending.has(observer) && attempt === 0) return;

    this.pending.add(observer);
    try {
      observer.unregister((error: BusinessError): void => {
        if (error === undefined || error === null) {
          this.pending.delete(observer);
          return;
        }

        if (!this.destroyed) {
          this.context.logger.warn(`Unable to stop the Expo Network observer: ${String(error)}`);
        }

        if (isTransientNetworkError(error) && attempt < RETRY_LIMIT) {
          setTimeout(
            (): void => {
              this.unregisterObserver(observer, attempt + 1);
            },
            Math.min(RETRY_BASE_DELAY_MS * Math.pow(2, attempt), RETRY_MAX_DELAY_MS),
          );
        }
      });
    } catch (error) {
      if (!this.destroyed) {
        this.context.logger.warn(`Unable to stop the Expo Network observer: ${String(error)}`);
      }
    }
  }

  private stopObserving(): void {
    this.observing = false;

    this.eventTimers.forEach((timer: number): void => clearTimeout(timer));
    this.eventTimers.clear();

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

  private scheduleNetworkStateEvent(observer: connection.NetConnection): void {
    if (this.destroyed || !this.observing || this.observer !== observer) return;

    const timer = setTimeout((): void => {
      this.eventTimers.delete(timer);
      this.publishNetworkState(observer).catch((error: Object): void => {
        if (!this.destroyed) {
          this.context.logger.warn(`Unable to publish an Expo Network state change: ${String(error)}`);
        }
      });
    }, CHANGE_DELAY_MS);
    this.eventTimers.add(timer);
  }

  private async publishNetworkState(observer: connection.NetConnection): Promise<void> {
    if (this.destroyed || !this.observing || this.observer !== observer) return;

    const state = await this.readNetworkState();
    if (this.destroyed || !this.observing || this.observer !== observer) return;

    this.sendEvent(STATE_EVENT, state);
  }

  private async readNetworkState(): Promise<NetworkState> {
    let handle: connection.NetHandle;
    try {
      handle = await connection.getDefaultNet();
    } catch (_) {
      return unknownState();
    }

    if (handle.netId === 0) return disconnectedState();
    if (handle.netId < 0) return unknownState();

    try {
      const capabilities = await connection.getNetCapabilities(handle);

      const type = networkType(capabilities.bearerTypes);
      const flags = capabilities.networkCap ?? [];
      const reachable = flags.includes(connection.NetCap.NET_CAPABILITY_INTERNET) && flags.includes(connection.NetCap.NET_CAPABILITY_VALIDATED);

      return new NetworkState(type, true, reachable);
    } catch (_) {
      return unknownState();
    }
  }

  private async readIpAddress(): Promise<string> {
    let handle: connection.NetHandle;
    try {
      handle = await connection.getDefaultNet();
    } catch (error) {
      throw new ExpoModuleError('ERR_NETWORK_IP_ADDRESS', 'Unable to query the default HarmonyOS network.', error as Object);
    }

    if (handle.netId === 0) return FALLBACK_IP;
    if (handle.netId < 0) {
      throw new ExpoModuleError('ERR_NETWORK_IP_ADDRESS', 'HarmonyOS returned an invalid network handle.');
    }

    let properties: connection.ConnectionProperties;
    try {
      properties = await connection.getConnectionProperties(handle);
    } catch (error) {
      throw new ExpoModuleError('ERR_NETWORK_IP_ADDRESS', 'Unable to query HarmonyOS network connection properties.', error as Object);
    }

    for (let index = 0; index < properties.linkAddresses.length; ++index) {
      const address = properties.linkAddresses[index].address;
      if (isUsableIpv4Address(address)) return address.address;
    }

    return FALLBACK_IP;
  }

  private async readAirplaneMode(): Promise<boolean> {
    let value: string;
    try {
      value = settings.getValueSync(this.context.uiAbilityContext, settings.general.AIRPLANE_MODE_STATUS, MISSING_SETTING);
    } catch (error) {
      throw new ExpoModuleError('ERR_NETWORK_AIRPLANE_MODE', 'Unable to read the HarmonyOS airplane mode setting.', error as Object);
    }

    if (value === MISSING_SETTING) return false;
    if (value === '0') return false;
    if (value === '1') return true;

    throw new ExpoModuleError('ERR_NETWORK_AIRPLANE_MODE', `HarmonyOS returned an invalid airplane mode value: '${value}'.`);
  }
}

function disconnectedState(): NetworkState {
  return new NetworkState(NetworkStateType.NONE, false, false);
}

function unknownState(): NetworkState {
  return new NetworkState(NetworkStateType.UNKNOWN, false, false);
}

function isTransientNetworkError(error: Object): boolean {
  const code = (error as BusinessError).code;
  return typeof code === 'number' && TRANSIENT_ERRORS.has(code);
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
  if (value === FALLBACK_IP || value.startsWith('127.')) return false;

  const octets = value.split('.');

  return octets.every((octet: string): boolean => {
    const number = Number(octet);
    return Number.isInteger(number) && number >= 0 && number <= 255;
  });
}

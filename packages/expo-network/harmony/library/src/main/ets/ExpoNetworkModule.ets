/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { connection } from '@kit.NetworkKit';
import { BusinessError, settings } from '@kit.BasicServicesKit';

const STATE_EVENT: string = 'onNetworkStateChanged';
const CHANGE_DELAY_MS: number = 250;
const RETRY_BASE_DELAY_MS: number = 500;
const RETRY_MAX_DELAY_MS: number = 8000;
const RETRY_LIMIT: number = 5;
const FALLBACK_IP: string = '0.0.0.0';
// NetworkKit reserves 0 for no default network. Assigned IDs start at 100.
const FIRST_NETWORK_ID: number = 100;
const INVALID_NETWORK_ARGUMENT: number = 2100001;
const SERVICE_UNAVAILABLE: number = 2100002;
const INTERNAL_ERROR: number = 2100003;

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
  private observerRegistered: boolean = false;
  private changeTimer: number = -1;
  private pendingImmediateChange: boolean = false;
  private revision: number = 0;
  private retryTimer: number = -1;
  private attempt: number = 0;
  private observing: boolean = false;
  private destroyed: boolean = false;
  private readonly lostNetworkIds: Set<number> = new Set<number>();
  private readonly blockedNetworkIds: Set<number> = new Set<number>();

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

    try {
      const current = connection.createNetConnection();
      this.lostNetworkIds.clear();
      this.blockedNetworkIds.clear();

      current.on('netAvailable', (handle: connection.NetHandle): void => {
        if (this.observer !== current) return;

        this.lostNetworkIds.delete(handle.netId);
        this.scheduleNetworkStateEvent(current);
      });
      current.on('netLost', (handle: connection.NetHandle): void => {
        if (this.observer !== current) return;

        this.lostNetworkIds.add(handle.netId);
        this.blockedNetworkIds.delete(handle.netId);
        this.scheduleNetworkStateEvent(current, 0);
      });
      current.on('netUnavailable', (): void => this.scheduleNetworkStateEvent(current, 0));
      current.on('netCapabilitiesChange', (_: connection.NetCapabilityInfo): void => this.scheduleNetworkStateEvent(current));
      current.on('netBlockStatusChange', (status: connection.NetBlockStatusInfo): void => {
        if (this.observer !== current || this.lostNetworkIds.has(status.netHandle.netId)) return;

        if (status.blocked) this.blockedNetworkIds.add(status.netHandle.netId);
        else this.blockedNetworkIds.delete(status.netHandle.netId);
        this.scheduleNetworkStateEvent(current);
      });

      this.observer = current;
      current.register((error: BusinessError): void => {
        if (error !== undefined && error !== null) {
          if (this.observer !== current) return;

          this.observer = undefined;
          this.blockedNetworkIds.clear();

          if (!this.destroyed) {
            this.context.logger.warn(`Unable to observe Expo Network state changes: ${String(error)}`);
          }

          this.scheduleObserverRetry(error);
          return;
        }

        // stopObserving cannot unregister before this callback. Dispose any
        // registration that completed after its listener generation ended.
        if (this.observer !== current) {
          this.unregisterObserver(current);
          return;
        }

        this.observerRegistered = true;
        this.attempt = 0;
        this.scheduleNetworkStateEvent(current);
      });
    } catch (error) {
      this.observer = undefined;

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
    const revision = this.revision;
    this.attempt += 1;

    this.retryTimer = setTimeout((): void => {
      if (revision !== this.revision) return;

      this.retryTimer = -1;
      this.registerObserver();
    }, delay + jitter);
  }

  private unregisterObserver(observer: connection.NetConnection, attempt: number = 0): void {
    try {
      observer.unregister((error: BusinessError): void => {
        if (error !== undefined && error !== null) this.handleUnregisterError(observer, error, attempt);
      });
    } catch (error) {
      this.handleUnregisterError(observer, error as Object, attempt);
    }
  }

  private handleUnregisterError(observer: connection.NetConnection, error: Object, attempt: number): void {
    if (!this.destroyed) {
      this.context.logger.warn(`Unable to stop the Expo Network observer: ${String(error)}`);
    }

    if (isTransientNetworkError(error) && attempt < RETRY_LIMIT) {
      const delay = Math.min(RETRY_BASE_DELAY_MS * Math.pow(2, attempt), RETRY_MAX_DELAY_MS);

      setTimeout((): void => this.unregisterObserver(observer, attempt + 1), delay);
    }
  }

  private stopObserving(): void {
    this.observing = false;
    this.lostNetworkIds.clear();
    this.blockedNetworkIds.clear();
    this.pendingImmediateChange = false;
    this.revision += 1;

    if (this.changeTimer >= 0) {
      clearTimeout(this.changeTimer);
      this.changeTimer = -1;
    }

    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }

    const observer = this.observer;
    const registered = this.observerRegistered;
    this.observer = undefined;
    this.observerRegistered = false;

    if (observer !== undefined && registered) this.unregisterObserver(observer);
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.stopObserving();
  }

  private scheduleNetworkStateEvent(observer: connection.NetConnection, delay: number = CHANGE_DELAY_MS): void {
    if (this.observer !== observer || !this.observerRegistered) return;

    const revision = ++this.revision;

    if (this.changeTimer >= 0) clearTimeout(this.changeTimer);
    this.pendingImmediateChange = this.pendingImmediateChange || delay === 0;

    this.changeTimer = setTimeout((): void => {
      if (this.observer !== observer || revision !== this.revision) return;

      this.changeTimer = -1;
      this.pendingImmediateChange = false;

      this.publishNetworkState(observer, revision).catch((error: Object): void => {
        if (!this.destroyed) {
          this.context.logger.warn(`Unable to publish an Expo Network state change: ${String(error)}`);
        }
      });
    }, this.pendingImmediateChange ? 0 : delay);
  }

  private async publishNetworkState(observer: connection.NetConnection, revision: number): Promise<void> {
    if (this.observer !== observer || revision !== this.revision) return;

    const state = await this.readNetworkState(revision);

    if (this.observer !== observer || revision !== this.revision) return;

    this.sendEvent(STATE_EVENT, state);
  }

  private async readNetworkState(eventRevision?: number): Promise<NetworkState> {
    let handle: connection.NetHandle;

    try {
      handle = await connection.getDefaultNet();
    } catch (_) {
      return unknownState();
    }

    if (handle.netId === 0) return disconnectedState();
    if (handle.netId < FIRST_NETWORK_ID) return unknownState();

    // Only events use the lost-network history to reject an outdated system handle.
    if (eventRevision !== undefined) {
      if (eventRevision !== this.revision) return unknownState();
      if (this.lostNetworkIds.has(handle.netId)) return disconnectedState();
    }

    try {
      const capabilities = await connection.getNetCapabilities(handle);
      const type = networkType(capabilities.bearerTypes);
      const reachable = !this.blockedNetworkIds.has(handle.netId) && isInternetReachable(capabilities);
      if (eventRevision === this.revision) this.lostNetworkIds.clear();

      return new NetworkState(type, type !== NetworkStateType.UNKNOWN, reachable);
    } catch (_) {
      return unknownState();
    }
  }

  private async readIpAddress(): Promise<string> {
    let failure: Object | undefined;

    try {
      const handle = await connection.getDefaultNet();

      try {
        return await ipAddressForNetwork(handle);
      } catch (error) {
        failure = error as Object;
        if ((error as BusinessError).code === INVALID_NETWORK_ARGUMENT) {
          // The default network may have disappeared between the two IPC calls.
          const next = await connection.getDefaultNet();
          if (next.netId !== handle.netId) return await ipAddressForNetwork(next);
        }
      }
    } catch (error) {
      failure = error as Object;
    }

    throw new ExpoModuleError('ERR_NETWORK_IP_ADDRESS', 'Unable to read the default HarmonyOS network address.', failure);
  }

  private async readAirplaneMode(): Promise<boolean> {
    let value: string;

    try {
      value = await settings.getValue(this.context.uiAbilityContext, settings.general.AIRPLANE_MODE_STATUS);
    } catch (error) {
      throw new ExpoModuleError('ERR_NETWORK_AIRPLANE_MODE', 'Unable to read the HarmonyOS airplane mode setting.', error as Object);
    }

    if (value === '0') return false;
    if (value === '1') return true;

    throw new ExpoModuleError('ERR_NETWORK_AIRPLANE_MODE', 'HarmonyOS returned no valid airplane mode setting.');
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
  return code === SERVICE_UNAVAILABLE || code === INTERNAL_ERROR;
}

function networkType(bearers: connection.NetBearType[]): NetworkStateType {
  if (bearers.includes(connection.NetBearType.BEARER_CELLULAR)) return NetworkStateType.CELLULAR;
  if (bearers.includes(connection.NetBearType.BEARER_WIFI)) return NetworkStateType.WIFI;
  if (bearers.includes(connection.NetBearType.BEARER_BLUETOOTH)) return NetworkStateType.BLUETOOTH;
  if (bearers.includes(connection.NetBearType.BEARER_ETHERNET)) return NetworkStateType.ETHERNET;
  if (bearers.includes(connection.NetBearType.BEARER_VPN)) return NetworkStateType.VPN;
  return NetworkStateType.UNKNOWN;
}

function isInternetReachable(capabilities: connection.NetCapabilities): boolean {
  const flags = capabilities.networkCap ?? [];

  // NetworkKit may still report VALIDATED while a connectivity check is in progress.
  if (!flags.includes(connection.NetCap.NET_CAPABILITY_INTERNET) ||
    !flags.includes(connection.NetCap.NET_CAPABILITY_VALIDATED) ||
    flags.includes(connection.NetCap.NET_CAPABILITY_CHECKING_CONNECTIVITY)) return false;

  // HarmonyOS does not expose Android's NOT_SUSPENDED capability. The default
  // network handle and the system's validation result supply the available state.
  return !capabilities.bearerTypes.includes(connection.NetBearType.BEARER_VPN) ||
    (capabilities.linkDownBandwidthKbps ?? 0) !== 0;
}

async function ipAddressForNetwork(handle: connection.NetHandle): Promise<string> {
  if (handle.netId === 0) return FALLBACK_IP;
  if (handle.netId < FIRST_NETWORK_ID) throw new Error('HarmonyOS returned an invalid network handle.');

  const properties = await connection.getConnectionProperties(handle);

  for (const link of properties.linkAddresses ?? []) {
    const address = link.address.address;
    if (isUsableIpv4Address(address)) return address;
  }

  return FALLBACK_IP;
}

function isUsableIpv4Address(value: string): boolean {
  // NetworkKit's family field is optional. Validate the numeric address itself.
  if (value === FALLBACK_IP || value.startsWith('127.') || !/^(?:\d{1,3}\.){3}\d{1,3}$/.test(value)) return false;

  return value.split('.').every((part: string): boolean => parseInt(part, 10) <= 255);
}

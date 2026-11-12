/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { http, mdns } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import util from '@ohos.util';
import { displayError, EXPO_MDNS_SERVICE, MANIFEST_PATH, HARMONY_PLATFORM } from './DevLauncherProtocol';

const HEALTH_CHECK_INTERVAL_MS = 3000;
const HEALTH_CHECK_TIMEOUT_MS = 5000;
const METRO_RUNNING_STATUS = 'packager-status:running';
const DISCOVERY_PREFERENCES = 'expo.modules.devlauncher.nsd';
const SLUG_FILTER_KEY = 'filterBySlug';
const MDNS_CAPABILITY = 'SystemCapability.Communication.NetManager.MDNS';

export class DiscoveredServer {
  readonly id: string;
  readonly name: string;
  readonly url: string;
  readonly slug?: string;

  constructor(id: string, name: string, url: string, slug?: string) {
    this.id = id;
    this.name = name;
    this.url = url;
    this.slug = slug;
  }
}

type DiscoveryListener = (servers: DiscoveredServer[]) => void;

function hostForURL(address: string): string {
  return address.includes(':') && !address.startsWith('[') ? `[${address}]` : address;
}

function txtValue(info: mdns.LocalServiceInfo, key: string): string | undefined {
  const attribute = info.serviceAttribute?.find((item: mdns.ServiceAttribute): boolean => item.key === key);
  if (attribute === undefined) return undefined;
  try {
    const value: string = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(attribute.value)).trim();
    return value.length > 0 ? value : undefined;
  } catch (_) {
    return undefined;
  }
}

export class DevServerDiscovery {
  private service?: mdns.DiscoveryService;
  private timer?: number;
  private readonly candidates = new Map<string, mdns.LocalServiceInfo>();
  private readonly pending = new Map<string, mdns.LocalServiceInfo>();
  private readonly requests = new Set<http.HttpRequest>();
  private readonly servers = new Map<string, DiscoveredServer>();
  private readonly listeners = new Set<DiscoveryListener>();
  private generation = 0;
  private readonly context: common.UIAbilityContext;
  private readonly store?: preferences.Preferences;
  private slugFilter = '';
  private discoveryError?: string;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    try {
      this.store = preferences.getPreferencesSync(context.getApplicationContext(), { name: DISCOVERY_PREFERENCES });
      const value = this.store.getSync(SLUG_FILTER_KEY, '');
      if (typeof value === 'string') this.slugFilter = value;
    } catch (error) {
      console.warn(`Unable to read development server preferences: ${displayError(error as Object)}`);
    }
  }

  get searching(): boolean {
    return this.service !== undefined;
  }

  get error(): string | undefined {
    return this.discoveryError;
  }

  get filterBySlug(): string {
    return this.slugFilter;
  }

  async setFilterBySlug(value: string): Promise<void> {
    this.slugFilter = value.trim();
    this.publish();

    if (this.store === undefined) throw new Error('Server preferences are unavailable. This filter applies only to this session.');
    this.store.putSync(SLUG_FILTER_KEY, this.slugFilter);
    await this.store.flush();
  }

  subscribe(listener: DiscoveryListener): () => void {
    this.listeners.add(listener);
    listener(this.snapshot());

    return (): void => {
      this.listeners.delete(listener);
    };
  }

  start(): void {
    if (this.service !== undefined) return;
    this.discoveryError = undefined;
    if (!canIUse(MDNS_CAPABILITY)) {
      this.fail('Server discovery is unavailable on this device. Enter the project URL manually.');
      return;
    }
    const generation = ++this.generation;

    try {
      const service = mdns.createDiscoveryService(this.context, EXPO_MDNS_SERVICE);
      this.service = service;
      service.on('discoveryStart', (event: mdns.DiscoveryEventInfo): void => {
        if (this.service !== service) return;
        if (event.errorCode !== undefined && event.errorCode !== 0) this.fail(`Server discovery failed (${event.errorCode}).`);
      });
      service.on('discoveryStop', (event: mdns.DiscoveryEventInfo): void => {
        if (this.service !== service) return;
        this.fail(event.errorCode ? `Server discovery stopped (${event.errorCode}).` : 'Server discovery stopped. Refresh to try again.');
      });
      service.on('serviceFound', (info: mdns.LocalServiceInfo): void => {
        if (this.service !== service) return;
        this.candidates.set(info.serviceName, info);
        this.check(info, generation).catch((error: Error): void => console.warn(displayError(error)));
      });
      service.on('serviceLost', (info: mdns.LocalServiceInfo): void => {
        if (this.generation !== generation || this.service !== service) return;
        this.candidates.delete(info.serviceName);
        this.servers.delete(info.serviceName);
        this.publish();
      });

      service.startSearchingMDNS();
      if (this.service === service) {
        this.candidates.forEach((info: mdns.LocalServiceInfo): void => {
          this.check(info, generation).catch((error: Error): void => console.warn(displayError(error)));
        });
        this.timer = setInterval((): void => {
          this.candidates.forEach((info: mdns.LocalServiceInfo): void => {
            this.check(info, generation).catch((error: Error): void => console.warn(displayError(error)));
          });
        }, HEALTH_CHECK_INTERVAL_MS);
      }
    } catch (error) {
      this.fail(`Unable to discover development servers. ${displayError(error as Object)}`);
    }
    this.publish();
  }

  restart(): void {
    this.stop(false);
    this.start();
  }

  stop(clearServers: boolean = true): void {
    const service = this.service;
    this.generation += 1;
    this.service = undefined;
    if (this.timer !== undefined) clearInterval(this.timer);
    this.timer = undefined;
    this.requests.forEach((request: http.HttpRequest): void => request.destroy());
    this.requests.clear();
    this.pending.clear();
    if (clearServers) this.candidates.clear();
    try {
      service?.stopSearchingMDNS();
    } catch (error) {
      console.warn(`Unable to stop Expo development server discovery: ${String(error)}`);
    }
    try {
      service?.off('serviceFound');
      service?.off('serviceLost');
      service?.off('discoveryStart');
      service?.off('discoveryStop');
    } catch (error) {
      console.warn(`Unable to detach development server discovery: ${displayError(error as Object)}`);
    }
    if (clearServers) this.servers.clear();
    this.publish();
  }

  private fail(message: string): void {
    this.stop();
    this.discoveryError = message;
    this.publish();
  }

  private async check(info: mdns.LocalServiceInfo, generation: number): Promise<void> {
    const name = info.serviceName;
    if (this.pending.get(name) === info) return;
    this.pending.set(name, info);
    let request: http.HttpRequest | undefined;
    try {
      const resolved = await mdns.resolveLocalService(this.context, info);
      if (!this.isCurrent(info, generation)) return;

      const address = resolved.host?.address;
      const port = resolved.port;
      if (!address || port === undefined || !Number.isInteger(port) || port < 1 || port > 65535) {
        this.servers.delete(name);
        this.publish();
        return;
      }
      const origin = `http://${hostForURL(address)}:${port}`;
      request = http.createHttp();
      this.requests.add(request);
      const response = await request.request(`${origin}/status`, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: HEALTH_CHECK_TIMEOUT_MS,
        readTimeout: HEALTH_CHECK_TIMEOUT_MS,
        maxLimit: 16 * 1024,
      });
      if (!this.isCurrent(info, generation)) return;
      if (response.responseCode >= 200 && response.responseCode < 300
        && typeof response.result === 'string' && response.result.trim() === METRO_RUNNING_STATUS) {
        const url = `${origin}${MANIFEST_PATH}?platform=${HARMONY_PLATFORM}`;
        this.servers.set(name, new DiscoveredServer(name, txtValue(resolved, 'name') ?? txtValue(info, 'name') ?? name,
          url, txtValue(resolved, 'slug') ?? txtValue(info, 'slug')));
      } else {
        this.servers.delete(name);
      }
      this.publish();
    } catch (_) {
      if (this.isCurrent(info, generation)) {
        this.servers.delete(name);
        this.publish();
      }
    } finally {
      if (this.generation === generation && this.pending.get(name) === info) this.pending.delete(name);
      if (request !== undefined && this.requests.delete(request)) request.destroy();
    }
  }

  private isCurrent(info: mdns.LocalServiceInfo, generation: number): boolean {
    return this.generation === generation && this.service !== undefined && this.candidates.get(info.serviceName) === info;
  }

  private snapshot(): DiscoveredServer[] {
    return Array.from(this.servers.values())
      .filter((server: DiscoveredServer): boolean => !this.slugFilter || server.slug === this.slugFilter)
      .sort((left: DiscoveredServer, right: DiscoveredServer): number => left.name.localeCompare(right.name));
  }

  private publish(): void {
    const value = this.snapshot();
    this.listeners.forEach((listener: DiscoveryListener): void => listener(value));
  }
}

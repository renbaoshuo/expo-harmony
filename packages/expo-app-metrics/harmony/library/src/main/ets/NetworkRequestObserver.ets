/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import util from '@ohos.util';
import url from '@ohos.url';
import { RNInstanceImpl } from '@rnoh/react-native-openharmony';
import type { HttpClient } from '@rnoh/react-native-openharmony/src/main/ets/HttpClient/HttpClient';
import type {
  CancelRequestCallback, HttpResponse, RequestInterceptor, RequestOptions, ResponseInterceptor,
} from '@rnoh/react-native-openharmony/src/main/ets/HttpClient/types';
import {
  ExpoFunction, ExpoModuleContext, ExpoModuleError, ExpoNetworkObservation,
  ExpoNetworkRequestCompleted, ExpoNetworkRequestListener, ExpoNetworkRequestRedirect, ExpoNetworkRequestStarted,
  ExpoSharedObject, ExpoSharedObjectClassDefinition, ExpoValueType, ExpoValueTypes, ReactRuntimeBinding, ReactRuntimeContext,
} from '@expo-harmony/expo-modules-core';

interface NativeHttpRequest {
  cancel: CancelRequestCallback;
  promise: Promise<HttpResponse>;
}

/** Preserve the native transport, cookies, cancellation, custom interceptors and errors. */
class ObservedHttpClient implements HttpClient {
  private readonly client: HttpClient;
  private readonly runtimeId: number;
  constructor(client: HttpClient, runtimeId: number) {
    this.client = client;
    this.runtimeId = runtimeId;
  }
  addRequestInterceptor(interceptor: RequestInterceptor): void { this.client.addRequestInterceptor(interceptor); }
  addResponseInterceptor(interceptor: ResponseInterceptor): void { this.client.addResponseInterceptor(interceptor); }
  clearCookies(): Promise<boolean> { return this.client.clearCookies(); }

  sendRequest(target: string, options: RequestOptions): NativeHttpRequest {
    const observation = ExpoNetworkObservation.start(this.runtimeId, target, options.method ?? 'GET');
    try {
      const request: NativeHttpRequest = this.client.sendRequest(target, options);
      const promise: Promise<HttpResponse> = request.promise.then((response: HttpResponse): HttpResponse => {
        observation?.finish(response.statusCode);
        return response;
      }, (error: ESObject): Promise<HttpResponse> => {
        observation?.finish(requestErrorStatus(error), requestErrorMessage(error));
        return Promise.reject<HttpResponse>(error);
      });
      return {
        cancel: (): void => {
          observation?.finish(null, 'Request cancelled');
          request.cancel();
        },
        promise,
      };
    } catch (error) {
      observation?.finish(requestErrorStatus(error), requestErrorMessage(error));
      throw error as Error;
    }
  }
}

function requestErrorStatus(value: ESObject): number | null {
  if (value === null || typeof value !== 'object') return null;
  const status: ESObject = (value as Record<string, ESObject>)['statusCode'];
  return typeof status === 'number' && Number.isInteger(status) && status >= 100 && status <= 599 ? status : null;
}

function requestErrorMessage(value: ESObject): string {
  if (value instanceof Error) return value.message;
  if (value !== null && typeof value === 'object') {
    const record = value as Record<string, ESObject>;
    const error: ESObject = record['error'];
    if (error instanceof Error) return error.message;
    if (error !== null && typeof error === 'object') {
      const message: ESObject = (error as Record<string, ESObject>)['message'];
      if (typeof message === 'string') return message;
    }
    const message: ESObject = record['message'];
    if (typeof message === 'string') return message;
  }
  return String(value);
}

export class ExpoAppMetricsNetworkBinding implements ReactRuntimeBinding {
  constructor(_context: common.Context) {}
  bind(context: ReactRuntimeContext): (() => void) | void {
    const instance = context.instance;
    const runtimeId = instance.getId();
    if (requestMonitors.has(runtimeId)) return;

    const monitor = new NetworkRequestMonitor(runtimeId);
    requestMonitors.set(runtimeId, monitor);
    // Worker Networking has a separate actor-owned HttpClient. Never mutate it from UI.
    // Runtime binding runs before the application bundle. Host initialization
    // notification can arrive after requests made by startup JS.
    let restore: (() => void) | undefined;
    if (instance instanceof RNInstanceImpl) {
      const previous = instance.httpClient;
      const observed = new ObservedHttpClient(previous, runtimeId);
      instance.httpClient = observed;
      restore = (): void => {
        if (instance.httpClient === observed) instance.httpClient = previous;
      };
    }

    return (): void => {
      if (requestMonitors.get(runtimeId) !== monitor) return;
      requestMonitors.delete(runtimeId);
      monitor.release();
      restore?.();
    };
  }
}

class NetworkFilter {
  hosts?: string[];
  methods?: string[];
}

class NetworkRequestStarted {
  readonly id: string = util.generateRandomUUID(true);
  readonly url: string;
  readonly method: string;
  readonly startedAt: string;

  constructor(start: ExpoNetworkRequestStarted) {
    this.url = start.url;
    this.method = start.method;
    this.startedAt = networkTimestamp(start.startedAtMilliseconds);
  }
}

class NetworkRequestCompleted {
  readonly id: string;
  readonly url: string;
  readonly method: string;
  readonly startedAt: string;
  readonly completedAt: string;
  readonly statusCode: number | null;
  readonly networkProtocol: string | null = null;
  readonly requestBytesSent: number | null = null;
  readonly responseBytesReceived: number | null = null;
  readonly errorDescription: string | null;
  readonly totalDuration: number;
  readonly redirects: ExpoNetworkRequestRedirect[];

  constructor(start: NetworkRequestStarted, result: ExpoNetworkRequestCompleted) {
    this.id = start.id;
    this.url = start.url;
    this.method = start.method;
    this.startedAt = start.startedAt;
    this.completedAt = networkTimestamp(result.completedAtMilliseconds);
    this.statusCode = result.statusCode;
    this.errorDescription = result.errorDescription;
    this.totalDuration = result.totalDuration;
    this.redirects = result.redirects;
  }
}

function networkTimestamp(milliseconds: number): string {
  return new Date(Math.floor(milliseconds / 1000) * 1000).toISOString();
}

class TimedNetworkRequest {
  readonly request: NetworkRequestCompleted;
  readonly startedAt: number;
  constructor(request: NetworkRequestCompleted, startedAt: number) {
    this.request = request;
    this.startedAt = startedAt;
  }
}

const requestMonitors: Map<number, NetworkRequestMonitor> = new Map<number, NetworkRequestMonitor>();

export function getNetworkRequestMonitor(runtimeId: number): NetworkRequestMonitor | undefined {
  return requestMonitors.get(runtimeId);
}

/** One monitor owns the public request identities and completion history for a runtime. */
export class NetworkRequestMonitor implements ExpoNetworkRequestListener {
  private readonly pending = new WeakMap<ExpoNetworkRequestStarted, NetworkRequestStarted>();
  private readonly recent: TimedNetworkRequest[] = [];
  private readonly observers = new Set<NetworkRequestObserver>();
  private readonly unsubscribe: () => void;

  constructor(runtimeId: number) {
    this.unsubscribe = ExpoNetworkObservation.subscribe(runtimeId, this);
  }

  addObserver(observer: NetworkRequestObserver): void { this.observers.add(observer); }
  removeObserver(observer: NetworkRequestObserver): void { this.observers.delete(observer); }

  started(start: ExpoNetworkRequestStarted): void {
    const snapshot = new NetworkRequestStarted(start);
    this.pending.set(start, snapshot);
    for (const observer of this.observers) {
      try { observer.started(snapshot); } catch (_) { /* Keep other observers and transport independent. */ }
    }
  }

  completed(result: ExpoNetworkRequestCompleted, start: ExpoNetworkRequestStarted): void {
    const began = this.pending.get(start);
    if (began === undefined) return;
    this.pending.delete(start);
    const snapshot = new NetworkRequestCompleted(began, result);
    this.recent.push(new TimedNetworkRequest(snapshot, start.startedAtMilliseconds));
    // Same 200-completion window used by the upstream native monitor.
    if (this.recent.length > 200) this.recent.shift();
    for (const observer of this.observers) {
      try { observer.completed(snapshot, began); } catch (_) { /* Keep other observers and transport independent. */ }
    }
  }

  release(): void {
    this.unsubscribe();
    this.observers.clear();
    this.recent.length = 0;
  }

  summarize(start: number, end: number): Record<string, ESObject> {
    const requests = this.recent.filter((entry: TimedNetworkRequest): boolean => entry.startedAt >= start && entry.startedAt <= end)
      .map((entry: TimedNetworkRequest): NetworkRequestCompleted => entry.request);
    if (requests.length === 0) return {};

    let failed = 0;
    let total = 0;
    let slowest = requests[0];
    requests.forEach((request: NetworkRequestCompleted): void => {
      if (request.errorDescription !== null || request.statusCode === null || request.statusCode >= 400) failed += 1;
      total += request.totalDuration;
      if (request.totalDuration > slowest.totalDuration) slowest = request;
    });
    const result: Record<string, ESObject> = {
      'expo.network.requests.count': requests.length,
      'expo.network.requests.failed': failed,
      'expo.network.requests.totalDuration': total,
      'expo.network.requests.slowestDuration': slowest.totalDuration,
    };
    // RNOH/RCP do not report wire bytes; omitting them avoids reporting body bytes as wire bytes.
    try { result['expo.network.requests.slowestHost'] = new url.URL(slowest.url).hostname; } catch (_) {}

    return result;
  }
}

function parseFilter(value: ESObject): NetworkFilter {
  const filter = new NetworkFilter();
  if (value === undefined || value === null) return filter;
  if (typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoModuleError('ERR_INVALID_ARGUMENT', 'Network filter must be an object or null.');
  }

  const input = value as Record<string, ESObject>;
  filter.hosts = filterStrings(input['hosts'], 'hosts');
  filter.methods = filterStrings(input['methods'], 'methods');
  return filter;
}

function filterStrings(value: ESObject, field: string): string[] | undefined {
  if (value === undefined || value === null) return undefined;
  if (!Array.isArray(value) || !value.every((item: ESObject): boolean => typeof item === 'string')) {
    throw new ExpoModuleError('ERR_INVALID_ARGUMENT', `Network filter ${field} must be an array of strings.`);
  }
  return (value as string[]).map((item: string): string => item.toLowerCase());
}

export class NetworkRequestObserver extends ExpoSharedObject {
  private filter: NetworkFilter;
  private readonly pending = new WeakSet<NetworkRequestStarted>();
  private readonly monitor: NetworkRequestMonitor;

  constructor(context: ExpoModuleContext, filter: ESObject) {
    super(context);
    this.filter = parseFilter(filter);
    const monitor = getNetworkRequestMonitor(context.runtimeId);
    if (monitor === undefined) {
      throw new ExpoModuleError('ERR_APP_METRICS_NETWORK_UNAVAILABLE', 'App Metrics requires its autolinked network runtime binding.');
    }
    this.monitor = monitor;
    monitor.addObserver(this);
  }

  setFilter(value: ESObject): void { this.filter = parseFilter(value); }

  started(request: NetworkRequestStarted): void {
    if (!this.matches(request)) return;
    this.pending.add(request);
    this.sendEvent('requestStarted', request);
  }

  completed(request: NetworkRequestCompleted, start: NetworkRequestStarted): void {
    if (!this.pending.delete(start)) return;
    this.sendEvent('requestCompleted', request);
  }

  private matches(request: NetworkRequestStarted): boolean {
    if (this.filter.methods !== undefined && !this.filter.methods.includes(request.method.toLowerCase())) return false;
    if (this.filter.hosts === undefined) return true;
    try { return this.filter.hosts.includes(new url.URL(request.url).hostname.toLowerCase()); }
    catch (_) { return false; }
  }

  override sharedObjectWillRelease(): void {
    this.monitor.removeObserver(this);
  }
}

export function networkRequestObserverClass(): ExpoSharedObjectClassDefinition<NetworkRequestObserver> {
  const inputType: ExpoValueType<ESObject> = ExpoValueTypes.custom<ESObject>('NetworkRequestFilter',
    (value: ESObject): ESObject => value, (value: ESObject): ESObject => value);
  return new ExpoSharedObjectClassDefinition<NetworkRequestObserver>('NetworkRequestObserver')
    .construct(ExpoFunction.ownedTyped1(inputType.nullable().optional(),
      (context: ExpoModuleContext, filter: ESObject): NetworkRequestObserver => new NetworkRequestObserver(context, filter)))
    .events(['requestStarted', 'requestCompleted'])
    .syncFunction('setFilter', ExpoFunction.ownedTyped1(inputType.nullable(),
      (observer: NetworkRequestObserver, filter: ESObject): void => observer.setFilter(filter)));
}

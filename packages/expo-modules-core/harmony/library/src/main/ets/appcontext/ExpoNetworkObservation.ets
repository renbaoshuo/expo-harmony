/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import systemDateTime from '@ohos.systemDateTime';

export interface ExpoNetworkRequestStarted {
  readonly url: string;
  readonly method: string;
  readonly startedAtMilliseconds: number;
}

export interface ExpoNetworkRequestCompleted {
  readonly statusCode: number | null;
  readonly errorDescription: string | null;
  readonly completedAtMilliseconds: number;
  /** Elapsed time in seconds, using the monotonic clock when available. */
  readonly totalDuration: number;
  readonly redirects: ExpoNetworkRequestRedirect[];
}

export interface ExpoNetworkRequestRedirect {
  readonly fromUrl: string;
  readonly toUrl: string;
  readonly statusCode: number;
}

export interface ExpoNetworkRequestListener {
  started(request: ExpoNetworkRequestStarted): void;
  /** `start` is the same object delivered to `started` for this request. */
  completed(request: ExpoNetworkRequestCompleted, start: ExpoNetworkRequestStarted): void;
}

class Registration {
  runtimeId: number;
  listener?: ExpoNetworkRequestListener;

  constructor(runtimeId: number, listener: ExpoNetworkRequestListener) {
    this.runtimeId = runtimeId;
    this.listener = listener;
  }
}

interface Recipient {
  readonly registration: Registration;
  readonly start: ExpoNetworkRequestStarted;
}

/** Read-only native transport notifications. No request/response bodies are retained. */
export class ExpoNetworkObservation {
  private static readonly registrations: Set<Registration> = new Set<Registration>();
  private readonly startedAtMilliseconds: number = Date.now();
  private readonly monotonicStart?: number;
  private readonly recipients: Recipient[];
  private ended: boolean = false;
  private readonly redirects: ExpoNetworkRequestRedirect[] = [];

  static subscribe(runtimeId: number, listener: ExpoNetworkRequestListener): () => void {
    const registration = new Registration(runtimeId, listener);
    ExpoNetworkObservation.registrations.add(registration);

    return (): void => {
      ExpoNetworkObservation.registrations.delete(registration);
      // A long-lived in-flight request must not retain a released JS observer.
      registration.listener = undefined;
    };
  }

  static start(runtimeId: number, url: string, method: string): ExpoNetworkObservation | undefined {
    const recipients = Array.from(ExpoNetworkObservation.registrations).filter((entry: Registration): boolean => entry.runtimeId === runtimeId);
    if (recipients.length === 0) return undefined;

    // Instrumentation must never fail the transport request.
    try {
      return new ExpoNetworkObservation(url, method, recipients);
    } catch (_) {
      return undefined;
    }
  }

  private constructor(url: string, method: string, recipients: Registration[]) {
    try { this.monotonicStart = systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE); } catch (_) {}
    this.recipients = recipients.map((registration: Registration): Recipient => {
      const start: ExpoNetworkRequestStarted = { url, method, startedAtMilliseconds: this.startedAtMilliseconds };
      return { registration, start };
    });

    this.recipients.forEach((entry: Recipient): void => {
      try { entry.registration.listener?.started(entry.start); } catch (_) {}
    });
  }

  finish(status: number | null, error: string | null = null): void {
    if (this.ended) return;
    this.ended = true;

    const completed = Date.now();
    let elapsed = completed - this.startedAtMilliseconds;
    try {
      if (this.monotonicStart !== undefined) {
        elapsed = systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE) - this.monotonicStart;
      }
    } catch (_) {}

    const duration = Math.max(0, elapsed / 1000);
    this.recipients.forEach((entry: Recipient): void => {
      const listener = entry.registration.listener;
      if (listener === undefined) return;

      try {
        listener.completed({
          statusCode: status,
          errorDescription: error,
          completedAtMilliseconds: completed,
          totalDuration: duration,
          redirects: this.redirects.map((redirect: ExpoNetworkRequestRedirect): ExpoNetworkRequestRedirect => ({
            fromUrl: redirect.fromUrl,
            toUrl: redirect.toUrl,
            statusCode: redirect.statusCode,
          })),
        }, entry.start);
      } catch (_) {}
    });
  }

  redirect(fromUrl: string, toUrl: string, statusCode: number): void {
    if (!this.ended) this.redirects.push({ fromUrl, toUrl, statusCode });
  }
}

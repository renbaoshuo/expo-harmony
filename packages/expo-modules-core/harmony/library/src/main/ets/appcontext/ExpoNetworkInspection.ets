/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { bundleManager } from '@kit.AbilityKit';
import util from '@ohos.util';
import { InspectorNetworkReporter } from '@rnoh/react-native-openharmony/src/main/ets/RNOHCorePackage/turboModules/Networking/InspectorNetworkReporter';

// Instrument Expo-owned transports only. RN Networking already reports itself.
export class ExpoNetworkInspection {
  private static sequence = 0;
  private readonly id: string;
  private readonly url: string;
  private bytes = 0;
  private preview = new Uint8Array(0);
  private previewAllowed = true;
  private responseType = '';
  private responded = false;
  private ended = false;
  private static readonly previewLimit = 1024 * 1024;

  static headers(values: Record<string, string | string[] | undefined>): Record<string, string> {
    const headers: Record<string, string> = {};
    Object.keys(values).forEach((key: string): void => {
      const value = values[key];
      if (value !== undefined) headers[key] = Array.isArray(value) ? value.join(', ') : value;
    });
    return headers;
  }

  static start(url: string, method: string, headers: Record<string, string>, body?: string | ArrayBuffer): ExpoNetworkInspection | undefined {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      if (!info.appInfo.debug || !InspectorNetworkReporter.isDebuggingEnabled()) return undefined;
      return new ExpoNetworkInspection(url, method, headers, body);
    } catch (_) {
      return undefined;
    }
  }

  private constructor(url: string, method: string, headers: Record<string, string>, body?: string | ArrayBuffer) {
    this.id = `expo-native-${Date.now()}-${++ExpoNetworkInspection.sequence}`;
    this.url = url;
    this.previewAllowed = !ExpoNetworkInspection.streamingType(ExpoNetworkInspection.header(headers, 'accept'));

    // Only inspect already-buffered bodies. Never read files, multipart sources
    // or one-shot streams for DevTools. CDP postData has no binary encoding flag.
    let postData = '';
    let size = body instanceof ArrayBuffer ? body.byteLength : 0;
    if (
      body !== undefined &&
      ExpoNetworkInspection.textType(ExpoNetworkInspection.header(headers, 'content-type')) &&
      (typeof body === 'string' ? body.length : body.byteLength) <= ExpoNetworkInspection.previewLimit
    ) {
      const bytes = typeof body === 'string' ? new util.TextEncoder().encodeInto(body) : new Uint8Array(body);
      size = bytes.byteLength;
      if (size <= ExpoNetworkInspection.previewLimit) {
        try {
          postData = ExpoNetworkInspection.decode(bytes);
        } catch (_) {
          /* Invalid UTF-8 is not text. */
        }
      }
    }

    InspectorNetworkReporter.reportRequestStart(this.id, url, method, headers, postData, size);
  }

  private static header(headers: Record<string, string>, name: string): string {
    const key = Object.keys(headers).find((key: string): boolean => key.toLowerCase() === name);
    return key === undefined ? '' : headers[key].toLowerCase();
  }

  private static streamingType(value: string): boolean {
    return value
      .split(',')
      .some((type: string): boolean =>
        ['text/event-stream', 'text/x-component', 'audio/', 'video/'].some((prefix: string): boolean => type.trim().startsWith(prefix)),
      );
  }

  private static textType(value: string): boolean {
    const mime = value.split(';')[0].trim();
    const charset = /charset\s*=\s*"?([^;"\s]+)/.exec(value)?.[1];
    return (
      (charset === undefined || charset === 'utf-8' || charset === 'utf8' || charset === 'us-ascii') &&
      (mime.startsWith('text/') ||
        ['application/json', 'application/xml', 'application/javascript', 'application/x-www-form-urlencoded'].includes(mime) ||
        mime.endsWith('+json') ||
        mime.endsWith('+xml'))
    );
  }

  private static decode(bytes: Uint8Array): string {
    return bytes.byteLength === 0 ? '' : util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true }).decodeToString(bytes);
  }

  private discardPreview(): void {
    this.previewAllowed = false;
    this.preview = new Uint8Array(0);
  }

  response(status: number, headers: Record<string, string>): void {
    if (this.ended || this.responded || status < 200) return;
    this.responded = true;

    const length = Number(ExpoNetworkInspection.header(headers, 'content-length') || -1);
    this.responseType = ExpoNetworkInspection.header(headers, 'content-type');
    if (
      length > ExpoNetworkInspection.previewLimit ||
      ExpoNetworkInspection.streamingType(this.responseType) ||
      ExpoNetworkInspection.header(headers, 'transfer-encoding')
        .split(',')
        .some((value: string): boolean => value.trim() === 'chunked')
    ) {
      this.discardPreview();
    }

    InspectorNetworkReporter.reportResponseStart(this.id, this.url, status, headers, Number.isFinite(length) ? length : -1);
  }

  data(chunk: ArrayBuffer): void {
    if (this.ended) return;
    this.bytes += chunk.byteLength;

    // Do not retain unbounded streamed downloads, or expose a truncated body as complete.
    if (this.bytes > ExpoNetworkInspection.previewLimit) this.discardPreview();
    if (!this.previewAllowed || chunk.byteLength === 0) return;

    // A bounded contiguous buffer also avoids one allocation per tiny chunk.
    if (this.preview.length < this.bytes) {
      const capacity = Math.min(ExpoNetworkInspection.previewLimit, Math.max(this.bytes, this.preview.length * 2, 4096));
      const next = new Uint8Array(capacity);
      next.set(this.preview);
      this.preview = next;
    }
    this.preview.set(new Uint8Array(chunk), this.bytes - chunk.byteLength);
  }

  finish(complete: boolean = true): void {
    if (this.ended) return;

    this.ended = true;
    if (complete && this.responded && this.previewAllowed) {
      const body = this.preview.subarray(0, this.bytes);
      let text: string | undefined;
      if (ExpoNetworkInspection.textType(this.responseType)) {
        try {
          text = ExpoNetworkInspection.decode(body);
        } catch (_) {}
      }

      try {
        const content = text ?? new util.Base64Helper().encodeToStringSync(body);
        InspectorNetworkReporter.maybeStoreResponseBody(this.id, content, text === undefined);
      } catch (_) {
        // A failed preview must still emit request completion.
      }
    }

    this.discardPreview();
    InspectorNetworkReporter.reportResponseEnd(this.id, this.bytes);
  }

  fail(cancelled: boolean): void {
    if (this.ended) return;
    this.ended = true;
    this.discardPreview();
    InspectorNetworkReporter.reportRequestFailed(this.id, cancelled);
  }
}

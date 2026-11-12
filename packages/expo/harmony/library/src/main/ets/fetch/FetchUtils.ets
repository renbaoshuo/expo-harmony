/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError, ExpoValueType, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import util from '@ohos.util';
import url from '@ohos.url';
import webview from '@ohos.web.webview';
import uniformTypeDescriptor from '@ohos.data.uniformTypeDescriptor';
import type { rcp } from '@kit.RemoteCommunicationKit';
import { ExpoFetchError } from './ExpoFetchError';
import { FetchInit } from './FetchTypes';
import { collectRequestHeaders, mergeCookieHeaders } from './FetchHeaderPolicy';
import { createHeaderRecord } from './FetchHeaderRecord';

export const HEADER_PAIRS_TYPE: ExpoValueType<string[][]> = ExpoValueTypes.array(ExpoValueTypes.array(ExpoValueTypes.string()));

export const FETCH_INIT_TYPE: ExpoValueType<FetchInit> = new ExpoValueType<FetchInit>(
  'fetch request init object',
  (value: ESObject, path: string): FetchInit => parseFetchInit(value, path),
  (value: FetchInit): ESObject => encodeFetchInit(value),
);

export function parseFetchInit(value: ESObject, path: string): FetchInit {
  const input = requireRecord(value, path);
  const result = new FetchInit();
  const credentials = optionalString(input['credentials'], `${path}.credentials`);
  if (credentials !== undefined) {
    if (credentials !== 'include' && credentials !== 'omit') {
      throw new ExpoModuleError('ERR_INVALID_ARGUMENT', `${path}.credentials expected 'include' or 'omit'.`);
    }
    result.credentials = credentials;
  }
  result.method = optionalString(input['method'], `${path}.method`) ?? 'GET';
  const redirect = optionalString(input['redirect'], `${path}.redirect`);
  if (redirect !== undefined) {
    if (redirect !== 'follow' && redirect !== 'error' && redirect !== 'manual') {
      throw new ExpoModuleError('ERR_INVALID_ARGUMENT', `${path}.redirect expected 'follow', 'error', or 'manual'.`);
    }
    result.redirect = redirect;
  }
  result.headers = optionalHeaderPairs(input['headers'], `${path}.headers`) ?? [];

  return result;
}

export function encodeFetchInit(value: FetchInit): ESObject {
  const result = new Object();
  if (value.credentials !== undefined) Reflect.set(result, 'credentials', value.credentials);
  if (value.method !== undefined) Reflect.set(result, 'method', value.method);
  if (value.redirect !== undefined) Reflect.set(result, 'redirect', value.redirect);
  if (value.headers !== undefined) Reflect.set(result, 'headers', value.headers);

  return result;
}

export function requireRecord(value: ESObject, path: string): Record<string, ESObject> {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoModuleError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected a fetch request init object.`);
  }
  return value as Record<string, ESObject>;
}

export function optionalString(value: ESObject, path: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') {
    throw new ExpoModuleError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected a string.`);
  }

  return value;
}

export function optionalHeaderPairs(value: ESObject, path: string): string[][] | undefined {
  if (value === undefined || value === null) return undefined;

  const pairs = HEADER_PAIRS_TYPE.decode(value, path);
  pairs.forEach((pair: string[], index: number): void => {
    if (pair.length !== 2) {
      throw new ExpoModuleError('ERR_INVALID_ARGUMENT', `${path}[${index}] expected exactly two strings.`);
    }
  });

  return pairs;
}

export function makeHeaders(init: FetchInit): rcp.RequestHeaders {
  const values = collectRequestHeaders(init.headers ?? []);
  const headers = createHeaderRecord();
  values.forEach((value: string | string[], name: string): void => {
    headers[name] = value;
  });

  return headers;
}

export function headerPairs(headers: rcp.ResponseHeaders): string[][] {
  const result: string[][] = [];
  Object.keys(headers).forEach((name: string): void => {
    const value = headers[name];
    if (value === undefined) return;

    if (Array.isArray(value)) {
      value.forEach((item: string): void => {
        result.push([name, item]);
      });
    } else {
      value.split(/\r?\n/).forEach((item: string): void => {
        result.push([name, item]);
      });
    }
  });
  return result;
}

export function headerFromPairs(headers: string[][], name: string): string | null {
  const pair = headers.find((candidate: string[]): boolean => {
    return candidate.length >= 2 && candidate[0].toLowerCase() === name;
  });
  return pair === undefined ? null : pair[1];
}

export function isRedirectStatus(status: number): boolean {
  return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
}

export function isFileURL(value: string): boolean {
  return /^file:/i.test(value);
}

export function isHttpURL(value: string): boolean {
  return /^https?:\/\//i.test(value);
}

export function requestMethodRequiresBody(method: string): boolean {
  const normalized = method.toUpperCase();
  return normalized === 'POST' || normalized === 'PUT' || normalized === 'PATCH';
}

export function sameOrigin(left: string, right: string): boolean {
  try {
    return url.URL.parseURL(left).origin === url.URL.parseURL(right).origin;
  } catch (_error) {
    return false;
  }
}

export function withoutHeaders(headers: rcp.RequestHeaders, names: string[]): rcp.RequestHeaders {
  const result = createHeaderRecord();
  Object.keys(headers).forEach((name: string): void => {
    if (!names.includes(name.toLowerCase())) {
      result[name] = headers[name];
    }
  });
  return result;
}

export function mimeType(path: string): string {
  const dot = path.lastIndexOf('.');
  if (dot <= path.lastIndexOf('/') || dot === path.length - 1) return 'application/octet-stream';

  try {
    const typeIds = uniformTypeDescriptor.getUniformDataTypesByFilenameExtension(path.slice(dot).toLowerCase());
    for (const typeId of typeIds) {
      const mimeTypes = uniformTypeDescriptor.getTypeDescriptor(typeId).mimeTypes;
      if (mimeTypes.length > 0) return mimeTypes[0];
    }
  } catch (_error) {}

  return 'application/octet-stream';
}

export function encodeString(value: string): Uint8Array {
  return new util.TextEncoder('utf-8').encode(value);
}

export function copyBytes(bytes: Uint8Array): ArrayBuffer {
  const buffer = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(buffer).set(bytes);
  return buffer;
}

export function chunksToBuffer(chunks: ArrayBuffer[]): ArrayBuffer {
  const size = chunks.reduce((total: number, chunk: ArrayBuffer): number => total + chunk.byteLength, 0);
  const buffer = new ArrayBuffer(size);
  const output = new Uint8Array(buffer);
  let offset = 0;
  chunks.forEach((chunk: ArrayBuffer): void => {
    output.set(new Uint8Array(chunk), offset);
    offset += chunk.byteLength;
  });

  return buffer;
}

export async function withStoredCookies(headers: rcp.RequestHeaders, target: string, credentials?: string): Promise<rcp.RequestHeaders> {
  if (credentials !== 'include') return headers;

  let stored = '';

  try {
    stored = (await webview.WebCookieManager.fetchCookie(target, false)).replace(/,/g, ';');
  } catch (error) {
    throw new ExpoFetchError('ERR_FETCH_COOKIE_READ', `Unable to read cookies for ${target}: ${errorMessage(error as Object)}`, error as Object);
  }
  if (stored.length === 0) return headers;

  const result = withoutHeaders(headers, ['cookie']);
  const name = Object.keys(headers).find((key: string): boolean => key.toLowerCase() === 'cookie');
  const explicit = name === undefined ? undefined : headers[name];
  result['cookie'] = mergeCookieHeaders(typeof explicit === 'string' ? explicit : null, stored);

  return result;
}

export async function storeResponseCookies(target: string, headers: string[][]): Promise<void> {
  const cookies = headers
    .filter((pair: string[]): boolean => {
      return pair.length >= 2 && pair[0].toLowerCase() === 'set-cookie';
    })
    .map((pair: string[]): string => pair[1]);
  if (cookies.length === 0) return;

  for (const cookie of cookies) {
    try {
      await webview.WebCookieManager.configCookie(target, cookie, false, true);
    } catch (error) {
      console.warn(`[expo-fetch] Ignoring an invalid Set-Cookie value for ${target}: ${errorMessage(error as Object)}`);
    }
  }

  try {
    await webview.WebCookieManager.saveCookieAsync();
  } catch (error) {
    console.warn(`[expo-fetch] Unable to persist cookies for ${target}: ${errorMessage(error as Object)}`);
  }
}

export function formatError(error: ExpoFetchError): string {
  return `${error.code}: ${error.message}`;
}

export function errorMessage(error: Object): string {
  try {
    if (error !== null && typeof error === 'object') {
      const message: ESObject = Reflect.get(error, 'message');
      const code: ESObject = Reflect.get(error, 'code');
      if (typeof message === 'string' && message.length > 0) {
        return typeof code === 'number' || typeof code === 'string' ? `${message} (Harmony code ${String(code)})` : message;
      }
    }
  } catch (_error) {}
  return String(error).replace(/^(?:Error:\s*)+/, '');
}

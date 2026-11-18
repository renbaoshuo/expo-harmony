/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError, ExpoValueType, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import url from '@ohos.url';
import webview from '@ohos.web.webview';
import uniformTypeDescriptor from '@ohos.data.uniformTypeDescriptor';
import type { BusinessError } from '@kit.BasicServicesKit';
import { ExpoFetchError } from './ExpoFetchError';
import { FetchInit } from './FetchTypes';
import { collectRequestHeaders, mergeCookieHeaders } from './FetchHeaderPolicy';

const COOKIE_UNAVAILABLE = 17100002;

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

export function makeHeaders(init: FetchInit): Object {
  const values = collectRequestHeaders(init.headers ?? []);
  const headers = new Object();
  values.forEach((value: string, name: string): void => {
    Reflect.set(headers, name, value);
  });

  return headers;
}

export function headerPairs(headers: Object): string[][] {
  const result: string[][] = [];
  Object.keys(headers).forEach((name: string): void => {
    const value: ESObject = Reflect.get(headers, name);
    if (Array.isArray(value)) {
      (value as ESObject[]).forEach((item: ESObject): void => {
        result.push([name, String(item)]);
      });
    } else {
      String(value)
        .split(/\r?\n/)
        .forEach((item: string): void => {
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

export function withoutHeaders(headers: Object, names: string[]): Object {
  const result = new Object();
  Object.keys(headers).forEach((name: string): void => {
    if (!names.includes(name.toLowerCase())) {
      Reflect.set(result, name, Reflect.get(headers, name));
    }
  });
  return result;
}

export function mimeType(path: string): string {
  const dot = path.lastIndexOf('.');
  if (dot < 0 || dot === path.length - 1) return 'application/octet-stream';

  try {
    const typeId = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(path.slice(dot));
    const mimeTypes = uniformTypeDescriptor.getTypeDescriptor(typeId).mimeTypes;
    if (mimeTypes.length > 0) return mimeTypes[0];
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

export async function readFileBuffer(path: string, size: number): Promise<ArrayBuffer> {
  const output = new ArrayBuffer(size);
  if (size === 0) return output;

  const outputBytes = new Uint8Array(output);
  const chunk = new ArrayBuffer(Math.min(64 * 1024, size));
  const file = await fs.open(path, fs.OpenMode.READ_ONLY);

  try {
    let consumed = 0;
    while (consumed < size) {
      const count = await fs.read(file.fd, chunk, {
        length: Math.min(chunk.byteLength, size - consumed),
      });
      if (count <= 0) throw new ExpoFetchError('ERR_FETCH_FILE_READ', path);

      outputBytes.set(new Uint8Array(chunk, 0, count), consumed);
      consumed += count;
    }
    return output;
  } finally {
    await fs.close(file.fd);
  }
}

export async function withStoredCookies(headers: Object, target: string, credentials?: string): Promise<Object> {
  if (credentials !== 'include') return headers;

  let stored = '';

  try {
    stored = (await webview.WebCookieManager.fetchCookie(target, false)).replace(/,/g, ';');
  } catch (error) {
    const code = (error as BusinessError).code;
    if (code !== COOKIE_UNAVAILABLE) console.warn(`[expo-fetch] Unable to read stored cookies (Harmony code ${code}).`);

    return headers;
  }

  if (stored.length === 0) return headers;

  const result = withoutHeaders(headers, ['cookie']);
  const explicit = headerValue(headers, 'cookie');
  Reflect.set(result, 'cookie', mergeCookieHeaders(explicit, stored));

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
      console.warn(`[expo-fetch] Unable to store a response cookie (Harmony code ${(error as BusinessError).code}).`);
    }
  }

  Promise.resolve()
    .then((): Promise<void> => webview.WebCookieManager.saveCookieAsync())
    .catch((error: BusinessError): void => {
      console.warn(`[expo-fetch] Unable to persist response cookies (Harmony code ${error.code}).`);
    });
}

export function headerValue(headers: Object, name: string): string | null {
  const key = Object.keys(headers).find((candidate: string): boolean => {
    return candidate.toLowerCase() === name;
  });
  return key === undefined ? null : String(Reflect.get(headers, key));
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

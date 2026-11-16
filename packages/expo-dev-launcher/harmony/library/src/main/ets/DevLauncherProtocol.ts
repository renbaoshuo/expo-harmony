/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import uri from '@ohos.uri';
import url from '@ohos.url';

// An explicit development selection takes precedence over installed production updates.
export const DevLauncherHostPriority = 20;
export const DEEP_LINK_SCHEME = 'expo-harmony';
export const DEEP_LINK_HOST = 'open';
export const EXPO_DEV_CLIENT_HOST = 'expo-development-client';
export const MANIFEST_PATH = '/manifest';
export const HARMONY_PLATFORM = 'harmony';
export const RUNTIME_CONTRACT_ASSET = 'expo-harmony-runtime.json';
export const DEFAULT_LAUNCH_URL_METADATA = 'DEV_CLIENT_DEFAULT_LAUNCHER_URL';
export const EMBEDDED_BUNDLE_METADATA = 'EXDevClientEmbeddedBundle';
export const EXPO_MDNS_SERVICE = '_expo._tcp';
export const MAX_MANIFEST_BYTES = 2 * 1024 * 1024;
export const NETWORK_TIMEOUT_MS = 60_000;

const EXPO_UPDATES_HOSTS = ['u.expo.dev', 'staging-u.expo.dev'];

export function hasEnabledFlag(value: string, name: string): boolean {
  return getQueryValue(value, name) === '1';
}

export function getQueryValue(value: string, name: string): string | undefined {
  const query = new uri.URI(value.trim()).encodedQuery ?? '';
  return new url.URLParams(query).get(name) ?? undefined;
}

export function isEASUpdateURL(value: string): boolean {
  return EXPO_UPDATES_HOSTS.includes((new uri.URI(value).host ?? '').toLowerCase());
}

function isLauncherURI(parsed: uri.URI): boolean {
  const scheme = (parsed.scheme ?? '').toLowerCase();
  const host = (parsed.host ?? '').toLowerCase();
  return scheme === DEEP_LINK_SCHEME ? host === DEEP_LINK_HOST : host === EXPO_DEV_CLIENT_HOST;
}

export function isLauncherLink(value: string): boolean {
  try {
    return isLauncherURI(new uri.URI(value.trim()));
  } catch (_) {
    return false;
  }
}

export function isLauncherHomeLink(value: string): boolean {
  try {
    const parsed = new uri.URI(value.trim());
    decodeURIComponent(value);

    return isLauncherURI(parsed) && !value.includes('#') && !(parsed.authority ?? '').includes('@')
      && getQueryValue(value, 'url') === undefined;
  } catch (_) {
    return false;
  }
}

export function bundleURL(value: string): string {
  const target = parseHTTPURL(normalizedNetworkURL(value));
  if (target.pathname.endsWith('.js')) return target.toString();

  if (target.pathname === '' || target.pathname === '/') {
    target.pathname = '/index.bundle';
    target.params.set('dev', 'true');
    target.params.set('minify', 'false');
  }
  target.params.set('platform', HARMONY_PLATFORM);

  return target.toString();
}

export class DevLauncherError extends Error {
  readonly code: string;

  constructor(code: string, message: string, cause?: Object) {
    super(cause === undefined ? message : `${message} ${String(cause)}`);
    this.code = code;
    this.name = 'DevLauncherError';
  }
}

function normalizedNetworkURL(value: string): string {
  const text = value.trim();
  if (text.length === 0) throw new DevLauncherError('ERR_DEV_LAUNCHER_INVALID_URL', 'The development URL is empty.');

  const lower = text.toLowerCase();
  const target = lower.startsWith('exp://')
    ? `http://${text.slice('exp://'.length)}`
    : lower.startsWith('exps://')
      ? `https://${text.slice('exps://'.length)}`
      : text;

  return parseNetworkURI(target).toString();
}

function parseNetworkURI(value: string): uri.URI {
  try {
    decodeURIComponent(value);
  } catch (error) {
    throw new DevLauncherError('ERR_DEV_LAUNCHER_INVALID_URL', 'The development URL contains invalid percent encoding.', error as Object);
  }

  let parsed: uri.URI;

  try {
    parsed = new uri.URI(value);
  } catch (error) {
    throw new DevLauncherError('ERR_DEV_LAUNCHER_INVALID_URL', 'The development URL is malformed.', error as Object);
  }


  const scheme = (parsed.scheme ?? '').toLowerCase();
  const authority = parsed.authority ?? '';
  if ((scheme !== 'http' && scheme !== 'https') || !(parsed.host ?? '').length
    || authority.includes('@') || value.includes('#')) {
    throw new DevLauncherError('ERR_DEV_LAUNCHER_INVALID_URL', 'Development URLs must use HTTP or HTTPS without credentials or fragments.');
  }
  return parsed;
}

export function parseHTTPURL(value: string): url.URL {
  const source = parseNetworkURI(value);
  let parsed: url.URL;
  try {
    parsed = url.URL.parseURL(source.toString());
  } catch (error) {
    throw new DevLauncherError('ERR_DEV_LAUNCHER_INVALID_URL', 'The development URL is malformed.', error as Object);
  }
  if (parsed.username || parsed.password) {
    throw new DevLauncherError('ERR_DEV_LAUNCHER_INVALID_URL', 'Development URLs must not contain credentials.');
  }
  return parsed;
}

export function resolveDevelopmentURL(value: string): string {
  let parsed: uri.URI;

  try {
    decodeURIComponent(value.trim());
  } catch (error) {
    throw new DevLauncherError('ERR_DEV_LAUNCHER_INVALID_URL', 'The development URL contains invalid percent encoding.', error as Object);
  }

  try {
    parsed = new uri.URI(value.trim());
  } catch (_) {
    return normalizedNetworkURL(value);
  }

  const scheme = (parsed.scheme ?? '').toLowerCase();
  if (!isLauncherURI(parsed)) {
    if (scheme === DEEP_LINK_SCHEME) {
      throw new DevLauncherError('ERR_DEV_LAUNCHER_INVALID_URL', `Expected ${DEEP_LINK_SCHEME}://${DEEP_LINK_HOST}.`);
    }
    return normalizedNetworkURL(value);
  }
  if (value.includes('#') || (parsed.authority ?? '').includes('@')) {
    throw new DevLauncherError('ERR_DEV_LAUNCHER_INVALID_URL', 'Development-client links must not contain credentials or fragments.');
  }

  const target = getQueryValue(value, 'url');
  if (target === undefined || target.length === 0) {
    throw new DevLauncherError('ERR_DEV_LAUNCHER_INVALID_URL', 'The development-client link is missing its url parameter.');
  }

  return normalizedNetworkURL(target);
}

export function manifestURL(value: string): string {
  const source = resolveDevelopmentURL(value);
  const parsed = new uri.URI(source);
  const path = parsed.encodedPath ?? '';
  if (path.endsWith('.bundle') || path.endsWith('.js')) return source;

  if (path === '' || path === '/' || path === MANIFEST_PATH || path === '/index.exp') {
    const target = parseHTTPURL(source);
    target.params.set('platform', HARMONY_PLATFORM);
    return canonicalDevelopmentManifestURL(target.toString());
  }

  return source;
}

// Strict identity validation is separate from user-input normalization: never
// silently repair a manifest's wrong/duplicate platform or discard its query.
export function canonicalDevelopmentManifestURL(value: string): string {
  const target = parseHTTPURL(value);
  if (!['/', MANIFEST_PATH, '/index.exp'].includes(target.pathname)
    || target.params.getAll('platform').length !== 1 || target.params.get('platform') !== HARMONY_PLATFORM) {
    throw new DevLauncherError('ERR_DEV_LAUNCHER_INVALID_URL', 'Expected an HTTP(S) Harmony manifest URL without credentials or fragments.');
  }
  target.pathname = MANIFEST_PATH;
  target.params.delete('platform');
  target.params.append('platform', HARMONY_PLATFORM);

  return target.toString();
}

export function displayError(error: Object): string {
  if (error instanceof Error && error.message.length > 0) return error.message;
  // Harmony BusinessError may be a plain object rather than an Error instance.
  if (error !== null && typeof error === 'object') {
    const details = error as { message?: string; code?: string | number };
    const message = typeof details.message === 'string' ? details.message : '';
    const code = typeof details.code === 'string' || typeof details.code === 'number' ? String(details.code) : '';
    if (message.length > 0) return code.length > 0 ? `${message} (${code})` : message;
    if (code.length > 0) return `Native operation failed (${code}).`;
  }
  return String(error);
}

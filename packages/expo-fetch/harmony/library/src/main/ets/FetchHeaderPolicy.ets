import { ExpoFetchError } from './ExpoFetchError';
import url from '@ohos.url';

const NON_COMBINABLE_REQUEST_HEADERS: Set<string> = new Set<string>(['authorization', 'content-length', 'host', 'proxy-authorization']);

export function collectRequestHeaders(pairs: string[][]): Map<string, string> {
  const values: Map<string, string> = new Map<string, string>();
  const names: Map<string, string> = new Map<string, string>();

  pairs.forEach((pair: string[]): void => {
    if (pair.length !== 2) {
      throw new ExpoFetchError('ERR_FETCH_HEADERS', 'Each request header must contain exactly a name and a value');
    }

    const normalized = pair[0].toLowerCase();
    const name = names.get(normalized) ?? pair[0];
    names.set(normalized, name);
    const prior = values.get(name);

    if (prior !== undefined && NON_COMBINABLE_REQUEST_HEADERS.has(normalized)) {
      throw new ExpoFetchError('ERR_FETCH_HEADERS', `HarmonyOS NetStack cannot preserve duplicate ${pair[0]} request headers`);
    }

    values.set(name, prior === undefined ? pair[1] : `${prior}${normalized === 'cookie' ? '; ' : ', '}${pair[1]}`);
  });

  return values;
}

export function filePathFromUrl(value: string): string {
  try {
    const parsed = url.URL.parseURL(value);
    if (parsed.protocol.toLowerCase() !== 'file:') throw new Error('Not a file URL');
    const host = parsed.hostname.toLowerCase();
    if (host.length > 0 && host !== 'localhost') throw new Error('Remote file authority');

    const path = decodeURIComponent(parsed.pathname);
    if (!path.startsWith('/') || path.includes('\u0000')) throw new Error('Invalid file path');
    return path;
  } catch (_error) {
    throw new ExpoFetchError('ERR_FETCH_INVALID_URL', `Invalid file URL: ${value}`);
  }
}

export function headersForDecodedResponse(pairs: string[][]): string[][] {
  const encoding = pairs.find((pair: string[]): boolean => {
    return pair.length >= 2 && pair[0].toLowerCase() === 'content-encoding';
  });

  if (encoding === undefined || encoding[1].trim().toLowerCase() === 'identity') {
    return pairs;
  }

  return pairs.filter((pair: string[]): boolean => {
    const name = pair[0].toLowerCase();
    return name !== 'content-encoding' && name !== 'content-length';
  });
}

export function mergeCookieHeaders(explicit: string | null, stored: string): string {
  if (explicit === null || explicit.trim().length === 0) return stored;

  const names = new Set<string>();
  explicit.split(';').forEach((cookie: string): void => {
    const equals = cookie.indexOf('=');
    if (equals > 0) names.add(cookie.slice(0, equals).trim());
  });

  const extra = stored.split(';').filter((cookie: string): boolean => {
    const equals = cookie.indexOf('=');
    return equals > 0 && !names.has(cookie.slice(0, equals).trim());
  });

  return extra.length === 0 ? explicit : `${explicit}; ${extra.join('; ')}`;
}

export class RequestMethodPolicy {
  readonly method: string;
  readonly standard: boolean;

  constructor(method: string, standard: boolean) {
    this.method = method;
    this.standard = standard;
  }
}

export function requestMethodPolicy(method: string): RequestMethodPolicy {
  if (!/^[A-Za-z0-9!#$%&'*+.^_`|~-]+$/.test(method)) {
    throw new ExpoFetchError('ERR_FETCH_METHOD', method);
  }

  return new RequestMethodPolicy(
    method,
    method === 'OPTIONS' ||
      method === 'GET' ||
      method === 'HEAD' ||
      method === 'POST' ||
      method === 'PUT' ||
      method === 'DELETE' ||
      method === 'TRACE' ||
      method === 'CONNECT',
  );
}

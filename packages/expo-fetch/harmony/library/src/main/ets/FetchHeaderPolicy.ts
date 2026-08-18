import { ExpoFetchError } from './ExpoFetchError';

export function collectRequestHeaders(pairs: string[][]): Map<string, string> {
  const values: Map<string, string> = new Map();
  const names: Map<string, string> = new Map();

  pairs.forEach((pair: string[]): void => {
    if (pair.length < 2) return;

    const normalized = pair[0].toLowerCase();
    const name = names.get(normalized) ?? pair[0];
    names.set(normalized, name);
    const prior = values.get(name);

    values.set(
      name,
      prior === undefined
        ? pair[1]
        : `${prior}${normalized === 'cookie' ? '; ' : ', '}${pair[1]}`
    );
  });

  return values;
}

export function filePathFromUrl(value: string): string {
  const encoded = value.slice('file://'.length);
  const query = encoded.indexOf('?');
  const fragment = encoded.indexOf('#');
  let end = encoded.length;

  if (query >= 0) end = Math.min(end, query);
  if (fragment >= 0) end = Math.min(end, fragment);

  try {
    return decodeURIComponent(encoded.slice(0, end));
  } catch (_) {
    throw new ExpoFetchError('ERR_FETCH_INVALID_URL', `Invalid file URL: ${value}`);
  }
}

export function headersForDecodedResponse(pairs: string[][]): string[][] {
  const encoding = pairs.find((pair: string[]): boolean =>
    pair.length >= 2 && pair[0].toLowerCase() === 'content-encoding'
  );

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

export interface RequestMethodPolicy {
  method: string;
  standard: boolean;
}

export function requestMethodPolicy(method: string): RequestMethodPolicy {
  if (!/^[A-Za-z0-9!#$%&'*+.^_`|~-]+$/.test(method)) {
    throw new ExpoFetchError('ERR_FETCH_METHOD', method);
  }

  return {
    method,
    standard: method === 'OPTIONS' || method === 'GET' || method === 'HEAD'
      || method === 'POST' || method === 'PUT' || method === 'DELETE'
      || method === 'TRACE' || method === 'CONNECT',
  };
}

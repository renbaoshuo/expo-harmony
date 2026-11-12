/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { LogRecord } from './AppMetricsModels.ts';

// Keep these limits in sync with SDK 57's LogEvents validation on Android/iOS.
const MAX_EVENT_NAME_LENGTH: number = 256;
const MAX_EVENT_BODY_LENGTH: number = 4096;
const MAX_DISPLAY_NAME_LENGTH: number = 128;
const MAX_ATTRIBUTE_COUNT: number = 128;
const TRUNCATION_SUFFIX: string = '…';

export type MetricsWarn = (message: string) => void;

export function truncateLogText(text: string, limit: number, warn: MetricsWarn): string {
  if (text.length <= limit) return text;
  warn(`Expo App Metrics truncated text to ${limit} UTF-16 code units.`);
  let end = limit - TRUNCATION_SUFFIX.length;
  // Never create a dangling high surrogate at the truncation boundary.
  const last = text.charCodeAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end -= 1;

  return text.slice(0, end) + TRUNCATION_SUFFIX;
}

export class SanitizedAttributes {
  attributes?: Record<string, ESObject>;
  dropped: number = 0;
}

export function sanitizeAttributes(input: Record<string, ESObject> | undefined, warn: MetricsWarn): SanitizedAttributes {
  const result = new SanitizedAttributes();
  if (input === undefined) return result;

  const attributes: Record<string, ESObject> = {};
  Object.keys(input).forEach((key: string): void => {
    const normalized = key.trim();
    if (normalized.length === 0 || /^expo\..+/.test(normalized) || normalized === 'session.id' || normalized === 'event.name') {
      result.dropped += 1;
    } else {
      setAttribute(attributes, normalized, input[key]);
    }
  });
  const keys = Object.keys(attributes).sort();
  keys.slice(MAX_ATTRIBUTE_COUNT).forEach((key: string): void => { delete attributes[key]; result.dropped += 1; });
  if (result.dropped > 0) warn(`Expo App Metrics dropped ${result.dropped} empty, reserved or excess attributes.`);
  if (Object.keys(attributes).length > 0) result.attributes = attributes;

  return result;
}

export function makeLogEvent(
  name: string,
  options: Record<string, ESObject> | undefined,
  warn: MetricsWarn,
): LogRecord | undefined {
  const normalized = name.trim();
  if (normalized.length === 0 || normalized.startsWith('expo.') || normalized.length > MAX_EVENT_NAME_LENGTH) {
    warn('Expo App Metrics dropped an empty, reserved or overlong event name.');
    return undefined;
  }
  const sanitized = sanitizeAttributes(optionalMap(options?.['attributes']), warn);
  const displayName = optionalText(options?.['displayName'])?.trim();
  if (displayName !== undefined && displayName.length > 0) {
    if (sanitized.attributes === undefined) sanitized.attributes = {};
    sanitized.attributes['expo.log.display_name'] = truncateLogText(displayName, MAX_DISPLAY_NAME_LENGTH, warn);
  }
  const body = optionalText(options?.['body']);
  const log = new LogRecord(
    new Date().toISOString(), normalized, optionalText(options?.['severity']) ?? 'info',
    body === undefined ? undefined : truncateLogText(body, MAX_EVENT_BODY_LENGTH, warn), sanitized.attributes,
  );
  log.droppedAttributesCount = sanitized.dropped;

  return log;
}

export function makeErrorLog(report: Record<string, ESObject>): LogRecord {
  const fatal: boolean = report['isFatal'] === true;
  const attributes: Record<string, ESObject> = {};
  attributes['expo.error.source'] = optionalText(report['source']) ?? 'global';
  attributes['expo.error.is_fatal'] = fatal;
  attributes['exception.type'] = optionalText(report['type']) ?? null;
  attributes['exception.message'] = optionalText(report['message']) ?? '';
  attributes['exception.stacktrace'] = optionalText(report['stacktrace']) ?? null;
  const stack = optionalText(report['componentStack']);
  if (stack !== undefined) attributes['expo.error.component_stack'] = stack;

  return new LogRecord(new Date().toISOString(), 'js.exception', fatal ? 'fatal' : 'error', undefined, attributes);
}

export function optionalText(value: ESObject): string | undefined {
  return typeof value === 'string' ? value : undefined;
}

export function optionalMap(value: ESObject): Record<string, ESObject> | undefined {
  return value !== null && value !== undefined && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, ESObject> : undefined;
}

// TypeScript keeps safe own-property writes available to ArkTS callers as well.
export function setAttribute(attributes: Record<string, ESObject>, key: string, value: ESObject): void {
  Object.defineProperty(attributes, key, { value, enumerable: true, configurable: true, writable: true });
}

export function mergeAttributes(base?: Record<string, ESObject>, overrides?: Record<string, ESObject>): Record<string, ESObject> {
  const result: Record<string, ESObject> = {};
  if (base !== undefined) Object.keys(base).forEach((key: string): void => setAttribute(result, key, base[key]));
  if (overrides !== undefined) Object.keys(overrides).forEach((key: string): void => setAttribute(result, key, overrides[key]));
  return result;
}

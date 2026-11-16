/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export type JSONValue = Object | null | undefined;
export type JSONObject = Record<string, JSONValue>;

export class JSONUtilsError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'JSONUtilsError';
  }
}

export class JSONObjectUtils {
  static hasValue(json: JSONObject, key: string): boolean {
    return Object.prototype.hasOwnProperty.call(json, key);
  }

  static require(json: JSONObject, key: string): JSONValue {
    return requireDataValue(Object.getOwnPropertyDescriptor(json, key), key);
  }

  static getNullable(json: JSONObject, key: string): JSONValue {
    const field = Object.getOwnPropertyDescriptor(json, key);
    return field === undefined ? null : requireDataValue(field, key);
  }

  static requireString(json: JSONObject, key: string): string {
    const value = JSONObjectUtils.require(json, key);

    if (typeof value === 'string') return value;
    if (value === null) return 'null';

    if (typeof value === 'boolean' || (typeof value === 'number' && Number.isFinite(value))) {
      return String(value);
    }

    if (Array.isArray(value) || isJSONObject(value)) {
      try {
        validateJSON(value, key);

        return JSON.stringify(value);
      } catch {
        throw new JSONUtilsError(`Value for ${key} cannot be converted to JSON string`);
      }
    }

    throw new JSONUtilsError(`Value for ${key} cannot be converted to string`);
  }

  static getNullableString(json: JSONObject, key: string): string | null {
    return JSONObjectUtils.hasValue(json, key) ? JSONObjectUtils.requireString(json, key) : null;
  }

  static requireNumber(json: JSONObject, key: string): number {
    const value = JSONObjectUtils.require(json, key);

    if (typeof value === 'number') return value;

    if (typeof value === 'string') {
      // eslint-disable-next-line no-control-regex -- Match Java's trim range in the anchored match.
      const match = /^[\x00-\x20]*([+-]?(?:(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?[fFdD]?|NaN|Infinity))[\x00-\x20]*$/.exec(value);
      if (match) {
        return Number(match[1].replace(/[fFdD]$/, ''));
      }
    }

    throw new JSONUtilsError(`Value for ${key} cannot be converted to number`);
  }

  static getNullableNumber(json: JSONObject, key: string): number | null {
    return JSONObjectUtils.hasValue(json, key) ? JSONObjectUtils.requireNumber(json, key) : null;
  }

  static requireBoolean(json: JSONObject, key: string): boolean {
    const value = JSONObjectUtils.require(json, key);

    if (typeof value === 'boolean') return value;

    if (typeof value === 'string') {
      if (/^true$/iu.test(value)) return true;
      if (/^false$/iu.test(value)) return false;
    }

    throw new JSONUtilsError(`Value for ${key} cannot be converted to boolean`);
  }

  static getNullableBoolean(json: JSONObject, key: string): boolean | null {
    return JSONObjectUtils.hasValue(json, key) ? JSONObjectUtils.requireBoolean(json, key) : null;
  }

  static requireArray(json: JSONObject, key: string): JSONValue[] {
    const value = JSONObjectUtils.require(json, key);

    if (!Array.isArray(value)) throw new JSONUtilsError(`Value for ${key} cannot be converted to array`);

    return value;
  }

  static getNullableArray(json: JSONObject, key: string): JSONValue[] | null {
    return JSONObjectUtils.hasValue(json, key) ? JSONObjectUtils.requireArray(json, key) : null;
  }

  static requireObject(json: JSONObject, key: string): JSONObject {
    const value = JSONObjectUtils.require(json, key);

    if (!isJSONObject(value)) throw new JSONUtilsError(`Value for ${key} cannot be converted to object`);

    return value;
  }

  static getNullableObject(json: JSONObject, key: string): JSONObject | null {
    return JSONObjectUtils.hasValue(json, key) ? JSONObjectUtils.requireObject(json, key) : null;
  }
}

function requireDataValue(field: PropertyDescriptor | undefined, key: string): JSONValue {
  if (field === undefined) {
    throw new JSONUtilsError(`No value for ${key}`);
  }
  if (!Object.prototype.hasOwnProperty.call(field, 'value')) {
    throw new JSONUtilsError(`Value for ${key} must be a data property`);
  }

  return field.value;
}

function isJSONObject(value: unknown): value is JSONObject {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;

  const prototype = Object.getPrototypeOf(value);

  return prototype === Object.prototype || prototype === null;
}

function validateJSON(root: unknown, key: string): void {
  const pending: unknown[] = [root];
  const seen = new Set<object>();

  while (pending.length > 0) {
    const value = pending.pop();

    if (value === null || typeof value === 'string' || typeof value === 'boolean'
      || (typeof value === 'number' && Number.isFinite(value))) continue;

    if (!Array.isArray(value) && !isJSONObject(value)) {
      throw new JSONUtilsError(`Value for ${key} cannot be converted to JSON value`);
    }

    if (seen.has(value)) continue;
    seen.add(value);

    const array = Array.isArray(value);
    let prototype = Object.getPrototypeOf(value);
    if (array && prototype !== Array.prototype) {
      throw new JSONUtilsError(`Value for ${key} cannot be converted to JSON array`);
    }

    // Inspect descriptors without invoking getters or inherited toJSON hooks.
    while (prototype !== null) {
      if (Object.getOwnPropertyDescriptor(prototype, 'toJSON') !== undefined) {
        throw new JSONUtilsError(`Value for ${key} cannot be converted to JSON value`);
      }
      prototype = Object.getPrototypeOf(prototype);
    }

    const toJSON = Object.getOwnPropertyDescriptor(value, 'toJSON');
    if (toJSON !== undefined && (!Object.prototype.hasOwnProperty.call(toJSON, 'value') || typeof toJSON.value === 'function')) {
      throw new JSONUtilsError(`Value for ${key} cannot be converted to JSON value`);
    }

    if (array) {
      for (let index = 0; index < value.length; index++) {
        const name = String(index);
        pending.push(requireDataValue(Object.getOwnPropertyDescriptor(value, name), name));
      }
    } else {
      for (const name of Object.keys(value)) {
        pending.push(requireDataValue(Object.getOwnPropertyDescriptor(value, name), name));
      }
    }
  }
}

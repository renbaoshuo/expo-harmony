/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export type JSONValue = Object | null | undefined;
export type JSONObject = Record<string, JSONValue>;

// eslint-disable-next-line no-control-regex -- Java trims characters U+0000 through U+0020.
const DECIMAL_DOUBLE = /^[\x00-\x20]*([+-]?(?:(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?[fFdD]?|NaN|Infinity))[\x00-\x20]*$/;
// eslint-disable-next-line no-control-regex -- Java trims characters U+0000 through U+0020.
const HEXADECIMAL_DOUBLE = /^[\x00-\x20]*([+-]?)0[xX]([0-9a-fA-F]*)(?:\.([0-9a-fA-F]*))?[pP]([+-]?[0-9]+)[fFdD]?[\x00-\x20]*$/;
const BITS_PER_HEX_DIGIT = 4;
const HEX_SIGNIFICAND_DIGITS = 15;
const BINARY64_OVERFLOW_SCALE = 1024 + BITS_PER_HEX_DIGIT;
const BINARY64_UNDERFLOW_SCALE = -1075;

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
      const decimal = DECIMAL_DOUBLE.exec(value);
      if (decimal !== null) return Number(decimal[1].replace(/[fFdD]$/, ''));

      const hex = HEXADECIMAL_DOUBLE.exec(value);
      if (hex !== null) {
        const [, sign, whole, fraction = '', exponent] = hex;

        if (whole.length + fraction.length > 0) {
          return hexToNumber(sign === '-' ? -1 : 1, whole, fraction, exponent);
        }
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

function hexToNumber(sign: number, whole: string, fraction: string, exponent: string): number {
  const digits = (whole + fraction).replace(/^0+/, '');
  if (digits.length === 0) return sign * 0;

  // With the point before the first nonzero digit, the mantissa is in [1/16, 1).
  const scale = Number(exponent) + BITS_PER_HEX_DIGIT * (digits.length - fraction.length);
  if (scale >= BINARY64_OVERFLOW_SCALE) return sign * Infinity;
  if (scale <= BINARY64_UNDERFLOW_SCALE) return sign * 0;

  // Keep more than the 54 bits needed to distinguish binary64 midpoints.
  let prefix = digits.slice(0, HEX_SIGNIFICAND_DIGITS);
  if (/[1-9a-f]/i.test(digits.slice(HEX_SIGNIFICAND_DIGITS))) prefix += '1';

  const significand = BigInt('0x' + prefix);
  const power = scale - BITS_PER_HEX_DIGIT * prefix.length;
  if (power >= 0) return sign * Number(significand << BigInt(power));

  // Convert by 2^n = 5^(-n) * 10^n, so Number rounds only once, including for subnormals.
  const decimal = significand * BigInt(5) ** BigInt(-power);

  return sign * Number(decimal.toString() + 'e' + power);
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

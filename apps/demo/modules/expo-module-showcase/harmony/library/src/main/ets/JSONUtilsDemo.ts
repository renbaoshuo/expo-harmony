/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { JSONObject, JSONObjectUtils, JSONUtilsError, JSONValue } from '@expo-harmony/expo-json-utils';

export function readJSON(input: string, key: string, type: string, nullable: boolean): string {
  const data = JSON.parse(input) as JSONObject;
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    throw new JSONUtilsError('Input must be a JSON object');
  }

  if (type === 'hasValue') return JSON.stringify(JSONObjectUtils.hasValue(data, key));

  let value: JSONValue;
  switch (type) {
    case 'raw':
      value = nullable ? JSONObjectUtils.getNullable(data, key) : JSONObjectUtils.require(data, key);
      break;
    case 'string':
      value = nullable ? JSONObjectUtils.getNullableString(data, key) : JSONObjectUtils.requireString(data, key);
      break;
    case 'number':
      value = nullable ? JSONObjectUtils.getNullableNumber(data, key) : JSONObjectUtils.requireNumber(data, key);
      break;
    case 'boolean':
      value = nullable ? JSONObjectUtils.getNullableBoolean(data, key) : JSONObjectUtils.requireBoolean(data, key);
      break;
    case 'array':
      value = nullable ? JSONObjectUtils.getNullableArray(data, key) : JSONObjectUtils.requireArray(data, key);
      break;
    case 'object':
      value = nullable ? JSONObjectUtils.getNullableObject(data, key) : JSONObjectUtils.requireObject(data, key);
      break;
    default: throw new JSONUtilsError(`Unknown reader type: ${type}`);
  }

  return JSON.stringify(typeof value === 'number' && !Number.isFinite(value) ? String(value) : value);
}

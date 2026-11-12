/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  BareItem, ByteSequence, Decimal, Dictionary, InnerList, Item, List, Parameters, Token,
  parseBareItem, parseBoolean, parseByteSequence, parseDictionary, parseInnerList, parseIntegerOrDecimal,
  parseItem, parseItemOrInnerList, parseKey, parseList, parseParameters, parseString, parseToken,
  serializeDictionary, serializeItem, serializeList,
} from '@expo-harmony/expo-structured-headers';

function encode(value: ESObject): ESObject {
  if (value instanceof Map) return Object.fromEntries(Array.from(value.entries()).map(([key, item]) => [key, encode(item)]));
  if (Array.isArray(value)) return value.map(item => encode(item));
  if (value instanceof Token) return { token: value.toString() };
  if (value instanceof ByteSequence) return { base64: value.toBase64() };
  if (value instanceof Decimal) return { permille: value.permille };

  return value;
}

export function parseHeader(method: string, input: string, multipleLines: boolean): string {
  const field = multipleLines ? input.split(/\r?\n/) : input;
  let value: ESObject;

  switch (method) {
    case 'parseDictionary': value = parseDictionary(field); break;
    case 'parseList': value = parseList(field); break;
    case 'parseItem': value = parseItem(field); break;
    case 'parseBareItem': value = parseBareItem(input); break;
    case 'parseParameters': value = parseParameters(input); break;
    case 'parseKey': value = parseKey(input); break;
    case 'parseString': value = parseString(input); break;
    case 'parseToken': value = parseToken(input); break;
    case 'parseByteSequence': value = parseByteSequence(input); break;
    case 'parseBoolean': value = parseBoolean(input); break;
    case 'parseIntegerOrDecimal': value = parseIntegerOrDecimal(input); break;
    case 'parseInnerList': value = parseInnerList(input); break;
    case 'parseItemOrInnerList': value = parseItemOrInnerList(input); break;
    default: throw new Error(`Unknown parser: ${method}`);
  }

  return JSON.stringify(encode(value));
}

type JSONBareItem = string | boolean | number | { token: string } | { base64: string } | { permille: number };
type JSONParameters = Record<string, JSONBareItem>;
type JSONItem = [JSONBareItem, JSONParameters];
type JSONEntry = JSONItem | [JSONItem[], JSONParameters];

function bareItem(value: JSONBareItem): BareItem {
  if (typeof value === 'string' || typeof value === 'boolean' || typeof value === 'number') return value;
  if (value !== null && typeof value === 'object') {
    if ('token' in value) return new Token(value.token);
    if ('base64' in value) return new ByteSequence(value.base64);
    if ('permille' in value) return Decimal.fromPermille(value.permille);
  }
  throw new Error('Use a string, boolean, number, token, base64 or permille.');
}

function parameters(value: JSONParameters): Parameters {
  return new Map(Object.entries(value).map(([key, item]) => [key, bareItem(item)]));
}

function item(value: JSONItem): Item {
  return [bareItem(value[0]), parameters(value[1])];
}

function entry(value: JSONEntry): Item | InnerList {
  const [content, params] = value;
  return Array.isArray(content)
    ? [content.map(child => item(child)), parameters(params)]
    : [bareItem(content), parameters(params)];
}

export function serializeHeader(format: string, input: string): string {
  switch (format) {
    case 'item': return serializeItem(item(JSON.parse(input) as JSONItem));
    case 'list': {
      const values = JSON.parse(input) as JSONEntry[];
      const list: List = values.map(value => entry(value));
      return serializeList(list);
    }
    case 'dictionary': {
      const values = JSON.parse(input) as Record<string, JSONEntry>;
      const dictionary: Dictionary = new Map(Object.entries(values).map(([key, value]) => [key, entry(value)]));
      return serializeDictionary(dictionary);
    }
    default: throw new Error(`Unknown serializer: ${format}`);
  }
}

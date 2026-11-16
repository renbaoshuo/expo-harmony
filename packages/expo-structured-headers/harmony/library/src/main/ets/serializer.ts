/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  BareItem,
  ByteSequence,
  Dictionary,
  InnerList,
  Item,
  List,
  Parameters,
  Decimal,
} from './types';

import { Token } from './token';

import { isAscii, isInnerList, isValidKeyStr, isValidTokenStr } from './util';

export class SerializeError extends Error {
  constructor(message: string, cause?: Error) {
    super(message);
    this.name = 'SerializeError';
    if (cause !== undefined) this.cause = cause;
  }

  readonly cause?: Error;
}

export function serializeList(input: List): string {
  if (!Array.isArray(input)) throw new SerializeError('A list must be an array.');

  return Array.from(input, value => isInnerList(value) ? serializeInnerList(value) : serializeItem(value)).join(', ');
}

export function serializeDictionary(input: Dictionary): string {
  if (!(input instanceof Map)) throw new SerializeError('A dictionary must be a Map.');

  return Array.from(input.entries()).map(([key, value]) => {
    checkMember(value);
    const name = serializeKey(key);
    if (value[0] === true) return name + serializeParameters(value[1]);

    const member = isInnerList(value) ? serializeInnerList(value) : serializeItem(value);
    return `${name}=${member}`;
  }).join(', ');
}

export function serializeItem(input: Item): string {
  checkMember(input);
  return serializeBareItem(input[0]) + serializeParameters(input[1]);
}

function serializeInnerList(input: InnerList): string {
  checkMember(input);
  return `(${Array.from(input[0], serializeItem).join(' ')})${serializeParameters(input[1])}`;
}

function checkMember(input: Item | InnerList): void {
  if (!Array.isArray(input) || input.length !== 2) {
    throw new SerializeError('A member must contain a value and parameters.');
  }
}

function serializeBareItem(input: BareItem): string {
  if (typeof input === 'number') {
    if (Number.isInteger(input)) {
      return serializeInteger(input);
    }
    return serializeDecimal(input);
  }
  if (input instanceof Decimal) return serializeDecimalPermille(input.permille);
  if (typeof input === 'string') {
    return serializeString(input);
  }
  if (input instanceof Token) {
    return serializeToken(input);
  }
  if (input instanceof ByteSequence) {
    return serializeByteSequence(input);
  }
  if (typeof input === 'boolean') {
    return serializeBoolean(input);
  }
  throw new SerializeError(`Cannot serialize values of type ${typeof input}`);
}

function serializeInteger(input: number): string {
  if (input < -999_999_999_999_999 || input > 999_999_999_999_999) {
    throw new SerializeError('Structured headers can only encode integers in the range of -999,999,999,999,999 to 999,999,999,999,999 inclusive');
  }
  return input.toString();
}

function serializeDecimal(input: number): string {
  try {
    return serializeDecimalPermille(Decimal.valueOf(input).permille);
  } catch (error) {
    throw new SerializeError(error instanceof Error ? error.message : String(error), error instanceof Error ? error : undefined);
  }
}

function serializeDecimalPermille(input: number): string {
  const negative = input < 0;
  const value = Math.abs(input);
  if (!Number.isInteger(value) || value > 999_999_999_999_999) {
    throw new SerializeError('A decimal must contain a valid signed permille value.');
  }

  const whole = Math.floor(value / 1000);
  let fraction = String(value % 1000).padStart(3, '0').replace(/0+$/, '');
  if (!fraction) fraction = '0';

  return `${negative ? '-' : ''}${whole}.${fraction}`;
}

function serializeString(input: string): string {
  if (!isAscii(input)) {
    throw new SerializeError('Only ASCII strings may be serialized');
  }
  return `"${input.replace(/("|\\)/g, (v) => '\\' + v)}"`;
}

function serializeBoolean(input: boolean): string {
  return input ? '?1' : '?0';
}

function serializeByteSequence(input: ByteSequence): string {
  return `:${input.toBase64()}:`;
}

function serializeToken(input: Token): string {
  const value = input.toString();
  if (!isValidTokenStr(value)) throw new SerializeError('Invalid token.');
  return value;
}

function serializeParameters(input: Parameters): string {
  if (!(input instanceof Map)) throw new SerializeError('Parameters must be a Map.');

  return Array.from(input).map(([key, value]) => {
    const name = ';' + serializeKey(key);
    return value === true ? name : `${name}=${serializeBareItem(value)}`;
  }).join('');
}

function serializeKey(input: string): string {
  if (!isValidKeyStr(input)) {
    throw new SerializeError('Keys in dictionaries must only contain lowercase letter, numbers, _-*. and must start with a letter or *');
  }
  return input;
}

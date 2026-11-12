/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import util from '@ohos.util';
import { Token } from './token';

export type List = (InnerList|Item)[];

export type InnerList = [Item[], Parameters];

export type Parameters = Map<string, BareItem>;

export type Dictionary = Map<string, Item|InnerList>;

export class Decimal {
  readonly permille: number;

  private constructor(permille: number) {
    this.permille = permille;
  }

  static valueOf(value: number): Decimal {
    if (!Number.isFinite(value)) throw new TypeError('Decimal must be finite.');
    if (value === 0) return Decimal.fromPermille(0);

    // Decode the IEEE 754 binary64 value so scaling does not introduce a second
    // floating-point rounding. RFC 8941 section 4.1.5 rounds ties to even.
    const view = new DataView(new ArrayBuffer(8));
    view.setFloat64(0, Math.abs(value), false);

    const high = view.getUint32(0, false);
    const low = view.getUint32(4, false);
    const exponent = (high >>> 20) & 0x7ff;
    const fraction = (BigInt(high & 0xfffff) << BigInt(32)) | BigInt(low);
    const significand = exponent === 0 ? fraction : (BigInt(1) << BigInt(52)) | fraction;
    const shift = exponent === 0 ? -1074 : exponent - 1023 - 52;

    const scaled = significand * BigInt(1000);
    let rounded: bigint;
    if (shift >= 0) {
      rounded = scaled << BigInt(shift);
    } else {
      const divisor = BigInt(1) << BigInt(-shift);
      const quotient = scaled / divisor;
      const remainder = scaled % divisor;
      const twice = remainder * BigInt(2);

      rounded = quotient + (twice > divisor || (twice === divisor && quotient % BigInt(2) !== BigInt(0)) ? BigInt(1) : BigInt(0));
    }

    const permille = Number(rounded) * (value < 0 ? -1 : 1);

    return Decimal.fromPermille(permille);
  }

  static fromPermille(permille: number): Decimal {
    if (!Number.isInteger(permille) || Math.abs(permille) > 999_999_999_999_999) {
      throw new TypeError('Decimal permille is out of range.');
    }

    return new Decimal(permille);
  }

  valueOf(): number { return this.permille / 1000; }
  toNumber(): number { return this.valueOf(); }
}

export class ByteSequence {
  private readonly bytes: Uint8Array;

  constructor(value: string | Uint8Array) {
    if (value instanceof Uint8Array) {
      this.bytes = value.slice();
      return;
    }

    if (typeof value !== 'string') throw new TypeError('Base64 byte sequence must be a string or Uint8Array.');
    if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}(?:==)?|[A-Za-z0-9+/]{3}=?)?$/.test(value)) {
      throw new TypeError('Invalid Base64 byte sequence.');
    }

    const padded = value.padEnd(Math.ceil(value.length / 4) * 4, '=');
    this.bytes = padded ? new util.Base64Helper().decodeSync(padded) : new Uint8Array();
  }

  toBase64(): string {
    return this.bytes.length === 0 ? '' : new util.Base64Helper().encodeToStringSync(this.bytes);
  }

  toBytes(): Uint8Array { return this.bytes.slice(); }
}

export type BareItem = number | Decimal | string | Token | ByteSequence | boolean;

export type Item = [BareItem, Parameters];

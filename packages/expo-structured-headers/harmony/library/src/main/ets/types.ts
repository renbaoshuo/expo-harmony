/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { util } from '@kit.ArkTS';
import { Token } from './token';

export type List = (InnerList|Item)[];

export type InnerList = [Item[], Parameters];

export type Parameters = Map<string, BareItem>;

export type Dictionary = Map<string, Item|InnerList>;

const MAX_PERMILLE = 999_999_999_999_999;

export class Decimal {
  readonly permille: number;

  private constructor(permille: number) {
    this.permille = permille === 0 ? 0 : permille;
  }

  static valueOf(value: number): Decimal {
    if (!Number.isFinite(value)) throw new TypeError('Decimal must be finite.');
    const magnitude = Math.abs(value);
    if (magnitude >= 1_000_000_000_000) throw new TypeError('Decimal permille is out of range.');

    // Exact ties are odd multiples of 1/16. toFixed rounds up, so correct odd results to the even neighbor.
    let permille = Number(magnitude.toFixed(3).replace('.', ''));
    if (magnitude % (1 / 8) === 1 / 16 && permille % 2 !== 0) permille--;

    return Decimal.fromPermille(value < 0 ? -permille : permille);
  }

  static fromPermille(permille: number): Decimal {
    if (!Number.isInteger(permille) || Math.abs(permille) > MAX_PERMILLE) {
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
      this.bytes = new Uint8Array(value);
      return;
    }

    if (typeof value !== 'string') throw new TypeError('Base64 byte sequence must be a string or Uint8Array.');
    if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}(?:==)?|[A-Za-z0-9+/]{3}=?)?$/.test(value)) {
      throw new TypeError('Invalid Base64 byte sequence.');
    }

    const padded = value.padEnd(Math.ceil(value.length / 4) * 4, '=');

    try {
      this.bytes = padded ? new util.Base64Helper().decodeSync(padded) : new Uint8Array();
    } catch (_) {
      throw new TypeError('Invalid Base64 byte sequence.');
    }
  }

  toBase64(): string {
    return this.bytes.length === 0 ? '' : new util.Base64Helper().encodeToStringSync(this.bytes);
  }

  toBytes(): Uint8Array { return this.bytes.slice(); }
}

export type BareItem = number | Decimal | string | Token | ByteSequence | boolean;

export type Item = [BareItem, Parameters];

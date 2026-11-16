/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { isValidTokenStr } from './util';

export class Token {
  private readonly value: string;

  constructor(value: string) {
    if (!isValidTokenStr(value)) {
      throw new TypeError('Tokens must begin with an ASCII letter or * and contain only valid token characters.');
    }
    this.value = value;
  }

  toString(): string {
    return this.value;
  }
}

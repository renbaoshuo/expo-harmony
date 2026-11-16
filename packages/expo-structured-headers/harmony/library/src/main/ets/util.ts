/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Item, InnerList } from './types';

const asciiRe = /^[\x20-\x7E]*$/;
const tokenRe = /^[a-zA-Z*][:/!#$%&'*+\-.^_`|~A-Za-z0-9]*$/;
const keyRe = /^[a-z*][*\-_.a-z0-9]*$/;

export function isAscii(str: string): boolean {
  return typeof str === 'string' && asciiRe.test(str);
}

export function isValidTokenStr(str: string): boolean {
  return typeof str === 'string' && tokenRe.test(str);
}

export function isValidKeyStr(str: string): boolean {
  return typeof str === 'string' && keyRe.test(str);
}

export function isInnerList(input: Item | InnerList): input is InnerList {
  return Array.isArray(input) && Array.isArray(input[0]);
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';

const HermesMagic = Buffer.from('c61fbc03c103191f', 'hex');

export function readHermesBytecode(file: string): { bytecodeVersion: number; size: number } {
  const descriptor = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK);

  try {
    const stat = fs.fstatSync(descriptor);
    const header = Buffer.alloc(12);
    if (!stat.isFile() || stat.size <= header.length
      || fs.readSync(descriptor, header, 0, header.length, 0) !== header.length
      || !header.subarray(0, HermesMagic.length).equals(HermesMagic)) {
      throw new Error('Expected non-empty Hermes bytecode.');
    }

    return { bytecodeVersion: header.readUInt32LE(8), size: stat.size };
  } finally {
    fs.closeSync(descriptor);
  }
}

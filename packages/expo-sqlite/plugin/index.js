/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const pkg = require('../package.json');
const sqlite = (props = {}) => [pkg.name, props];

module.exports = sqlite;
Object.defineProperty(module.exports, '__esModule', { value: true });
module.exports.default = sqlite;

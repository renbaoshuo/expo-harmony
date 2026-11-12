/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { getLinkingURL } = require('expo-linking');
const upstream = require('expo-router/build/link/linking');

// Router applies redirects and +native-intent to this result. Read the
// current Expo scope synchronously before the navigator mounts.
function getInitialURL() {
  if (typeof window === 'undefined') return '';

  return getLinkingURL() ?? upstream.getRootURL();
}

module.exports = { ...upstream, getInitialURL };

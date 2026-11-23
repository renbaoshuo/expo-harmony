/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { getBaseURL: getUpstreamBaseURL } = require('expo/src/dom/base');

let cachedBaseURL = null;

function getBaseURL() {
  if (cachedBaseURL !== null) return cachedBaseURL;

  const url = globalThis.expo?.modules?.['ExpoUpdates']?.domAssetBaseUrl;
  if (typeof url === 'string' && url.length > 0) {
    cachedBaseURL = url;
  } else {
    const upstreamBaseURL = getUpstreamBaseURL();
    // Harmony export:embed packages the DOM pages under rawfile/www.bundle.
    cachedBaseURL = process.env.EXPO_OS === 'harmony' && process.env.NODE_ENV === 'production' && upstreamBaseURL === ''
      ? 'resource://rawfile/www.bundle'
      : upstreamBaseURL;
  }

  return cachedBaseURL;
}

module.exports = { getBaseURL };

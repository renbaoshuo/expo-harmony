'use strict';

const assert = require('node:assert/strict');
const Module = require('node:module');
const path = require('node:path');
const test = require('node:test');

test('loads the built-in and application preludes before Expo Router', () => {
  const requests = [];
  const originalLoad = Module._load;

  Module._load = function load(request, parent, isMain) {
    if (
      request === './prelude'
      || request === '@expo-harmony/entry/app-prelude'
      || request === 'expo-router/entry'
    ) {
      requests.push(request);
      return {};
    }

    return originalLoad.call(this, request, parent, isMain);
  };

  try {
    const entryPath = path.join(__dirname, '..', 'index.js');
    delete require.cache[entryPath];
    require(entryPath);
  } finally {
    Module._load = originalLoad;
  }

  assert.deepEqual(requests, [
    './prelude',
    '@expo-harmony/entry/app-prelude',
    'expo-router/entry',
  ]);
});

test('installs the Expo Modules global polyfill in the Harmony prelude', () => {
  let installations = 0;
  let useReactNativeFetchDuringInstallation;
  const originalLoad = Module._load;
  const previousUseReactNativeFetch = process.env.EXPO_PUBLIC_USE_RN_FETCH;

  Module._load = function load(request, parent, isMain) {
    if (request === 'expo-modules-core/src/polyfill/dangerous-internal') {
      return {
        installExpoGlobalPolyfill() {
          installations += 1;
          useReactNativeFetchDuringInstallation = process.env.EXPO_PUBLIC_USE_RN_FETCH;
        },
      };
    }

    return originalLoad.call(this, request, parent, isMain);
  };

  try {
    const preludePath = path.join(__dirname, '..', 'prelude.harmony.js');
    delete require.cache[preludePath];
    require(preludePath);
  } finally {
    Module._load = originalLoad;
    if (previousUseReactNativeFetch === undefined) {
      delete process.env.EXPO_PUBLIC_USE_RN_FETCH;
    } else {
      process.env.EXPO_PUBLIC_USE_RN_FETCH = previousUseReactNativeFetch;
    }
  }

  assert.equal(installations, 1);
  assert.equal(useReactNativeFetchDuringInstallation, '1');
});

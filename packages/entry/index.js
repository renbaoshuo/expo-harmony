'use strict';

// Metro selects prelude.harmony.js here. Other platforms use the no-op
// prelude.js so their native Expo Modules installation remains untouched.
require('./prelude');

// @expo-harmony/metro-config resolves this module from the application root.
require('@expo-harmony/entry/app-prelude');

// Keep this last: application polyfills must be installed before Expo Router
// (and therefore @expo/metro-runtime and Expo.fx) starts evaluating.
require('expo-router/entry');

'use strict';

// RNOH already provides React Native's Networking module, while Expo's native
// fetch module is not available on HarmonyOS.
process.env.EXPO_PUBLIC_USE_RN_FETCH = '1';

// Install Expo's global polyfill for HarmonyOS, which is required for some Expo modules to work correctly.
const { installExpoGlobalPolyfill } = require('expo-modules-core/src/polyfill/dangerous-internal');
installExpoGlobalPolyfill();

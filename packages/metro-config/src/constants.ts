/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export const HarmonyPlatform = 'harmony';
export const DefaultReactNativeHarmonyPackage = '@react-native-oh/react-native-harmony';
export const HarmonyScreensPackage = '@react-native-ohos/react-native-screens';
export const HarmonyPlatformExtensions = ['harmony', 'native'] as const;
// Use \x2f for slash so Metro can combine this pattern with Unicode sets (/v).
export const HarmonyBuildArtifacts = /(?:^|[\\\x2f])harmony[\\\x2f](?:[^\\\x2f]+[\\\x2f])*(?:build|oh_modules|\.hvigor|\.cxx)(?:[\\\x2f]|$)/;

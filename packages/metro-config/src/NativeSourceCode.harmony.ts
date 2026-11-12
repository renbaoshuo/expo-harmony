/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

// @ts-expect-error React Native's private SourceCode wrapper has no declarations.
import native from 'react-native/Libraries/NativeModules/specs/NativeSourceCode';

interface SourceCodeConstants {
  scriptURL: string | null;
}
const runtime = globalThis as typeof globalThis & {
  __RNOH_EXECUTING_MODULE_BUNDLE_URL__?: string;
  __RNOH_CURRENT_BUNDLE_URL__?: string;
};
const HttpBundleUrl = /^https?:\/\/[^\s/?#]+\//;
let fallback: SourceCodeConstants | undefined;

function isHttpBundleUrl(value: string | null | undefined): value is string {
  return typeof value === 'string' && HttpBundleUrl.test(value);
}

export default {
  ...native,
  getConstants(): SourceCodeConstants {
    const constants = native.getConstants() as SourceCodeConstants;
    if (isHttpBundleUrl(constants.scriptURL)) return constants;
    if (fallback) return fallback;

    // SourceCode's worker constants can be read before RNOH publishes the initial
    // bundle URL. The resource-context prelude sets these globals before evaluation.
    const scriptURL = [
      runtime.__RNOH_EXECUTING_MODULE_BUNDLE_URL__,
      runtime.__RNOH_CURRENT_BUNDLE_URL__,
    ].find(isHttpBundleUrl);
    if (!scriptURL) return constants;

    fallback = { ...constants, scriptURL };
    return fallback;
  },
};

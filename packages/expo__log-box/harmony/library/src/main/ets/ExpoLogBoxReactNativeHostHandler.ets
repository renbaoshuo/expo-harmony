/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import type { ReactNativeHostHandler } from '@expo-harmony/expo-modules-core';

import { expoLogBoxController } from './ExpoLogBoxController';

const WEBVIEW_CAPABILITY: string = 'SystemCapability.Web.Webview.Core';
const ENABLED_METADATA: string = 'expo.logBox.enabled';

export class ExpoLogBoxReactNativeHostHandler implements ReactNativeHostHandler {
  constructor(_context: common.Context) {}

  onWillCreateReactInstance(debug: boolean): void {
    expoLogBoxController.setEnabled(debug && canIUse(WEBVIEW_CAPABILITY) && isEnabledInManifest());
  }
}

function isEnabledInManifest(): boolean {
  try {
    const info = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION |
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE |
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_METADATA,
    );

    return info.appInfo.debug && info.hapModulesInfo.some((module): boolean =>
      module.metadata?.some((entry): boolean => entry.name === ENABLED_METADATA && entry.value === 'true') === true,
    );
  } catch (error) {
    console.warn(`Expo LogBox could not read its manifest setting: ${String(error)}`);
    return false;
  }
}

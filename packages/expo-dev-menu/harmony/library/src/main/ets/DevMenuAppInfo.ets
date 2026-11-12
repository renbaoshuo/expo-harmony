/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { bundleManager } from '@kit.AbilityKit';
import { DrawableDescriptor } from '@kit.ArkUI';
import { RNOHCoreContext } from '@rnoh/react-native-openharmony';

export interface DevMenuAppInfoProvider {
  getDevMenuAppInfo(): DevMenuAppMetadata;
}

export class DevMenuAppMetadata {
  appName?: string;
  appVersion?: string;
  runtimeVersion?: string;
  sdkVersion?: string;
  localBundlePath?: string;
  engine?: string;
}

export class DevMenuAppInfo extends DevMenuAppMetadata {
  hostUrl: string = '';
  icon?: DrawableDescriptor;

  serialize(): string {
    const result: Record<string, ESObject> = {};
    result.appName = this.appName ?? null;
    result.appVersion = this.appVersion ?? null;
    result.runtimeVersion = this.runtimeVersion ?? null;
    result.sdkVersion = this.sdkVersion ?? null;
    result.hostUrl = this.hostUrl;
    result.engine = this.engine ?? null;

    return JSON.stringify(result, null, 2);
  }
}

export function readDevMenuAppInfo(core: RNOHCoreContext, bundleUrl: string, provider?: DevMenuAppInfoProvider): DevMenuAppInfo {
  const result = new DevMenuAppInfo();
  result.hostUrl = bundleUrl;

  try {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    result.appName = info.name;
    result.appVersion = info.versionName;
    if (info.appInfo.labelId > 0) {
      try {
        result.appName = core.uiAbilityContext.resourceManager.getStringSync(info.appInfo.labelId);
      } catch (error) {
        core.logger.warn(`Unable to resolve Dev Menu app label: ${String(error)}`);
      }
    }
    if (info.appInfo.iconId > 0) {
      try {
        result.icon = core.uiAbilityContext.resourceManager.getDrawableDescriptor(info.appInfo.iconId);
      } catch (error) {
        core.logger.warn(`Unable to resolve Dev Menu app icon: ${String(error)}`);
      }
    }
  } catch (error) {
    core.logger.warn(`Unable to read Dev Menu native app metadata: ${String(error)}`);
  }
  if (provider !== undefined) {
    try {
      const metadata = provider.getDevMenuAppInfo();
      result.appName = metadata.appName ?? result.appName;
      result.appVersion = metadata.appVersion ?? result.appVersion;
      result.runtimeVersion = metadata.runtimeVersion;
      result.sdkVersion = metadata.sdkVersion;
      result.localBundlePath = metadata.localBundlePath;
      result.engine = metadata.engine;
    } catch (error) {
      core.logger.warn(`Unable to resolve Dev Menu host app metadata: ${String(error)}`);
    }
  }

  return result;
}

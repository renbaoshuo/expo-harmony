/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { EmbeddedManifest, ExpoUpdatesManifest, Manifest } from '@expo-harmony/expo-manifests';

export function readManifest(input: string, method: string, pluginName: string): string {
  const manifest = Manifest.fromManifestJson(JSON.parse(input));

  switch (method) {
    case 'fromManifestJson': return JSON.stringify(manifest instanceof EmbeddedManifest ? 'EmbeddedManifest' : 'ExpoUpdatesManifest');
    case 'getRawJson': return JSON.stringify(manifest.getRawJson());
    case 'toString': return JSON.stringify(manifest.toString());
    case 'getID': return JSON.stringify(manifest.getID());
    case 'getLegacyID': return JSON.stringify(manifest.getLegacyID());
    case 'getStableLegacyID': return JSON.stringify(manifest.getStableLegacyID());
    case 'getMetadata': return JSON.stringify(manifest.getMetadata());
    case 'getAssets': return JSON.stringify(manifest.getAssets());
    case 'isVerified': return JSON.stringify(manifest.isVerified());
    case 'getScopeKey': return JSON.stringify(manifest.getScopeKey());
    case 'getEASProjectID': return JSON.stringify(manifest.getEASProjectID());
    case 'getBundleURL': return JSON.stringify(manifest.getBundleURL());
    case 'getCommitTimeLong': return JSON.stringify(manifest instanceof EmbeddedManifest ? manifest.getCommitTimeLong() : null);
    case 'getRuntimeVersion': return JSON.stringify(manifest instanceof ExpoUpdatesManifest ? manifest.getRuntimeVersion() : null);
    case 'getCreatedAt': return JSON.stringify(manifest instanceof ExpoUpdatesManifest ? manifest.getCreatedAt() : null);
    case 'getLaunchAsset': return JSON.stringify(manifest instanceof ExpoUpdatesManifest ? manifest.getLaunchAsset() : null);
    case 'getExpoGoSDKVersion': return JSON.stringify(manifest.getExpoGoSDKVersion());
    case 'getExpoGoConfigRootObject': return JSON.stringify(manifest.getExpoGoConfigRootObject());
    case 'isDevelopmentMode': return JSON.stringify(manifest.isDevelopmentMode());
    case 'isDevelopmentSilentLaunch': return JSON.stringify(manifest.isDevelopmentSilentLaunch());
    case 'isUsingDeveloperTool': return JSON.stringify(manifest.isUsingDeveloperTool());
    case 'getDebuggerHost': return JSON.stringify(manifest.getDebuggerHost());
    case 'getMainModuleName': return JSON.stringify(manifest.getMainModuleName());
    case 'getExpoGoUsername': return JSON.stringify(manifest.getExpoGoUsername());
    case 'getExpoClientConfigRootObject': return JSON.stringify(manifest.getExpoClientConfigRootObject());
    case 'getSlug': return JSON.stringify(manifest.getSlug());
    case 'getAppKey': return JSON.stringify(manifest.getAppKey());
    case 'getRevisionId': return JSON.stringify(manifest.getRevisionId());
    case 'getHostUri': return JSON.stringify(manifest.getHostUri());
    case 'getName': return JSON.stringify(manifest.getName());
    case 'getVersion': return JSON.stringify(manifest.getVersion());
    case 'getUpdatesInfo': return JSON.stringify(manifest.getUpdatesInfo());
    case 'getPrimaryColor': return JSON.stringify(manifest.getPrimaryColor());
    case 'getOrientation': return JSON.stringify(manifest.getOrientation());
    case 'getIconUrl': return JSON.stringify(manifest.getIconUrl());
    case 'getFacebookAppId': return JSON.stringify(manifest.getFacebookAppId());
    case 'getFacebookApplicationName': return JSON.stringify(manifest.getFacebookApplicationName());
    case 'getFacebookAutoInitEnabled': return JSON.stringify(manifest.getFacebookAutoInitEnabled());
    case 'getPlatformConfig': return JSON.stringify(manifest.getPlatformConfig());
    case 'getUserInterfaceStyle': return JSON.stringify(manifest.getUserInterfaceStyle());
    case 'getBackgroundColor': return JSON.stringify(manifest.getBackgroundColor());
    case 'getPluginProperties': return JSON.stringify(manifest.getPluginProperties(pluginName));
    default: throw new Error(`Unknown manifest method: ${method}`);
  }
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import Constants from 'expo-constants';

import { DataRow, Panel } from '../ui';
import { SystemApiActions } from './system-api-actions';

type HarmonyConstants = {
  apiVersion?: number;
  bundleName?: string;
  deviceType?: string;
  osFullName?: string;
  versionCode?: number;
  versionName?: string;
};

export function ConstantsDemo() {
  const harmony = (Constants.platform as { harmony?: HarmonyConstants } | undefined)?.harmony;

  return (
    <>
      <Panel title="运行环境">
        <DataRow label="executionEnvironment" value={Constants.executionEnvironment} />
        <DataRow label="appOwnership" value={String(Constants.appOwnership)} />
        <DataRow label="sessionId" value={Constants.sessionId} />
        <DataRow label="deviceName" value={String(Constants.deviceName)} />
        <DataRow label="deviceYearClass" value={String(Constants.deviceYearClass)} />
        <DataRow label="systemVersion" value={String(Constants.systemVersion)} />
        <DataRow label="statusBarHeight" value={String(Constants.statusBarHeight)} />
        <DataRow label="debugMode" value={String(Constants.debugMode)} />
        <DataRow label="isHeadless" value={String(Constants.isHeadless)} />
        <DataRow label="isDetached" value={String(Constants.isDetached)} />
        <DataRow label="expoRuntimeVersion" value={String(Constants.expoRuntimeVersion)} />
        <DataRow label="expoVersion" value={String(Constants.expoVersion)} />
      </Panel>

      <Panel title="应用链接">
        <DataRow label="experienceUrl" value={String(Constants.experienceUrl)} />
        <DataRow label="linkingUri" value={String(Constants.linkingUri)} />
        <DataRow label="intentUri" value={String(Constants.intentUri)} />
      </Panel>

      <Panel title="应用配置">
        <SystemApiActions
          actions={[
            ['Expo 配置', () => Constants.expoConfig],
            ['Expo Go 配置', () => Constants.expoGoConfig],
            ['EAS 配置', () => Constants.easConfig],
            ['平台清单', () => Constants.platform ?? null],
            ['内嵌清单', () => Constants.manifest],
            ['更新清单', () => Constants.manifest2],
          ]}
        />
      </Panel>

      {harmony
        ? (
            <Panel title="HarmonyOS 应用信息">
              <DataRow label="bundleName" value={String(harmony.bundleName)} />
              <DataRow label="versionName" value={String(harmony.versionName)} />
              <DataRow label="versionCode" value={String(harmony.versionCode)} />
              <DataRow label="deviceType" value={String(harmony.deviceType)} />
              <DataRow label="apiVersion" value={String(harmony.apiVersion)} />
              <DataRow label="osFullName" value={String(harmony.osFullName)} />
            </Panel>
          )
        : null}

      <Panel title="系统字体与 WebView">
        <SystemApiActions
          actions={[
            ['列出系统字体', () => Constants.systemFonts],
            ['读取 User Agent', () => Constants.getWebViewUserAgentAsync()],
          ]}
        />
      </Panel>
    </>
  );
}

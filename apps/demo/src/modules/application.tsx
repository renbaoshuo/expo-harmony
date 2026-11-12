/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Application from 'expo-application';
import { Platform } from 'react-native';

import { DataRow, Panel } from '../ui';
import { SystemApiActions } from './system-api-actions';

const harmony = String(Platform.OS) === 'harmony';

export function ApplicationDemo() {
  return (
    <>
      <Panel title="应用信息">
        <DataRow label="applicationId" value={String(Application.applicationId)} />
        <DataRow label="applicationName" value={String(Application.applicationName)} />
        <DataRow label="nativeApplicationVersion" value={String(Application.nativeApplicationVersion)} />
        <DataRow label="nativeBuildVersion" value={String(Application.nativeBuildVersion)} />
      </Panel>

      {Platform.OS !== 'web'
        ? (
            <Panel title="安装记录">
              <SystemApiActions
                actions={[
                  ['读取首次安装时间', Application.getInstallationTimeAsync],
                  ...(harmony || Platform.OS === 'android'
                    ? [['读取最后更新时间', Application.getLastUpdateTimeAsync] as const]
                    : []),
                ]}
              />
            </Panel>
          )
        : null}

      {Platform.OS === 'android'
        ? (
            <Panel title="Android 应用信息">
              <SystemApiActions
                actions={[
                  ['读取 Android ID', Application.getAndroidId],
                  ['读取安装来源', Application.getInstallReferrerAsync],
                ]}
              />
            </Panel>
          )
        : null}

      {Platform.OS === 'ios'
        ? (
            <Panel title="iOS 应用信息">
              <SystemApiActions
                actions={[
                  ['读取供应商标识符', Application.getIosIdForVendorAsync],
                  ['读取应用分发类型', Application.getIosApplicationReleaseTypeAsync],
                  ['读取推送服务环境', Application.getIosPushNotificationServiceEnvironmentAsync],
                ]}
              />
            </Panel>
          )
        : null}
    </>
  );
}

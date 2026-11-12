/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Device from 'expo-device';
import { useState } from 'react';
import { Platform } from 'react-native';

import { DataRow, Field, Panel } from '../ui';
import { SystemApiActions } from './system-api-actions';

const harmony = String(Platform.OS) === 'harmony';

export function DeviceDemo() {
  const [feature, setFeature] = useState('android.hardware.camera');

  return (
    <>
      <Panel title="设备信息">
        <DataRow label="isDevice" value={String(Device.isDevice)} />
        <DataRow label="brand" value={String(Device.brand)} />
        <DataRow label="manufacturer" value={String(Device.manufacturer)} />
        <DataRow label="modelId" value={String(Device.modelId)} />
        <DataRow label="modelName" value={String(Device.modelName)} />
        <DataRow label="designName" value={String(Device.designName)} />
        <DataRow label="productName" value={String(Device.productName)} />
        <DataRow label="deviceType" value={String(Device.deviceType)} />
        <DataRow label="deviceName" value={String(Device.deviceName)} />
        <DataRow label="deviceYearClass" value={String(Device.deviceYearClass)} />
        <DataRow label="totalMemory（字节）" value={String(Device.totalMemory)} />
        <DataRow label="supportedCpuArchitectures" value={Device.supportedCpuArchitectures?.join(', ') ?? 'null'} />
      </Panel>

      <Panel title="系统版本">
        <DataRow label="osName" value={String(Device.osName)} />
        <DataRow label="osVersion" value={String(Device.osVersion)} />
        <DataRow label="osBuildId" value={String(Device.osBuildId)} />
        <DataRow label="osInternalBuildId" value={String(Device.osInternalBuildId)} />
        <DataRow label="osBuildFingerprint" value={String(Device.osBuildFingerprint)} />
        <DataRow label="platformApiLevel" value={String(Device.platformApiLevel)} />
      </Panel>

      <Panel title="设备查询">
        <SystemApiActions
          actions={[
            ['读取设备类型', async () => {
              const type = await Device.getDeviceTypeAsync();
              return { type, name: Device.DeviceType[type] };
            }],
            ...(Platform.OS !== 'web'
              ? [['读取开机时长（毫秒）', Device.getUptimeAsync, 'device-uptime'] as const]
              : []),
            ...(Platform.OS === 'android'
              ? [
                  ['读取虚拟机内存上限（字节）', Device.getMaxMemoryAsync] as const,
                  ['查询 Root 状态', Device.isRootedExperimentalAsync] as const,
                  ['查询是否允许侧载', Device.isSideLoadingEnabledAsync] as const,
                ]
              : Platform.OS === 'ios' ? [['查询越狱状态', Device.isRootedExperimentalAsync] as const] : []),
          ]}
        />
      </Panel>

      {harmony || Platform.OS === 'android'
        ? (
            <Panel title="系统功能">
              <Field label="功能名称" onChangeText={setFeature} value={feature} />
              <SystemApiActions
                actions={[
                  ['列出系统功能', Device.getPlatformFeaturesAsync],
                  ['查询指定功能', () => Device.hasPlatformFeatureAsync(feature), undefined, !feature.trim()],
                ]}
              />
            </Panel>
          )
        : null}
    </>
  );
}

import * as Device from 'expo-device';
import { Platform } from 'react-native';

import { ActionButton, DataRow, Note, Panel, ResultPanel, useAsyncResult } from './ui';

const TYPES: Record<Device.DeviceType, string> = {
  [Device.DeviceType.UNKNOWN]: '未知',
  [Device.DeviceType.PHONE]: '手机',
  [Device.DeviceType.TABLET]: '平板',
  [Device.DeviceType.DESKTOP]: '桌面设备',
  [Device.DeviceType.TV]: '电视',
};

export function DeviceDemo() {
  const clock = useAsyncResult();
  const constants = useAsyncResult();
  const platform = useAsyncResult();
  const busy = [clock, constants, platform].some(result => result.state.phase === 'running');
  const harmony = (Platform.OS as string) === 'harmony';

  const inspect = () => clock.run(async () => {
    const before = await Device.getUptimeAsync();
    const [type, uptime] = await Promise.all([Device.getDeviceTypeAsync(), Device.getUptimeAsync()]);

    if (!Number.isFinite(before) || before < 0 || !Number.isFinite(uptime) || uptime < before) {
      throw new Error(`开机时长不是非负递增的毫秒值：${before} → ${uptime}`);
    }
    if (!Object.prototype.hasOwnProperty.call(TYPES, type) || type !== Device.deviceType) {
      throw new Error(`设备类型与常量不一致：${type} / ${Device.deviceType}`);
    }

    return `设备类型：${TYPES[type]} (${type})\n开机时长：${uptime} ms\n两次读取间隔：${uptime - before} ms\n枚举与计时校验通过`;
  });

  const verify = () => constants.run(() => {
    const strings = {
      brand: Device.brand,
      manufacturer: Device.manufacturer,
      modelId: Device.modelId,
      modelName: Device.modelName,
      designName: Device.designName,
      productName: Device.productName,
      osName: Device.osName,
      osVersion: Device.osVersion,
      osBuildId: Device.osBuildId,
      osInternalBuildId: Device.osInternalBuildId,
      osBuildFingerprint: Device.osBuildFingerprint,
      deviceName: Device.deviceName,
    };
    const numbers = {
      deviceYearClass: Device.deviceYearClass,
      totalMemory: Device.totalMemory,
      platformApiLevel: Device.platformApiLevel,
    };
    const abis = Device.supportedCpuArchitectures;

    for (const [name, value] of Object.entries(strings)) {
      if (value !== null && typeof value !== 'string') {
        throw new Error(`${name} 必须是字符串或 null：${String(value)}`);
      }
    }
    for (const [name, value] of Object.entries(numbers)) {
      if (value !== null && (!Number.isSafeInteger(value) || value <= 0)) {
        throw new Error(`${name} 必须是正安全整数或 null：${String(value)}`);
      }
    }
    if (typeof Device.isDevice !== 'boolean') {
      throw new Error('isDevice 必须是布尔值。');
    }
    if (Device.deviceType !== null && !Object.prototype.hasOwnProperty.call(TYPES, Device.deviceType)) {
      throw new Error(`设备类型枚举无效：${Device.deviceType}`);
    }
    if (abis !== null && (!Array.isArray(abis) || abis.length === 0
      || abis.some(abi => typeof abi !== 'string' || !abi.trim()))) {
      throw new Error(`CPU 架构列表无效：${String(abis)}`);
    }

    return JSON.stringify({
      passed: true,
      isDevice: Device.isDevice,
      deviceType: Device.deviceType,
      supportedCpuArchitectures: abis,
      ...strings,
      ...numbers,
    }, null, 2);
  });

  const verifyPlatform = () => platform.run(async () => {
    const methods = {
      getMaxMemoryAsync: Device.getMaxMemoryAsync,
      isRootedExperimentalAsync: Device.isRootedExperimentalAsync,
      isSideLoadingEnabledAsync: Device.isSideLoadingEnabledAsync,
    };
    const names = Object.keys(methods);
    const results = await Promise.allSettled(Object.values(methods).map(method => method()));
    const [features, camera] = await Promise.all([
      Device.getPlatformFeaturesAsync(),
      Device.hasPlatformFeatureAsync('android.hardware.camera'),
    ]);
    const missing = [Device.modelId, Device.designName, Device.productName, Device.deviceYearClass,
      Device.deviceName, Device.osInternalBuildId, Device.osBuildFingerprint, Device.platformApiLevel];

    for (const [index, result] of results.entries()) {
      if (result.status !== 'rejected' || !(result.reason instanceof Error)
        || !('code' in result.reason) || result.reason.code !== 'ERR_UNAVAILABLE') {
        throw new Error(`${names[index]} 未按预期抛出 ERR_UNAVAILABLE。`);
      }
    }
    if (!Array.isArray(features) || features.length !== 0 || camera !== false) {
      throw new Error('平台特性接口没有返回 [] / false。');
    }
    if (!Device.isDevice || missing.some(value => value !== null)) {
      throw new Error('HarmonyOS 的模拟器标志或不支持字段与约定不符。');
    }

    return `${names.join('、')}：ERR_UNAVAILABLE\n平台特性：[] / false\n不支持字段：null\nisDevice：true（模拟器也如此）\n平台行为校验通过`;
  });

  return (
    <>
      <Panel eyebrow="设备信息" title="系统报告的硬件常量">
        <DataRow label="品牌 / 制造商" value={`${Device.brand} / ${Device.manufacturer}`} />
        <DataRow label="型号" value={String(Device.modelName)} />
        <DataRow label="设备名称" value={String(Device.deviceName)} />
        <DataRow label="设备类型" value={Device.deviceType === null ? 'null' : `${TYPES[Device.deviceType]} (${Device.deviceType})`} />
        <DataRow label="isDevice" value={String(Device.isDevice)} />
        <DataRow label="总内存（字节）" value={String(Device.totalMemory)} />
        <DataRow label="CPU 架构" value={Device.supportedCpuArchitectures?.join(', ') ?? 'null'} />
        <ActionButton disabled={busy} label="校验全部常量" onPress={() => void verify()} testID="device-constants" />
        <ResultPanel state={constants.state} />
      </Panel>

      <Panel eyebrow="系统信息" title="系统版本与运行时钟">
        <DataRow label="系统名称" value={String(Device.osName)} />
        <DataRow label="系统版本" value={String(Device.osVersion)} />
        <DataRow label="显示构建版本" value={String(Device.osBuildId)} />
        <Note>开机时长以毫秒返回，不包含深度休眠；连续读取应保持不减。设备类型应与常量一致。</Note>
        <ActionButton disabled={busy || Platform.OS === 'web'} label="读取类型与开机时长" onPress={() => void inspect()} testID="device-uptime" />
        <ResultPanel state={clock.state} />
      </Panel>

      <Panel eyebrow="平台行为" title="验证 HarmonyOS 的接口限制">
        <Note>模拟器上 isDevice 也为 true。用户设备名称、设备年份和平台专属字段可能为 null；Java VM 内存上限、root 与侧载查询不支持。</Note>
        <ActionButton disabled={busy || !harmony} label="校验平台限制" onPress={() => void verifyPlatform()} testID="device-platform" />
        <ResultPanel state={platform.state} />
      </Panel>
    </>
  );
}

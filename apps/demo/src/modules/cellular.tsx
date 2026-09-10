import * as Cellular from 'expo-cellular';
import { useState } from 'react';
import { Platform } from 'react-native';

import { ActionButton, ActionRow, DataRow, Note, Panel, ResultPanel, useAsyncResult } from '../ui';

const GENERATIONS: Record<Cellular.CellularGeneration, string> = {
  [Cellular.CellularGeneration.UNKNOWN]: '未知',
  [Cellular.CellularGeneration.CELLULAR_2G]: '2G',
  [Cellular.CellularGeneration.CELLULAR_3G]: '3G',
  [Cellular.CellularGeneration.CELLULAR_4G]: '4G',
  [Cellular.CellularGeneration.CELLULAR_5G]: '5G',
};

async function read() {
  const [generation, country, carrier, mcc, mnc, voip] = await Promise.all([
    Cellular.getCellularGenerationAsync(),
    Cellular.getIsoCountryCodeAsync(),
    Cellular.getCarrierNameAsync(),
    Cellular.getMobileCountryCodeAsync(),
    Cellular.getMobileNetworkCodeAsync(),
    Cellular.allowsVoipAsync(),
  ]);

  return { generation, country, carrier, mcc, mnc, voip };
}

export function CellularDemo() {
  const [permission, request, get] = Cellular.usePermissions();
  const [info, setInfo] = useState<Awaited<ReturnType<typeof read>>>();
  const action = useAsyncResult();
  const access = useAsyncResult();
  const checks = useAsyncResult();
  const busy = action.state.phase === 'running' || access.state.phase === 'running' || checks.state.phase === 'running';

  const inspect = () => action.run(async () => {
    const value = await read();
    setInfo(value);

    return JSON.stringify(value, null, 2);
  });

  const verify = () => checks.run(async () => {
    const [value, current, requested] = await Promise.all([
      read(),
      Cellular.getPermissionsAsync(),
      Cellular.requestPermissionsAsync(),
    ]);
    setInfo(value);

    if (typeof value.generation !== 'number' || !Object.prototype.hasOwnProperty.call(GENERATIONS, value.generation)) {
      throw new Error(`未知的蜂窝代际枚举：${value.generation}`);
    }
    if (value.country !== null && (typeof value.country !== 'string' || !/^[a-z]{2}$/.test(value.country))) {
      throw new Error(`ISO 国家码格式不正确：${value.country}`);
    }
    if (value.carrier !== null && typeof value.carrier !== 'string') {
      throw new Error('服务商名称必须为字符串或 null。');
    }
    if (value.mcc !== null && (typeof value.mcc !== 'string' || !/^\d{3}$/.test(value.mcc))) {
      throw new Error(`MCC 格式不正确：${value.mcc}`);
    }
    if (value.mnc !== null && (typeof value.mnc !== 'string' || !/^\d{2,3}$/.test(value.mnc))) {
      throw new Error(`MNC 格式不正确：${value.mnc}`);
    }
    if (value.voip !== null && typeof value.voip !== 'boolean') {
      throw new Error('VoIP 查询必须返回布尔值或 null。');
    }
    if (Platform.OS !== 'android' && value.voip !== null) {
      throw new Error('非 Android 平台的 VoIP 查询应返回 null。');
    }

    for (const result of [current, requested]) {
      if (Platform.OS !== 'android' && (!result.granted || result.status !== 'granted' || result.expires !== 'never' || !result.canAskAgain)) {
        throw new Error('非 Android 平台权限结果与官方 JS 默认值不一致。');
      }
    }

    return JSON.stringify({ passed: true, info: value, permissions: { current, requested } }, null, 2);
  });

  return (
    <>
      <Panel eyebrow="蜂窝信息" title="读取网络代际与 SIM 信息">
        <DataRow label="网络代际" value={info ? `${GENERATIONS[info.generation]} (${info.generation})` : '尚未读取'} />
        <DataRow label="ISO 国家码" value={info ? String(info.country) : '尚未读取'} />
        <DataRow label="服务商" value={info ? String(info.carrier) : '尚未读取'} />
        <DataRow label="MCC" value={info ? String(info.mcc) : '尚未读取'} />
        <DataRow label="MNC" value={info ? String(info.mnc) : '尚未读取'} />
        <DataRow label="VoIP 能力" value={info ? String(info.voip) : '尚未读取'} />
        <ActionButton disabled={busy} label="读取蜂窝信息" onPress={() => void inspect()} testID="cellular-read" />
        <ResultPanel state={action.state} />
      </Panel>

      <Panel eyebrow="权限" title="检查与请求电话状态权限">
        <DataRow label="usePermissions 状态" value={permission?.status ?? '加载中'} />
        <DataRow label="已授权" value={permission ? String(permission.granted) : '加载中'} />
        <DataRow label="可再次询问" value={permission ? String(permission.canAskAgain) : '加载中'} />
        <ActionRow>
          <ActionButton disabled={busy} label="检查权限" onPress={() => void access.run(async () => JSON.stringify(await get(), null, 2))} testID="cellular-permissions-get" />
          <ActionButton disabled={busy} label="请求权限" onPress={() => void access.run(async () => JSON.stringify(await request(), null, 2))} testID="cellular-permissions-request" tone="secondary" />
        </ActionRow>
        <ResultPanel state={access.state} />
      </Panel>

      <Panel eyebrow="接口校验" title="验证枚举、空值和权限结果">
        <Note>模拟器可能没有 SIM 或蜂窝服务，UNKNOWN 和 null 都是有效结果。真实运营商、双卡切换和漫游需要在插卡设备上验证。</Note>
        <ActionButton disabled={busy} label="校验接口返回值" onPress={() => void verify()} testID="cellular-verify" />
        <ResultPanel state={checks.state} />
      </Panel>

      <Panel eyebrow="平台行为" title="理解查询结果">
        <Note>HarmonyOS 直接使用官方 JS 的非 Android 权限结果，不弹出授权框；VoIP 查询返回 null。双卡设备上的国家码、服务商名称和 MCC/MNC 可能来自不同的系统默认订阅。</Note>
      </Panel>
    </>
  );
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Network from 'expo-network';
import { Platform } from 'react-native';

import { DataRow, Panel } from '../ui';
import { SystemApiActions, SystemEvent } from './system-api-actions';

const hasAirplaneMode = String(Platform.OS) === 'harmony' || Platform.OS === 'android';

export function NetworkDemo() {
  const state = Network.useNetworkState();

  return (
    <>
      <Panel title="网络查询">
        <SystemApiActions
          actions={[
            ['读取网络状态', Network.getNetworkStateAsync, 'network-read-state'],
            [Platform.OS === 'web' ? '读取公网 IP 地址' : '读取 IP 地址', Network.getIpAddressAsync],
            ...(hasAirplaneMode ? [['查询飞行模式', Network.isAirplaneModeEnabledAsync] as const] : []),
          ]}
        />
      </Panel>

      <Panel title="useNetworkState">
        <DataRow label="连接类型" value={state.type ?? '未读取'} />
        <DataRow label="已连接" value={String(state.isConnected ?? '未读取')} />
        <DataRow label="互联网可达" value={String(state.isInternetReachable ?? '未读取')} />
      </Panel>

      <Panel title="网络事件">
        <SystemEvent label="网络状态变化" subscribe={Network.addNetworkStateListener} />
      </Panel>
    </>
  );
}

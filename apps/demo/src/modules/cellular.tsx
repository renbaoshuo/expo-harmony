/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Cellular from 'expo-cellular';
import { useState } from 'react';
import { Switch } from 'react-native';

import { DataRow, Panel } from '../ui';
import { SystemApiActions } from './system-api-actions';

export function CellularDemo() {
  const [get, setGet] = useState(true);
  const [request, setRequest] = useState(false);
  const [permission, ask, read] = Cellular.usePermissions({ get, request });

  return (
    <>
      <Panel title="蜂窝网络">
        <SystemApiActions
          actions={[
            ['读取网络代际', async () => {
              const generation = await Cellular.getCellularGenerationAsync();
              return { generation, name: Cellular.CellularGeneration[generation] };
            }, 'cellular-read'],
            ['读取 ISO 国家码', Cellular.getIsoCountryCodeAsync],
            ['读取运营商名称', Cellular.getCarrierNameAsync],
            ['读取移动国家码（MCC）', Cellular.getMobileCountryCodeAsync],
            ['读取移动网络码（MNC）', Cellular.getMobileNetworkCodeAsync],
            ['查询 VoIP 支持', Cellular.allowsVoipAsync],
          ]}
        />
      </Panel>

      <Panel title="电话状态权限">
        <SystemApiActions
          actions={[
            ['查询权限', Cellular.getPermissionsAsync, 'cellular-permissions-get'],
            ['请求权限', Cellular.requestPermissionsAsync, 'cellular-permissions-request'],
          ]}
        />
      </Panel>

      <Panel title="usePermissions">
        <DataRow label="自动查询权限" value={<Switch accessibilityLabel="自动查询权限" onValueChange={setGet} value={get} />} />
        <DataRow label="自动请求权限" value={<Switch accessibilityLabel="自动请求权限" onValueChange={setRequest} value={request} />} />
        <DataRow label="当前权限" value={permission?.status ?? '未读取'} />
        <SystemApiActions
          actions={[
            ['刷新权限', read],
            ['请求权限', ask],
          ]}
        />
      </Panel>
    </>
  );
}

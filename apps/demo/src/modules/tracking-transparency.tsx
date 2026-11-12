/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Tracking from 'expo-tracking-transparency';
import { useState } from 'react';
import { Alert, Platform, Switch } from 'react-native';

import { json } from '../format';
import { ActionButton, DataRow, Panel, ResultPanel, useAsyncResult } from '../ui';
import { SystemApiActions } from './system-api-actions';

const harmony = String(Platform.OS) === 'harmony';

export function TrackingTransparencyDemo() {
  const [get, setGet] = useState(false);
  const [request, setRequest] = useState(false);
  const [permission, ask, read] = Tracking.useTrackingPermissions({ get, request });
  const identifier = useAsyncResult();

  const readIdentifier = () => identifier.run(async () => {
    if (harmony) {
      const module = await import('@expo-harmony/expo-tracking-transparency');
      return json(await module.getAdvertisingIdAsync());
    }

    return json(Tracking.getAdvertisingId());
  });

  const requestIdentifier = () => {
    if (harmony) {
      Alert.alert('读取广告标识', '本页会读取并显示 OAID。', [
        { text: '取消', style: 'cancel' },
        { text: '同意并读取', onPress: () => void readIdentifier() },
      ]);
    } else {
      void readIdentifier();
    }
  };

  return (
    <>
      <Panel title="跟踪权限">
        <DataRow label="isAvailable" value={String(Tracking.isAvailable())} />
        <SystemApiActions
          actions={[
            ['查询跟踪权限', Tracking.getTrackingPermissionsAsync, 'tracking-query'],
            ['请求跟踪权限', Tracking.requestTrackingPermissionsAsync, 'tracking-request'],
          ]}
        />
      </Panel>

      <Panel title="useTrackingPermissions">
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

      <Panel title="广告标识">
        <ActionButton disabled={identifier.state.phase === 'running'} label="读取广告标识" onPress={requestIdentifier} testID="tracking-read" />
        <ResultPanel state={identifier.state} />
      </Panel>
    </>
  );
}

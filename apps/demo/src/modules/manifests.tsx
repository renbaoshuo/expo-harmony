/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { useState } from 'react';
import { json } from '../format';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { runtimeDemo } from './runtime-demo';

const embedded = {
  id: '6b91b9ac-5e23-4a35-a69c-b92818c32eef',
  commitTime: 1750000000000,
  bundleUrl: 'file:///demo/hermes_bundle.hbc',
  name: 'Embedded demo',
  version: '1.0.0',
  slug: 'demo',
  projectId: 'demo',
  sdkVersion: '57.0.0',
  appKey: 'main',
  revisionId: 'demo.1',
  hostUri: 'localhost:8088',
  debuggerHost: 'localhost:8088',
  mainModuleName: 'index',
  developer: { tool: 'expo-cli' },
  packagerOpts: { dev: true },
  developmentClient: { silentLaunch: false },
  isVerified: true,
  assets: [],
  updates: { enabled: true },
  harmony: { backgroundColor: '#F2F2F7', userInterfaceStyle: 'light' },
  plugins: [['expo-splash-screen', { backgroundColor: '#F2F2F7' }]],
};
const remote = {
  id: '57a94ee9-ff97-4be5-9313-77cbf9349fba',
  createdAt: '2025-06-15T15:06:40.000Z',
  runtimeVersion: 'demo-runtime',
  metadata: {},
  launchAsset: { url: 'https://example.com/update.hbc' },
  extra: { scopeKey: 'demo', expoClient: { name: 'Remote demo' } },
};

const groups = {
  '清单与资源': [
    'fromManifestJson',
    'getRawJson',
    'toString',
    'getID',
    'getLegacyID',
    'getStableLegacyID',
    'getMetadata',
    'getAssets',
    'isVerified',
    'getScopeKey',
    'getEASProjectID',
    'getBundleURL',
    'getCommitTimeLong',
    'getRuntimeVersion',
    'getCreatedAt',
    'getLaunchAsset',
  ],
  'Expo Go 配置': [
    'getExpoGoSDKVersion',
    'getExpoGoConfigRootObject',
    'isDevelopmentMode',
    'isDevelopmentSilentLaunch',
    'isUsingDeveloperTool',
    'getDebuggerHost',
    'getMainModuleName',
    'getExpoGoUsername',
  ],
  '应用配置': [
    'getExpoClientConfigRootObject',
    'getSlug',
    'getAppKey',
    'getRevisionId',
    'getHostUri',
    'getName',
    'getVersion',
    'getUpdatesInfo',
    'getPrimaryColor',
    'getOrientation',
    'getIconUrl',
    'getFacebookAppId',
    'getFacebookApplicationName',
    'getFacebookAutoInitEnabled',
    'getPlatformConfig',
    'getUserInterfaceStyle',
    'getBackgroundColor',
    'getPluginProperties',
  ],
};

export function ManifestsDemo() {
  const result = useAsyncResult();
  const [input, setInput] = useState(json(embedded));
  const [group, setGroup] = useState<keyof typeof groups>('清单与资源');
  const [plugin, setPlugin] = useState('expo-splash-screen');

  if (!runtimeDemo) return <Panel title="此示例需要 HarmonyOS 原生模块" />;

  return (
    <Panel title="Manifest">
      <ActionRow>
        <ActionButton
          label="内置清单"
          onPress={() => {
            setInput(json(embedded));
            result.clear();
          }}
          tone="secondary"
        />
        <ActionButton
          label="远程清单"
          onPress={() => {
            setInput(json(remote));
            result.clear();
          }}
          tone="secondary"
        />
      </ActionRow>
      <Field label="清单（JSON 对象）" multiline onChangeText={setInput} value={input} />
      <ActionRow>
        {(Object.keys(groups) as (keyof typeof groups)[]).map(value => (
          <ActionButton
            key={value}
            label={value}
            onPress={() => {
              setGroup(value);
              result.clear();
            }}
            tone={group === value ? 'primary' : 'secondary'}
          />
        ))}
      </ActionRow>
      {group === '应用配置' ? <Field label="插件名称" value={plugin} onChangeText={setPlugin} /> : null}
      <ActionRow>
        {groups[group].map(method => (
          <ActionButton
            key={method}
            label={`${method}()`}
            onPress={() => void result.run(() =>
              json(JSON.parse(runtimeDemo!.readManifest(input, method, plugin))))}
          />
        ))}
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}

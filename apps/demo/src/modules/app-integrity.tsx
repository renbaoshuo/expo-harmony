/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as AppIntegrity from '@expo/app-integrity';
import { randomUUID } from 'expo-crypto';
import { useState } from 'react';
import { Platform } from 'react-native';

import { ActionButton, DataRow, Field, Panel } from '../ui';
import { SystemApiActions } from './system-api-actions';

function HardwareAttestationDemo() {
  const [alias, setAlias] = useState('expo-harmony-demo.app-integrity');
  const [challenge, setChallenge] = useState(() => randomUUID());

  return (
    <Panel title="硬件密钥证明">
      <DataRow label="App Attest 支持" value={String(AppIntegrity.isSupported)} />
      <SystemApiActions
        actions={[
          ['查询硬件证明支持', AppIntegrity.isHardwareAttestationSupportedAsync, 'app-integrity-support'],
        ]}
      />
      <Field label="密钥别名" onChangeText={setAlias} testID="app-integrity-alias" value={alias} />
      <Field label="挑战字符串" onChangeText={setChallenge} testID="app-integrity-challenge" value={challenge} />
      <ActionButton
        label="生成随机挑战字符串"
        onPress={() => setChallenge(randomUUID())}
        testID="app-integrity-challenge-new"
        tone="secondary"
      />
      <SystemApiActions
        actions={[
          ['生成硬件证明密钥', () => AppIntegrity.generateHardwareAttestedKeyAsync(alias, challenge), 'app-integrity-generate'],
          ['读取证书链', () => AppIntegrity.getAttestationCertificateChainAsync(alias), 'app-integrity-read'],
        ]}
      />
    </Panel>
  );
}

function AppleAttestationDemo() {
  const [keyId, setKeyId] = useState('');
  const [challenge, setChallenge] = useState(() => randomUUID());

  return (
    <Panel title="App Attest">
      <DataRow label="isSupported" value={String(AppIntegrity.isSupported)} />
      <Field label="密钥 ID" onChangeText={setKeyId} value={keyId} />
      <Field label="挑战字符串" onChangeText={setChallenge} value={challenge} />
      <SystemApiActions
        actions={[
          ['生成 App Attest 密钥', async () => {
            const id = await AppIntegrity.generateKeyAsync();
            setKeyId(id);
            return id;
          }, undefined, !AppIntegrity.isSupported],
          ['证明密钥', () => AppIntegrity.attestKeyAsync(keyId, challenge), undefined, !AppIntegrity.isSupported || !keyId],
          ['生成断言', () => AppIntegrity.generateAssertionAsync(keyId, challenge), undefined, !AppIntegrity.isSupported || !keyId],
        ]}
      />
    </Panel>
  );
}

function PlayIntegrityDemo() {
  const [project, setProject] = useState('');
  const [hash, setHash] = useState('');

  return (
    <Panel title="Play Integrity">
      <Field keyboardType="number-pad" label="Cloud 项目编号" onChangeText={setProject} value={project} />
      <Field label="请求哈希" onChangeText={setHash} value={hash} />
      <SystemApiActions
        actions={[
          ['准备完整性令牌', () => AppIntegrity.prepareIntegrityTokenProviderAsync(project), undefined, !project.trim()],
          ['请求完整性判定', () => AppIntegrity.requestIntegrityCheckAsync(hash), undefined, !hash.trim()],
        ]}
      />
    </Panel>
  );
}

export function AppIntegrityDemo() {
  if (Platform.OS === 'ios') return <AppleAttestationDemo />;

  return (
    <>
      {String(Platform.OS) === 'harmony' || Platform.OS === 'android' ? <HardwareAttestationDemo /> : null}
      {Platform.OS === 'android' ? <PlayIntegrityDemo /> : null}
    </>
  );
}

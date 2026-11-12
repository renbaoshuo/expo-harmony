/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as AgeRange from 'expo-age-range';
import { useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { Field, Panel } from '../ui';
import { SystemApiActions } from './system-api-actions';

const SAMPLE_SIGNALS: AgeRange.FakeAgeSignals = {
  ageSignalsStatus: 'SHARED',
  lowerBound: 13,
  upperBound: 15,
  installId: 'demo-install',
  ageRangeSource: 'TIER_B',
  significantChangeStatus: 'PENDING',
  significantChangeApprovalDate: null,
};

function AndroidAgeSignalsDemo() {
  const [signals, setSignals] = useState(json(SAMPLE_SIGNALS));
  const [errorCode, setErrorCode] = useState('-1');
  const applied = useRef(false);

  useEffect(() => () => {
    if (applied.current) AgeRange.setFakeAgeSignals(null);
  }, []);

  return (
    <>
      <Panel title="年龄信号授权">
        <SystemApiActions actions={[['请求共享年龄信号', AgeRange.requestAgeSignalsAccessAsync]]} />
      </Panel>
      {__DEV__
        ? (
            <Panel title="模拟年龄信号">
              <Field label="模拟返回值（JSON）" multiline onChangeText={setSignals} value={signals} />
              <Field keyboardType="numbers-and-punctuation" label="模拟错误码" onChangeText={setErrorCode} value={errorCode} />
              <SystemApiActions
                actions={[
                  ['使用模拟信号', () => {
                    AgeRange.setFakeAgeSignals(JSON.parse(signals) as AgeRange.FakeAgeSignals);
                    applied.current = true;
                  }],
                  ['使用模拟错误', () => {
                    const code = Number(errorCode);
                    if (!errorCode.trim() || !Number.isInteger(code)) throw new Error('请输入整数错误码。');
                    AgeRange.setFakeAgeSignals({ errorCode: code });
                    applied.current = true;
                  }],
                  ['恢复系统信号', () => {
                    AgeRange.setFakeAgeSignals(null);
                    applied.current = false;
                  }],
                ]}
              />
            </Panel>
          )
        : null}
    </>
  );
}

export function AgeRangeDemo() {
  const [first, setFirst] = useState('18');
  const [second, setSecond] = useState('');
  const [third, setThird] = useState('');
  const [description, setDescription] = useState('新版增加了消息功能。');
  const [canShowUpdate, setCanShowUpdate] = useState(false);
  const ios = Platform.OS === 'ios';

  return (
    <>
      {Platform.OS === 'android' ? <AndroidAgeSignalsDemo /> : null}
      <Panel title="年龄范围">
        {ios
          ? (
              <>
                <Field keyboardType="number-pad" label="第一个年龄阈值" onChangeText={setFirst} value={first} />
                <Field keyboardType="number-pad" label="第二个年龄阈值（选填）" onChangeText={setSecond} value={second} />
                <Field keyboardType="number-pad" label="第三个年龄阈值（选填）" onChangeText={setThird} value={third} />
              </>
            )
          : null}
        <SystemApiActions
          actions={[
            ['读取年龄范围', () => AgeRange.requestAgeRangeAsync({
              threshold1: ios ? Number(first) : 18,
              ...(ios && second.trim() ? { threshold2: Number(second) } : {}),
              ...(ios && third.trim() ? { threshold3: Number(third) } : {}),
            }), 'age-range-read', ios && !first.trim()],
          ]}
        />
      </Panel>

      {ios
        ? (
            <Panel title="年龄验证与更新确认">
              <SystemApiActions
                actions={[
                  ['查询年龄验证是否适用', AgeRange.isEligibleForAgeFeaturesAsync],
                  ['查询所需的监管功能', async () => {
                    const features = await AgeRange.getRequiredRegulatoryFeaturesAsync();
                    setCanShowUpdate(features?.includes('significantAppChangeRequiresAdultNotification') ?? false);
                    return features;
                  }],
                ]}
              />
              <Field label="更新说明" onChangeText={setDescription} value={description} />
              <SystemApiActions
                actions={[
                  ['显示更新确认', () => AgeRange.showSignificantUpdateAcknowledgmentAsync(description), undefined, !canShowUpdate || !description.trim()],
                ]}
              />
            </Panel>
          )
        : null}
    </>
  );
}

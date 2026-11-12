/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Application from 'expo-application';
import * as IntentLauncher from 'expo-intent-launcher';
import { useState } from 'react';
import { Image, Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const ECHO_ACTION = 'cn.baoshuo.expoharmonydemo.action.ECHO';

export function IntentLauncherDemo() {
  const harmony = String(Platform.OS) === 'harmony';
  const [bundle, setBundle] = useState(Application.applicationId ?? '');
  const [icon, setIcon] = useState('');
  const [action, setAction] = useState(harmony ? ECHO_ACTION : IntentLauncher.ActivityAction.WIRELESS_SETTINGS);
  const [targetPackage, setTargetPackage] = useState(harmony ? Application.applicationId ?? '' : '');
  const [ability, setAbility] = useState(harmony ? 'IntentLauncherAbility' : '');
  const [uri, setUri] = useState(harmony ? 'expoharmonydemo://intent-result/中文' : '');
  const [type, setType] = useState(harmony ? 'text/plain' : '');
  const [category, setCategory] = useState(harmony ? 'cn.baoshuo.expoharmonydemo.entity.TEST' : '');
  const [flags, setFlags] = useState('');
  const [extra, setExtra] = useState(harmony ? '{"message":"你好","count":2}' : '');
  const apps = useAsyncResult();
  const launch = useAsyncResult();
  const busy = apps.state.phase === 'running' || launch.state.phase === 'running';

  const start = () => launch.run(async () => {
    const extraValues: unknown = extra.trim() ? JSON.parse(extra) : undefined;
    if (extraValues !== undefined && (typeof extraValues !== 'object' || extraValues === null || Array.isArray(extraValues))) {
      throw new Error('附加参数需要填写 JSON 对象');
    }

    return json(await IntentLauncher.startActivityAsync(action, {
      packageName: targetPackage || undefined,
      className: ability || undefined,
      data: uri || undefined,
      type: type || undefined,
      category: category || undefined,
      flags: flags.trim() ? Number(flags) : undefined,
      extra: extraValues,
    }));
  });

  return (
    <>
      <Panel title="应用入口">
        <Field label="应用包名" onChangeText={setBundle} testID="intent-bundle" value={bundle} />
        <ActionRow>
          <ActionButton
            disabled={busy || !bundle}
            label="读取应用图标"
            onPress={() => void apps.run(async () => {
              setIcon('');
              const image = await IntentLauncher.getApplicationIconAsync(bundle);
              setIcon(image);
              return image ? '已读取图标' : '没有图标';
            })}
            testID="intent-icon"
          />
          <ActionButton
            disabled={busy || !bundle}
            label="打开应用"
            onPress={() => void apps.run(() => {
              IntentLauncher.openApplication(bundle);
              return '已调用打开应用';
            })}
            testID="intent-open"
            tone="secondary"
          />
        </ActionRow>
        {icon ? <Image accessibilityLabel="应用图标" source={{ uri: icon }} style={{ width: 72, height: 72 }} /> : null}
        <ResultPanel state={apps.state} />
      </Panel>

      <Panel title={harmony ? '启动 UIAbility' : '启动 Activity'}>
        <Field label="Action" onChangeText={setAction} testID="intent-action" value={action} />
        <Field label="目标包名" onChangeText={setTargetPackage} value={targetPackage} />
        <Field label={harmony ? 'Ability 名称' : 'Activity 类名'} onChangeText={setAbility} testID="intent-ability" value={ability} />
        <Field label="数据 URI" onChangeText={setUri} value={uri} />
        <Field label="MIME 类型" onChangeText={setType} value={type} />
        <Field label="Category" onChangeText={setCategory} value={category} />
        <Field label="启动标志位" onChangeText={setFlags} value={flags} />
        <Field label="附加参数（JSON 对象）" multiline onChangeText={setExtra} value={extra} />
        <ActionButton disabled={busy || !action} label="启动并等待结果" testID="intent-start" onPress={() => void start()} />
        <ResultPanel state={launch.state} />
      </Panel>
    </>
  );
}

import * as Application from 'expo-application';
import * as IntentLauncher from 'expo-intent-launcher';
import { useState } from 'react';
import { Image, Platform } from 'react-native';

import { ActionButton, ActionRow, Field, Note, Panel, ResultPanel, useAsyncResult } from './ui';

const ACTION = 'cn.baoshuo.expoharmonydemo.action.ECHO';
const ABILITY = 'IntentLauncherAbility';
const RESULT_OK = 42;
const RESULT_CANCELLED = 0;
const PARAMS = {
  className: ABILITY,
  data: 'expoharmonydemo://intent-result/中文?value=100%25',
  type: 'text/plain',
  category: 'cn.baoshuo.expoharmonydemo.entity.TEST',
  flags: 0,
  extra: { text: 'Hello · 中文', fraction: 3.75, enabled: true, nested: { value: 1.5 }, list: ['a', 'b'] },
};

export function IntentLauncherDemo() {
  const [bundle, setBundle] = useState(Application.applicationId ?? '');
  const [icon, setIcon] = useState('');
  const [action, setAction] = useState(ACTION);
  const [ability, setAbility] = useState(ABILITY);
  const apps = useAsyncResult();
  const launch = useAsyncResult();
  const checks = useAsyncResult();
  const busy = [apps, launch, checks].some(item => item.state.phase === 'running');
  const harmony = String(Platform.OS) === 'harmony';

  const verify = (cancelled = false, concurrent = false) => checks.run(async () => {
    const pending = IntentLauncher.startActivityAsync(ACTION, PARAMS);
    const requests = concurrent
      ? [pending, IntentLauncher.startActivityAsync(ACTION, PARAMS)]
      : [pending];
    const [first, second] = await Promise.allSettled(requests);
    if (first?.status !== 'fulfilled') throw new Error(`启动失败：${String(first?.reason)}`);
    if (concurrent && (second?.status !== 'rejected' || second.reason?.code !== 'E_ACTIVITY_ALREADY_STARTED')) {
      throw new Error('并发启动未返回 E_ACTIVITY_ALREADY_STARTED。');
    }

    const result = first.value;
    if (result.resultCode !== (cancelled ? RESULT_CANCELLED : RESULT_OK)) {
      throw new Error(`结果码不符：${result.resultCode}，请点击目标页面对应的返回按钮。`);
    }
    if (!cancelled) {
      const extra = result.extra as {
        action?: string;
        type?: string;
        entities?: string[];
        received?: typeof PARAMS.extra;
      } | undefined;
      const received = extra?.received;
      if (result.data !== PARAMS.data || extra?.action !== ACTION || extra?.type !== PARAMS.type
        || extra?.entities?.[0] !== PARAMS.category || received?.text !== PARAMS.extra.text
        || received?.fraction !== 3 || received?.enabled !== true || received?.nested?.value !== 1.5
        || JSON.stringify(received?.list) !== JSON.stringify(PARAMS.extra.list)) {
        throw new Error(`Want 参数或结果回传不符：${JSON.stringify(result)}`);
      }
    }

    return `${cancelled ? '取消结果' : 'URI、MIME、category、extra 和数值转换'}：通过${concurrent ? '\n并发启动正确拒绝：通过' : ''}\n${JSON.stringify(result, null, 2)}`;
  });

  const verifyErrors = () => checks.run(async () => {
    let failure: unknown;
    try {
      await IntentLauncher.startActivityAsync('');
    } catch (error) {
      failure = error;
    }
    if (!(failure instanceof TypeError)) throw new Error(`空 action 应由官方 JS 拒绝为 TypeError，实际 ${String(failure)}。`);

    const cases = [
      { label: '未知 Ability', run: () => IntentLauncher.startActivityAsync(ACTION, { className: `${ABILITY}Missing` }), code: 'ERR_INTENT_LAUNCHER_START_ACTIVITY' },
      { label: '再次启动未知 Ability', run: () => IntentLauncher.startActivityAsync(ACTION, { className: `${ABILITY}Missing` }), code: 'ERR_INTENT_LAUNCHER_START_ACTIVITY' },
    ];
    const rows = ['空 action：官方 JS 正确拒绝为 TypeError'];
    for (const item of cases) {
      let code: unknown;
      try {
        await item.run();
      } catch (error) {
        code = error instanceof Error && 'code' in error ? error.code : undefined;
      }
      if (code !== item.code) throw new Error(`${item.label}：预期 ${item.code}，实际 ${String(code)}。`);
      rows.push(`${item.label}：正确拒绝`);
    }

    return `${rows.join('\n')}\n错误后未残留等待状态；可继续验证结果回传。`;
  });

  return (
    <>
      <Panel eyebrow="应用" title="应用图标与桌面入口">
        <Field label="应用包名 / bundleName" onChangeText={setBundle} testID="intent-bundle" value={bundle} />
        <ActionRow>
          <ActionButton
            disabled={busy || !bundle}
            label="读取图标"
            testID="intent-icon"
            onPress={() => void apps.run(async () => {
              setIcon('');
              const uri = await IntentLauncher.getApplicationIconAsync(bundle);
              if (!uri.startsWith('data:image/png;base64,')) throw new Error('没有返回 PNG 图标。');
              setIcon(uri);

              return `PNG 图标：${uri.length} 字符；请检查卡片中的图片。`;
            })}
          />
          <ActionButton
            disabled={busy || !bundle}
            label="打开应用"
            testID="intent-open"
            tone="secondary"
            onPress={() => void apps.run(() => {
              const result = IntentLauncher.openApplication(bundle);
              if (result !== undefined) throw new Error('同步接口应返回 undefined。');

              return '调用返回 undefined；请检查目标应用是否打开。';
            })}
          />
        </ActionRow>
        {icon ? <Image accessibilityLabel="目标应用图标" source={{ uri: icon }} style={{ width: 72, height: 72 }} /> : null}
        <Note>默认查询当前应用。查询其他应用可能因系统权限或包可见性限制而失败。</Note>
        <ResultPanel state={apps.state} />
      </Panel>

      <Panel eyebrow="启动" title="按目标应用协议启动">
        <Field label="Action" onChangeText={setAction} testID="intent-action" value={action} />
        <Field label="UIAbility / className" onChangeText={setAbility} testID="intent-ability" value={ability} />
        <ActionButton
          disabled={busy}
          label="启动并等待结果"
          testID="intent-start"
          onPress={() => void launch.run(async () => {
            const result = await IntentLauncher.startActivityAsync(action, {
              ...(ability ? { className: ability, packageName: bundle } : {}),
            });

            return JSON.stringify(result, null, 2);
          })}
        />
        <Note>默认打开 demo 的原生结果页。回到应用前台不会自动完成请求，目标 Ability 必须返回结果；Android 设置 action 不能直接套用到 HarmonyOS。</Note>
        <ResultPanel state={launch.state} />
      </Panel>

      <Panel eyebrow="接口验证" title="结果回传、并发与错误恢复">
        <ActionRow>
          <ActionButton disabled={busy || !harmony} label="验证结果回传" testID="intent-verify-result" onPress={() => void verify()} />
          <ActionButton disabled={busy || !harmony} label="验证取消" testID="intent-verify-cancel" tone="secondary" onPress={() => void verify(true)} />
          <ActionButton disabled={busy || !harmony} label="验证并发" testID="intent-verify-concurrent" tone="secondary" onPress={() => void verify(false, true)} />
          <ActionButton disabled={busy || !harmony} label="验证错误与恢复" testID="intent-verify-errors" tone="secondary" onPress={() => void verifyErrors()} />
        </ActionRow>
        <Note>
          HarmonyOS 专用：在原生页面点击「返回结果」或「取消」，系统返回键同样按取消处理。demo 协议约定 42 为成功、0 为取消，
          校验 URI、MIME、category、嵌套 extra 和顶层小数截断。并发验证会同时发起两次请求。
        </Note>
        <ResultPanel state={checks.state} />
      </Panel>
    </>
  );
}

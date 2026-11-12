/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Updates from 'expo-updates';
import { useEffect, useRef, useState } from 'react';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function UpdatesDemo() {
  return (
    <>
      <UpdateState />
      <UpdateRequests />
      <ReloadScreen />
      <UpdateLogs />
      <ExtraParams />
      <RequestOverrides />
    </>
  );
}

function UpdateState() {
  const state = Updates.useUpdates();
  const result = useAsyncResult();

  return (
    <Panel title="当前更新">
      <DataRow label="isEnabled" value={String(Updates.isEnabled)} />
      <DataRow label="updateId" value={Updates.updateId ?? 'null'} />
      <DataRow label="channel" value={Updates.channel ?? 'null'} />
      <DataRow label="runtimeVersion" value={Updates.runtimeVersion ?? 'null'} />
      <DataRow label="checkAutomatically" value={Updates.checkAutomatically ?? 'null'} />
      <DataRow label="isEmbeddedLaunch" value={String(Updates.isEmbeddedLaunch)} />
      <DataRow label="isUsingEmbeddedAssets" value={String(Updates.isUsingEmbeddedAssets)} />
      <DataRow label="isEmergencyLaunch" value={String(Updates.isEmergencyLaunch)} />
      <DataRow label="emergencyLaunchReason" value={Updates.emergencyLaunchReason ?? 'null'} />
      <DataRow label="launchDuration（毫秒）" value={Updates.launchDuration ?? 'null'} />
      <DataRow label="createdAt" value={Updates.createdAt?.toISOString() ?? 'null'} />
      <DataRow label="downloadProgress" value={state.downloadProgress ?? 'null'} />
      <ActionRow>
        <ActionButton label="manifest" onPress={() => void result.run(() => json(Updates.manifest))} />
        <ActionButton label="localAssets" onPress={() => void result.run(() => json(Updates.localAssets))} />
        <ActionButton
          label="useUpdates()"
          onPress={() => void result.run(() => json({
            ...state,
            checkError: state.checkError?.message,
            downloadError: state.downloadError?.message,
          }))}
        />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}

function UpdateRequests() {
  const result = useAsyncResult();
  const disabled = !Updates.isEnabled || result.state.phase === 'running';

  return (
    <Panel title="检查和下载更新">
      <ActionRow>
        <ActionButton label="checkForUpdateAsync()" disabled={disabled} onPress={() => void result.run(async () => json(await Updates.checkForUpdateAsync()))} />
        <ActionButton label="fetchUpdateAsync()" disabled={disabled} onPress={() => void result.run(async () => json(await Updates.fetchUpdateAsync()))} />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}

function ReloadScreen() {
  const result = useAsyncResult();
  const [options, setOptions] = useState(json({
    backgroundColor: '#F2F2F7',
    fade: true,
    spinner: { enabled: true, color: '#0A63D5', size: 'medium' },
  }));
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const busy = result.state.phase === 'running';

  useEffect(() => () => {
    if (timer.current) {
      clearTimeout(timer.current);
      void Updates.hideReloadScreen().catch(() => {});
    }
  }, []);

  const reloadOptions = () => ({ reloadScreenOptions: JSON.parse(options) as Updates.ReloadScreenOptions });

  return (
    <Panel title="重载画面">
      <Field label="reloadScreenOptions（JSON 对象）" value={options} onChangeText={setOptions} multiline />
      <ActionRow>
        <ActionButton
          label="reloadAsync()"
          disabled={busy || !Updates.isEnabled}
          onPress={() => void result.run(async () => {
            await Updates.reloadAsync(reloadOptions());
            return '正在重新加载';
          })}
        />
        {__DEV__
          ? (
              <>
                <ActionButton
                  label="预览画面 2 秒"
                  disabled={busy}
                  onPress={() => void result.run(async () => {
                    await Updates.showReloadScreen(reloadOptions());
                    clearTimeout(timer.current);
                    timer.current = setTimeout(() => {
                      timer.current = undefined;
                      void Updates.hideReloadScreen().catch(() => {});
                    }, 2000);
                    return 'showReloadScreen()';
                  })}
                />
                <ActionButton
                  label="hideReloadScreen()"
                  disabled={busy}
                  onPress={() => void result.run(async () => {
                    await Updates.hideReloadScreen();
                    clearTimeout(timer.current);
                    timer.current = undefined;
                    return '已隐藏画面';
                  })}
                />
              </>
            )
          : null}
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}

function UpdateLogs() {
  const result = useAsyncResult();
  const [maxAge, setMaxAge] = useState('3600000');
  const busy = result.state.phase === 'running';

  return (
    <Panel title="更新日志">
      <Field label="maxAge（毫秒）" value={maxAge} onChangeText={setMaxAge} keyboardType="number-pad" />
      <ActionRow>
        <ActionButton
          label="readLogEntriesAsync()"
          disabled={busy}
          onPress={() => void result.run(async () =>
            json(await Updates.readLogEntriesAsync(maxAge === '' ? undefined : Number(maxAge))))}
        />
        <ActionButton
          label="clearLogEntriesAsync()"
          disabled={busy}
          onPress={() => void result.run(async () => {
            await Updates.clearLogEntriesAsync();
            return '已清空日志';
          })}
        />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}

function ExtraParams() {
  const result = useAsyncResult();
  const [key, setKey] = useState('demo');
  const [value, setValue] = useState('harmony');
  const disabled = !Updates.isEnabled || result.state.phase === 'running';

  function setParam(nextValue: string | null) {
    void result.run(async () => {
      await Updates.setExtraParamAsync(key, nextValue);
      return json({ key, value: nextValue });
    });
  }

  return (
    <Panel title="额外请求参数">
      <Field label="key" value={key} onChangeText={setKey} />
      <Field label="value" value={value} onChangeText={setValue} />
      <ActionRow>
        <ActionButton label="setExtraParamAsync()" disabled={disabled || !key} onPress={() => setParam(value)} />
        <ActionButton label="移除此参数" disabled={disabled || !key} onPress={() => setParam(null)} />
        <ActionButton label="getExtraParamsAsync()" disabled={disabled} onPress={() => void result.run(async () => json(await Updates.getExtraParamsAsync()))} />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}

function RequestOverrides() {
  const result = useAsyncResult();
  const [url, setUrl] = useState('');
  const [headers, setHeaders] = useState('{"expo-channel-name": "preview"}');

  function override(operation: () => void) {
    void result.run(() => {
      operation();
      return '已更新请求配置';
    });
  }

  return (
    <Panel title="覆盖更新请求">
      <Field label="updateUrl" value={url} onChangeText={setUrl} />
      <Field label="requestHeaders（JSON 对象）" value={headers} onChangeText={setHeaders} multiline />
      <ActionRow>
        <ActionButton
          label="覆盖 URL 和请求头"
          disabled={!Updates.isEnabled || !url}
          onPress={() => override(() =>
            Updates.setUpdateURLAndRequestHeadersOverride({ updateUrl: url, requestHeaders: JSON.parse(headers) }))}
        />
        <ActionButton
          label="恢复默认 URL 和请求头"
          disabled={!Updates.isEnabled}
          onPress={() => override(() =>
            Updates.setUpdateURLAndRequestHeadersOverride(null))}
        />
        <ActionButton
          label="覆盖请求头"
          disabled={!Updates.isEnabled}
          onPress={() => override(() =>
            Updates.setUpdateRequestHeadersOverride(JSON.parse(headers)))}
        />
        <ActionButton
          label="恢复默认请求头"
          disabled={!Updates.isEnabled}
          onPress={() => override(() =>
            Updates.setUpdateRequestHeadersOverride(null))}
        />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}

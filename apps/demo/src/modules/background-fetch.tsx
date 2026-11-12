/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as BackgroundFetch from 'expo-background-fetch';
import { useEffect, useState } from 'react';
import { Platform, Switch } from 'react-native';

import {
  BACKGROUND_FETCH_OPTIONS,
  BACKGROUND_FETCH_TASK,
  getBackgroundFetchExecution,
  subscribeToBackgroundFetchExecution,
} from './background-fetch/tasks';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function BackgroundFetchDemo() {
  const action = useAsyncResult();
  const [interval, setInterval] = useState(String(BACKGROUND_FETCH_OPTIONS.minimumInterval));
  const [boot, setBoot] = useState(BACKGROUND_FETCH_OPTIONS.startOnBoot ?? false);
  const [terminate, setTerminate] = useState(BACKGROUND_FETCH_OPTIONS.stopOnTerminate ?? false);
  const [execution, setExecution] = useState(getBackgroundFetchExecution);
  const busy = action.state.phase === 'running';

  useEffect(() => subscribeToBackgroundFetchExecution(setExecution), []);

  return (
    <>
      <Panel title="后台拉取">
        <DataRow label="任务名" value={BACKGROUND_FETCH_TASK} />
        <Field label="最小间隔（秒）" keyboardType="numeric" onChangeText={setInterval} value={interval} />
        {Platform.OS !== 'ios' && Platform.OS !== 'web'
          ? (
              <>
                <DataRow label="设备重启后恢复" value={<Switch accessibilityLabel="设备重启后恢复" onValueChange={setBoot} value={boot} testID="background-fetch-boot" />} />
                <DataRow label="应用终止后停止" value={<Switch accessibilityLabel="应用终止后停止" onValueChange={setTerminate} value={terminate} testID="background-fetch-terminate" />} />
              </>
            )
          : null}
        <ActionRow>
          <ActionButton
            disabled={busy}
            label="注册任务"
            onPress={() => void action.run(async () => {
              await BackgroundFetch.registerTaskAsync(BACKGROUND_FETCH_TASK, {
                minimumInterval: interval.trim() ? Number(interval) : undefined,
                startOnBoot: boot,
                stopOnTerminate: terminate,
              });
              return '已注册';
            })}
            testID="background-fetch-register"
          />
          <ActionButton
            disabled={busy}
            label="取消注册"
            onPress={() => void action.run(async () => {
              await BackgroundFetch.unregisterTaskAsync(BACKGROUND_FETCH_TASK);
              return '已取消注册';
            })}
            testID="background-fetch-unregister"
            tone="secondary"
          />
          <ActionButton
            disabled={busy}
            label="查询拉取状态"
            onPress={() => void action.run(async () => {
              const status = await BackgroundFetch.getStatusAsync();
              return status === null ? 'null' : BackgroundFetch.BackgroundFetchStatus[status];
            })}
            testID="background-fetch-inspect"
            tone="secondary"
          />
          {Platform.OS === 'ios'
            ? <ActionButton
                disabled={busy || !interval.trim()}
                label="设置系统拉取间隔"
                onPress={() => void action.run(async () => {
                  await BackgroundFetch.setMinimumIntervalAsync(Number(interval));
                  return '已设置';
                })}
                tone="secondary"
              />
            : null}
        </ActionRow>
        <ResultPanel state={action.state} />
      </Panel>
      <Panel title="最近一次拉取">
        <DataRow label="执行次数" value={execution?.count ?? 0} />
        {execution
          ? (
              <>
                <DataRow label="事件 ID" value={execution.eventId} />
                <DataRow label="时间" value={execution.occurredAt} />
                {execution.error ? <DataRow label="错误" value={execution.error} /> : null}
              </>
            )
          : null}
        <ActionButton label="刷新执行记录" onPress={() => setExecution(getBackgroundFetchExecution())} tone="secondary" />
      </Panel>
    </>
  );
}

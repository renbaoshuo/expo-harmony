/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as BackgroundTask from 'expo-background-task';
import { useEffect, useState } from 'react';
import { Platform } from 'react-native';

import {
  BACKGROUND_TASK,
  BACKGROUND_TASK_OPTIONS,
  getBackgroundTaskExecution,
  subscribeToBackgroundTaskExecution,
} from './background-task/tasks';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function BackgroundTaskDemo() {
  const action = useAsyncResult();
  const [interval, setInterval] = useState(String(BACKGROUND_TASK_OPTIONS.minimumInterval));
  const [execution, setExecution] = useState(getBackgroundTaskExecution);
  const [listening, setListening] = useState(false);
  const [expirations, setExpirations] = useState(0);
  const busy = action.state.phase === 'running';
  const supportsExpiration = Platform.OS === 'ios' || String(Platform.OS) === 'harmony';

  useEffect(() => subscribeToBackgroundTaskExecution(setExecution), []);

  useEffect(() => {
    if (!listening) return;
    const subscription = BackgroundTask.addExpirationListener(() => setExpirations(value => value + 1));
    return () => subscription.remove();
  }, [listening]);

  return (
    <>
      <Panel title="后台任务">
        <DataRow label="任务名" value={BACKGROUND_TASK} />
        <Field label="最小间隔（分钟）" keyboardType="numeric" onChangeText={setInterval} value={interval} />
        <ActionRow>
          <ActionButton
            disabled={busy}
            label="注册任务"
            onPress={() => void action.run(async () => {
              await BackgroundTask.registerTaskAsync(BACKGROUND_TASK, {
                minimumInterval: interval.trim() ? Number(interval) : undefined,
              });
              return '已请求注册';
            })}
            testID="background-task-register"
          />
          <ActionButton
            disabled={busy}
            label="取消注册"
            onPress={() => void action.run(async () => {
              await BackgroundTask.unregisterTaskAsync(BACKGROUND_TASK);
              return '已取消注册';
            })}
            testID="background-task-unregister"
            tone="secondary"
          />
          <ActionButton
            disabled={busy}
            label="查询后台任务状态"
            onPress={() => void action.run(async () => (
              BackgroundTask.BackgroundTaskStatus[await BackgroundTask.getStatusAsync()]
            ))}
            testID="background-task-inspect"
            tone="secondary"
          />
          {__DEV__ && Platform.OS !== 'web'
            ? <ActionButton
                disabled={busy}
                label="立即触发后台任务"
                onPress={() => void action.run(async () => String(
                  await BackgroundTask.triggerTaskWorkerForTestingAsync()
                ))}
                testID="background-task-trigger"
                tone="secondary"
              />
            : null}
        </ActionRow>
        <ResultPanel state={action.state} />
      </Panel>
      <Panel title="最近一次执行">
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
        <ActionButton label="刷新执行记录" onPress={() => setExecution(getBackgroundTaskExecution())} tone="secondary" />
      </Panel>
      {supportsExpiration
        ? (
            <Panel title="执行超时">
              <DataRow label="超时事件次数" value={expirations} />
              <ActionButton label={listening ? '移除超时监听' : '监听执行超时'} onPress={() => setListening(value => !value)} />
            </Panel>
          )
        : null}
    </>
  );
}

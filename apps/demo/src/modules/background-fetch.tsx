import * as BackgroundFetch from 'expo-background-fetch';
import * as TaskManager from 'expo-task-manager';
import { useEffect, useState } from 'react';
import { Switch } from 'react-native';
import { BACKGROUND_FETCH_OPTIONS, BACKGROUND_FETCH_TASK, getBackgroundFetchExecution, subscribeToBackgroundFetchExecution } from './background-fetch/tasks';
import { ActionButton, ActionRow, DataRow, Note, Panel, ResultPanel, Tag, useAsyncResult } from '../ui';
import { json } from '../format';

function backgroundFetchStatusLabel(status: BackgroundFetch.BackgroundFetchStatus | null): string {
  if (status === null) return '不可用';

  return BackgroundFetch.BackgroundFetchStatus[status] ?? String(status);
}

export function BackgroundFetchDemo() {
  const action = useAsyncResult();
  const [registered, setRegistered] = useState(false);
  const [execution, setExecution] = useState(getBackgroundFetchExecution);
  const [boot, setBoot] = useState(BACKGROUND_FETCH_OPTIONS.startOnBoot ?? false);
  const [terminate, setTerminate] = useState(BACKGROUND_FETCH_OPTIONS.stopOnTerminate ?? true);

  useEffect(() => subscribeToBackgroundFetchExecution(setExecution), []);

  const inspect = () => action.run(async () => {
    const [available, status, isRegistered] = await Promise.all([
      TaskManager.isAvailableAsync(),
      BackgroundFetch.getStatusAsync(),
      TaskManager.isTaskRegisteredAsync(BACKGROUND_FETCH_TASK),
    ]);
    const options = isRegistered
      ? await TaskManager.getTaskOptionsAsync<BackgroundFetch.BackgroundFetchOptions>(BACKGROUND_FETCH_TASK)
      : null;

    setRegistered(isRegistered);
    setExecution(getBackgroundFetchExecution());
    if (options) {
      setBoot(options.startOnBoot ?? false);
      setTerminate(options.stopOnTerminate ?? true);
    }

    return json({ available, options, registered: isRegistered, status: backgroundFetchStatusLabel(status) });
  });

  const register = () => action.run(async () => {
    await BackgroundFetch.registerTaskAsync(BACKGROUND_FETCH_TASK, {
      ...BACKGROUND_FETCH_OPTIONS,
      startOnBoot: boot,
      stopOnTerminate: terminate,
    });

    setRegistered(true);

    return `已注册 ${BACKGROUND_FETCH_TASK}，最小间隔为不精确的 2 小时。`;
  });

  const unregister = () => action.run(async () => {
    await BackgroundFetch.unregisterTaskAsync(BACKGROUND_FETCH_TASK);

    setRegistered(false);

    return `已取消注册 ${BACKGROUND_FETCH_TASK}。`;
  });

  return (
    <>
      <Panel eyebrow="原生状态" title="检查 BackgroundFetch 与 TaskManager">
        <DataRow label="任务名" value={BACKGROUND_FETCH_TASK} />
        <DataRow label="已注册" value={<Tag tone={registered ? 'success' : 'signal'}>{registered ? '是' : '否'}</Tag>} />
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="读取原生状态"
          onPress={() => void inspect()}
          testID="background-fetch-inspect"
        />
      </Panel>

      <Panel eyebrow="WORKSCHEDULER" title="注册 Expo 后台拉取任务">
        <DataRow
          label="设备重启后恢复"
          value={<Switch disabled={registered || action.state.phase === 'running'} onValueChange={setBoot} value={boot} testID="background-fetch-boot" />}
        />
        <DataRow
          label="应用终止后停止"
          value={<Switch disabled={registered || action.state.phase === 'running'} onValueChange={setTerminate} value={terminate} testID="background-fetch-terminate" />}
        />
        <ActionRow>
          <ActionButton
            disabled={registered || action.state.phase === 'running'}
            label="注册任务"
            onPress={() => void register()}
            testID="background-fetch-register"
          />
          <ActionButton
            disabled={!registered || action.state.phase === 'running'}
            label="取消注册"
            onPress={() => void unregister()}
            testID="background-fetch-unregister"
            tone="secondary"
          />
        </ActionRow>
        <Note>
          Release demo 已配置无界面冷启动。系统最小间隔为 2 小时，并可能出于功耗策略推迟周期任务。
        </Note>
      </Panel>

      <Panel eyebrow="任务执行" title="观察 JavaScript 回调">
        <DataRow label="回调次数" value={String(execution?.count ?? 0)} />
        <DataRow label="最近事件" value={execution?.eventId ?? '尚未观测到'} />
        <DataRow label="发生时间" value={execution?.occurredAt ?? '尚未观测到'} />
        <DataRow label="执行环境" value={execution ? (execution.headless ? '无界面后台运行时' : '页面运行时') : '尚未观测到'} />
        <DataRow label="错误" value={execution?.error ?? '无'} />
        <Note>
          回调记录保存在应用目录，进程重启后仍可读取。点击“读取原生状态”可刷新后台执行结果。
        </Note>
      </Panel>

      <ResultPanel state={action.state} />
    </>
  );
}

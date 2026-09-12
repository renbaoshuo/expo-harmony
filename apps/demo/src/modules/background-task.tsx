import * as BackgroundTask from 'expo-background-task';
import * as TaskManager from 'expo-task-manager';
import { useEffect, useState } from 'react';
import { BACKGROUND_TASK, BACKGROUND_TASK_OPTIONS, getBackgroundTaskExecution, subscribeToBackgroundTaskExecution } from './background-task/tasks';
import { ActionButton, ActionRow, DataRow, Note, Panel, ResultPanel, Tag, useAsyncResult } from '../ui';
import { json } from '../format';

function backgroundTaskStatusLabel(status: BackgroundTask.BackgroundTaskStatus): string {
  return BackgroundTask.BackgroundTaskStatus[status] ?? String(status);
}

export function BackgroundTaskDemo() {
  const action = useAsyncResult();
  const [registered, setRegistered] = useState(false);
  const [execution, setExecution] = useState(getBackgroundTaskExecution);
  const [expirations, setExpirations] = useState(0);

  useEffect(() => {
    const unsubscribe = subscribeToBackgroundTaskExecution(setExecution);
    const expiration = BackgroundTask.addExpirationListener(() => {
      setExpirations(value => value + 1);
    });

    return () => {
      unsubscribe();
      expiration.remove();
    };
  }, []);

  const inspect = () => action.run(async () => {
    const [available, status, isRegistered, tasks] = await Promise.all([
      TaskManager.isAvailableAsync(),
      BackgroundTask.getStatusAsync(),
      TaskManager.isTaskRegisteredAsync(BACKGROUND_TASK),
      TaskManager.getRegisteredTasksAsync(),
    ]);

    const options = isRegistered
      ? await TaskManager.getTaskOptionsAsync<BackgroundTask.BackgroundTaskOptions>(BACKGROUND_TASK)
      : null;
    const task = tasks.find(value => value.taskName === BACKGROUND_TASK) ?? null;

    setRegistered(isRegistered);
    setExecution(getBackgroundTaskExecution());

    return json({
      available,
      options,
      registered: isRegistered,
      status: backgroundTaskStatusLabel(status),
      taskType: task?.taskType ?? null,
    });
  });

  const register = () => action.run(async () => {
    await BackgroundTask.registerTaskAsync(BACKGROUND_TASK, BACKGROUND_TASK_OPTIONS);

    const registered = await TaskManager.isTaskRegisteredAsync(BACKGROUND_TASK);
    setRegistered(registered);
    if (!registered) {
      throw new Error('任务未注册。请先检查原生状态；Harmony 宿主需要配置 TaskManager 冷启动 runtime loader。');
    }

    return `已注册 ${BACKGROUND_TASK}，最小间隔为不精确的 2 小时。`;
  });

  const unregister = () => action.run(async () => {
    await BackgroundTask.unregisterTaskAsync(BACKGROUND_TASK);

    setRegistered(false);

    return `已取消注册 ${BACKGROUND_TASK}。`;
  });

  const trigger = () => action.run(async () => {
    const triggered = await BackgroundTask.triggerTaskWorkerForTestingAsync();
    const current = getBackgroundTaskExecution();

    return json({
      callbackCount: current?.count ?? 0,
      eventId: current?.eventId ?? null,
      triggered,
    });
  });

  return (
    <>
      <Panel eyebrow="原生状态" title="检查 BackgroundTask 与 TaskManager">
        <DataRow label="任务名" value={BACKGROUND_TASK} />
        <DataRow label="已注册" value={<Tag tone={registered ? 'success' : 'signal'}>{registered ? '是' : '否'}</Tag>} />
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="读取原生状态"
          onPress={() => void inspect()}
          testID="background-task-inspect"
        />
      </Panel>

      <Panel eyebrow="WORKSCHEDULER" title="注册新一代 Expo 后台任务">
        <ActionRow>
          <ActionButton
            disabled={registered || action.state.phase === 'running'}
            label="注册任务"
            onPress={() => void register()}
            testID="background-task-register"
          />
          <ActionButton
            disabled={!registered || action.state.phase === 'running'}
            label="取消注册"
            onPress={() => void unregister()}
            testID="background-task-unregister"
            tone="secondary"
          />
        </ActionRow>
        <Note>
          Release demo 已配置无界面冷启动。系统最小间隔为 2 小时，并可能出于功耗策略推迟周期任务。
        </Note>
      </Panel>

      <Panel eyebrow="调试执行" title="立即运行原生 worker">
        <ActionButton
          disabled={!registered || action.state.phase === 'running'}
          label="触发调试 worker"
          onPress={() => void trigger()}
          testID="background-task-trigger"
        />
        <DataRow label="回调次数" value={String(execution?.count ?? 0)} />
        <DataRow label="最近事件" value={execution?.eventId ?? '尚未观测到'} />
        <DataRow label="发生时间" value={execution?.occurredAt ?? '尚未观测到'} />
        <DataRow label="执行环境" value={execution ? (execution.headless ? '无界面后台运行时' : '页面运行时') : '尚未观测到'} />
        <DataRow label="错误" value={execution?.error ?? '无'} />
        <DataRow label="过期事件数" value={String(expirations)} />
        <Note>
          触发 API 仅在 debug 构建中可用；常规周期执行仍由系统调度。
        </Note>
      </Panel>

      <ResultPanel state={action.state} />
    </>
  );
}

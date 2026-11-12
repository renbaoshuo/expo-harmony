/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as TaskManager from 'expo-task-manager';
import { useState } from 'react';

import { BACKGROUND_FETCH_TASK } from './background-fetch/tasks';
import { BACKGROUND_TASK } from './background-task/tasks';
import { json } from '../format';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function TaskManagerDemo() {
  const [taskName, setTaskName] = useState(BACKGROUND_TASK);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="任务管理">
      <Field label="任务名" value={taskName} onChangeText={setTaskName} />
      <ActionRow>
        <ActionButton label="使用后台任务名" onPress={() => setTaskName(BACKGROUND_TASK)} tone="secondary" />
        <ActionButton label="使用后台拉取任务名" onPress={() => setTaskName(BACKGROUND_FETCH_TASK)} tone="secondary" />
      </ActionRow>
      <ActionRow>
        <ActionButton disabled={busy} label="查询任务定义" onPress={() => void action.run(() => String(TaskManager.isTaskDefined(taskName)))} />
        <ActionButton disabled={busy} label="查询注册状态" onPress={() => void action.run(async () => String(await TaskManager.isTaskRegisteredAsync(taskName)))} />
        <ActionButton disabled={busy} label="读取任务参数" onPress={() => void action.run(async () => json(await TaskManager.getTaskOptionsAsync(taskName)))} />
        <ActionButton
          disabled={busy}
          label="取消注册此任务"
          onPress={() => void action.run(async () => {
            await TaskManager.unregisterTaskAsync(taskName);
            return '已取消注册';
          })}
          tone="secondary"
        />
      </ActionRow>
      <ActionRow>
        <ActionButton disabled={busy} label="查询任务管理是否可用" onPress={() => void action.run(async () => String(await TaskManager.isAvailableAsync()))} tone="secondary" />
        <ActionButton disabled={busy} label="列出已注册任务" onPress={() => void action.run(async () => json(await TaskManager.getRegisteredTasksAsync()))} tone="secondary" />
        <ActionButton
          disabled={busy}
          label="取消注册全部任务"
          onPress={() => void action.run(async () => {
            await TaskManager.unregisterAllTasksAsync();
            return '已取消注册全部任务';
          })}
          tone="danger"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

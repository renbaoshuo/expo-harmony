import * as TaskManager from 'expo-task-manager';
import { BACKGROUND_FETCH_CHECK_TASK, BACKGROUND_FETCH_TASK } from './background-fetch/tasks';
import { BACKGROUND_TASK, BACKGROUND_TASK_CHECK } from './background-task/tasks';
import { ActionButton, Panel, ResultPanel, useAsyncResult } from '../ui';
import { json } from '../format';

export function TaskManagerDemo() {
  const availability = useAsyncResult();
  const registrations = useAsyncResult();

  const inspectDefinitions = () => availability.run(async () => {
    const available = await TaskManager.isAvailableAsync();
    const definitions = [
      BACKGROUND_FETCH_TASK,
      BACKGROUND_FETCH_CHECK_TASK,
      BACKGROUND_TASK,
      BACKGROUND_TASK_CHECK,
    ].map(taskName => ({ defined: TaskManager.isTaskDefined(taskName), taskName }));
    if (!definitions.every(item => item.defined)) throw new Error(`缺少全局任务定义：${json(definitions)}`);
    return json({ available, definitions });
  });

  const inspectRegistrations = () => registrations.run(async () => {
    const tasks = await TaskManager.getRegisteredTasksAsync();
    return json({ count: tasks.length, tasks });
  });

  return (
    <>
      <Panel eyebrow="全局定义" title="验证任务在 React 挂载前已定义">
        <ActionButton label="检查任务定义" onPress={() => void inspectDefinitions()} />
        <ResultPanel state={availability.state} />
      </Panel>
      <Panel eyebrow="持久化状态" title="列出原生任务注册">
        <ActionButton label="列出已注册任务" onPress={() => void inspectRegistrations()} />
        <ResultPanel state={registrations.state} />
      </Panel>
    </>
  );
}

import * as BackgroundTask from 'expo-background-task';
import * as TaskManager from 'expo-task-manager';
import { readExecution, recordExecution, type BackgroundExecution } from '../background-execution';

export const BACKGROUND_TASK = 'expo-harmony-demo-background-task';
export const BACKGROUND_TASK_CHECK = 'expo-harmony-check-background-task';
export const BACKGROUND_TASK_INTERVAL = 2 * 60;
export const BACKGROUND_TASK_TYPE = 'expo-background-task';

export const BACKGROUND_TASK_OPTIONS: BackgroundTask.BackgroundTaskOptions = {
  minimumInterval: BACKGROUND_TASK_INTERVAL,
};

export type BackgroundTaskExecution = BackgroundExecution;

let checkExecutions = 0;
const listeners = new Set<(value: BackgroundTaskExecution) => void>();

TaskManager.defineTask(BACKGROUND_TASK, async ({ error, executionInfo }) => {
  const value = recordExecution(BACKGROUND_TASK, executionInfo.eventId, error?.message ?? null);

  listeners.forEach(listener => listener(value));

  return error
    ? BackgroundTask.BackgroundTaskResult.Failed
    : BackgroundTask.BackgroundTaskResult.Success;
});

TaskManager.defineTask(BACKGROUND_TASK_CHECK, async ({ error }) => {
  checkExecutions += 1;

  return error
    ? BackgroundTask.BackgroundTaskResult.Failed
    : BackgroundTask.BackgroundTaskResult.Success;
});

export function getBackgroundTaskCheckExecutions(): number {
  return checkExecutions;
}

export function getBackgroundTaskExecution(): BackgroundTaskExecution | null {
  return readExecution(BACKGROUND_TASK);
}

export function subscribeToBackgroundTaskExecution(
  listener: (value: BackgroundTaskExecution) => void
): () => void {
  listeners.add(listener);

  return () => listeners.delete(listener);
}

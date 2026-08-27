import * as BackgroundTask from 'expo-background-task';
import * as TaskManager from 'expo-task-manager';

export const BACKGROUND_TASK = 'expo-harmony-demo-background-task';
export const BACKGROUND_TASK_CHECK = 'expo-harmony-check-background-task';
export const BACKGROUND_TASK_INTERVAL = 20;
export const BACKGROUND_TASK_TYPE = 'expo-background-task';

export const BACKGROUND_TASK_OPTIONS: BackgroundTask.BackgroundTaskOptions = {
  minimumInterval: BACKGROUND_TASK_INTERVAL,
};

export type BackgroundTaskExecution = {
  count: number;
  error: string | null;
  eventId: string;
  occurredAt: string;
};

let execution: BackgroundTaskExecution | null = null;
let checkExecutions = 0;
const listeners = new Set<(value: BackgroundTaskExecution) => void>();

TaskManager.defineTask(BACKGROUND_TASK, async ({ error, executionInfo }) => {
  const value = {
    count: (execution?.count ?? 0) + 1,
    error: error?.message ?? null,
    eventId: executionInfo.eventId,
    occurredAt: new Date().toISOString(),
  };

  execution = value;
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
  return execution;
}

export function subscribeToBackgroundTaskExecution(
  listener: (value: BackgroundTaskExecution) => void
): () => void {
  listeners.add(listener);

  return () => listeners.delete(listener);
}

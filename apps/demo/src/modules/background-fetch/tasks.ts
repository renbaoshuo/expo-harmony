import * as BackgroundFetch from 'expo-background-fetch';
import * as TaskManager from 'expo-task-manager';
import { readExecution, recordExecution, type BackgroundExecution } from '../background-execution';

export const BACKGROUND_FETCH_TASK = 'expo-harmony-demo-background-fetch';
export const BACKGROUND_FETCH_CHECK_TASK = 'expo-harmony-check-background-fetch';
export const BACKGROUND_FETCH_SECONDARY_CHECK_TASK = 'expo-harmony-check-background-fetch-secondary';
export const BACKGROUND_FETCH_MISSING_CHECK_TASK = 'expo-harmony-check-background-fetch-missing';
export const BACKGROUND_FETCH_CHECK_PASS = 'EXPO_HARMONY_BACKGROUND_FETCH_CHECK:PASS';
export const BACKGROUND_FETCH_INTERVAL = 2 * 60 * 60;

export const BACKGROUND_FETCH_OPTIONS: BackgroundFetch.BackgroundFetchOptions = {
  minimumInterval: BACKGROUND_FETCH_INTERVAL,
  startOnBoot: false,
  stopOnTerminate: false,
};

export type BackgroundFetchExecution = BackgroundExecution;

const listeners = new Set<(value: BackgroundFetchExecution) => void>();

TaskManager.defineTask(BACKGROUND_FETCH_TASK, async ({ error, executionInfo }) => {
  const value = recordExecution(BACKGROUND_FETCH_TASK, executionInfo.eventId, error?.message ?? null);

  listeners.forEach(listener => listener(value));

  return error
    ? BackgroundFetch.BackgroundFetchResult.Failed
    : BackgroundFetch.BackgroundFetchResult.NoData;
});

TaskManager.defineTask(BACKGROUND_FETCH_CHECK_TASK, async () => {
  return BackgroundFetch.BackgroundFetchResult.NoData;
});

TaskManager.defineTask(BACKGROUND_FETCH_SECONDARY_CHECK_TASK, async () => {
  return BackgroundFetch.BackgroundFetchResult.NoData;
});

export function getBackgroundFetchExecution(): BackgroundFetchExecution | null {
  return readExecution(BACKGROUND_FETCH_TASK);
}

export function subscribeToBackgroundFetchExecution(
  listener: (value: BackgroundFetchExecution) => void
): () => void {
  listeners.add(listener);

  return () => listeners.delete(listener);
}

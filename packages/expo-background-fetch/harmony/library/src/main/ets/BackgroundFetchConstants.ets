export const TASK_TYPE: string = 'backgroundFetch';

export const WORK_SCHEDULER_EXTENSION_NAME: string = 'ExpoBackgroundFetchWorkSchedulerExtension';
export const WORK_SCHEDULER_CAPABILITY: string = 'SystemCapability.ResourceSchedule.WorkScheduler';
export const WORK_SCHEDULER_MINIMUM_INTERVAL_MS: number = 2 * 60 * 60 * 1000;
export const WORK_SCHEDULER_EXECUTION_WINDOW_MS: number = 2 * 60 * 1000;
export const WORK_SCHEDULER_CLEANUP_MARGIN_MS: number = 10 * 1000;
export const DEFAULT_MINIMUM_INTERVAL_SECONDS: number = 10 * 60;

export const OWNER_PARAMETER: string = 'expo.backgroundFetch.owner';
export const OWNER_PARAMETER_VALUE: string = '@expo-harmony/expo-background-fetch';
export const TASK_NAME_PARAMETER: string = 'expo.backgroundFetch.taskName';
export const SCHEDULER_GENERATION_PARAMETER: string = 'expo.backgroundFetch.schedulerGeneration';
export const MINIMUM_INTERVAL_PARAMETER: string = 'expo.backgroundFetch.minimumInterval';
export const STOP_ON_TERMINATE_PARAMETER: string = 'expo.backgroundFetch.stopOnTerminate';
export const START_ON_BOOT_PARAMETER: string = 'expo.backgroundFetch.startOnBoot';

export const BACKGROUND_FETCH_STATUS_RESTRICTED: number = 2;
export const BACKGROUND_FETCH_STATUS_AVAILABLE: number = 3;

export const WORK_ID_MINIMUM: number = 1;
export const WORK_ID_MAXIMUM: number = 0x7fffffff;

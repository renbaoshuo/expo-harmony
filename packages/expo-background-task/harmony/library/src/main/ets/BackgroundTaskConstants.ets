export const BACKGROUND_TASK_SERVICE_NAME: string = 'ExpoBackgroundTaskService';
export const BACKGROUND_TASK_MODULE_NAME: string = 'ExpoBackgroundTask';
export const BACKGROUND_TASK_TYPE: string = 'expo-background-task';
export const EXPIRATION_EVENT_NAME: string = 'onTasksExpired';

export const WORK_SCHEDULER_EXTENSION_NAME: string = 'ExpoBackgroundTaskWorkScheduler';
export const WORK_SCHEDULER_CAPABILITY: string = 'SystemCapability.ResourceSchedule.WorkScheduler';
export const WORK_SCHEDULER_MINIMUM_INTERVAL_MS: number = 20 * 60 * 1000;
export const EXPO_DEFAULT_INTERVAL_MS: number = 24 * 60 * 60 * 1000;
export const MILLISECONDS_PER_MINUTE: number = 60 * 1000;

export const OWNER_PARAMETER: string = 'expo.backgroundTask.owner';
export const OWNER_PARAMETER_VALUE: string = '@expo-harmony/expo-background-task';
export const TASK_MANAGER_OWNER_PARAMETER: string = 'expo.taskManager.owner';

export const BACKGROUND_TASK_STATUS_RESTRICTED: number = 1;
export const BACKGROUND_TASK_STATUS_AVAILABLE: number = 2;

export const WORK_ID_MINIMUM: number = 1;
export const WORK_ID_MAXIMUM: number = 0x7fffffff;
export const FNV_OFFSET_BASIS: number = 0x811c9dc5;
export const FNV_PRIME: number = 0x01000193;

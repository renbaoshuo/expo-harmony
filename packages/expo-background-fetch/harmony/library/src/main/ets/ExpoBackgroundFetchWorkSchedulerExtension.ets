import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';

import { ExpoTaskManagerRegistry } from '@expo-harmony/expo-task-manager';
import { SCHEDULER_GENERATION_PARAMETER, WORK_SCHEDULER_EXTENSION_NAME } from './BackgroundFetchConstants';
import { BackgroundFetchRuntime } from './BackgroundFetchRuntime';

export class ExpoBackgroundFetchWorkSchedulerExtension extends WorkSchedulerExtensionAbility {
  private readonly requests: Map<string, Promise<string | undefined>[]> = new Map();

  override onWorkStart(work: workScheduler.WorkInfo): void {
    ExpoTaskManagerRegistry.prepareExtension(this.context, WORK_SCHEDULER_EXTENSION_NAME);

    const request = BackgroundFetchRuntime.start(this.context, work, Date.now());
    const key = `${work.workId}:${work.parameters?.[SCHEDULER_GENERATION_PARAMETER] ?? ''}`;
    const requests = this.requests.get(key) ?? [];

    requests.push(request);
    this.requests.set(key, requests);
  }

  override onWorkStop(work: workScheduler.WorkInfo): void {
    ExpoTaskManagerRegistry.prepareExtension(this.context, WORK_SCHEDULER_EXTENSION_NAME);

    const key = `${work.workId}:${work.parameters?.[SCHEDULER_GENERATION_PARAMETER] ?? ''}`;
    const requests = this.requests.get(key);
    const request = requests?.shift();
    if (requests !== undefined && requests.length === 0) this.requests.delete(key);
    BackgroundFetchRuntime.stop(this.context, work, request);
  }
}

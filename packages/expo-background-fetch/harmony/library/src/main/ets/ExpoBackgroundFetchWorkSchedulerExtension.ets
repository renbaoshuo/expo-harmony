import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';

import { BackgroundFetchRuntime } from './BackgroundFetchRuntime';
import { registerBackgroundFetchConsumer } from './ExpoBackgroundFetchPackage';

export class ExpoBackgroundFetchWorkSchedulerExtension extends WorkSchedulerExtensionAbility {
  private readonly requests: Map<number, Promise<string | undefined>[]> = new Map();

  override onWorkStart(work: workScheduler.WorkInfo): void {
    registerBackgroundFetchConsumer();
    const request = BackgroundFetchRuntime.start(this.context, work, Date.now());
    const requests = this.requests.get(work.workId) ?? [];
    requests.push(request);
    this.requests.set(work.workId, requests);
  }

  override onWorkStop(work: workScheduler.WorkInfo): void {
    registerBackgroundFetchConsumer();
    const requests = this.requests.get(work.workId);
    const request = requests?.shift();
    if (requests !== undefined && requests.length === 0) this.requests.delete(work.workId);
    BackgroundFetchRuntime.stop(this.context, work, request);
  }
}

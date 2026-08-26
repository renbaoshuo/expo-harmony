import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';

import { BackgroundFetchRuntime } from './BackgroundFetchRuntime';

export class ExpoBackgroundFetchWorkSchedulerExtension extends WorkSchedulerExtensionAbility {
  override onWorkStart(work: workScheduler.WorkInfo): void {
    BackgroundFetchRuntime.start(this.context, work);
  }

  override onWorkStop(work: workScheduler.WorkInfo): void {
    BackgroundFetchRuntime.stop(this.context, work);
  }
}

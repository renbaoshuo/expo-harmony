/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';

import { ExpoTaskManagerRegistry, ExpoTaskManagerWorkMetadata } from '@expo-harmony/expo-task-manager';
import { SCHEDULER_GENERATION_PARAMETER, WORK_SCHEDULER_EXTENSION_NAME } from './BackgroundFetchConstants';
import { BackgroundFetchRuntime } from './BackgroundFetchRuntime';

class WorkRun {
  stopped: boolean = false;
  request?: Promise<string | undefined>;
}

export class ExpoBackgroundFetchWorkSchedulerExtension extends WorkSchedulerExtensionAbility {
  private readonly requests: Map<string, WorkRun[]> = new Map();

  override onWorkStart(work: workScheduler.WorkInfo): void {
    const startedAt = Date.now();
    work.parameters = ExpoTaskManagerWorkMetadata.parameters(work.parameters);
    ExpoTaskManagerRegistry.prepareExtension(this.context, WORK_SCHEDULER_EXTENSION_NAME);

    const key = `${work.workId}:${work.parameters?.[SCHEDULER_GENERATION_PARAMETER] ?? ''}`;
    const requests = this.requests.get(key) ?? [];
    const run = new WorkRun();

    requests.push(run);
    this.requests.set(key, requests);
    run.request = BackgroundFetchRuntime.start(this.context, work, startedAt, (): boolean => run.stopped);
  }

  override onWorkStop(work: workScheduler.WorkInfo): void {
    work.parameters = ExpoTaskManagerWorkMetadata.parameters(work.parameters);
    ExpoTaskManagerRegistry.prepareExtension(this.context, WORK_SCHEDULER_EXTENSION_NAME);

    const key = `${work.workId}:${work.parameters?.[SCHEDULER_GENERATION_PARAMETER] ?? ''}`;
    const requests = this.requests.get(key);
    const run = requests?.shift();

    if (run !== undefined) run.stopped = true;
    if (requests !== undefined && requests.length === 0) this.requests.delete(key);

    BackgroundFetchRuntime.stop(this.context, work, run?.request);
  }
}

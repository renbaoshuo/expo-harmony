/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';

import { ExpoTaskManagerRegistry } from '@expo-harmony/expo-task-manager';
import { WORK_SCHEDULER_EXTENSION_NAME } from './BackgroundFetchConstants';
import { BackgroundFetchRuntime, isOwnedWork, schedulerGenerationFromWork } from './BackgroundFetchRuntime';

class WorkRun {
  stopped: boolean = false;
  request?: Promise<string | undefined>;
}

export class ExpoBackgroundFetchWorkSchedulerExtension extends WorkSchedulerExtensionAbility {
  private readonly requests: Map<string, WorkRun[]> = new Map();

  override onWorkStart(work: workScheduler.WorkInfo): void {
    const startedAt = Date.now();
    if (!this.accepts(work)) return;

    const key = `${work.workId}:${schedulerGenerationFromWork(work)}`;
    const runs = this.requests.get(key) ?? [];
    const run = new WorkRun();

    runs.push(run);
    this.requests.set(key, runs);

    run.request = BackgroundFetchRuntime.start(this.context, work, startedAt, (): boolean => run.stopped);
  }

  override onWorkStop(work: workScheduler.WorkInfo): void {
    if (!this.accepts(work)) return;

    const key = `${work.workId}:${schedulerGenerationFromWork(work)}`;
    const runs = this.requests.get(key);
    const run = runs?.shift();

    if (run !== undefined) run.stopped = true;
    if (runs !== undefined && runs.length === 0) this.requests.delete(key);

    BackgroundFetchRuntime.stop(this.context, work, run?.request);
  }

  private accepts(work: workScheduler.WorkInfo): boolean {
    try {
      ExpoTaskManagerRegistry.prepareExtension(this.context, WORK_SCHEDULER_EXTENSION_NAME);
      return isOwnedWork(work, this.context.extensionAbilityInfo.bundleName);
    } catch (error) {
      console.error(`Unable to initialize Expo Background Fetch WorkScheduler: ${String(error)}`);
      return false;
    }
  }
}

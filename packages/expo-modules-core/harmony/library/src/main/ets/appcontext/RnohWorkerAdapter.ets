import { UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { lang } from '@kit.ArkTS';
import { EtsUITurboModuleContext, SupportedTaskParams, WorkerTaskRunnable } from '@rnoh/react-native-openharmony/src/main/ets/RNOH/ets';

/** @internal Isolates the RNOH 0.84 worker API pending a package-root export. */
export type ExpoRnohWorkerParams = SupportedTaskParams;

/** @internal */
export interface ExpoRnohWorkerTask<Params extends SupportedTaskParams, Result extends lang.ISendable | void> extends WorkerTaskRunnable<
  Params,
  Result
> {}

/** @internal */
export async function runOnRnohWorker<
  Params extends SupportedTaskParams,
  Result extends lang.ISendable | void,
  Task extends WorkerTaskRunnable<Params, Result>,
>(context: UITurboModuleContext, task: Task, params: Params): Promise<Result> {
  if (!(context instanceof EtsUITurboModuleContext)) {
    throw new Error('The current RNOH context does not provide a worker task runner.');
  }
  return await context.runOnWorkerThread<Params, Result, Task>(task, params);
}

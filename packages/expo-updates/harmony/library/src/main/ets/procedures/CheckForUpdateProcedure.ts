/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoUpdatesError, Json } from '../UpdatesProtocol';
import { ProcedureContext, StateMachineProcedure } from './StateMachineProcedure';
import { UpdatesProcedureHost } from './UpdatesProcedureHost';

export class CheckForUpdateProcedure implements StateMachineProcedure<Json> {
  constructor(private readonly host: UpdatesProcedureHost) {}

  async run(context: ProcedureContext): Promise<Json> {
    context.process({ type: 'check' });

    try {
      const host = this.host;
      await host.loadEmbedded();

      const { result } = await host.loader.check(host.configuration, host.policy, host.launched, host.embedded);

      if (result.isAvailable) context.process({ type: 'checkCompleteWithUpdate', manifest: result.manifest });
      else if (result.isRollBackToEmbedded) context.process({ type: 'checkCompleteWithRollback', commitTime: result.time });
      else context.process({ type: 'checkCompleteUnavailable' });

      const { time, ...value } = result;

      return value;
    } catch (error) {
      const text = String(error);
      context.process({ type: 'checkError', errorMessage: error instanceof Error ? error.message : text });
      this.host.storage.logger.error(text, error as Error, 'UpdateFailedToLoad');

      throw new ExpoUpdatesError('ERR_UPDATES_CHECK', `Unable to check for updates: ${text}`, error as Error);
    }
  }
}

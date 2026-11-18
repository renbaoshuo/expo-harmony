/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoUpdatesError, Json } from '../UpdatesProtocol';
import { ProcedureContext, StateMachineProcedure } from './StateMachineProcedure';
import { UpdatesProcedureHost } from './UpdatesProcedureHost';

export class FetchUpdateProcedure implements StateMachineProcedure<Json> {
  constructor(private readonly host: UpdatesProcedureHost) {}

  run(context: ProcedureContext): Promise<Json> {
    const remote = this.fetch(context);
    this.host.remote(remote);
    return remote;
  }

  private async fetch(context: ProcedureContext): Promise<Json> {
    context.process({ type: 'download' });

    try {
      const host = this.host;
      await host.loadEmbedded();

      const { configuration: config, launched, embedded } = host;
      const { response, result } = await host.loader.check(config, host.policy, launched, embedded, true);
      const value = await host.loader.fetch(response, result, config, launched, embedded,
        progress => context.process({ type: 'downloadProgress', progress }));

      if (value.isRollBackToEmbedded) context.process({ type: 'downloadCompleteWithRollback', commitTime: result.time });
      else if (value.isNew) context.process({ type: 'downloadCompleteWithUpdate', manifest: value.manifest });
      else context.process({ type: 'downloadComplete' });

      return value;
    } catch (error) {
      const text = String(error);
      context.process({ type: 'downloadError', errorMessage: error instanceof Error ? error.message : text });
      this.host.storage.logger.error(text, error as Error, 'UpdateFailedToLoad');

      throw new ExpoUpdatesError('ERR_UPDATES_FETCH', `Unable to fetch update: ${text}`, error as Error);
    }
  }
}

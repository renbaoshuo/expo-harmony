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
      await this.host.loadEmbedded();
      const host = this.host;
      const configuration = host.configuration;
      const launched = host.launched;
      const embedded = host.embedded;
      const { response, result } = await host.loader.check(configuration, host.policy, launched, embedded, true);
      const value = await host.loader.fetch(response, result, configuration, launched, embedded,
        progress => context.process({ type: 'downloadProgress', progress }));
      if (value.isRollBackToEmbedded) context.process({ type: 'downloadCompleteWithRollback', commitTime: result.time });
      else if (value.isNew) context.process({ type: 'downloadCompleteWithUpdate', manifest: value.manifest });
      else context.process({ type: 'downloadComplete' });

      return value;
    } catch (error) {
      context.process({ type: 'downloadError', errorMessage: error instanceof Error ? error.message : String(error) });
      this.host.storage.logger.error(String(error), error as Error, 'UpdateFailedToLoad');
      throw new ExpoUpdatesError(error instanceof ExpoUpdatesError ? error.code : 'ERR_UPDATES_FETCH', `Unable to fetch update: ${String(error)}`, error as Error);
    }
  }
}

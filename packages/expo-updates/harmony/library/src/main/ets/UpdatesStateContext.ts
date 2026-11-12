/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Json } from './UpdatesProtocol';
import { UpdatesStateEvent } from './UpdatesStateEvent';

export function initialContext(): Json {
  return {
    isStartupProcedureRunning: false, isUpdateAvailable: false, isUpdatePending: false,
    isChecking: false, isDownloading: false, isRestarting: false, restartCount: 0,
    downloadProgress: 0, sequenceNumber: 0,
  };
}

export function reduceContext(context: Json, event: UpdatesStateEvent): Json {
  let changes: Json;
  switch (event.type) {
    case 'startStartup': changes = { isStartupProcedureRunning: true }; break;
    case 'endStartup': changes = { isStartupProcedureRunning: false }; break;
    case 'check': changes = { isChecking: true }; break;
    case 'checkCompleteUnavailable':
    case 'checkCompleteWithUpdate':
    case 'checkCompleteWithRollback':
      changes = {
        isChecking: false, checkError: null, isUpdateAvailable: event.type !== 'checkCompleteUnavailable',
        latestManifest: event.type === 'checkCompleteWithUpdate' ? event.manifest : null,
        rollback: event.type === 'checkCompleteWithRollback' ? { commitTime: new Date(event.commitTime).toISOString() } : null,
        lastCheckForUpdateTimeString: new Date().toISOString(),
      };
      break;
    case 'checkError':
      changes = { isChecking: false, checkError: { message: event.errorMessage }, lastCheckForUpdateTimeString: new Date().toISOString() };
      break;
    case 'download':
      changes = { isDownloading: true, downloadProgress: 0, downloadStartTime: Date.now(), downloadFinishTime: null };
      break;
    case 'downloadProgress': changes = { downloadProgress: event.progress }; break;
    case 'downloadComplete':
      changes = { isDownloading: false, downloadError: null, isUpdatePending: false, downloadProgress: 1, downloadStartTime: null, downloadFinishTime: null };
      break;
    case 'downloadCompleteWithRollback':
      changes = { isDownloading: false, downloadError: null, isUpdatePending: true, isUpdateAvailable: true,
        latestManifest: null, downloadedManifest: null, rollback: { commitTime: new Date(event.commitTime).toISOString() },
        downloadStartTime: null, downloadFinishTime: null };
      break;
    case 'downloadCompleteWithUpdate':
      changes = { isDownloading: false, downloadError: null, isUpdatePending: true, isUpdateAvailable: true,
        latestManifest: event.manifest, downloadedManifest: event.manifest, rollback: null, downloadFinishTime: Date.now() };
      break;
    case 'downloadError':
      changes = { isDownloading: false, downloadError: { message: event.errorMessage }, downloadStartTime: null, downloadFinishTime: null };
      break;
    case 'restart': changes = { isRestarting: true }; break;
  }

  return { ...context, ...changes, sequenceNumber: context.sequenceNumber + 1 };
}

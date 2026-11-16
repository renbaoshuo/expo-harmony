/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { isRecord } from './UpdatesJson';
import { UpdatesStateSubscription } from './UpdatesState';
import { IUpdatesController } from './IUpdatesController';
import { UpdatesController } from './UpdatesController';
import { ExpoUpdatesError, Json } from './UpdatesProtocol';
import { UpdatesReloadScreen } from './UpdatesReloadScreen';
import { UpdatesLogReader } from './logging/UpdatesLogReader';

const event = 'Expo.nativeUpdatesStateChangeEvent';
const object = ExpoValueTypes.custom<Json>(
  'JSON object',
  (value: ESObject): Json => {
    if (!isRecord(value)) throw new ExpoUpdatesError('ERR_UPDATES_ARGUMENT', 'Expected a JSON object.');
    return value;
  },
  (value: Json): ESObject => value,
);

export class ExpoUpdatesModule extends ExpoModule {
  private subscription?: UpdatesStateSubscription;

  private get controller(): IUpdatesController {
    return UpdatesController.get(this.context.uiAbilityContext.getApplicationContext());
  }

  definition(): ExpoModuleDefinition {
    const definition = new ExpoModuleDefinition().name('ExpoUpdates').events([event]);
    for (const key of Object.keys(this.controller.constants(this.context.runtimeId))) {
      definition.constant(key, (): ESObject => this.controller.constants(this.context.runtimeId)[key]);
    }
    return definition
      .asyncFunction('checkForUpdateAsync', async (): Promise<Json> => this.controller.checkForUpdateAsync())
      .asyncFunction('fetchUpdateAsync', async (): Promise<Json> => this.controller.fetchUpdateAsync())
      .asyncFunction('getExtraParamsAsync', async (): Promise<Record<string, string>> => this.controller.extra())
      .asyncFunction(
        'setExtraParamAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          ExpoValueTypes.string().nullable(),
          async (key: string, value: string | null): Promise<void> => this.controller.setExtra(key, value),
        ),
      )
      .asyncFunction(
        'readLogEntriesAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.number(),
          async (age: number): Promise<Json[]> => new UpdatesLogReader(this.context.uiAbilityContext.getApplicationContext()).read(age),
        ),
      )
      .asyncFunction(
        'clearLogEntriesAsync',
        async (): Promise<void> => new UpdatesLogReader(this.context.uiAbilityContext.getApplicationContext()).clear(),
      )
      .asyncFunction(
        'reload',
        ExpoFunction.typed1(object.nullable().optional(), async (options: Json | null | undefined): Promise<void> => {
          const controller = this.controller;

          if (controller.enabled && !this.context.isHeadless) {
            try {
              UpdatesReloadScreen.show(this.context.uiAbilityContext, options ?? {});
            } catch (error) {
              if (!(error instanceof ExpoUpdatesError) || error.code !== 'ERR_UPDATES_RELOAD_SCREEN') {
                return Promise.reject(error as Error);
              }

              console.warn(error.message);
            }
          }

          try {
            await controller.reload(this.context.runtimeId, async (reason: string): Promise<void> => this.context.reloadAppAsync(reason));
          } catch (error) {
            UpdatesReloadScreen.hide(this.context.uiAbilityContext);
            throw new ExpoUpdatesError(error instanceof ExpoUpdatesError ? error.code : 'ERR_UPDATES_RELOAD', String(error));
          }
        }),
      )
      .syncFunction(
        'setUpdateURLAndRequestHeadersOverride',
        ExpoFunction.typed1(object.nullable(), (value: Json | null): void => {
          if (value !== null && (typeof value.updateUrl !== 'string' || !value.updateUrl)) {
            throw new ExpoUpdatesError('ERR_UPDATES_RUNTIME_OVERRIDE', 'An Updates URL override requires a nonempty URL string.');
          }

          this.controller.override(value === null ? null : { url: value.updateUrl, requestHeaders: value.requestHeaders });
        }),
      )
      .syncFunction(
        'setUpdateRequestHeadersOverride',
        ExpoFunction.typed1(ExpoValueTypes.record(ExpoValueTypes.string()).nullable(), (headers: Record<string, string> | null): void =>
          this.controller.overrideHeaders(headers),
        ),
      )
      .asyncFunction(
        'showReloadScreen',
        ExpoFunction.typed1(object.nullable().optional(), async (options: Json | null | undefined): Promise<void> => {
          if (this.context.isDebug && this.controller.enabled && !this.context.isHeadless) {
            UpdatesReloadScreen.show(this.context.uiAbilityContext, options ?? {});
          }
        }),
      )
      .asyncFunction('hideReloadScreen', async (): Promise<void> => {
        if (this.context.isDebug) UpdatesReloadScreen.hide(this.context.uiAbilityContext);
      })
      .onStartObserving(event, (): void => {
        this.subscription?.remove();
        this.subscription = this.controller.state.subscribeContext((value: Json): void => this.sendEvent(event, value));
        const initial: Record<string, ESObject> = { 'context': this.subscription.getContext() };
        this.sendEvent(event, initial);
      })
      .onStopObserving(event, (): void => {
        this.subscription?.remove();
        this.subscription = undefined;
      })
      .onJavaScriptBundleLoaded((): void => {
        if (!this.context.isHeadless) UpdatesReloadScreen.hide(this.context.uiAbilityContext);
      })
      .onContentAppeared((): void => {
        this.controller.contentAppeared(this.context.runtimeId);
        UpdatesReloadScreen.hide(this.context.uiAbilityContext);
      })
      .onDestroy((): void => {
        this.subscription?.remove();
        this.subscription = undefined;
      });
  }
}

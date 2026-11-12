/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoSharedObjectClassDefinition,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';

import { ExpoFetchRuntime } from './FetchRuntime';
import { FetchInit } from './FetchTypes';
import { NativeRequest } from './NativeRequest';
import { NativeResponse } from './NativeResponse';
import { FETCH_INIT_TYPE, HEADER_PAIRS_TYPE } from './FetchUtils';
import { createBlobData } from './FetchBlob';

export class ExpoFetchModule extends ExpoModule {
  private readonly runtime: ExpoFetchRuntime;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.runtime = new ExpoFetchRuntime(context);
  }

  override definition(): ExpoModuleDefinition {
    const responseClass = new ExpoSharedObjectClassDefinition<NativeResponse>('NativeResponse')
      .construct((context: ExpoModuleContext): NativeResponse => {
        return new NativeResponse(context, this.runtime);
      })
      .asyncFunction(
        'startStreaming',
        ExpoFunction.ownedTyped0(async (response: NativeResponse): Promise<Uint8Array | null> => {
          return await response.startStreaming();
        }).returns(ExpoValueTypes.uint8Array().nullable()),
      )
      .syncFunction(
        'cancelStreaming',
        ExpoFunction.ownedTyped1(ExpoValueTypes.string(), (response: NativeResponse, reason: string): void => response.cancelStreaming(reason)),
      )
      .asyncFunction(
        'arrayBuffer',
        ExpoFunction.ownedTyped0(async (response: NativeResponse): Promise<ArrayBuffer> => response.arrayBuffer()).returns(
          ExpoValueTypes.arrayBuffer(),
        ),
      )
      .asyncFunction(
        'text',
        ExpoFunction.ownedTyped0(async (response: NativeResponse): Promise<string> => response.text()).returns(ExpoValueTypes.string()),
      )
      .property('bodyUsed', ExpoValueTypes.boolean(), (response: NativeResponse): boolean => response.bodyUsed())
      .property('_rawHeaders', HEADER_PAIRS_TYPE, (response: NativeResponse): string[][] => response.rawHeaders())
      .property('status', ExpoValueTypes.number(), (response: NativeResponse): number => response.status())
      .property('statusText', ExpoValueTypes.string(), (response: NativeResponse): string => response.statusText())
      .property('url', ExpoValueTypes.string(), (response: NativeResponse): string => response.url())
      .property('redirected', ExpoValueTypes.boolean(), (response: NativeResponse): boolean => response.redirected())
      .event('didReceiveResponseData', ExpoValueTypes.uint8Array())
      .event('didFailWithError', ExpoValueTypes.string())
      .events(['didComplete', 'readyForJSFinalization']);

    const requestClass = new ExpoSharedObjectClassDefinition<NativeRequest>('NativeRequest')
      .construct(
        ExpoFunction.ownedTyped1(responseClass.valueType(), (context: ExpoModuleContext, response: NativeResponse): NativeRequest => {
          return new NativeRequest(context, this.runtime, response);
        }),
      )
      .asyncFunction(
        'start',
        ExpoFunction.ownedTyped3(
          ExpoValueTypes.string(),
          FETCH_INIT_TYPE,
          ExpoValueTypes.uint8Array().nullable(),
          async (request: NativeRequest, inputUrl: string, init: FetchInit, body: Uint8Array | null): Promise<void> =>
            request.start(inputUrl, init, body),
        ),
      )
      .syncFunction('cancel', (request: NativeRequest): void => request.cancel());

    return new ExpoModuleDefinition()
      .name('ExpoFetchModule')
      .asyncFunction(
        'unstable_createBlobData',
        ExpoFunction.typed1(ExpoValueTypes.uint8Array(), async (data: Uint8Array): Promise<string> => {
          return createBlobData(this.context, data);
        }).returns(ExpoValueTypes.string()),
      )
      .sharedObjectClass(responseClass)
      .sharedObjectClass(requestClass)
      .onDestroy((): void => this.runtime.destroy());
  }
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import {
  UpdatesControllerRegistry, UpdatesStateChangeListener, UpdatesStateChangeSubscription,
} from '@expo-harmony/expo-updates-interface';
import { readJSON } from './JSONUtilsDemo';
import { readManifest } from './ManifestDemo';
import { parseHeader, serializeHeader } from './StructuredHeadersDemo';
import { readImage } from './ImageLoaderDemo';

export class RuntimeDemoModule extends ExpoModule {
  private subscription?: UpdatesStateChangeSubscription;

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('RuntimeDemo')
      .events(['onUpdatesStateChange'])
      .asyncFunction('readImage', ExpoFunction.typed3(
        ExpoValueTypes.string(), ExpoValueTypes.boolean(), ExpoValueTypes.boolean(),
        (uri: string, editing: boolean, callback: boolean): Promise<string> => readImage(this.context, uri, editing, callback)))
      .syncFunction('readJSON', ExpoFunction.typed4(
        ExpoValueTypes.string(), ExpoValueTypes.string(), ExpoValueTypes.string(), ExpoValueTypes.boolean(),
        (input: string, key: string, type: string, nullable: boolean): string => readJSON(input, key, type, nullable)))
      .syncFunction('readManifest', ExpoFunction.typed3(
        ExpoValueTypes.string(), ExpoValueTypes.string(), ExpoValueTypes.string(), readManifest))
      .syncFunction('parseHeader', ExpoFunction.typed3(
        ExpoValueTypes.string(), ExpoValueTypes.string(), ExpoValueTypes.boolean(), parseHeader))
      .syncFunction('serializeHeader', ExpoFunction.typed2(
        ExpoValueTypes.string(), ExpoValueTypes.string(), serializeHeader))
      .syncFunction('readUpdates', ExpoFunction.typed1(
        ExpoValueTypes.string(), (property: string): string => this.readUpdates(property)))
      .onStartObserving((_event: string): void => {
        this.subscription?.remove();
        const forwarder = new UpdatesStateForwarder((event: Record<string, ESObject>): void => {
          const payload: Record<string, ESObject> = { 'event': JSON.stringify(event) };
          this.sendEvent('onUpdatesStateChange', payload);
        });
        this.subscription = UpdatesControllerRegistry.controller?.subscribeToUpdatesStateChanges(forwarder);
      })
      .onStopObserving((_event: string): void => this.stop())
      .onDestroy((): void => this.stop());
  }

  private readUpdates(property: string): string {
    const controller = UpdatesControllerRegistry.controller;
    if (!controller) throw new ExpoModuleError('ERR_DEMO_UPDATES_UNAVAILABLE', 'No Updates controller is registered.');

    switch (property) {
      case 'isEnabled': return JSON.stringify(controller.isEnabled);
      case 'runtimeVersion': return JSON.stringify(controller.runtimeVersion);
      case 'updateUrl': return JSON.stringify(controller.updateUrl);
      case 'requestHeaders': return JSON.stringify(controller.requestHeaders);
      case 'launchedUpdateId': return JSON.stringify(controller.launchedUpdateId);
      case 'embeddedUpdateId': return JSON.stringify(controller.embeddedUpdateId);
      case 'launchAssetPath': return JSON.stringify(controller.launchAssetPath);
      case 'getContext': return JSON.stringify(this.subscription?.getContext() ?? null);
      default: throw new ExpoModuleError('ERR_DEMO_UPDATES_PROPERTY', 'Unknown Updates property.');
    }
  }

  private stop(): void {
    this.subscription?.remove();
    this.subscription = undefined;
  }
}

class UpdatesStateForwarder implements UpdatesStateChangeListener {
  private readonly forward: (event: Record<string, ESObject>) => void;

  constructor(forward: (event: Record<string, ESObject>) => void) {
    this.forward = forward;
  }

  updatesStateDidChange(event: Record<string, ESObject>): void {
    this.forward(event);
  }
}

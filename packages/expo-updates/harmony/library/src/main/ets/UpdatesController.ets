/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type common from '@ohos.app.ability.common';
import bundleManager from '@ohos.bundle.bundleManager';
import { UpdatesControllerRegistry } from '@expo-harmony/expo-updates-interface';
import { IUpdatesController } from './IUpdatesController';
import { EnabledUpdatesController } from './EnabledUpdatesController';
import { DisabledUpdatesController } from './DisabledUpdatesController';
import { UpdatesDevLauncherController } from './UpdatesDevLauncherController';
import { ExpoUpdatesAdapter, ExpoUpdatesDevLauncherAdapter } from './ExpoUpdatesAdapter';
import { UpdatesConfiguration } from './UpdatesConfiguration';
import { decode } from './UpdatesStorage';
import { ExpoUpdatesError, Json } from './UpdatesProtocol';

export class UpdatesController {
  private static readonly controllers = new Map<string, IUpdatesController>();
  private static readonly adapters = new Map<string, ExpoUpdatesAdapter>();
  private static readonly overrides = new Map<string, Json>();

  static get(context: common.ApplicationContext): IUpdatesController {
    return UpdatesController.initialize(context);
  }

  static initialize(context: common.ApplicationContext, development?: boolean): IUpdatesController {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const current = UpdatesController.controllers.get(info.name);
    if (current !== undefined) return current;

    const controller = UpdatesController.initializeWithoutStarting(context, development ?? info.appInfo.debug);
    controller.start();

    return controller;
  }

  static initializeWithoutStarting(context: common.ApplicationContext, development: boolean): IUpdatesController {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const current = UpdatesController.controllers.get(info.name);
    if (current !== undefined) return current;

    const embedded = UpdatesController.readEmbeddedConfiguration(context);
    const configuration = UpdatesController.configuration(embedded, info.name, development);
    const controller: IUpdatesController = configuration.enabled
      ? new EnabledUpdatesController(context, configuration, development, (error: Error): void => {
          const disabled = new DisabledUpdatesController(context, configuration, error);
          UpdatesController.controllers.set(info.name, disabled);
          disabled.start();
        })
      : new DisabledUpdatesController(context, configuration);
    UpdatesController.controllers.set(info.name, controller);
    const adapter = new ExpoUpdatesAdapter(context);
    UpdatesController.adapters.set(info.name, adapter);
    UpdatesControllerRegistry.controller = adapter;

    return controller;
  }

  static initializeAsDevLauncherWithoutStarting(context: common.ApplicationContext): UpdatesDevLauncherController {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const current = UpdatesController.controllers.get(info.name);
    if (current instanceof UpdatesDevLauncherController) {
      UpdatesControllerRegistry.controller = UpdatesController.adapters.get(info.name);
      return current;
    }
    if (current !== undefined)
      throw new ExpoUpdatesError('ERR_UPDATES_INITIALIZATION', 'Initialize the development launcher before initializing Updates.');

    const embedded = UpdatesController.readEmbeddedConfiguration(context);
    const effective = UpdatesController.configuration(embedded, info.name, false);
    const packaged = UpdatesController.overrides.has(info.name)
      ? UpdatesController.parseConfiguration(embedded, false)
      : effective;
    const controller = new UpdatesDevLauncherController(context, effective, packaged.url || null);
    UpdatesController.controllers.set(info.name, controller);
    const adapter = new ExpoUpdatesDevLauncherAdapter(context, controller);
    UpdatesController.adapters.set(info.name, adapter);
    UpdatesControllerRegistry.controller = adapter;

    return controller;
  }

  static overrideConfiguration(context: common.ApplicationContext, value: Json): void {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    if (UpdatesController.controllers.has(info.name))
      throw new ExpoUpdatesError('ERR_UPDATES_INITIALIZATION', 'Override Updates configuration before initializing its controller.');

    try {
      const embedded = UpdatesController.readEmbeddedConfiguration(context);
      const configuration = new UpdatesConfiguration(UpdatesConfiguration.merge(embedded, value), false);
      if (!configuration.enabled) {
        console.warn('Ignoring an invalid Updates configuration override.');
        return;
      }
      UpdatesController.overrides.set(info.name, configuration.raw);
    } catch (error) {
      console.warn(`Ignoring an invalid Updates configuration override: ${String(error)}`);
    }
  }

  private static readEmbeddedConfiguration(context: common.ApplicationContext): Json {
    try {
      return JSON.parse(decode(context.resourceManager.getRawFileContentSync('expo-updates/config.json')));
    } catch (error) {
      console.info(`No embedded Updates configuration: ${String(error)}`);
      return {};
    }
  }

  private static configuration(embedded: Json, name: string, development: boolean): UpdatesConfiguration {
    const override = UpdatesController.overrides.get(name);
    const raw: Json = override === undefined ? embedded : UpdatesConfiguration.merge(embedded, override);
    return UpdatesController.parseConfiguration(raw, development);
  }

  private static parseConfiguration(raw: Json, development: boolean): UpdatesConfiguration {
    try {
      return new UpdatesConfiguration(raw, development);
    } catch (error) {
      console.error(`Invalid embedded Updates configuration: ${String(error)}`);
      return new UpdatesConfiguration({ enabled: false, useNativeDebug: raw?.useNativeDebug === true }, development);
    }
  }
}

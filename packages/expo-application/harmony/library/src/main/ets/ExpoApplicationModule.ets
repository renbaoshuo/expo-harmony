/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { bundleManager } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';

const RESOURCE_INVALID_ID: number = 9001001;
const RESOURCE_NOT_FOUND: number = 9001002;
const MAX_ECMASCRIPT_TIMESTAMP: number = 8_640_000_000_000_000;

export class ExpoApplicationModule extends ExpoModule {
  private cache?: bundleManager.BundleInfo = undefined;
  private pending?: Promise<bundleManager.BundleInfo> = undefined;

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoApplication')
      .constant('applicationName', (): string | null => {
        const info = this.readConstantInfo();
        return info === undefined ? null : resolveApplicationName(this.context, info);
      })
      .constant('applicationId', (): string | null => nonEmptyOrNull(this.readConstantInfo()?.name))
      .constant('nativeApplicationVersion', (): string | null => nonEmptyOrNull(this.readConstantInfo()?.versionName))
      .constant('nativeBuildVersion', (): string | null => {
        const code = this.readConstantInfo()?.versionCode;
        return code !== undefined && Number.isSafeInteger(code) ? String(code) : null;
      })
      .asyncFunction('getInstallationTimeAsync', async (): Promise<number> => {
        const info = await this.readBundleInfo('ERR_APPLICATION_INSTALLATION_TIME', 'installation time');
        return installationTime(info);
      })
      .asyncFunction('getLastUpdateTimeAsync', async (): Promise<number> => {
        const info = await this.readBundleInfo('ERR_APPLICATION_LAST_UPDATE_TIME', 'last update time');
        return checkedTimestamp(info.updateTime, 'last update', 'ERR_APPLICATION_LAST_UPDATE_TIME');
      });
  }

  private readConstantInfo(): bundleManager.BundleInfo | undefined {
    if (this.cache !== undefined) return this.cache;

    try {
      this.cache = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);

      return this.cache;
    } catch (error) {
      this.context.logger.warn(`Unable to read the running Harmony application's constants: ${String(error)}`);

      return undefined;
    }
  }

  private async readBundleInfo(code: string, label: string): Promise<bundleManager.BundleInfo> {
    let pending: Promise<bundleManager.BundleInfo> | undefined;

    try {
      pending = this.pending ?? bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.pending = pending;

      return await pending;
    } catch (error) {
      throw new ExpoModuleError(code, `Unable to read the running Harmony application's ${label}: ${String(error)}`, error as Object);
    } finally {
      if (this.pending === pending) this.pending = undefined;
    }
  }
}

function nonEmptyOrNull(value: string | undefined): string | null {
  return value !== undefined && value.length > 0 ? value : null;
}

function installationTime(info: bundleManager.BundleInfo): number {
  let time: number = info.installTime;

  // Keep the SDK check separate so ArkTS recognizes the API 18 guard.
  if (deviceInfo.sdkApiVersion >= 18) {
    if (info.firstInstallTime !== undefined) {
      time = info.firstInstallTime;
    }
  }

  return checkedTimestamp(time, 'installation', 'ERR_APPLICATION_INSTALLATION_TIME');
}

function checkedTimestamp(time: number, kind: string, code: string): number {
  if (!Number.isSafeInteger(time) || time < 0 || time > MAX_ECMASCRIPT_TIMESTAMP) {
    throw new ExpoModuleError(code, `Harmony returned an invalid ${kind} timestamp.`);
  }

  return time;
}

function literalApplicationLabel(label: string): string | null {
  return label.length === 0 || /^\$string:[A-Za-z0-9_]+$/.test(label) ? null : label;
}

function resolveApplicationName(context: ExpoModuleContext, info: bundleManager.BundleInfo): string | null {
  const resource = info.appInfo.labelResource;
  const local = (resource.bundleName.length === 0 || resource.bundleName === info.name)
    && (resource.moduleName.length === 0 || resource.moduleName === context.uiAbilityContext.currentHapModuleInfo.name);

  if (Number.isSafeInteger(resource.id) && resource.id > 0) {
    // A cross-module ID needs its Resource scope for a synchronous lookup.
    const name = readApplicationNameResource(context, local ? resource.id : resource);
    if (name !== null) return name;
  }

  const id = info.appInfo.labelId;
  if (local && id !== resource.id && Number.isSafeInteger(id) && id > 0) {
    const name = readApplicationNameResource(context, id);
    if (name !== null) return name;
  }

  return literalApplicationLabel(info.appInfo.label);
}

function readApplicationNameResource(context: ExpoModuleContext, resource: number | Resource): string | null {
  try {
    const manager = context.uiAbilityContext.resourceManager;
    return nonEmptyOrNull(typeof resource === 'number' ? manager.getStringSync(resource) : manager.getStringSync(resource));
  } catch (error) {
    const code = (error as BusinessError).code;
    if (code !== RESOURCE_INVALID_ID && code !== RESOURCE_NOT_FOUND) {
      context.logger.warn(`Unable to resolve the running Harmony application's name: ${String(error)}`);
    }

    return null;
  }
}

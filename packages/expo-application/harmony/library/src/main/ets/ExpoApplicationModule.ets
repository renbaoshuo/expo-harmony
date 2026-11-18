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
const RESOURCE_NAME_NOT_FOUND: number = 9001004;
const MAX_ECMASCRIPT_TIMESTAMP: number = 8_640_000_000_000_000;
const STRING_RESOURCE_REFERENCE: RegExp = /^\$string:([A-Za-z0-9_]+)$/;

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
      .constant('nativeBuildVersion', (): string | null => nativeBuildVersion(this.readConstantInfo()))
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

function nativeBuildVersion(info: bundleManager.BundleInfo | undefined): string | null {
  if (info === undefined) return null;

  if (deviceInfo.sdkApiVersion >= 23) {
    const build = nonEmptyOrNull(info.buildVersion);
    if (build !== null) return build;
  }

  const code = info.versionCode;
  return Number.isSafeInteger(code) && code >= 0 ? String(code) : null;
}

function installationTime(info: bundleManager.BundleInfo): number {
  // Keep the SDK check separate so ArkTS recognizes the API 18 guard.
  if (deviceInfo.sdkApiVersion >= 18) {
    const first = info.firstInstallTime;
    if (first !== undefined && isValidTimestamp(first)) return first;
  }

  return checkedTimestamp(info.installTime, 'installation', 'ERR_APPLICATION_INSTALLATION_TIME');
}

function isValidTimestamp(time: number): boolean {
  return Number.isSafeInteger(time) && time >= 0 && time <= MAX_ECMASCRIPT_TIMESTAMP;
}

function checkedTimestamp(time: number, kind: string, code: string): number {
  if (!isValidTimestamp(time)) {
    throw new ExpoModuleError(code, `Harmony returned an invalid ${kind} timestamp.`);
  }

  return time;
}

function resolveApplicationName(context: ExpoModuleContext, info: bundleManager.BundleInfo): string | null {
  const appInfo = info.appInfo;
  const label: Resource | undefined = appInfo.labelResource;
  const currentModule = context.uiAbilityContext.currentHapModuleInfo?.name ?? '';
  const bundleName = label?.bundleName || info.name;
  const moduleName = label?.moduleName || currentModule;
  const local = bundleName === info.name && moduleName === currentModule;

  const resourceId = label?.id;
  const labelId = appInfo.labelId;
  const ids = resourceId === undefined || resourceId === labelId ? [labelId] : [resourceId, labelId];

  for (const id of ids) {
    if (!Number.isSafeInteger(id) || id <= 0) continue;

    // The numeric overload reads within the current HAP. Other HAPs need a scoped synchronous lookup.
    const resource: Resource = { bundleName, moduleName, id };
    const name = local ? readApplicationNameResource(context, id) : readApplicationNameResource(context, resource);
    if (name !== null) return name;
  }

  const reference = STRING_RESOURCE_REFERENCE.exec(appInfo.label);
  if (reference === null) return nonEmptyOrNull(appInfo.label);
  return local ? readApplicationNameResource(context, reference[1]) : null;
}

function readApplicationNameResource(context: ExpoModuleContext, resource: number | Resource | string): string | null {
  try {
    const manager = context.uiAbilityContext.resourceManager;
    if (typeof resource === 'string') return nonEmptyOrNull(manager.getStringByNameSync(resource));

    // ArkTS must resolve the numeric and scoped overloads separately.
    return nonEmptyOrNull(typeof resource === 'number' ? manager.getStringSync(resource) : manager.getStringSync(resource));
  } catch (error) {
    const code = (error as BusinessError).code;
    if (code !== RESOURCE_INVALID_ID && code !== RESOURCE_NOT_FOUND && code !== RESOURCE_NAME_NOT_FOUND) {
      context.logger.warn(`Unable to resolve the running Harmony application's name: ${String(error)}`);
    }

    return null;
  }
}

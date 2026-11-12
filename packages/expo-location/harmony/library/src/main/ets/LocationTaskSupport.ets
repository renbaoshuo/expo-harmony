/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { bundleManager, common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { geoLocationManager } from '@kit.LocationKit';
import { ExpoModuleContext, ExpoModuleError, ExpoPermissionStatus } from '@expo-harmony/expo-modules-core';
import { ExpoTaskManagerBackgroundQueue, ExpoTaskManagerRegistry, ExpoTaskRecord } from '@expo-harmony/expo-task-manager';

export const BACKGROUND_TASK_TYPE: string = 'location';
export const GEOFENCE_TASK_TYPE: string = 'geofencing';
export const FENCE_EXTENSION_NAME: string = 'ExpoLocationFenceExtension';
const BACKGROUND_METADATA: string = 'expo.location.background';
const TASK_EVENT_EXPIRY_MS: number = 60_000;

export function continuousLocationRequest(): backgroundTaskManager.ContinuousTaskRequest {
  const request = new backgroundTaskManager.ContinuousTaskRequest();
  request.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_LOCATION];
  request.backgroundTaskSubmodes = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_NORMAL_NOTIFICATION];

  return request;
}

export function isContinuousLocationSupported(): boolean {
  try {
    return continuousLocationRequest().isModeSupported();
  } catch (_) {
    return false;
  }
}

export function hasBackgroundConfiguration(context: common.UIAbilityContext): boolean {
  if (deviceInfo.sdkApiVersion < 21 || !canIUse('SystemCapability.Location.Location.Core') ||
    !canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask')) return false;

  try {
    const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE | bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_ABILITY |
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_METADATA;
    const bundle = bundleManager.getBundleInfoForSelfSync(flags);
    const module = bundle.hapModulesInfo.find((value: bundleManager.HapModuleInfo): boolean => value.name === context.currentHapModuleInfo.name);
    const ability = module?.abilitiesInfo?.find((value: bundleManager.AbilityInfo): boolean => value.name === context.abilityInfo.name);
    return ability?.metadata?.some((item: bundleManager.Metadata): boolean => item.name === BACKGROUND_METADATA && item.value === 'true') === true;
  } catch (_) {
    return false;
  }
}

export function hasGeofenceConfiguration(context: common.UIAbilityContext): boolean {
  if (deviceInfo.sdkApiVersion < 23 || !canIUse('SystemCapability.Location.Location.Geofence')) return false;

  try {
    const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE | bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_EXTENSION_ABILITY;
    const bundle = bundleManager.getBundleInfoForSelfSync(flags);
    const module = bundle.hapModulesInfo.find((value: bundleManager.HapModuleInfo): boolean => value.name === context.currentHapModuleInfo.name);
    return module?.extensionAbilitiesInfo?.some((value: bundleManager.ExtensionAbilityInfo): boolean =>
      value.name === FENCE_EXTENSION_NAME && value.extensionAbilityType === bundleManager.ExtensionAbilityType.FENCE && value.enabled) === true &&
      geoLocationManager.getGeofenceSupportedCoordTypes().includes(geoLocationManager.CoordinateSystemType.WGS84);
  } catch (_) {
    return false;
  }
}

export function hasLocationTaskPermission(context: ExpoModuleContext, precise: boolean = false): boolean {
  return context.permissionStatus('ohos.permission.APPROXIMATELY_LOCATION') === ExpoPermissionStatus.GRANTED &&
    (!precise || context.permissionStatus('ohos.permission.LOCATION') === ExpoPermissionStatus.GRANTED) &&
    context.permissionStatus('ohos.permission.LOCATION_IN_BACKGROUND') === ExpoPermissionStatus.GRANTED;
}

export function requireLocationTaskPermission(context: ExpoModuleContext, precise: boolean): void {
  if (!hasLocationTaskPermission(context, precise)) {
    throw new ExpoModuleError(
      'ERR_LOCATION_BACKGROUND_UNAUTHORIZED',
      precise ? 'Grant precise location and choose Always allow in system settings.' : 'Grant foreground location and choose Always allow in system settings.',
    );
  }
}

export async function isLocationTaskRegistered(context: ExpoModuleContext, taskName: string, taskType: string): Promise<boolean> {
  let found = false;
  await ExpoTaskManagerRegistry.withRegisteredTasks(
    context.uiAbilityContext,
    ExpoTaskManagerRegistry.ownerKey(context),
    taskType,
    async (tasks: ExpoTaskRecord[]): Promise<void> => {
      found = tasks.some((task: ExpoTaskRecord): boolean => task.taskName === taskName);
    },
  );
  return found;
}

export async function deliverLocationTask(
  context: common.Context,
  task: ExpoTaskRecord,
  data: ESObject,
  error: ESObject = null,
  expiresAt: number = Date.now() + TASK_EVENT_EXPIRY_MS,
): Promise<void> {
  await ExpoTaskManagerBackgroundQueue.enqueue(
    context, task.ownerKey, task.taskType, expiresAt,
    util.generateRandomUUID(), task.taskName, data, error, true, task.registrationGeneration,
  );
}

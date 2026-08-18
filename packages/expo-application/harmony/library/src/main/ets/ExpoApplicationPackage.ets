import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { ExpoPlatformServiceError, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import bundleManager from '@ohos.bundle.bundleManager';
import deviceInfo from '@ohos.deviceInfo';
import { literalApplicationLabel, selectInstallationTimestamp } from './ApplicationSemantics';

const SERVICE_NAME: string = 'ExpoApplicationService';
let registered: boolean = false;

class ExpoApplicationService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;
  private info?: bundleManager.BundleInfo;
  private promise?: Promise<bundleManager.BundleInfo>;

  constructor(context: UITurboModuleContext) {
    this.context = context;
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (method === 'getInstallationTime') {
      const info = await this.readBundleInfo('ERR_APPLICATION_INSTALLATION_TIME', 'installation time');

      return installationTime(info);
    }

    if (method === 'getLastUpdateTime') {
      const info = await this.readBundleInfo('ERR_APPLICATION_LAST_UPDATE_TIME', 'last update time');

      return checkedTimestamp(info.updateTime, 'last update', 'ERR_APPLICATION_LAST_UPDATE_TIME');
    }

    return this.invokeSync(method, args);
  }

  invokeSync(method: string, args: ESObject[]): ESObject {
    if (method === 'getApplicationName') {
      const info = this.readBundleInfoSync('ERR_APPLICATION_NAME', 'application name');

      return resolveApplicationName(this.context, info);
    }

    if (method === 'getApplicationId') {
      const info = this.readBundleInfoSync('ERR_APPLICATION_ID', 'application ID');

      return nonEmptyOrNull(info.name);
    }

    if (method === 'getNativeApplicationVersion') {
      const info = this.readBundleInfoSync('ERR_APPLICATION_VERSION', 'application version');

      return nonEmptyOrNull(info.versionName);
    }

    if (method === 'getNativeBuildVersion') {
      const info = this.readBundleInfoSync('ERR_APPLICATION_BUILD_VERSION', 'application build version');

      return Number.isFinite(info.versionCode) && Number.isInteger(info.versionCode) ? String(info.versionCode) : null;
    }

    throw new ExpoPlatformServiceError('ERR_APPLICATION_UNKNOWN_METHOD', `Unknown ExpoApplication Harmony method '${method}'.`);
  }

  private readBundleInfoSync(code: string, label: string): bundleManager.BundleInfo {
    if (this.info !== undefined) {
      return this.info;
    }

    try {
      this.info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);

      return this.info;
    } catch (error) {
      throw new ExpoPlatformServiceError(code, `Unable to read the running Harmony application's ${label}: ${String(error)}`);
    }
  }

  private async readBundleInfo(code: string, label: string): Promise<bundleManager.BundleInfo> {
    if (this.info !== undefined) {
      return this.info;
    }

    if (this.promise === undefined) {
      this.promise = bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    }

    try {
      this.info = await this.promise;

      return this.info;
    } catch (error) {
      throw new ExpoPlatformServiceError(code, `Unable to read the running Harmony application's ${label}: ${String(error)}`);
    } finally {
      this.promise = undefined;
    }
  }
}

function nonEmptyOrNull(value: string): string | null {
  return value.length > 0 ? value : null;
}

function installationTime(info: bundleManager.BundleInfo): number {
  return checkedTimestamp(
    selectInstallationTimestamp(deviceInfo.sdkApiVersion, info.firstInstallTime, info.installTime),
    'installation',
    'ERR_APPLICATION_INSTALLATION_TIME',
  );
}

function checkedTimestamp(time: number, kind: string, code: string): number {
  if (!Number.isFinite(time) || time < 0) {
    throw new ExpoPlatformServiceError(code, `Harmony returned an invalid ${kind} timestamp.`);
  }

  return time;
}

function resolveApplicationName(context: UITurboModuleContext, info: bundleManager.BundleInfo): string | null {
  try {
    const resolved = context.uiAbilityContext.resourceManager.getStringSync(info.appInfo.labelResource) as string;
    if (resolved.length > 0) return resolved;
  } catch (_) {
    // Older bundle records and resource overlays may not expose a resolvable
    // Resource object. Retain the numeric and literal fallbacks below.
  }

  const labelId = info.appInfo.labelId;
  if (Number.isSafeInteger(labelId) && labelId > 0) {
    try {
      const resolved = context.uiAbilityContext.resourceManager.getStringSync(labelId) as string;
      if (resolved.length > 0) return resolved;
    } catch (_) {
      // Fall through to the literal label. Some bundles expose labels from a
      // resource overlay that is not addressable through the current module.
    }
  }

  return literalApplicationLabel(info.appInfo.label);
}

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new ExpoApplicationService(context),
  });

  registered = true;
}

export class ExpoApplicationPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerService();
    super(context);
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-application';
  }
}

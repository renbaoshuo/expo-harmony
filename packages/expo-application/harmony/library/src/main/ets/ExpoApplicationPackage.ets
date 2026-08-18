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
  private bundleInfo?: bundleManager.BundleInfo;
  private bundleInfoPromise?: Promise<bundleManager.BundleInfo>;

  constructor(context: UITurboModuleContext) {
    this.context = context;
  }

  async invoke(methodName: string, argumentsValue: ESObject[]): Promise<ESObject> {
    if (methodName === 'getInstallationTime') {
      const info = await this.readBundleInfo('ERR_APPLICATION_INSTALLATION_TIME', 'installation time');
      return installationTime(info);
    }
    if (methodName === 'getLastUpdateTime') {
      const info = await this.readBundleInfo('ERR_APPLICATION_LAST_UPDATE_TIME', 'last update time');
      return checkedTimestamp(info.updateTime, 'last update', 'ERR_APPLICATION_LAST_UPDATE_TIME');
    }
    return this.invokeSync(methodName, argumentsValue);
  }

  invokeSync(methodName: string, _: ESObject[]): ESObject {
    if (methodName === 'getApplicationName') {
      const info = this.readBundleInfoSync('ERR_APPLICATION_NAME', 'application name');
      return resolveApplicationName(this.context, info);
    }
    if (methodName === 'getApplicationId') {
      const info = this.readBundleInfoSync('ERR_APPLICATION_ID', 'application ID');
      return nonEmptyOrNull(info.name);
    }
    if (methodName === 'getNativeApplicationVersion') {
      const info = this.readBundleInfoSync('ERR_APPLICATION_VERSION', 'application version');
      return nonEmptyOrNull(info.versionName);
    }
    if (methodName === 'getNativeBuildVersion') {
      const info = this.readBundleInfoSync('ERR_APPLICATION_BUILD_VERSION', 'application build version');
      return Number.isFinite(info.versionCode) && Number.isInteger(info.versionCode) ? String(info.versionCode) : null;
    }
    throw new ExpoPlatformServiceError('ERR_APPLICATION_UNKNOWN_METHOD', `Unknown ExpoApplication Harmony method '${methodName}'.`);
  }

  private readBundleInfoSync(errorCode: string, valueName: string): bundleManager.BundleInfo {
    if (this.bundleInfo !== undefined) return this.bundleInfo;
    try {
      this.bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      return this.bundleInfo;
    } catch (error) {
      throw bundleInfoError(errorCode, valueName, error);
    }
  }

  private async readBundleInfo(errorCode: string, valueName: string): Promise<bundleManager.BundleInfo> {
    if (this.bundleInfo !== undefined) {
      return this.bundleInfo;
    }
    if (this.bundleInfoPromise === undefined) {
      this.bundleInfoPromise = bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    }
    try {
      this.bundleInfo = await this.bundleInfoPromise;
      return this.bundleInfo;
    } catch (error) {
      throw bundleInfoError(errorCode, valueName, error);
    } finally {
      this.bundleInfoPromise = undefined;
    }
  }
}

function bundleInfoError(errorCode: string, valueName: string, error: Object): ExpoPlatformServiceError {
  return new ExpoPlatformServiceError(errorCode, `Unable to read the running Harmony application's ${valueName}: ${String(error)}`);
}

function nonEmptyOrNull(value: string): string | null {
  return value.length > 0 ? value : null;
}

function installationTime(info: bundleManager.BundleInfo): number {
  return checkedTimestamp(
    selectInstallationTimestamp(deviceInfo.sdkApiVersion, info.firstInstallTime, info.installTime),
    'installation', 'ERR_APPLICATION_INSTALLATION_TIME',
  );
}

function checkedTimestamp(value: number, kind: string, errorCode: string): number {
  if (!Number.isFinite(value) || value < 0) {
    throw new ExpoPlatformServiceError(errorCode, `Harmony returned an invalid ${kind} timestamp.`);
  }
  return value;
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

import { ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import bundleManager from '@ohos.bundle.bundleManager';
import deviceInfo from '@ohos.deviceInfo';
import { BusinessError } from '@kit.BasicServicesKit';

const RESOURCE_INVALID_ID: number = 9001001;
const RESOURCE_NOT_FOUND: number = 9001002;
const MAX_ECMASCRIPT_TIMESTAMP: number = 8_640_000_000_000_000;

export class ExpoApplicationModule extends ExpoModule {
  private constantInfo?: bundleManager.BundleInfo = undefined;
  private pendingInfo?: Promise<bundleManager.BundleInfo> = undefined;

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
        const versionCode = this.readConstantInfo()?.versionCode;
        return versionCode !== undefined && Number.isSafeInteger(versionCode) ? String(versionCode) : null;
      })
      .asyncFunction('getInstallationTimeAsync', async (): Promise<number> => {
        const current = await this.readBundleInfo('ERR_APPLICATION_INSTALLATION_TIME', 'installation time');
        return installationTime(current);
      })
      .asyncFunction('getLastUpdateTimeAsync', async (): Promise<number> => {
        const current = await this.readBundleInfo('ERR_APPLICATION_LAST_UPDATE_TIME', 'last update time');
        return checkedTimestamp(current.updateTime, 'last update', 'ERR_APPLICATION_LAST_UPDATE_TIME');
      });
  }

  private readConstantInfo(): bundleManager.BundleInfo | undefined {
    if (this.constantInfo !== undefined) return this.constantInfo;
    try {
      this.constantInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      return this.constantInfo;
    } catch (error) {
      this.context.logger.warn(`Unable to read the running Harmony application's constants: ${String(error)}`);
      return undefined;
    }
  }

  private async readBundleInfo(code: string, label: string): Promise<bundleManager.BundleInfo> {
    try {
      if (this.pendingInfo === undefined) {
        this.pendingInfo = bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      }
      return await this.pendingInfo;
    } catch (error) {
      throw new ExpoModuleError(code, `Unable to read the running Harmony application's ${label}: ${String(error)}`, error as Object);
    } finally {
      this.pendingInfo = undefined;
    }
  }
}

function nonEmptyOrNull(value: string | undefined): string | null {
  return value !== undefined && value.length > 0 ? value : null;
}

function installationTime(info: bundleManager.BundleInfo): number {
  let time = info.installTime;
  // ArkTS requires the literal API level here to narrow firstInstallTime safely.
  if (deviceInfo.apiAvailable(18) && info.firstInstallTime !== undefined) {
    time = info.firstInstallTime;
  }
  return checkedTimestamp(time, 'installation', 'ERR_APPLICATION_INSTALLATION_TIME');
}

function checkedTimestamp(time: number, kind: string, code: string): number {
  if (!Number.isSafeInteger(time) || time < 0 || time > MAX_ECMASCRIPT_TIMESTAMP) {
    throw new ExpoModuleError(code, `Harmony returned an invalid ${kind} timestamp.`);
  }
  return time;
}

export function literalApplicationLabel(label: string): string | null {
  return label.length === 0 || /^\$string:[A-Za-z_][A-Za-z0-9_]*$/.test(label) ? null : label;
}

function resolveApplicationName(context: ExpoModuleContext, info: bundleManager.BundleInfo): string | null {
  try {
    const resolved = context.uiAbilityContext.resourceManager.getStringSync(info.appInfo.labelResource) as string;
    if (resolved.length > 0) return resolved;
  } catch (error) {
    if (!isMissingResource(error)) {
      throw new ExpoModuleError(
        'ERR_APPLICATION_NAME',
        `Unable to resolve the running Harmony application's name: ${String(error)}`,
        error as Object,
      );
    }
  }

  const labelId = info.appInfo.labelId;
  if (Number.isSafeInteger(labelId) && labelId > 0) {
    try {
      const resolved = context.uiAbilityContext.resourceManager.getStringSync(labelId) as string;
      if (resolved.length > 0) return resolved;
    } catch (error) {
      if (!isMissingResource(error)) {
        throw new ExpoModuleError(
          'ERR_APPLICATION_NAME',
          `Unable to resolve the running Harmony application's name: ${String(error)}`,
          error as Object,
        );
      }
    }
  }
  return literalApplicationLabel(info.appInfo.label);
}

function isMissingResource(error: Object): boolean {
  const code = (error as BusinessError).code;
  return code === RESOURCE_INVALID_ID || code === RESOURCE_NOT_FOUND;
}

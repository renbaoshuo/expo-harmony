import { ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import bundleManager from '@ohos.bundle.bundleManager';
import deviceInfo from '@ohos.deviceInfo';
import util from '@ohos.util';
import webview from '@ohos.web.webview';
import window from '@ohos.window';

const APP_CONFIG_RAW_FILE: string = 'app.config';

class HarmonyPlatformConstants {
  bundleName: string;
  versionName: string;
  versionCode: number;
  deviceType: string;
  apiVersion: number;
  osFullName: string;

  constructor(bundleName: string, versionName: string, versionCode: number, deviceType: string, apiVersion: number, osFullName: string) {
    this.bundleName = bundleName;
    this.versionName = versionName;
    this.versionCode = versionCode;
    this.deviceType = deviceType;
    this.apiVersion = apiVersion;
    this.osFullName = osFullName;
  }
}

class PlatformConstants {
  harmony: HarmonyPlatformConstants;

  constructor(harmony: HarmonyPlatformConstants) {
    this.harmony = harmony;
  }
}

export class ExpoConstantsModule extends ExpoModule {
  private readonly sessionId: string = util.generateRandomUUID();

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExponentConstants')
      .constant('appOwnership', null)
      .constant('debugMode', (): boolean => this.context.isDebug)
      .constant('deviceName', deviceName())
      .constant('deviceYearClass', null)
      .constant('executionEnvironment', 'bare')
      .constant('isHeadless', false)
      .constant('manifest', (): string | null => this.readAppConfig())
      .constant('manifest2', null)
      .constant('sessionId', this.sessionId)
      .constant('statusBarHeight', (): number => this.readStatusBarHeight())
      .constant('systemFonts', (): string[] => this.readSystemFonts())
      .constant('systemVersion', systemVersion())
      .constant('platform', (): PlatformConstants => this.readPlatformConstants())
      .asyncFunction('getWebViewUserAgentAsync', async (): Promise<string | null> => {
        try {
          return webview.WebviewController.getDefaultUserAgent();
        } catch (error) {
          this.context.logger.warn(`Unable to read the default Harmony WebView user agent: ${String(error)}`);
          return null;
        }
      });
  }

  private readAppConfig(): string | null {
    let rawFiles: string[];
    try {
      rawFiles = this.context.uiAbilityContext.resourceManager.getRawFileListSync('');
    } catch (error) {
      throw new ExpoModuleError('ERR_CONSTANTS_APP_CONFIG_READ_FAILED', 'Unable to enumerate embedded HarmonyOS raw files.', error as Object);
    }
    if (!rawFiles.includes(APP_CONFIG_RAW_FILE)) return null;

    let bytes: Uint8Array;
    try {
      bytes = this.context.uiAbilityContext.resourceManager.getRawFileContentSync(APP_CONFIG_RAW_FILE);
    } catch (error) {
      throw new ExpoModuleError('ERR_CONSTANTS_APP_CONFIG_READ_FAILED', 'Unable to read the embedded Expo app config.', error as Object);
    }

    let value: ESObject;
    try {
      value = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes));
    } catch (error) {
      throw new ExpoModuleError('ERR_CONSTANTS_INVALID_APP_CONFIG', 'The embedded Expo app config is invalid JSON.', error as Object);
    }

    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw new ExpoModuleError('ERR_CONSTANTS_INVALID_APP_CONFIG', 'The embedded Expo app config must be a JSON object.');
    }
    return JSON.stringify(value);
  }

  private readStatusBarHeight(): number {
    try {
      const stage = this.context.uiAbilityContext.windowStage;
      const mainWindow = stage.getMainWindowSync();
      const area = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const height = mainWindow.getUIContext().px2vp(area.topRect.height);
      return Number.isFinite(height) && height >= 0 ? height : 0;
    } catch (error) {
      this.context.logger.warn(`Unable to read the HarmonyOS status bar height; using 0: ${String(error)}`);
      return 0;
    }
  }

  private readSystemFonts(): string[] {
    try {
      const names = this.context.uiAbilityContext.windowStage.getMainWindowSync().getUIContext().getFont().getSystemFontList();
      const unique = new Set<string>();
      names.forEach((name: string): void => {
        if (name.length > 0) unique.add(name);
      });
      return Array.from(unique).sort();
    } catch (error) {
      this.context.logger.warn(`Unable to enumerate HarmonyOS system fonts; returning an empty list: ${String(error)}`);
      return [];
    }
  }

  private readPlatformConstants(): PlatformConstants {
    let bundleName: string;
    let versionName: string;
    let versionCode: number;
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      bundleName = info.name;
      versionName = info.versionName;
      versionCode = info.versionCode;
    } catch (error) {
      throw new ExpoModuleError('ERR_CONSTANTS_PLATFORM_INFO', 'Unable to read HarmonyOS bundle information.', error as Object);
    }
    if (bundleName.length === 0 || versionName.length === 0 || !Number.isSafeInteger(versionCode)) {
      throw new ExpoModuleError('ERR_CONSTANTS_PLATFORM_INFO', 'HarmonyOS returned invalid bundle information.');
    }

    return new PlatformConstants(
      new HarmonyPlatformConstants(bundleName, versionName, versionCode, deviceInfo.deviceType, deviceInfo.sdkApiVersion, deviceInfo.osFullName),
    );
  }
}

function deviceName(): string {
  if (deviceInfo.marketName.length > 0) return deviceInfo.marketName;
  if (deviceInfo.productModel.length > 0) return deviceInfo.productModel;
  if (deviceInfo.deviceType.length > 0) return `HarmonyOS ${deviceInfo.deviceType}`;
  return 'HarmonyOS device';
}

function systemVersion(): string {
  return deviceInfo.displayVersion;
}

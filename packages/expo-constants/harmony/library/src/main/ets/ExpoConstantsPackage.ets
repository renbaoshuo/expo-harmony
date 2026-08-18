import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { ExpoPlatformServiceError, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import window from '@ohos.window';
import webview from '@ohos.web.webview';

const SERVICE_NAME: string = 'ExpoConstantsService';
let registered: boolean = false;

class ExpoConstantsService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;
  private readonly statusBarHeight: number;

  private constructor(context: UITurboModuleContext, statusBarHeight: number) {
    this.context = context;
    this.statusBarHeight = statusBarHeight;
  }

  static async create(context: UITurboModuleContext): Promise<ExpoConstantsService> {
    return new ExpoConstantsService(context, await readInitialStatusBarHeight(context));
  }

  invokeSync(method: string, _: ESObject[]): ESObject {
    if (method !== 'getStatusBarHeight') {
      throw new ExpoPlatformServiceError('ERR_CONSTANTS_UNKNOWN_METHOD', `Unknown synchronous constants method '${method}'.`);
    }

    return this.statusBarHeight;
  }

  async invoke(method: string, _: ESObject[]): Promise<ESObject> {
    if (method !== 'getWebViewUserAgent') {
      throw new ExpoPlatformServiceError('ERR_CONSTANTS_UNKNOWN_METHOD', `Unknown constants method '${method}'.`);
    }

    try {
      const agent = webview.WebviewController.getDefaultUserAgent();

      return agent;
    } catch (error) {
      this.context.logger.warn(`Unable to read the default Harmony WebView user agent: ${String(error)}`);

      return null;
    }
  }
}

async function readInitialStatusBarHeight(context: UITurboModuleContext): Promise<number> {
  try {
    await context.safeAreaInsetsProvider.ready;

    const win = await window.getLastWindow(context.uiAbilityContext);
    const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);

    const height = win.getUIContext().px2vp(area.topRect.height);

    return Number.isFinite(height) && height >= 0 ? height : 0;
  } catch (error) {
    context.logger.warn(`Unable to read the initial Harmony status bar height: ${String(error)}`);

    return 0;
  }
}

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => ExpoConstantsService.create(context),
  });

  registered = true;
}

export class ExpoConstantsPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerService();

    super(context);
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-constants';
  }
}

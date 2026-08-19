import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import type common from '@ohos.app.ability.common';
import { ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';

import {
  bindSplashScreenServiceRuntime,
  destroySplashScreenAbility,
  endSplashScreenRuntime,
  ExpoSplashScreenError,
  findSplashScreenRuntime,
  prepareSplashScreenRuntimeReload,
  SplashScreenRuntimeOwner,
} from './SplashScreenLifecycle';

const SERVICE_NAME: string = 'ExpoSplashScreenService';

class ExpoSplashScreenService {
  readonly name: string = SERVICE_NAME;
  private readonly id: number;
  private readonly ability: common.UIAbilityContext;
  private owner: SplashScreenRuntimeOwner | undefined;
  private unsubscribe: (() => void) | undefined = undefined;
  private destroyed: boolean = false;

  constructor(context: UITurboModuleContext) {
    this.id = context.rnInstance.getId();
    this.ability = context.uiAbilityContext;

    this.owner = bindSplashScreenServiceRuntime(context.uiAbilityContext, this.id);

    this.unsubscribe = context.devToolsController.eventEmitter.subscribe('RELOAD', (): void => {
      if (this.destroyed) return;

      try {
        prepareSplashScreenRuntimeReload(this.id);
      } catch (error) {
        context.logger.warn(`Unable to re-arm the Expo splash screen during reload: ${String(error)}`);
      }
    });
  }

  onDestroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.unsubscribeFromReload();
    endSplashScreenRuntime(this.id);
    this.owner = undefined;
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    const owner = this.resolveOwner();

    if (method === 'preventAutoHideAsync') {
      return owner?.prevent(true) ?? true;
    }
    if (method === 'internalPreventAutoHideAsync') {
      owner?.prevent(false);
      return null;
    }
    if (method === 'hideAsync') {
      owner?.hide();
      return null;
    }
    if (method === 'internalMaybeHideAsync') {
      owner?.internalMaybeHide();
      return null;
    }

    return this.invokeSync(method, args);
  }

  invokeSync(method: string, args: ESObject[]): ESObject {
    const owner = this.resolveOwner();

    if (method === 'getRuntimeId') {
      return this.id;
    }
    if (method === 'isAbilityDestroyed') {
      return owner?.isDestroyed() ?? true;
    }
    if (method === 'setOptions') {
      owner?.setOptions(Number(args[0]), Boolean(args[1]));
      return null;
    }
    if (method === 'hide') {
      owner?.hide();
      return null;
    }
    if (method === 'contentAppeared') {
      owner?.contentAppeared();
      return null;
    }
    if (method === 'runtimeWillDestroy') {
      this.onDestroy();
      return null;
    }
    if (method === 'abilityWillDestroy') {
      this.onDestroy();
      destroySplashScreenAbility(this.ability);
      return null;
    }

    throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_UNKNOWN_METHOD', `Unknown Expo splash screen service method '${method}'.`);
  }

  prepareForReload(): void {
    if (this.destroyed) return;
    prepareSplashScreenRuntimeReload(this.id);
  }

  private resolveOwner(): SplashScreenRuntimeOwner | undefined {
    if (this.destroyed) return undefined;
    return this.owner ?? findSplashScreenRuntime(this.id);
  }

  private unsubscribeFromReload(): void {
    const unsubscribe = this.unsubscribe;

    this.unsubscribe = undefined;
    if (unsubscribe !== undefined) unsubscribe();
  }
}

let registered: boolean = false;

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new ExpoSplashScreenService(context),
  });

  registered = true;
}

export class ExpoSplashScreenPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    super(context);
    registerService();
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-splash-screen';
  }
}

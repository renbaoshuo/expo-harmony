import { EtsUITurboModule, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { abilityAccessCtrl, PermissionRequestResult, Permissions, Want } from '@kit.AbilityKit';
import { ExpoLifecycleDispatcher } from './appcontext/LifecycleDispatcher';
import { ExpoPlatformServiceRegistry } from './services/PlatformService';
import type { ExpoPlatformServiceResult } from './services/PlatformService';
import { EXPO_LIFECYCLE_DESTROY, EXPO_LIFECYCLE_BACKGROUND, EXPO_LIFECYCLE_EVENT, EXPO_LIFECYCLE_FOREGROUND } from './protocol/Protocol';

export interface ExpoAbilityResult {
  resultCode: number;
  want?: Want;
}

export interface ExpoRawFileDescriptor {
  fd: number;
  offset: number;
  length: number;
}

/**
 * Copy-value-only platform adapter for the C++ Expo Modules runtime.
 * Module definitions, bodies and JSI wrappers intentionally do not live here.
 */
export class ExpoModulesCoreTurboModule extends EtsUITurboModule {
  static readonly NAME: string = 'ExpoModulesCore';
  private readonly unsubscribeLifecycle: (() => void)[] = [];
  private readonly coreContext: UITurboModuleContext;
  private readonly platformServices: ExpoPlatformServiceRegistry;

  static async create(coreContext: UITurboModuleContext): Promise<ExpoModulesCoreTurboModule> {
    const platformServices = await ExpoPlatformServiceRegistry.createScope(coreContext);
    return new ExpoModulesCoreTurboModule(coreContext, platformServices);
  }

  constructor(coreContext: UITurboModuleContext, platformServices: ExpoPlatformServiceRegistry) {
    super(coreContext);
    this.coreContext = coreContext;
    this.platformServices = platformServices;
    this.unsubscribeLifecycle.push(
      ExpoLifecycleDispatcher.register(this),
      coreContext.rnInstance.subscribeToLifecycleEvents('FOREGROUND', () => this.postLifecycleEvent(EXPO_LIFECYCLE_FOREGROUND)),
      coreContext.rnInstance.subscribeToLifecycleEvents('BACKGROUND', () => this.postLifecycleEvent(EXPO_LIFECYCLE_BACKGROUND)),
    );
  }

  getCacheDirectory(): string {
    return ensureDirectoryUri(this.coreContext.uiAbilityContext.cacheDir);
  }

  getDocumentsDirectory(): string {
    return ensureDirectoryUri(this.coreContext.uiAbilityContext.filesDir);
  }

  getTemporaryDirectory(): string {
    return ensureDirectoryUri(this.coreContext.uiAbilityContext.tempDir);
  }

  getRawFileList(path: string): string[] {
    return this.coreContext.uiAbilityContext.resourceManager.getRawFileListSync(path);
  }

  getRawFileDescriptor(path: string): ExpoRawFileDescriptor {
    const descriptor = this.coreContext.uiAbilityContext.resourceManager.getRawFdSync(path);
    return {
      fd: descriptor.fd,
      offset: descriptor.offset,
      length: descriptor.length,
    };
  }

  closeRawFileDescriptor(path: string): void {
    this.coreContext.uiAbilityContext.resourceManager.closeRawFdSync(path);
  }

  getRuntimeId(): number {
    return this.coreContext.rnInstance.getId();
  }

  async reloadAppAsync(_reason: string): Promise<void> {
    await this.platformServices.prepareForReload();
    await this.coreContext.reloadRNInstance(this.coreContext.rnInstance);
  }

  async requestPermissions(permissions: string[]): Promise<PermissionRequestResult> {
    return abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.coreContext.uiAbilityContext, permissions as Permissions[]);
  }

  async startAbilityForResult(want: Want, requestCode: number = 0): Promise<ExpoAbilityResult> {
    const result = await this.coreContext.uiAbilityContext.startAbilityForResult(want);
    const abilityResult: ExpoAbilityResult = {
      resultCode: result.resultCode,
      want: result.want,
    };
    ExpoLifecycleDispatcher.onActivityResult(requestCode, abilityResult);
    return abilityResult;
  }

  async invokePlatformService(serviceName: string, methodName: string, argumentsValue: ESObject[]): Promise<ExpoPlatformServiceResult> {
    return await this.platformServices.invoke(serviceName, methodName, argumentsValue);
  }

  invokePlatformServiceSync(serviceName: string, methodName: string, argumentsValue: ESObject[]): ExpoPlatformServiceResult {
    return this.platformServices.invokeSync(serviceName, methodName, argumentsValue);
  }

  override __onDestroy__(): void {
    this.platformServices.destroyScope();
    this.postLifecycleEvent(EXPO_LIFECYCLE_DESTROY);
    this.unsubscribeLifecycle.forEach((unsubscribe) => unsubscribe());
    this.unsubscribeLifecycle.length = 0;
  }

  postLifecycleEvent(eventName: string, payload?: ESObject): void {
    this.coreContext.rnInstance.postMessageToCpp(EXPO_LIFECYCLE_EVENT, {
      eventName,
      payload,
    });
  }
}

function ensureDirectoryUri(path: string): string {
  const value = path.startsWith('file://') ? path : `file://${path}`;
  return value.endsWith('/') ? value : `${value}/`;
}

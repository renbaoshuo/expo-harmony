import { bundleManager, common, Want } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';

import { createWant, INTENT_PARAMS } from './IntentLauncherParams';

const BUNDLE_NOT_FOUND: number = 17700001;
const LAUNCH_BUNDLE_FLAGS: number =
  bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE |
  bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_ABILITY |
  bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_EXTENSION_ABILITY |
  bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_SKILL;
const HOME_ACTIONS: string[] = ['action.system.home', 'ohos.want.action.home'];
const HOME_ENTITY: string = 'entity.system.home';
const PNG_MIME_TYPE: string = 'image/png';

interface IntentLauncherResult {
  resultCode: number;
  data?: string;
  extra?: Record<string, Object>;
}

export class ExpoIntentLauncherModule extends ExpoModule {
  private pending: boolean = false;
  private destroyed: boolean = false;
  private cancel?: () => void;

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoIntentLauncher')
      .asyncFunction(
        'startActivity',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          INTENT_PARAMS,
          (action: string, params: Record<string, ESObject>): Promise<IntentLauncherResult> => this.startActivity(action, params),
        ),
      )
      .syncFunction(
        'openApplication',
        ExpoFunction.typed1(ExpoValueTypes.string(), (bundle: string): void => this.openApplication(bundle)),
      )
      .asyncFunction(
        'getApplicationIcon',
        ExpoFunction.typed1(ExpoValueTypes.string(), (bundle: string): Promise<string> => this.getApplicationIcon(bundle)),
      )
      .onAbilityDestroy((): void => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private async startActivity(action: string, params: Record<string, ESObject>): Promise<IntentLauncherResult> {
    this.assertActive();
    if (this.pending) {
      throw new ExpoModuleError(
        'E_ACTIVITY_ALREADY_STARTED',
        'IntentLauncher activity is already started. You need to wait for its result before starting another activity.',
      );
    }

    const want = createWant(action, params, this.context.uiAbilityContext.abilityInfo.bundleName);
    const cancellation = new Promise<common.AbilityResult>((_resolve, reject): void => {
      this.cancel = (): void =>
        reject(new ExpoModuleError('ERR_INTENT_LAUNCHER_DESTROYED', 'The IntentLauncher host was destroyed while an activity was open.'));
    });
    this.pending = true;

    try {
      const response = await Promise.race([this.context.uiAbilityContext.startAbilityForResult(want), cancellation]);
      this.assertActive();

      const result: IntentLauncherResult = { resultCode: response.resultCode };
      if (response.want?.uri !== undefined) result.data = response.want.uri;
      if (response.want?.parameters !== undefined) result.extra = response.want.parameters;

      return result;
    } catch (error) {
      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }

      const cause = error as BusinessError;
      throw new ExpoModuleError(
        'ERR_INTENT_LAUNCHER_START_ACTIVITY',
        `Unable to start the requested ability. ${cause.code}: ${cause.message}`,
        error,
      );
    } finally {
      this.pending = false;
      this.cancel = undefined;
    }
  }

  private openApplication(bundle: string): void {
    this.assertActive();

    // Completion can arrive after Core invalidates this.context.
    const logger = this.context.logger;
    let want: Want;
    try {
      const info = bundleManager.getBundleInfoSync(bundle, LAUNCH_BUNDLE_FLAGS);
      want = applicationWant(info);
    } catch (error) {
      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }

      const cause = error as BusinessError;
      if (cause.code === BUNDLE_NOT_FOUND) {
        throw new ExpoModuleError('ERR_PACKAGE_NOT_FOUND', `Package not found: ${bundle}`, error);
      }
      throw new ExpoModuleError('ERR_INTENT_LAUNCHER_BUNDLE_INFO', `Unable to query application '${bundle}'. ${cause.code}: ${cause.message}`, error);
    }

    try {
      this.context.uiAbilityContext.startAbility(want).catch((error: BusinessError): void => {
        logger.warn(`Unable to open application '${bundle}': ${error.code}: ${error.message}`);
      });
    } catch (error) {
      const cause = error as BusinessError;
      throw new ExpoModuleError(
        'ERR_INTENT_LAUNCHER_OPEN_APPLICATION',
        `Unable to open application '${bundle}'. ${cause.code}: ${cause.message}`,
        error,
      );
    }
  }

  private async getApplicationIcon(bundle: string): Promise<string> {
    this.assertActive();

    const logger = this.context.logger;
    let info: bundleManager.BundleInfo;
    try {
      info = await bundleManager.getBundleInfo(bundle, bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    } catch (error) {
      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }

      const cause = error as BusinessError;
      if (cause.code === BUNDLE_NOT_FOUND) {
        throw new ExpoModuleError('ERR_PACKAGE_NOT_FOUND', `Package not found: ${bundle}`, error);
      }
      throw new ExpoModuleError('ERR_INTENT_LAUNCHER_BUNDLE_INFO', `Unable to query application '${bundle}'. ${cause.code}: ${cause.message}`, error);
    }

    this.assertActive();
    let pixels: image.PixelMap | undefined;
    let packer: image.ImagePacker | undefined;
    try {
      const descriptor = this.context.uiAbilityContext.resourceManager.getDrawableDescriptor(info.appInfo.iconResource);
      pixels = descriptor.getPixelMap();

      packer = image.createImagePacker();
      const bytes = await packer.packToData(pixels, { format: PNG_MIME_TYPE, quality: 100 });
      const base64 = await new util.Base64Helper().encodeToString(new Uint8Array(bytes));

      this.assertActive();
      return `data:${PNG_MIME_TYPE};base64,${base64}`;
    } catch (error) {
      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }

      logger.warn(`Unable to encode application '${bundle}' icon: ${String(error)}`);
      return '';
    } finally {
      try {
        await packer?.release();
      } catch (error) {
        logger.warn(`Unable to release the icon packer: ${String(error)}`);
      }

      try {
        await pixels?.release();
      } catch (error) {
        logger.warn(`Unable to release the icon PixelMap: ${String(error)}`);
      }
    }
  }

  private assertActive(): void {
    if (this.destroyed) throw new ExpoModuleError('ERR_INTENT_LAUNCHER_DESTROYED', 'The IntentLauncher host was destroyed.');
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.cancel?.();
    this.cancel = undefined;
  }
}

function applicationWant(info: bundleManager.BundleInfo): Want {
  let first: Want | undefined;
  for (const module of info.hapModulesInfo) {
    if (module.type !== bundleManager.ModuleType.ENTRY) continue;
    for (const ability of module.abilitiesInfo) {
      if (!ability.exported || !ability.enabled) continue;
      const skill = ability.skills.find(
        (candidate: bundleManager.Skill): boolean =>
          candidate.entities.includes(HOME_ENTITY) && candidate.actions.some((action: string): boolean => HOME_ACTIONS.includes(action)),
      );
      if (skill === undefined) continue;

      const want: Want = {
        bundleName: info.name,
        moduleName: module.name,
        abilityName: ability.name,
        action: skill.actions.find((action: string): boolean => HOME_ACTIONS.includes(action)),
        entities: [HOME_ENTITY],
      };

      if (ability.name === module.mainElementName) return want;
      if (first === undefined) first = want;
    }
  }

  if (first !== undefined) return first;
  throw new ExpoModuleError('ERR_PACKAGE_NOT_FOUND', `Package has no exported, enabled launcher UIAbility: ${info.name}`);
}

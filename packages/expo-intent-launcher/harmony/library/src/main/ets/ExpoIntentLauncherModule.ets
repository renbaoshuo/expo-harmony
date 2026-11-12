/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { bundleManager, Want } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { ExpoFunction, ExpoModule, ExpoModuleAbilityResult, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';

import { createWant, INTENT_PARAMS } from './IntentLauncherParams';

const REQUEST_CODE: number = 12;
const BUNDLE_NOT_FOUND: number = 17700001;
const BUNDLE_DISABLED: number = 17700026;
const LAUNCH_WANT_NOT_FOUND: number = 17700072;
const LAUNCH_BUNDLE_FLAGS: number =
  bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE |
  bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_ABILITY |
  bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_EXTENSION_ABILITY |
  bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_SKILL;

// Older HAPs may declare the legacy home action.
const HOME_ACTIONS: string[] = ['action.system.home', 'ohos.want.action.home'];
const HOME_ENTITY: string = 'entity.system.home';
const PNG_MIME_TYPE: string = 'image/png';

interface IntentLauncherResult {
  resultCode: number;
  data?: string;
  extra?: Record<string, Object>;
}

export class ExpoIntentLauncherModule extends ExpoModule {
  private destroyed: boolean = false;
  private cancelPending?: () => void;

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
    if (this.cancelPending !== undefined) {
      throw new ExpoModuleError(
        'E_ACTIVITY_ALREADY_STARTED',
        'IntentLauncher activity is already started. You need to wait for its result before starting another activity.',
      );
    }

    const want = createWant(action, params, this.context.uiAbilityContext.abilityInfo.bundleName);
    const cancellation = new Promise<ExpoModuleAbilityResult>((_resolve, reject): void => {
      this.cancelPending = (): void =>
        reject(new ExpoModuleError('ERR_INTENT_LAUNCHER_DESTROYED', 'The IntentLauncher host was destroyed while an activity was open.'));
    });

    try {
      const response = await Promise.race([this.context.startAbilityForResult(want, REQUEST_CODE), cancellation]);
      this.assertActive();

      const result: IntentLauncherResult = { resultCode: response.resultCode };
      if (response.data?.uri !== undefined) result.data = response.data.uri;
      if (response.data?.parameters !== undefined) result.extra = response.data.parameters;

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
      this.cancelPending = undefined;
    }
  }

  private openApplication(bundle: string): void {
    this.assertActive();

    // Completion can arrive after Core invalidates this.context.
    const logger = this.context.logger;
    let want: Want;

    try {
      want = applicationWant(bundle, this.context.uiAbilityContext.abilityInfo.bundleName);
    } catch (error) {
      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }

      const cause = error as BusinessError;
      if (cause.code === BUNDLE_NOT_FOUND) {
        throw new ExpoModuleError('ERR_PACKAGE_NOT_FOUND', `Package not found: ${bundle}`, error);
      }
      if (cause.code === BUNDLE_DISABLED || cause.code === LAUNCH_WANT_NOT_FOUND) {
        throw new ExpoModuleError('ERR_PACKAGE_NOT_FOUND', `Package has no enabled launcher UIAbility: ${bundle}`, error);
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
      info =
        bundle === this.context.uiAbilityContext.abilityInfo.bundleName
          ? await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
          : await bundleManager.getBundleInfo(bundle, bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    } catch (error) {
      this.assertActive();
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
    let icon = '';

    try {
      const drawable = this.context.uiAbilityContext.resourceManager.getDrawableDescriptor(info.appInfo.iconResource);
      pixels = drawable.getPixelMap();

      packer = image.createImagePacker();
      const bytes = await packer.packToData(pixels, { format: PNG_MIME_TYPE, quality: 100 });
      const base64 = await new util.Base64Helper().encodeToString(new Uint8Array(bytes));

      icon = `data:${PNG_MIME_TYPE};base64,${base64}`;
    } catch (error) {
      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }

      logger.warn(`Unable to encode application '${bundle}' icon: ${String(error)}`);
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

    this.assertActive();

    return icon;
  }

  private assertActive(): void {
    if (this.destroyed) throw new ExpoModuleError('ERR_INTENT_LAUNCHER_DESTROYED', 'The IntentLauncher host was destroyed.');
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.cancelPending?.();
  }
}

function applicationWant(bundle: string, currentBundle: string): Want {
  if (bundle === currentBundle) {
    return bundleManager.getLaunchWant();
  }
  if (deviceInfo.sdkApiVersion >= 24) {
    return bundleManager.getLaunchWantForBundleSync(bundle);
  }

  const info = bundleManager.getBundleInfoSync(bundle, LAUNCH_BUNDLE_FLAGS);
  let entry: Want | undefined;
  let feature: Want | undefined;

  for (const module of info.hapModulesInfo) {
    const isEntry = module.type === bundleManager.ModuleType.ENTRY;
    if (!isEntry && module.type !== bundleManager.ModuleType.FEATURE) continue;

    let candidate: Want | undefined;
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

      if (ability.name === module.mainElementName) {
        if (isEntry) return want;
        candidate = want;
        break;
      }
      candidate ??= want;
    }

    if (isEntry) entry ??= candidate;
    else feature ??= candidate;
  }

  const want = entry ?? feature;
  if (want !== undefined) return want;

  throw new ExpoModuleError('ERR_PACKAGE_NOT_FOUND', `Package has no exported, enabled launcher UIAbility: ${info.name}`);
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import lazy { commentManager } from '@kit.AppGalleryKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { ExpoAppLifecycleState, ExpoModule, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';

const CAPABILITY: string = 'SystemCapability.AppGalleryService.Distribution.Comment';
const COMMENT_DIALOG_OS_API: number = 60000; // HarmonyOS 6.0.0 (API 20), encoded as X * 10000 + Y * 100 + Z.
const APP_GALLERY_DETAIL_URL: string = 'https://appgallery.huawei.com/app/detail';

function isCommentDialogAvailable(): boolean {
  if (deviceInfo.distributionOSApiVersion < COMMENT_DIALOG_OS_API || !canIUse(CAPABILITY)) return false;

  try {
    return typeof commentManager.showCommentDialog === 'function';
  } catch {
    return false;
  }
}

export class ExpoStoreReviewModule extends ExpoModule {
  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoStoreReview')
      .constant('storeUrl', (): string | null => this.storeUrl())
      .asyncFunction('isAvailableAsync', async (): Promise<boolean> => {
        return !this.context.isHeadless && isCommentDialogAvailable();
      })
      .asyncFunction('requestReview', async (): Promise<void> => this.request());
  }

  private storeUrl(): string | null {
    if (this.context.isHeadless) return null;

    const bundle = this.context.uiAbilityContext.applicationInfo.name;

    return bundle ? `${APP_GALLERY_DETAIL_URL}?id=${encodeURIComponent(bundle)}&action=write-review` : null;
  }

  private async request(): Promise<void> {
    if (this.context.isHeadless) {
      throw new ExpoModuleError('ERR_STORE_REVIEW_UNAVAILABLE', 'Store review requires an application interface.');
    }
    if (this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoModuleError('ERR_STORE_REVIEW_BACKGROUND', 'Store review requires a foreground application.');
    }

    const ability = this.context.uiAbilityContext;

    try {
      if (isCommentDialogAvailable()) {
        await commentManager.showCommentDialog(ability);

        return;
      }

      const url = this.storeUrl();

      if (url !== null) {
        await ability.openLink(url, { appLinkingOnly: false });

        return;
      }
    } catch (error) {
      const cause = error as BusinessError;

      throw new ExpoModuleError(
        cause?.code?.toString() || 'ERR_STORE_REVIEW_REQUEST_FAILED',
        cause?.message || 'Failed to request an AppGallery review.',
        cause,
      );
    }

    throw new ExpoModuleError('ERR_STORE_REVIEW_UNAVAILABLE', 'Unable to determine the AppGallery review link.');
  }
}

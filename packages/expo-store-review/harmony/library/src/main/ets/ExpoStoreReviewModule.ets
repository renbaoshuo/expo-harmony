/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { commentManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ExpoAppLifecycleState, ExpoModule, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';

const CAPABILITY: string = 'SystemCapability.AppGalleryService.Distribution.Comment';

export class ExpoStoreReviewModule extends ExpoModule {
  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoStoreReview')
      .asyncFunction('isAvailableAsync', async (): Promise<boolean> => {
        return !this.context.isHeadless && canIUse(CAPABILITY);
      })
      .asyncFunction('requestReview', async (): Promise<void> => this.request());
  }

  private async request(): Promise<void> {
    if (!this.context.isHeadless) {
      // Keep the capability guard at the call site for ArkTS API checking.
      if (canIUse(CAPABILITY)) {
        if (this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
          throw new ExpoModuleError('ERR_STORE_REVIEW_BACKGROUND', 'Store review requires a foreground application.');
        }

        try {
          await commentManager.showCommentDialog(this.context.uiAbilityContext);
        } catch (error) {
          const failure = error as BusinessError;

          throw new ExpoModuleError(
            failure?.code?.toString() || 'ERR_STORE_REVIEW_REQUEST_FAILED',
            failure?.message || 'Failed to request an AppGallery review.',
            error as Object,
          );
        }

        return;
      }
    }

    throw new ExpoModuleError('ERR_STORE_REVIEW_UNAVAILABLE', 'The AppGallery in-app review service is unavailable.');
  }
}

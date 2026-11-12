/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoAbilityLifecycleSubscriber } from '@expo-harmony/expo-modules-core';
import { window } from '@kit.ArkUI';

const StatusBarStyleMetadata = 'expo.harmony.statusBar.style';
const StatusBarHiddenMetadata = 'expo.harmony.statusBar.hidden';

export class ExpoStatusBarLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  override async onWindowSetup(target: window.Window): Promise<void> {
    const metadata = this.context.currentHapModuleInfo.metadata;
    const style = metadata?.find(item => item.name === StatusBarStyleMetadata)?.value;
    const hidden = metadata?.find(item => item.name === StatusBarHiddenMetadata)?.value;

    if (style === 'light' || style === 'dark') {
      try {
        // Match the foreground colors RNOH applies when JavaScript takes control.
        await target.setWindowSystemBarProperties({ statusBarContentColor: style === 'light' ? '#E5FFFFFF' : '#000000' });
      } catch (error) {
        console.warn(`Unable to apply the Expo status bar style: ${String(error)}`);
      }
    }

    if (hidden === 'true' || hidden === 'false') {
      try {
        await target.setSpecificSystemBarEnabled('status', hidden === 'false', false);
      } catch (error) {
        console.warn(`Unable to apply the Expo status bar visibility: ${String(error)}`);
      }
    }
  }
}

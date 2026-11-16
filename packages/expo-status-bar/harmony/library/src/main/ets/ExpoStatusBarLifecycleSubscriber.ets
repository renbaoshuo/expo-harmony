/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ExpoAbilityLifecycleSubscriber } from '@expo-harmony/expo-modules-core';

const StatusBarStyleMetadata = 'expo.harmony.statusBar.style';
const StatusBarHiddenMetadata = 'expo.harmony.statusBar.hidden';
const WindowManagerCapability = 'SystemCapability.WindowManager.WindowManager.Core';
const WindowSessionCapability = 'SystemCapability.Window.SessionManager';
const TwoInOneDeviceType = '2in1';

export class ExpoStatusBarLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  override async onWindowSetup(target: window.Window): Promise<void> {
    // Both status bar APIs are no-ops on 2-in-1 devices.
    if (deviceInfo.deviceType === TwoInOneDeviceType) return;

    const metadata = this.context.currentHapModuleInfo.metadata;
    const style = metadata?.find(item => item.name === StatusBarStyleMetadata)?.value;
    const hidden = metadata?.find(item => item.name === StatusBarHiddenMetadata)?.value;

    if ((style === 'light' || style === 'dark') && canIUse(WindowManagerCapability)) {
      try {
        // Match the foreground colors RNOH applies when JavaScript takes control.
        await target.setWindowSystemBarProperties({ statusBarContentColor: style === 'light' ? '#E5FFFFFF' : '#000000' });
      } catch (error) {
        console.warn(`Unable to apply the Expo status bar style: ${String(error)}`);
      }
    }

    if ((hidden === 'true' || hidden === 'false') && canIUse(WindowSessionCapability)) {
      try {
        await target.setSpecificSystemBarEnabled('status', hidden === 'false');
      } catch (error) {
        console.warn(`Unable to apply the Expo status bar visibility: ${String(error)}`);
      }
    }
  }
}

import {
  RNOHCoreContext,
  RNOHErrorDialog,
} from '@rnoh/react-native-openharmony';
import type { RNInstanceOptions } from '@rnoh/react-native-openharmony';
import { ExpoRNApp } from '@expo-harmony/expo-modules-core';
import { expoReactHost } from '../PackageProvider';
import { ExpoHarmonyRootView } from '../generated/ExpoHarmonyHostProvider';

@Entry
@Component
struct Index {
  @StorageLink('RNOHCoreContext') private rnohCoreContext: RNOHCoreContext | undefined = undefined;

  private instanceOptions(): RNInstanceOptions {
    const options = expoReactHost.createRNInstanceOptions();
    options.enableDebugger = this.rnohCoreContext?.isDebugModeEnabled ?? false;
    return options;
  }

  build(): void {
    Stack() {
      ExpoHarmonyRootView()
      Column() {
        if (this.rnohCoreContext !== undefined) {
          if (this.rnohCoreContext.isDebugModeEnabled) {
            RNOHErrorDialog({ ctx: this.rnohCoreContext });
          }
          ExpoRNApp({
            rnInstanceConfig: this.instanceOptions(),
            appKey: 'BareBattery',
            jsBundleProvider: expoReactHost.createJSBundleProvider(
              this.rnohCoreContext.uiAbilityContext,
              this.rnohCoreContext.isDebugModeEnabled,
            ),
          });
        }
      }
      .height('100%')
      .width('100%');
    }
    .height('100%')
    .width('100%');
  }
}

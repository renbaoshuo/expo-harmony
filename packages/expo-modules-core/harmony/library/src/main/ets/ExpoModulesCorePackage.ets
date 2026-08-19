import { RNOHPackage, UITurboModule, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import type { RNPackageContext } from '@rnoh/react-native-openharmony/ts';
import { ExpoModulesCoreTurboModule } from './ExpoModulesCoreTurboModule';
import { NativeUnimoduleProxyTurboModule } from './NativeUnimoduleProxyTurboModule';
import { buildExpoView } from './views/ExpoView';
import { ExpoViewAdapterRegistry } from './views/ExpoViewTypes';
import type { ComponentBuilderContext } from '@rnoh/react-native-openharmony';

export class ExpoModulesCorePackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    super(context);
  }

  override getUITurboModuleFactoryByNameMap(): Map<string, (ctx: UITurboModuleContext) => UITurboModule | null> {
    return new Map<string, (ctx: UITurboModuleContext) => UITurboModule | null>().set(
      NativeUnimoduleProxyTurboModule.NAME,
      (ctx) => new NativeUnimoduleProxyTurboModule(ctx),
    );
  }

  override async createEagerUITurboModuleByNameMap(ctx: UITurboModuleContext): Promise<Map<string, UITurboModule>> {
    return new Map<string, UITurboModule>().set(ExpoModulesCoreTurboModule.NAME, await ExpoModulesCoreTurboModule.create(ctx));
  }

  override createWrappedCustomRNComponentBuilderByComponentNameMap(): Map<string, WrappedBuilder<[ComponentBuilderContext]>> {
    const result = new Map<string, WrappedBuilder<[ComponentBuilderContext]>>();
    ExpoViewAdapterRegistry.names().forEach((name) => result.set(name, wrapBuilder(buildExpoView)));
    return result;
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-modules-core';
  }
}

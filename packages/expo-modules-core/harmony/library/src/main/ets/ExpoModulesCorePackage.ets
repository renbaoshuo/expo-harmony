import { RNOHPackage, UITurboModule, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import type { RNPackageContext } from '@rnoh/react-native-openharmony/ts';
import { ExpoModulesCoreTurboModule } from './ExpoModulesCoreTurboModule';
import { buildExpoView } from './views/ExpoView';
import { ExpoViewAdapterRegistry } from './views/ExpoViewTypes';
import type { ComponentBuilderContext } from '@rnoh/react-native-openharmony';
import type { ExpoModuleRegistration } from './modules/ExpoModule';
import type { ExpoHarmonyHostState } from './appcontext/HarmonyHostLifecycle';
import type { ExpoServiceClass } from './appcontext/ExpoServicesRegistry';
import { ExpoRuntimeConfig } from './appcontext/ExpoRuntimeConfig';

export class ExpoModulesCorePackage extends RNOHPackage {
  private readonly expoModules: ExpoModuleRegistration[];
  private readonly hostState: ExpoHarmonyHostState;
  private readonly services: ExpoServiceClass[];
  private readonly runtimeConfig: ExpoRuntimeConfig;

  constructor(context: RNPackageContext, expoModules: ExpoModuleRegistration[], hostState: ExpoHarmonyHostState, runtimeConfig: ExpoRuntimeConfig = new ExpoRuntimeConfig(), services: ExpoServiceClass[] = []) {
    super(context);
    this.expoModules = expoModules;
    this.hostState = hostState;
    this.runtimeConfig = runtimeConfig;
    this.services = services.slice();
  }

  override async createEagerUITurboModuleByNameMap(ctx: UITurboModuleContext): Promise<Map<string, UITurboModule>> {
    return new Map<string, UITurboModule>().set(
      ExpoModulesCoreTurboModule.NAME,
      await ExpoModulesCoreTurboModule.create(ctx, this.expoModules, this.hostState, this.runtimeConfig, this.services),
    );
  }

  override createWrappedCustomRNComponentBuilderByComponentNameMap(): Map<string, WrappedBuilder<[ComponentBuilderContext]>> {
    const builders = new Map<string, WrappedBuilder<[ComponentBuilderContext]>>();
    ExpoViewAdapterRegistry.names().forEach((name) => builders.set(name, wrapBuilder(buildExpoView)));
    return builders;
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-modules-core';
  }
}

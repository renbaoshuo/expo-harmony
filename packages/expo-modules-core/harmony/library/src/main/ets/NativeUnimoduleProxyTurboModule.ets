import { EtsUITurboModule, UITurboModuleContext } from '@rnoh/react-native-openharmony';

interface EmptyNativeModuleMap {}

interface NativeUnimoduleProxyConstants {
  modulesConstants: EmptyNativeModuleMap;
  exportedMethods: EmptyNativeModuleMap;
  viewManagersMetadata: EmptyNativeModuleMap;
}

/**
 * Compatibility sentinel required by Expo SDK 55's unmodified
 * NativeModulesProxy.native.ts. The actual constants and method calls come
 * from globalThis.expo.modules.NativeModulesProxy after the JSI installer ran.
 */
export class NativeUnimoduleProxyTurboModule extends EtsUITurboModule {
  static readonly NAME: string = 'NativeUnimoduleProxy';

  constructor(context: UITurboModuleContext) {
    super(context);
  }

  getConstants(): NativeUnimoduleProxyConstants {
    return {
      modulesConstants: {},
      exportedMethods: {},
      viewManagersMetadata: {},
    };
  }
}

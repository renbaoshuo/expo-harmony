import uri from '@ohos.uri';
import Url from '@ohos.url';
import call from '@ohos.telephony.call';
import bundleManager from '@ohos.bundle.bundleManager';
import type AbilityWant from '@ohos.app.ability.Want';
import { AnyThreadTurboModule, RNOHPackage } from '@rnoh/react-native-openharmony';
import type { AnyThreadTurboModuleContext, RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import type { Want } from '@kit.AbilityKit';
import { ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';

import { AbilityLinkingState } from './LinkingState';
import { normalizeSMSURL } from './LinkingURL';

const SERVICE_NAME: string = 'ExpoLinkingService';
let registered: boolean = false;
const abilityStates: WeakMap<Object, AbilityLinkingState> = new WeakMap<Object, AbilityLinkingState>();

function nonEmptyURL(value: string | undefined): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function stateForAbility(context: Object, launch: string | null): AbilityLinkingState {
  let state = abilityStates.get(context);
  if (state === undefined) {
    state = new AbilityLinkingState(launch);
    abilityStates.set(context, state);
  }

  return state;
}

export class ExpoLinkingLifecycle {
  static onCreate(context: Object, want: Want): void {
    abilityStates.set(context, new AbilityLinkingState(nonEmptyURL(want.uri)));
  }

  static shouldDispatchNewWant(context: Object, want: Want): boolean {
    const state = stateForAbility(context, null);

    return state.recordNewWant(nonEmptyURL(want.uri));
  }

  static onDestroy(context: Object): void {
    const state = abilityStates.get(context);
    state?.destroy();

    abilityStates.delete(context);
  }
}

class ExpoLinkingService {
  readonly name: string = SERVICE_NAME;
  private readonly state: AbilityLinkingState;
  private readonly runtimeId: number;

  constructor(context: UITurboModuleContext) {
    this.runtimeId = context.rnInstance.getId();

    this.state = stateForAbility(context.uiAbilityContext, nonEmptyURL(context.launchUri));

    this.state.registerRuntime(this.runtimeId);
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    return this.invokeSync(method, args);
  }

  onDestroy(): void {
    this.state.unregisterRuntime(this.runtimeId);
  }

  invokeSync(method: string, args: ESObject[]): ESObject {
    if (method === 'getURL') return this.state.getURL();

    if (method === 'getRuntimeId') return this.runtimeId;

    if (method === 'getRevision') return this.state.getRevision();

    if (method === 'clearURL') return this.state.clear();

    if (method === 'getDispatchedRevision') {
      const url: ESObject = args[0];
      const after: ESObject = args[1];

      if (typeof url !== 'string' || url.length === 0) {
        throw new Error('ERR_LINKING_INVALID_URL: ExpoLinkingService.getDispatchedRevision expected a non-empty URL string.');
      }

      if (typeof after !== 'number' || !Number.isInteger(after) || after < 0) {
        throw new Error('ERR_LINKING_INVALID_REVISION: ExpoLinkingService.getDispatchedRevision expected a non-negative integer revision.');
      }

      return this.state.takeDispatchedRevision(this.runtimeId, url, after);
    }

    if (method === 'runtimeWillDestroy') {
      this.onDestroy();
      return null;
    }

    if (method === 'isAbilityDestroyed') return this.state.isDestroyed();

    throw new Error(`ERR_LINKING_UNKNOWN_METHOD: ${method}`);
  }
}

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new ExpoLinkingService(context),
  });

  registered = true;
}

class ExpoHarmonyLinkingManager extends AnyThreadTurboModule {
  static readonly NAME: string = 'LinkingManager';
  private readonly initial: string | null;

  constructor(context: AnyThreadTurboModuleContext) {
    super(context);

    this.initial = stateForAbility(context.uiAbilityContext, nonEmptyURL(context.launchUri)).getInitialURL();
  }

  async getInitialURL(): Promise<string | null> {
    return this.initial;
  }

  async canOpenURL(url: string): Promise<boolean> {
    const parsed = new uri.URI(url);

    if (parsed.scheme === 'tel') return call.hasVoiceCapability();
    if (parsed.scheme === 'sms') return true;

    try {
      return bundleManager.canOpenLink(url);
    } catch (error) {
      const err: ESObject = error;

      if (err.code === 17700056) {
        if (this.ctx.isDebugModeEnabled) {
          throw new Error(`URL scheme ${parsed.scheme} is not declared in module.querySchemes`);
        }
        return false;
      }

      this.ctx.logger.error(err);

      return false;
    }
  }

  async openURL(url: string): Promise<boolean> {
    const parsed = new uri.URI(url);

    switch (parsed.scheme) {
      case 'tel':
        await call.makeCall(this.ctx.uiAbilityContext, parsed.ssp);
        break;
      case 'http':
      case 'https':
        await this.ctx.uiAbilityContext.startAbility({
          action: 'ohos.want.action.viewData',
          entities: ['entity.system.browsable'],
          uri: url,
        });
        break;
      case 'sms':
        await this.ctx.uiAbilityContext.startAbility(this.createSMSWant(url));
        break;
      default:
        try {
          await this.ctx.uiAbilityContext.startAbility({ uri: url });
        } catch (error) {
          throw new Error(`URL scheme ${parsed.scheme} is not supported: ${String(error)}`);
        }
    }

    return true;
  }

  openSettings(): Promise<void> {
    return this.ctx.uiAbilityContext.startAbility({
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: {
        settingsParamBundleName: this.ctx.uiAbilityContext.abilityInfo.bundleName,
      },
    });
  }

  private createSMSWant(url: string): AbilityWant {
    const normalized = normalizeSMSURL(url);
    const sms = Url.URL.parseURL(normalized);
    const params = new Url.URLParams(sms.search);
    const phone = sms.pathname;
    const body = params.get('body');

    const parameters: Record<string, Object> = {};

    if (phone) {
      parameters['contactObjects'] = `[{"telephone":${JSON.stringify(phone)}}]`;
      parameters['pageFlag'] = 'conversation';
      if (body !== null) parameters['content'] = body;
    }

    return {
      bundleName: 'com.ohos.mms',
      abilityName: 'com.ohos.mms.MainAbility',
      parameters: phone ? parameters : undefined,
    };
  }
}

export class ExpoLinkingPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    super(context);

    registerService();
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-linking';
  }

  override getAnyThreadTurboModuleFactoryByNameMap(): Map<string, (context: AnyThreadTurboModuleContext) => AnyThreadTurboModule | null> {
    return new Map<string, (context: AnyThreadTurboModuleContext) => AnyThreadTurboModule>().set(
      ExpoHarmonyLinkingManager.NAME,
      (context) => new ExpoHarmonyLinkingManager(context),
    );
  }
}

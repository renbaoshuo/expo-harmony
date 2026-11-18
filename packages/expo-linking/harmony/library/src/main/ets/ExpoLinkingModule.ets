/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { bundleManager } from '@kit.AbilityKit';
import type { Want } from '@kit.AbilityKit';
import { uri, url } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import { call, sms } from '@kit.TelephonyKit';
import {
  ExpoAbilityLifecycleSubscriber,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';

const URL_EVENT: string = 'onURLReceived';
const DIALER_CAPABILITY: string = 'SystemCapability.Applications.Contacts';
const VOICE_CALL_CAPABILITY: string = 'SystemCapability.Telephony.CallManager';
const SMS_CAPABILITY: string = 'SystemCapability.Telephony.SmsMms';
const TEL_URI_API_VERSION: number = 15;

// https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-access-control-16
const SETTINGS_BUNDLE_NAME: string = 'com.huawei.hmos.settings';
const SETTINGS_ABILITY_NAME: string = 'com.huawei.hmos.settings.MainAbility';
const APPLICATION_DETAILS_URI: string = 'application_info_entry';
const SETTINGS_BUNDLE_PARAMETER: string = 'settingsParamBundleName';
const SETTINGS_LEGACY_BUNDLE_PARAMETER: string = 'pushParams';

// https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/telephony-sms
const SMS_BUNDLE_NAME: string = 'com.ohos.mms';
const SMS_VIEW_ACTION: string = 'ohos.want.action.viewData';
const SMS_ABILITY_NAME: string = 'com.ohos.mms.MainAbility';
const SMS_COMPOSER_PAGE: string = 'conversation';
const SEND_TO_DATA_ACTION: string = 'ohos.want.action.sendToData';
const NO_MATCHING_ABILITY: number = 16000019;
const INVALID_LINK: number = 17700055;
const SCHEME_NOT_DECLARED: number = 17700056;

class URLReceivedEvent {
  url: string;

  constructor(url: string) {
    this.url = url;
  }
}

class AbilityLinkingState {
  readonly initialURL: string | null;
  readonly receivesModuleWants: boolean;
  private url: string | null;
  private destroyed: boolean = false;
  private readonly listeners: Set<(url: string) => void> = new Set();

  constructor(initialURL: string | null, receivesModuleWants: boolean = false) {
    this.initialURL = initialURL;
    this.receivesModuleWants = receivesModuleWants;
    this.url = initialURL;
  }

  getURL(): string | null {
    return this.destroyed ? null : this.url;
  }

  receive(url: string): void {
    if (this.destroyed) return;

    this.url = url;

    this.listeners.forEach((listener: (url: string) => void): void => {
      try {
        listener(url);
      } catch (error) {
        console.warn(`Unable to deliver Expo Linking URL: ${String(error)}`);
      }
    });
  }

  addListener(listener: (url: string) => void): void {
    this.listeners.add(listener);
  }

  removeListener(listener: (url: string) => void): void {
    this.listeners.delete(listener);
  }

  clear(): void {
    if (!this.destroyed) this.url = null;
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.url = null;

    this.listeners.clear();
  }
}

const states: WeakMap<Object, AbilityLinkingState> = new WeakMap();

export class ExpoLinkingLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  override onCreate(want: Want): void {
    states.set(this.context, new AbilityLinkingState(nonEmptyURL(want.uri)));
  }

  override onNewWant(want: Want): void {
    const url = nonEmptyURL(want.uri);
    if (url !== null) states.get(this.context)?.receive(url);
  }

  override onDestroy(): void {
    states.get(this.context)?.destroy();
    states.delete(this.context);
  }
}

function linkingState(context: ExpoModuleContext): AbilityLinkingState {
  const session = context.session;
  const existing = states.get(session ?? context.uiAbilityContext);

  if (existing !== undefined) return existing;

  // Custom hosts and isolated sessions receive Wants through module lifecycle events.
  const state = new AbilityLinkingState(nonEmptyURL(context.initialWant?.uri ?? context.launchUri), true);

  if (session !== undefined) {
    session.onClose((): void => {
      state.destroy();
      states.delete(session);
    });
    states.set(session, state);
  }

  return state;
}

function nonEmptyURL(value: string | undefined): string | null {
  return value !== undefined && value.trim().length > 0 ? value : null;
}

function canOpenDialer(): boolean {
  return canIUse(DIALER_CAPABILITY) && canIUse(VOICE_CALL_CAPABILITY) && call.hasVoiceCapability();
}

function canOpenSMSComposer(): boolean {
  return canIUse(SMS_CAPABILITY) && sms.hasSmsCapability();
}

export class ExpoLinkingModule extends ExpoModule {
  private readonly state?: AbilityLinkingState;
  private observing: boolean = false;
  private destroyed: boolean = false;
  private readonly onURL = (url: string): void => {
    if (!this.destroyed && this.observing) this.sendEvent(URL_EVENT, new URLReceivedEvent(url));
  };

  constructor(context: ExpoModuleContext) {
    super(context);

    if (!context.isHeadless) this.state = linkingState(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoLinking')
      .events([URL_EVENT])
      .syncFunction('getInitialURL', (): string | null => this.state?.initialURL ?? null)
      .syncFunction('getLinkingURL', (): string | null => this.state?.getURL() ?? null)
      .syncFunction('clearInitialURL', (): void => this.state?.clear())
      .asyncFunction(
        'openURL',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (url: string): Promise<boolean> => {
          await this.openURL(url);

          return true;
        }).returns(ExpoValueTypes.boolean()),
      )
      .asyncFunction(
        'canOpenURL',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (url: string): Promise<boolean> => {
          return this.canOpenURL(url);
        }).returns(ExpoValueTypes.boolean()),
      )
      .asyncFunction(
        'openSettings',
        ExpoFunction.typed0(async (): Promise<void> => {
          await this.openSettings();
        }),
      )
      .onStartObserving(URL_EVENT, (): void => {
        if (this.destroyed || this.observing) return;

        this.observing = true;
        this.state?.addListener(this.onURL);
      })
      .onStopObserving(URL_EVENT, (): void => {
        this.observing = false;
        this.state?.removeListener(this.onURL);
      })
      .onNewWant((want: Want): void => {
        if (this.state?.receivesModuleWants) this.receiveWant(want);
      })
      .onDestroy((): void => {
        this.destroyed = true;
        this.observing = false;

        this.state?.removeListener(this.onURL);
      });
  }

  private receiveWant(want: Want): void {
    if (this.destroyed) return;

    const url = nonEmptyURL(want.uri);
    if (url === null) return;

    this.state?.receive(url);
  }

  private async openURL(value: string): Promise<void> {
    const scheme = schemeForURL(value);
    if (this.context.isHeadless) throw new ExpoModuleError('ERR_LINKING_UNAVAILABLE', 'Opening a URL requires a UIAbility.');

    const link = `${scheme}${value.slice(scheme.length)}`;

    try {
      const context = this.context.uiAbilityContext;

      if (scheme === 'tel') {
        if (!canOpenDialer()) {
          throw new ExpoModuleError('ERR_LINKING_UNAVAILABLE', 'This device cannot open the phone dialer.');
        }

        const number = deviceInfo.sdkApiVersion >= TEL_URI_API_VERSION
          ? link
          : new uri.URI(link).ssp;
        await call.makeCall(context, number);

        return;
      }

      if (scheme === 'sms') {
        if (!canOpenSMSComposer()) {
          throw new ExpoModuleError('ERR_LINKING_UNAVAILABLE', 'This device cannot compose SMS messages.');
        }

        await this.openSMS(link);

        return;
      }

      if (scheme === 'mailto') {
        try {
          await context.startAbility({ action: SEND_TO_DATA_ACTION, uri: link });

          return;
        } catch (error) {
          if ((error as BusinessError).code !== NO_MATCHING_ABILITY) {
            throw new ExpoModuleError('ERR_LINKING_OPEN_URL', `Unable to open URL with scheme '${scheme}'.`, error as Object);
          }
        }
      }

      await context.openLink(link);
    } catch (error) {
      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }

      throw new ExpoModuleError('ERR_LINKING_OPEN_URL', `Unable to open URL with scheme '${scheme}'.`, error as Object);
    }
  }

  private canOpenURL(url: string): boolean {
    const scheme = schemeForURL(url);

    try {
      if (scheme === 'tel') return canOpenDialer();
      if (scheme === 'sms') return canOpenSMSComposer();

      return bundleManager.canOpenLink(`${scheme}${url.slice(scheme.length)}`);
    } catch (error) {
      const code = (error as BusinessError).code;
      if (code === INVALID_LINK) {
        throw new ExpoModuleError('ERR_LINKING_INVALID_URL', 'The URL is invalid.', error as Object);
      }
      if (code === SCHEME_NOT_DECLARED) {
        throw new ExpoModuleError('ERR_LINKING_CAN_OPEN_URL', `Declare '${scheme}' in HarmonyOS querySchemes before querying it.`, error as Object);
      }

      throw new ExpoModuleError('ERR_LINKING_CAN_OPEN_URL', `Unable to determine whether URL scheme '${scheme}' can be opened.`, error as Object);
    }
  }

  private async openSMS(value: string): Promise<void> {
    const url = normalizeSMSURL(value);
    const context = this.context.uiAbilityContext;

    try {
      await context.startAbility({ bundleName: SMS_BUNDLE_NAME, action: SMS_VIEW_ACTION, uri: url });
    } catch (error) {
      if ((error as BusinessError).code !== NO_MATCHING_ABILITY) {
        throw new ExpoModuleError('ERR_LINKING_OPEN_URL', "Unable to open URL with scheme 'sms'.", error as Object);
      }

      // Older system SMS apps may only expose the explicit composer entry.
      await context.startAbility(legacySMSWant(url));
    }
  }

  private async openSettings(): Promise<void> {
    if (this.context.isHeadless) throw new ExpoModuleError('ERR_LINKING_UNAVAILABLE', 'Opening settings requires a UIAbility.');

    try {
      const context = this.context.uiAbilityContext;
      const bundle = context.abilityInfo.bundleName;
      const params: Record<string, Object> = {};
      params[SETTINGS_BUNDLE_PARAMETER] = bundle;
      params[SETTINGS_LEGACY_BUNDLE_PARAMETER] = bundle;

      await context.startAbility({
        bundleName: SETTINGS_BUNDLE_NAME,
        abilityName: SETTINGS_ABILITY_NAME,
        uri: APPLICATION_DETAILS_URI,
        parameters: params,
      });
    } catch (error) {
      throw new ExpoModuleError('ERR_LINKING_OPEN_SETTINGS', 'Unable to open the HarmonyOS application settings page.', error as Object);
    }
  }
}

function normalizeSMSURL(value: string): string {
  // Accept the legacy SMS separator used by React Native's LinkingManager.
  const boundary = value.search(/[?#]/);
  const body = value.indexOf('&body=');
  const legacy = body >= 0 && (boundary < 0 || body < boundary);
  const end = legacy ? body : (boundary < 0 ? value.length : boundary);

  // RFC 5724 uses a literal leading '+' for international recipients.
  const recipients = value.slice(value.indexOf(':') + 1, end).replace(/(^|,)%2B/gi, '$1+');
  const suffix = legacy ? `?${value.slice(end + 1)}` : value.slice(end);

  return `sms:${recipients}${suffix}`;
}

function legacySMSWant(value: string): Want {
  const parsed = url.URL.parseURL(value);
  const contacts: string[] = parsed.pathname
    .split(',')
    .filter((telephone: string): boolean => telephone.length > 0)
    .map((encoded: string): string => {
      const telephone = decodeURIComponent(encoded);
      // The legacy composer uses commas as recipient separators after decoding.
      if (telephone.includes(',')) {
        throw new ExpoModuleError('ERR_LINKING_INVALID_URL', 'An SMS recipient cannot contain a comma.');
      }

      // These external keys must survive the application's property obfuscation.
      return `{"telephone":${JSON.stringify(telephone)}}`;
    });

  const parameters = JSON.parse(`{
    "contactObjects": ${JSON.stringify(`[${contacts.join(',')}]`)},
    "pageFlag": ${JSON.stringify(SMS_COMPOSER_PAGE)},
    "content": ${JSON.stringify(parsed.params.get('body') ?? '')}
  }`) as Record<string, Object>;

  return {
    bundleName: SMS_BUNDLE_NAME,
    abilityName: SMS_ABILITY_NAME,
    parameters,
  };
}

function schemeForURL(value: string): string {
  if (value.trim().length === 0) {
    throw new ExpoModuleError('ERR_LINKING_INVALID_URL', 'A URL cannot be empty.');
  }

  const scheme = /^([a-z][a-z\d+.-]*):/i.exec(value)?.[1];
  if (scheme === undefined) {
    throw new ExpoModuleError('ERR_LINKING_INVALID_URL', 'URL is missing a scheme.');
  }

  return scheme.toLowerCase();
}

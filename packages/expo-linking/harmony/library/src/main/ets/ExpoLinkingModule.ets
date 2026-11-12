/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { bundleManager } from '@kit.AbilityKit';
import type { Want, common } from '@kit.AbilityKit';
import { uri, url } from '@kit.ArkTS';
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
const SMS_CAPABILITY: string = 'SystemCapability.Telephony.SmsMms';

// https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-access-control-16
const SETTINGS_BUNDLE_NAME: string = 'com.huawei.hmos.settings';
const SETTINGS_ABILITY_NAME: string = 'com.huawei.hmos.settings.MainAbility';
const APPLICATION_DETAILS_URI: string = 'application_info_entry';

// https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/telephony-sms
const SMS_BUNDLE_NAME: string = 'com.ohos.mms';
const SMS_VIEW_ACTION: string = 'ohos.want.action.viewData';
const SMS_ABILITY_NAME: string = 'com.ohos.mms.MainAbility';
const SMS_COMPOSER_PAGE: string = 'conversation';
const NO_MATCHING_ABILITY: number = 16000019;

class URLReceivedEvent {
  url: string;

  constructor(url: string) {
    this.url = url;
  }
}

class AbilityLinkingState {
  private url: string | null;
  private destroyed: boolean = false;
  private readonly listeners: Set<(url: string) => void> = new Set();

  constructor(url: string | null) {
    this.url = url;
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
  private readonly state: AbilityLinkingState = new AbilityLinkingState(null);

  constructor(context: common.UIAbilityContext) {
    super(context);
    states.set(context, this.state);
  }

  override onCreate(want: Want): void {
    this.receive(want);
  }

  override onNewWant(want: Want): void {
    this.receive(want);
  }

  override onDestroy(): void {
    this.state.destroy();
    states.delete(this.context);
  }

  private receive(want: Want): void {
    const url = nonEmptyURL(want.uri);
    if (url !== null) this.state.receive(url);
  }
}

function linkingState(context: ExpoModuleContext): AbilityLinkingState {
  const session = context.session;
  const owner: Object = session ?? context.uiAbilityContext;
  let state = states.get(owner);

  if (state === undefined && session !== undefined) {
    state = new AbilityLinkingState(nonEmptyURL(session.initialWant?.uri));
    states.set(owner, state);

    const owned = state;

    session.onClose((): void => {
      owned.destroy();
      states.delete(owner);
    });
  }

  if (state === undefined) {
    throw new ExpoModuleError('ERR_LINKING_ABILITY_NOT_INITIALIZED', 'Expo Linking requires its autolinked Ability lifecycle subscriber.');
  }

  return state;
}

function nonEmptyURL(value: string | undefined): string | null {
  return value !== undefined && value.length > 0 ? value : null;
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
      .syncFunction('getInitialURL', (): string | null => this.state === undefined ? null : nonEmptyURL(this.context.launchUri))
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
        if (this.context.session !== undefined) this.receiveWant(want);
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

  private async openURL(url: string): Promise<void> {
    const scheme = schemeForURL(url);

    if (this.context.isHeadless) throw new ExpoModuleError('ERR_LINKING_UNAVAILABLE', 'Opening a URL requires a UIAbility.');

    try {
      if (scheme === 'tel') {
        if (!canIUse(DIALER_CAPABILITY)) {
          throw new ExpoModuleError('ERR_LINKING_UNAVAILABLE', 'This device cannot open the phone dialer.');
        }

        const number = new uri.URI(url).ssp;

        await call.makeCall(this.context.uiAbilityContext, number);

        return;
      }

      if (scheme === 'sms') {
        if (!canIUse(SMS_CAPABILITY) || !sms.hasSmsCapability()) {
          throw new ExpoModuleError('ERR_LINKING_UNAVAILABLE', 'This device cannot compose SMS messages.');
        }

        await this.openSMS(url);

        return;
      }

      await this.context.uiAbilityContext.openLink(url);
    } catch (error) {
      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }

      throw new ExpoModuleError('ERR_LINKING_OPEN_URL', `Unable to open URL with scheme '${scheme}'.`, error as Object);
    }
  }

  private canOpenURL(url: string): boolean {
    const scheme = schemeForURL(url);

    if (scheme === 'tel') return canIUse(DIALER_CAPABILITY);

    if (scheme === 'sms') {
      return canIUse(SMS_CAPABILITY) && sms.hasSmsCapability();
    }

    try {
      return bundleManager.canOpenLink(url);
    } catch (error) {
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
      await this.context.uiAbilityContext.startAbility({
        bundleName: SETTINGS_BUNDLE_NAME,
        abilityName: SETTINGS_ABILITY_NAME,
        uri: APPLICATION_DETAILS_URI,
        parameters: {
          settingsParamBundleName: this.context.uiAbilityContext.abilityInfo.bundleName,
        },
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

  // Classify the protocol without parsing the rest of the system-owned link.
  const scheme = /^([a-z][a-z\d+.-]*):/i.exec(value)?.[1];
  if (scheme === undefined) {
    throw new ExpoModuleError('ERR_LINKING_INVALID_URL', `URL is missing a scheme: '${value}'.`);
  }

  return scheme.toLowerCase();
}

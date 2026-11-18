/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import lazy { sms } from '@kit.TelephonyKit';
import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';

import { SMS_OPTIONS } from './SMSOptions';

const CAPABILITY: string = 'SystemCapability.Telephony.SmsMms';
const WINDOW_CAPABILITY: string = 'SystemCapability.WindowManager.WindowManager.Core';

// https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/telephony-sms
const SMS_BUNDLE_NAME: string = 'com.ohos.mms';
const SMS_VIEW_ACTION: string = 'ohos.want.action.viewData';
const SMS_ABILITY_NAME: string = 'com.ohos.mms.MainAbility';
const ABILITY_NOT_FOUND: number = 16000001;
const NO_MATCHING_ABILITY: number = 16000019;

interface SMSResponse {
  result: string;
}

class SMSRequest {
  started: boolean = false;
  leftHost: boolean = false;
  lostFocus: boolean = false;
  returned: boolean = false;
  stopObserving?: () => void;
  resolve: (response: SMSResponse) => void;
  reject: (error: ExpoModuleError) => void;

  constructor(resolve: (response: SMSResponse) => void, reject: (error: ExpoModuleError) => void) {
    this.resolve = resolve;
    this.reject = reject;
  }
}

export class ExpoSMSModule extends ExpoModule {
  private pending?: SMSRequest;
  private stage?: window.WindowStage;
  private destroyed: boolean = false;

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoSMS')
      .asyncFunction('isAvailableAsync', async (): Promise<boolean> => this.isAvailable())
      .asyncFunction(
        'sendSMSAsync',
        ExpoFunction.typed3(
          ExpoValueTypes.array(ExpoValueTypes.string()),
          ExpoValueTypes.string(),
          SMS_OPTIONS,
          (addresses: string[], message: string, options: Record<string, ESObject>): Promise<SMSResponse> =>
            this.sendSMS(addresses, message, options),
        ),
      )
      .onBackground((): void => {
        if (this.pending !== undefined) this.pending.leftHost = true;
      })
      .onForeground((): void => {
        const request = this.pending;

        if (request?.leftHost) this.onReturn(request);
      })
      .onWindowStageSetup((stage: window.WindowStage): void => {
        this.stage = stage;

        const request = this.pending;
        if (request !== undefined) {
          request.stopObserving?.();
          this.observeWindow(request);
        }
      })
      .onWindowStageWillDestroy((): void => {
        this.stage = undefined;

        const request = this.pending;
        if (request !== undefined) {
          this.fail(request, new ExpoModuleError('ERR_SMS_DESTROYED', 'The SMS composer lost its host window.'));
        }
      })
      .onPrepareForReload(async (): Promise<void> => this.destroy())
      .onAbilityDestroy((): void => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private isAvailable(): boolean {
    try {
      return canIUse(CAPABILITY) && sms.hasSmsCapability();
    } catch (_) {
      return false;
    }
  }

  private async sendSMS(addresses: string[], message: string, options: Record<string, ESObject>): Promise<SMSResponse> {
    if (this.destroyed) throw new ExpoModuleError('ERR_SMS_DESTROYED', 'The SMS module host was destroyed.');
    if (!this.isAvailable()) throw new ExpoModuleError('ERR_SMS_UNAVAILABLE', 'SMS service is not available.');
    if (this.pending !== undefined) {
      throw new ExpoModuleError('ERR_SMS_PENDING', 'SMS sending in progress, await the old request and then try again.');
    }
    this.assertForeground();

    const attachments = options['attachments'] as Record<string, ESObject>[] | undefined;
    if (attachments !== undefined && attachments.length > 0) {
      throw new ExpoModuleError('ERR_SMS_ATTACHMENTS_UNSUPPORTED', 'HarmonyOS does not expose SMS composer attachment parameters.');
    }

    const recipients = addresses.filter((address: string): boolean => address.length > 0);

    if (recipients.some((address: string): boolean => address.includes(','))) {
      throw new ExpoModuleError('ERR_SMS_SENDING', 'Pass each SMS recipient separately instead of embedding a comma in an address.');
    }

    return new Promise<SMSResponse>((resolve, reject): void => {
      const request = new SMSRequest(resolve, reject);
      this.pending = request;
      this.observeWindow(request);

      this.openComposer(request, recipients, message).catch((error: Object): void => this.fail(request, error));
    });
  }

  private observeWindow(request: SMSRequest): void {
    const stage = this.stage;
    if (stage === undefined || !canIUse(WINDOW_CAPABILITY)) return;

    const listener = (event: window.WindowStageEventType): void => {
      if (this.pending !== request || this.stage !== stage) return;

      if (event === window.WindowStageEventType.INACTIVE) {
        request.lostFocus = true;
      } else if (event === window.WindowStageEventType.ACTIVE && request.lostFocus) {
        this.onReturn(request);
      }
    };

    try {
      stage.on('windowStageEvent', listener);
      request.stopObserving = (): void => {
        request.stopObserving = undefined;
        try {
          stage.off('windowStageEvent', listener);
        } catch (_) {}
      };
    } catch (_) {
      // Ability lifecycle callbacks still cover full-screen returns.
    }
  }

  private onReturn(request: SMSRequest): void {
    request.returned = true;
    this.finish(request);
  }

  private assertForeground(): void {
    if (this.context.isHeadless || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoModuleError('ERR_SMS_BACKGROUND', 'The SMS composer must be opened from a foreground application.');
    }
  }

  private async openComposer(request: SMSRequest, addresses: string[], message: string): Promise<void> {
    // The SMS URI grammar uses a literal leading '+' for international numbers.
    const recipients = addresses
      .map((address: string): string => encodeSmsComponent(address).replace(/^%2B/, '+'))
      .join(',');
    const body = encodeSmsComponent(message);

    const want: Want = {
      bundleName: SMS_BUNDLE_NAME,
      action: SMS_VIEW_ACTION,
      uri: `sms:${recipients}?body=${body}`,
    };

    const context = this.context.uiAbilityContext;

    try {
      await context.startAbility(want);
    } catch (error) {
      const code = (error as BusinessError | undefined)?.code;

      if (code !== NO_MATCHING_ABILITY && code !== ABILITY_NOT_FOUND) {
        throw new ExpoModuleError('ERR_SMS_SENDING', 'Unable to open the SMS composer.', error);
      }

      if (this.pending !== request) return;
      this.assertForeground();

      // Keep the external field names stable when an app enables property obfuscation.
      const contacts = addresses.map((address: string): Record<string, string> => {
        const contact: Record<string, string> = {};
        Reflect.set(contact, 'contactsName', '');
        Reflect.set(contact, 'telephone', address);

        return contact;
      });

      const params: Record<string, Object> = {};
      Reflect.set(params, 'contactObjects', JSON.stringify(contacts));
      Reflect.set(params, 'pageFlag', 'conversation');
      Reflect.set(params, 'content', message);

      // Ignore focus changes from the failed URI launch.
      request.leftHost = false;
      request.lostFocus = false;
      request.returned = false;

      await context.startAbility({
        bundleName: SMS_BUNDLE_NAME,
        abilityName: SMS_ABILITY_NAME,
        parameters: params,
      });
    }

    request.started = true;
    this.finish(request);
  }

  private finish(request: SMSRequest): void {
    // Launch completion and the background/foreground callbacks can arrive in either order.
    if (this.pending !== request || !request.started || !request.returned) return;

    this.pending = undefined;
    request.stopObserving?.();

    request.resolve({ result: 'unknown' });
  }

  private fail(request: SMSRequest, error: Object): void {
    if (this.pending !== request) return;

    this.pending = undefined;
    request.stopObserving?.();

    request.reject(
      error instanceof ExpoModuleError ? error : new ExpoModuleError('ERR_SMS_SENDING', 'Unable to open the SMS composer.', error),
    );
  }

  private destroy(): void {
    const request = this.pending;

    this.destroyed = true;
    this.stage = undefined;
    this.pending = undefined;
    request?.stopObserving?.();

    request?.reject(new ExpoModuleError('ERR_SMS_DESTROYED', 'The SMS module host was destroyed while the composer was open.'));
  }
}

function encodeSmsComponent(value: string): string {
  return encodeURIComponent(value).replace(
    /[!'()*]/g,
    (character: string): string => `%${character.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

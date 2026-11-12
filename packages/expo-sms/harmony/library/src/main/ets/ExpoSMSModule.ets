/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { sms } from '@kit.TelephonyKit';
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

// https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/telephony-sms
const SMS_BUNDLE_NAME: string = 'com.ohos.mms';
const SMS_VIEW_ACTION: string = 'ohos.want.action.viewData';
const SMS_ABILITY_NAME: string = 'com.ohos.mms.MainAbility';
const NO_MATCHING_ABILITY: number = 16000019;

interface SMSResponse {
  result: string;
}

class SMSRequest {
  started: boolean = false;
  backgrounded: boolean = false;
  returned: boolean = false;
  resolve: (response: SMSResponse) => void;
  reject: (error: ExpoModuleError) => void;

  constructor(resolve: (response: SMSResponse) => void, reject: (error: ExpoModuleError) => void) {
    this.resolve = resolve;
    this.reject = reject;
  }
}

export class ExpoSMSModule extends ExpoModule {
  private pending?: SMSRequest;
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
        if (this.pending !== undefined) this.pending.backgrounded = true;
      })
      .onForeground((): void => {
        const request = this.pending;

        if (request === undefined || !request.backgrounded) return;

        request.returned = true;
        this.finish(request);
      })
      .onPrepareForReload(async (): Promise<void> => this.destroy())
      .onAbilityDestroy((): void => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private isAvailable(): boolean {
    return canIUse(CAPABILITY) && sms.hasSmsCapability();
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

    return new Promise<SMSResponse>((resolve, reject): void => {
      const request = new SMSRequest(resolve, reject);
      this.pending = request;

      this.openComposer(request, addresses, message).catch((error: Object): void => this.fail(request, error));
    });
  }

  private assertForeground(): void {
    if (this.context.isHeadless || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoModuleError('ERR_SMS_BACKGROUND', 'The SMS composer must be opened from a foreground application.');
    }
  }

  private async openComposer(request: SMSRequest, addresses: string[], message: string): Promise<void> {
    // The SMS URI grammar uses a literal leading '+' for international numbers.
    const recipients = addresses
      .map((address: string): string => encodeURIComponent(address).replace(/^%2B/, '+'))
      .join(',');
    const body = encodeURIComponent(message).replace(
      /[!'()*]/g,
      (character: string): string => `%${character.charCodeAt(0).toString(16).toUpperCase()}`,
    );

    const want: Want = {
      bundleName: SMS_BUNDLE_NAME,
      action: SMS_VIEW_ACTION,
      uri: `sms:${recipients}?body=${body}`,
    };

    const context = this.context.uiAbilityContext;

    try {
      await context.startAbility(want);
    } catch (error) {
      if ((error as BusinessError | undefined)?.code !== NO_MATCHING_ABILITY) throw error as Error;
      if (this.pending !== request) return;
      this.assertForeground();

      // The legacy composer combines telephone fields into a comma-separated list.
      if (addresses.some((address: string): boolean => address.includes(','))) {
        throw new ExpoModuleError('ERR_SMS_SENDING', 'The legacy SMS composer cannot open a recipient containing a comma.');
      }

      // Keep the external field names stable when an app enables property obfuscation.
      const contacts = addresses
        .filter((address: string): boolean => address.length > 0)
        .map((telephone: string): string => `{"telephone":${JSON.stringify(telephone)}}`);
      const parameters = JSON.parse(`{
        "contactObjects": ${JSON.stringify(`[${contacts.join(',')}]`)},
        "pageFlag": "conversation",
        "content": ${JSON.stringify(message)}
      }`) as Record<string, Object>;

      // A lifecycle cycle during failed URI resolution does not belong to the explicit launch.
      request.backgrounded = false;
      request.returned = false;
      await context.startAbility({
        bundleName: SMS_BUNDLE_NAME,
        abilityName: SMS_ABILITY_NAME,
        parameters,
      });
    }

    request.started = true;
    this.finish(request);
  }

  private finish(request: SMSRequest): void {
    // Launch completion and the background/foreground callbacks can arrive in either order.
    if (this.pending !== request || !request.started || !request.returned) return;

    this.pending = undefined;

    request.resolve({ result: 'unknown' });
  }

  private fail(request: SMSRequest, error: Object): void {
    if (this.pending !== request) return;

    this.pending = undefined;

    request.reject(
      error instanceof ExpoModuleError ? error : new ExpoModuleError('ERR_SMS_SENDING', 'Unable to open the SMS composer.', error),
    );
  }

  private destroy(): void {
    const request = this.pending;

    this.destroyed = true;
    this.pending = undefined;

    request?.reject(new ExpoModuleError('ERR_SMS_DESTROYED', 'The SMS module host was destroyed while the composer was open.'));
  }
}

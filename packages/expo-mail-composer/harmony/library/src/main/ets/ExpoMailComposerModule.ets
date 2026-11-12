/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { AbilityStartFailureCode, bundleManager, common, wantConstant } from '@kit.AbilityKit';
import { ExpoAppLifecycleState, ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';

import { attachmentUri } from './MailComposerAttachments';
import { MAIL_COMPOSER_OPTIONS, MailComposerOptions } from './MailComposerOptions';

const MAIL_TYPE: string = 'mail';
const URI_PERMISSION_FLAG: string = 'ability.want.params.uriPermissionFlag';
// canOpenLink requires ://, including for mailto.
const MAILTO_URI: string = 'mailto://';
const ABILITY_CAPABILITY: string = 'SystemCapability.Ability.AbilityRuntime.Core';
const BUNDLE_CAPABILITY: string = 'SystemCapability.BundleManager.BundleFramework.Core';

interface MailClient {
  label: string;
  packageName?: string;
  url?: string;
}

type MailComposerStatus = 'cancelled' | 'undetermined';

interface MailComposerResult {
  status: MailComposerStatus;
}

class MailComposerRequest {
  resolve: (result: MailComposerResult) => void;
  reject: (error: ExpoModuleError) => void;

  constructor(resolve: (result: MailComposerResult) => void, reject: (error: ExpoModuleError) => void) {
    this.resolve = resolve;
    this.reject = reject;
  }
}

export class ExpoMailComposerModule extends ExpoModule {
  private pending?: MailComposerRequest;
  private destroyed: boolean = false;

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoMailComposer')
      .syncFunction('getClients', (): MailClient[] => [])
      .asyncFunction('isAvailableAsync', async (): Promise<boolean> => this.isAvailable())
      .asyncFunction(
        'composeAsync',
        ExpoFunction.typed1(MAIL_COMPOSER_OPTIONS, (options: MailComposerOptions): Promise<MailComposerResult> => this.compose(options)),
      )
      .onPrepareForReload(async (): Promise<void> => this.destroy())
      .onAbilityDestroy((): void => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private isAvailable(): boolean {
    if (this.destroyed || this.context.isHeadless || !canIUse(ABILITY_CAPABILITY) || !canIUse(BUNDLE_CAPABILITY)) return false;

    try {
      return bundleManager.canOpenLink(MAILTO_URI);
    } catch (error) {
      throw new ExpoModuleError(
        'ERR_MAIL_COMPOSER_AVAILABILITY',
        `Unable to query email applications. Declare "mailto" in the host module's querySchemes. ${(error as Error)?.message ?? String(error)}`,
        error as Object,
      );
    }
  }

  private assertForeground(): void {
    if (this.destroyed) throw new ExpoModuleError('ERR_MAIL_COMPOSER_DESTROYED', 'The mail composer host was destroyed.');
    if (this.context.isHeadless || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoModuleError('ERR_MAIL_COMPOSER_BACKGROUND', 'The mail composer requires a foreground application.');
    }
    if (!canIUse(ABILITY_CAPABILITY)) {
      throw new ExpoModuleError('ERR_MAIL_COMPOSER_UNAVAILABLE', 'The system mail composer is unavailable.');
    }
  }

  private compose(options: MailComposerOptions): Promise<MailComposerResult> {
    this.assertForeground();

    if (this.pending !== undefined) {
      throw new ExpoModuleError('ERR_MAIL_COMPOSER_IN_PROGRESS', 'Another mail composer request is in progress.');
    }
    if (options.isHtml) {
      throw new ExpoModuleError('ERR_MAIL_COMPOSER_HTML_UNSUPPORTED', 'The HarmonyOS mail composer protocol only supports plain text bodies.');
    }

    return new Promise<MailComposerResult>((resolve, reject): void => {
      const request = new MailComposerRequest(resolve, reject);
      this.pending = request;

      this.open(request, options).catch((error: Object): void => this.fail(request, error));
    });
  }

  private async open(request: MailComposerRequest, options: MailComposerOptions): Promise<void> {
    // The mail protocol requires encodeURI even for strings that are not URIs.
    const params: Record<string, Object> = {};
    params.email = options.recipients.map((value: string): string => encodeURI(value));
    params.cc = options.ccRecipients.map((value: string): string => encodeURI(value));
    params.bcc = options.bccRecipients.map((value: string): string => encodeURI(value));
    if (options.subject !== undefined) params.subject = encodeURI(options.subject);
    if (options.body !== undefined) params.body = encodeURI(options.body);

    const uris: string[] = [];
    for (const value of options.attachments) {
      if (this.pending !== request) return;

      uris.push(encodeURI(await attachmentUri(value, this.context)));
    }

    if (uris.length > 0) {
      params[wantConstant.Params.PARAMS_STREAM] = uris;
      params[URI_PERMISSION_FLAG] = wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION;
    }

    if (this.pending !== request) return;
    this.assertForeground();

    const callback: common.AbilityStartCallback = {
      onError: (code: number, name: string, message: string): void => {
        this.fail(request, new ExpoModuleError('ERR_MAIL_COMPOSER_COMPOSE', `${name} (${code}): ${message}`));
      },
      onResult: (_result: common.AbilityResult): void => this.finish(request),
      completionHandler: {
        onRequestSuccess: (_name: string): void => this.finish(request),
        onRequestFailure: (name: string, code: AbilityStartFailureCode, message: string): void => {
          if (code === AbilityStartFailureCode.FAILURE_CODE_USER_CANCEL) {
            this.finish(request, 'cancelled');
          } else {
            this.fail(request, new ExpoModuleError('ERR_MAIL_COMPOSER_COMPOSE', `${name} (${code}): ${message}`));
          }
        },
      },
    };

    try {
      // ComposeMail clients need not declare mailto, so canOpenLink cannot gate this call.
      await this.context.uiAbilityContext.startAbilityByType(MAIL_TYPE, params, callback);
    } catch (error) {
      this.fail(request, error as Object);
    }
  }

  private finish(request: MailComposerRequest, status: MailComposerStatus = 'undetermined'): void {
    if (this.pending !== request) return;

    this.pending = undefined;

    request.resolve({ status });
  }

  private fail(request: MailComposerRequest, error: Object): void {
    if (this.pending !== request) return;

    this.pending = undefined;

    request.reject(
      error instanceof ExpoModuleError ? error : new ExpoModuleError('ERR_MAIL_COMPOSER_COMPOSE', (error as Error)?.message ?? String(error), error),
    );
  }

  private destroy(): void {
    this.destroyed = true;

    const request = this.pending;
    this.pending = undefined;

    request?.reject(new ExpoModuleError('ERR_MAIL_COMPOSER_DESTROYED', 'The mail composer host was destroyed while a request was pending.'));
  }
}

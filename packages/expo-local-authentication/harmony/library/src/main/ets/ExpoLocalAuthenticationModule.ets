/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleDefinition,
  ExpoModuleError,
  tryAcquireUserAuthPrompt,
} from '@expo-harmony/expo-modules-core';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { userAuth } from '@kit.UserAuthenticationKit';
import { BiometricsSecurityLevel, LOCAL_AUTHENTICATION_OPTIONS, LocalAuthenticationOptions } from './LocalAuthenticationOptions';
import {
  authenticationResult,
  AuthenticationType,
  availability,
  BIOMETRIC_TYPES,
  hasEnrolledBiometrics,
  isEnrolled,
  LocalAuthenticationResult,
  SecurityLevel,
  STRONG_TRUST_LEVEL,
  supportedAuthenticationTypes,
  WEAK_TRUST_LEVEL,
} from './LocalAuthenticationUtils';

const MAX_PROMPT_LENGTH: number = 500;
const MAX_NAVIGATION_LABEL_LENGTH: number = 60;
const CHALLENGE_BYTES: number = 32;
const MULTIPLE_BIOMETRICS_API_LEVEL: number = 18;
const SKIP_LOCKED_BIOMETRICS_API_LEVEL: number = 20;
const INVALID_NATIVE_PARAMETER: number = 401;
// The numeric result is SDK-stable. Its public UserAuthResultCode enum member starts at API 20.
const INVALID_AUTH_PARAMETERS: number = 12500008;

type CancellationReason = 'user_cancel' | 'app_cancel';

function exceedsCharacterLimit(value: string, limit: number): boolean {
  return value.length > limit && (value.length > limit * 2 || Array.from(value).length > limit);
}

function isInvalidParameter(code: number): boolean {
  return code === INVALID_NATIVE_PARAMETER || code === INVALID_AUTH_PARAMETERS;
}

class InvalidAuthenticationParametersError extends ExpoModuleError {
  constructor(cause?: BusinessError) {
    super(
      'ERR_LOCAL_AUTHENTICATION_INVALID_ARGUMENT',
      'The system rejected the authentication widget parameters.',
      cause,
    );
  }
}

export class ExpoLocalAuthenticationModule extends ExpoModule {
  private cancel?: (reason: CancellationReason) => void;
  private destroyed: boolean = false;

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoLocalAuthentication')
      .asyncFunction('hasHardwareAsync', async (): Promise<boolean> => supportedAuthenticationTypes().length > 0)
      .asyncFunction('supportedAuthenticationTypesAsync', async (): Promise<AuthenticationType[]> => supportedAuthenticationTypes())
      .asyncFunction('isEnrolledAsync', async (): Promise<boolean> => hasEnrolledBiometrics(WEAK_TRUST_LEVEL))
      .asyncFunction('getEnrolledLevelAsync', async (): Promise<SecurityLevel> => {
        if (hasEnrolledBiometrics(STRONG_TRUST_LEVEL)) return SecurityLevel.BIOMETRIC_STRONG;
        if (hasEnrolledBiometrics(WEAK_TRUST_LEVEL)) return SecurityLevel.BIOMETRIC_WEAK;

        const status = availability(userAuth.UserAuthType.PIN, WEAK_TRUST_LEVEL);

        if (isEnrolled(status) || status === userAuth.UserAuthResultCode.PIN_EXPIRED) return SecurityLevel.SECRET;

        return SecurityLevel.NONE;
      })
      .asyncFunction(
        'authenticateAsync',
        ExpoFunction.typed1(
          LOCAL_AUTHENTICATION_OPTIONS,
          (options: LocalAuthenticationOptions): Promise<LocalAuthenticationResult> => this.authenticate(options),
        ),
      )
      .asyncFunction('cancelAuthenticate', async (): Promise<void> => {
        this.cancel?.('user_cancel');
      })
      .onPrepareForReload(async (): Promise<void> => this.destroy())
      .onAbilityDestroy((): void => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private async authenticate(options: LocalAuthenticationOptions): Promise<LocalAuthenticationResult> {
    if (this.destroyed || !this.context.isValid || this.context.isHeadless || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      return { success: false, error: 'invalid_context' };
    }

    const release = tryAcquireUserAuthPrompt();
    if (release === undefined) return { success: false, error: 'app_cancel' };

    try {
      return await this.authenticateWithPrompt(options);
    } finally {
      release();
    }
  }

  private async authenticateWithPrompt(options: LocalAuthenticationOptions): Promise<LocalAuthenticationResult> {
    if (options.promptMessage.length === 0 || exceedsCharacterLimit(options.promptMessage, MAX_PROMPT_LENGTH)) {
      throw new ExpoModuleError('ERR_LOCAL_AUTHENTICATION_INVALID_ARGUMENT', `promptMessage must contain 1 to ${MAX_PROMPT_LENGTH} characters.`);
    }

    const level = options.biometricsSecurityLevel === BiometricsSecurityLevel.STRONG ? STRONG_TRUST_LEVEL : WEAK_TRUST_LEVEL;
    const candidates: userAuth.UserAuthType[] = BIOMETRIC_TYPES.slice();
    if (!options.disableDeviceFallback) candidates.push(userAuth.UserAuthType.PIN);

    let types: userAuth.UserAuthType[] = [];
    let preferred: userAuth.UserAuthType | undefined;
    let missing = false;
    let pinExpired = false;

    for (const type of candidates) {
      const status = availability(type, level);

      if (isEnrolled(status)) types.push(type);
      if (preferred === undefined && status === userAuth.UserAuthResultCode.SUCCESS && type !== userAuth.UserAuthType.PIN) {
        preferred = type;
      }
      if (status === userAuth.UserAuthResultCode.NOT_ENROLLED) missing = true;
      if (status === userAuth.UserAuthResultCode.PIN_EXPIRED) pinExpired = true;
    }

    if (types.length === 0) return { success: false, error: missing && !pinExpired ? 'not_enrolled' : 'not_available' };

    const widget: userAuth.WidgetParam = { title: options.promptMessage };

    if (!types.includes(userAuth.UserAuthType.PIN)) {
      if (exceedsCharacterLimit(options.cancelLabel, MAX_NAVIGATION_LABEL_LENGTH)) {
        throw new ExpoModuleError(
          'ERR_LOCAL_AUTHENTICATION_INVALID_ARGUMENT',
          `cancelLabel must not exceed ${MAX_NAVIGATION_LABEL_LENGTH} characters.`,
        );
      }

      // Offering both biometrics without a PIN requires API 18 and a custom button.
      if (types.length > 1 && (deviceInfo.sdkApiVersion < MULTIPLE_BIOMETRICS_API_LEVEL || options.cancelLabel.length === 0)) {
        types = [preferred ?? types[0]];
      }

      if (options.cancelLabel.length > 0) widget.navigationButtonText = options.cancelLabel;
    }

    let auth: userAuth.UserAuthInstance;

    try {
      if (!canIUse('SystemCapability.Security.CryptoFramework.Rand')) return { success: false, error: 'not_available' };

      const challenge = cryptoFramework.createRandom().generateRandomSync(CHALLENGE_BYTES).data;
      const params: userAuth.AuthParam = {
        challenge,
        authType: types,
        authTrustLevel: level,
      };

      if (deviceInfo.sdkApiVersion >= SKIP_LOCKED_BIOMETRICS_API_LEVEL && types.length > 1) {
        params.skipLockedBiometricAuth = true;
      }

      auth = userAuth.getUserAuthInstance(params, widget);
    } catch (error) {
      const cause = error as BusinessError;
      if (isInvalidParameter(cause.code)) throw new InvalidAuthenticationParametersError(cause);

      return authenticationResult(cause.code);
    }

    return new Promise<LocalAuthenticationResult>((resolve, reject): void => {
      let settled = false;
      let listening = false;
      let cancellation: CancellationReason | undefined;

      const retire = (): boolean => {
        if (settled) return false;

        settled = true;
        if (this.cancel === cancel) this.cancel = undefined;

        if (listening) {
          try {
            auth.off('result', callback);
          } catch (error) {
            this.warn('detach authentication listener', error as BusinessError);
          }

          listening = false;
        }

        return true;
      };

      const finish = (result: LocalAuthenticationResult): void => {
        if (retire()) resolve(result);
      };

      const complete = (code: number, cause?: BusinessError): void => {
        if (cancellation !== undefined) {
          finish({ success: false, error: cancellation });
        } else if (isInvalidParameter(code)) {
          if (retire()) reject(new InvalidAuthenticationParametersError(cause));
        } else {
          finish(authenticationResult(code));
        }
      };

      const callback: userAuth.IAuthCallback = {
        onResult: (result: userAuth.UserAuthResult): void => complete(result.result),
      };

      const cancel = (reason: CancellationReason): void => {
        if (settled) return;

        cancellation = reason;

        try {
          auth.cancel();
        } catch (error) {
          const failure = error as BusinessError;
          if (reason === 'user_cancel' && !settled) {
            // The system still owns the prompt. Keep listening and allow a retry.
            cancellation = undefined;

            throw new ExpoModuleError('ERR_LOCAL_AUTHENTICATION_CANCEL_FAILED', 'Unable to cancel authentication.', failure);
          }

          this.warn('cancel authentication', failure);
        }

        finish({ success: false, error: reason });
      };

      this.cancel = cancel;

      try {
        auth.on('result', callback);
        listening = true;

        auth.start();
      } catch (error) {
        const cause = error as BusinessError;
        complete(cause.code, cause);
      }
    });
  }

  private destroy(): void {
    this.destroyed = true;
    this.cancel?.('app_cancel');
  }

  private warn(action: string, error: BusinessError): void {
    console.warn(`ExpoLocalAuthentication: unable to ${action} (${error.code}).`);
  }
}

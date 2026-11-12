/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError, tryAcquireUserAuthPrompt } from '@expo-harmony/expo-modules-core';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { userAuth } from '@kit.UserAuthenticationKit';

import { ExpoSecureStoreError } from './ExpoSecureStoreError';
import { encode, sha256 } from './SecureStoreOptions';

const BIOMETRIC_TYPES: userAuth.UserAuthType[] = [userAuth.UserAuthType.FACE, userAuth.UserAuthType.FINGERPRINT];
const TRUST_LEVEL: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL3;
const MAX_PROMPT_LENGTH: number = 500;
const INVALID_NATIVE_PARAMETER: number = 401;

export function availableBiometric(): userAuth.UserAuthType | undefined {
  let lockout: BusinessError | undefined;

  for (const type of BIOMETRIC_TYPES) {
    try {
      userAuth.getAvailableStatus(type, TRUST_LEVEL);
      return type;
    } catch (error) {
      const status = error as BusinessError;
      switch (status.code) {
        case userAuth.UserAuthResultCode.LOCKED:
          lockout = status;
          break;
        case userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT:
        case userAuth.UserAuthResultCode.TRUST_LEVEL_NOT_SUPPORT:
        case userAuth.UserAuthResultCode.NOT_ENROLLED:
          break;
        default:
          throw new ExpoSecureStoreError(status);
      }
    }
  }

  if (lockout !== undefined) {
    throw new ExpoModuleError('ERR_SECURE_STORE_AUTH_FAILED', 'Biometric authentication is locked.', lockout);
  }

  return undefined;
}

export function requireAvailableBiometric(): userAuth.UserAuthType {
  const type = availableBiometric();
  if (type === undefined) {
    throw new ExpoModuleError('ERR_SECURE_STORE_AUTH_UNAVAILABLE', 'No enrolled biometric authenticator supports ATL3.');
  }

  return type;
}

export function credentialSnapshot(): Uint8Array {
  const states: number[] = [];

  for (const type of BIOMETRIC_TYPES) {
    try {
      const state = userAuth.getEnrolledState(type);
      states.push(type, state.credentialDigest, state.credentialCount);
    } catch (error) {
      const code = (error as BusinessError).code;

      if (code !== userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT && code !== userAuth.UserAuthResultCode.NOT_ENROLLED)
        throw new ExpoSecureStoreError(error as Object);

      states.push(type, 0, 0);
    }
  }

  return sha256(encode(JSON.stringify(states)));
}

export function credentialsMatch(item: asset.AssetMap): boolean {
  const stored = item.get(asset.Tag.DATA_LABEL_CRITICAL_1);
  if (!(stored instanceof Uint8Array)) throw new ExpoModuleError('ERR_SECURE_STORE_DECODE', 'Missing biometric enrollment state.');

  const current = credentialSnapshot();
  if (stored.length !== current.length) throw new ExpoModuleError('ERR_SECURE_STORE_DECODE', 'Invalid biometric enrollment state.');

  return stored.every((value: number, index: number): boolean => value === current[index]);
}

export class SecureStoreAuthentication {
  private cancelPending?: () => void;

  authenticate(challenge: Uint8Array, prompt: string): Promise<Uint8Array> {
    const tooLong = prompt.length > MAX_PROMPT_LENGTH &&
      (prompt.length > MAX_PROMPT_LENGTH * 2 || Array.from(prompt).length > MAX_PROMPT_LENGTH);
    if (prompt.length === 0 || tooLong) {
      throw new ExpoModuleError('ERR_SECURE_STORE_INVALID_ARGUMENT', `authenticationPrompt must contain 1 to ${MAX_PROMPT_LENGTH} characters.`);
    }

    const release = tryAcquireUserAuthPrompt();
    if (release === undefined) {
      throw new ExpoModuleError('ERR_SECURE_STORE_AUTH_FAILED', 'Another authentication prompt is already in progress.');
    }

    let instance: userAuth.UserAuthInstance;

    try {
      instance = userAuth.getUserAuthInstance(
        {
          challenge,
          // A biometric-only system widget can use one method on API 13.
          authType: [requireAvailableBiometric()],
          authTrustLevel: TRUST_LEVEL,
        },
        { title: prompt },
      );
    } catch (error) {
      release();
      const native = error as BusinessError;
      if (native.code === INVALID_NATIVE_PARAMETER) {
        throw new ExpoModuleError('ERR_SECURE_STORE_INVALID_ARGUMENT', 'The system rejected the authentication widget parameters.', native);
      }
      throw error as Error;
    }

    return new Promise<Uint8Array>((resolve, reject): void => {
      let settled = false;
      let retired = false;

      const finish = (token?: Uint8Array, failure?: Object): void => {
        if (settled) return;

        settled = true;
        this.cancelPending = undefined;

        if (failure !== undefined) reject(failure);
        else if (token !== undefined && token.length > 0) resolve(token);
        else reject(new ExpoModuleError('ERR_SECURE_STORE_AUTH_FAILED', 'Authentication returned no token.'));
      };

      const callback: userAuth.IAuthCallback = {
        onResult: (result: userAuth.UserAuthResult): void => {
          retire();
          if (result.result === userAuth.UserAuthResultCode.SUCCESS) finish(result.token);
          else finish(undefined, new ExpoModuleError('ERR_SECURE_STORE_AUTH_FAILED', `Biometric authentication failed (${result.result}).`));
        },
      };

      const retire = (): void => {
        if (retired) return;

        retired = true;
        release();

        try {
          instance.off('result', callback);
        } catch (error) {
          console.warn(`Unable to detach SecureStore authentication listener: ${(error as BusinessError).code}`);
        }
      };

      const cancel = (): void => {
        // cancel() may synchronously deliver a result; settle before invoking it.
        finish(undefined, new ExpoModuleError('ERR_SECURE_STORE_DESTROYED', 'SecureStore was destroyed during authentication.'));

        try {
          instance.cancel();
          retire();
        } catch (error) {
          console.warn(`Unable to cancel SecureStore authentication: ${(error as BusinessError).code}`);
        }
      };

      this.cancelPending = cancel;

      try {
        instance.on('result', callback);
        instance.start();
      } catch (error) {
        finish(undefined, error as Object);
        retire();
      }
    });
  }

  cancel(): void {
    this.cancelPending?.();
  }
}

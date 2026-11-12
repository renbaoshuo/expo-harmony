/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoAppLifecycleState, ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

import { ExpoSecureStoreError } from './ExpoSecureStoreError';
import {
  accessibility,
  assetAlias,
  decodeSecret,
  encodeSecret,
  KeychainAccessibility,
  SECURE_STORE_OPTIONS,
  SecureStoreOptions,
} from './SecureStoreOptions';
import {
  availableBiometric,
  credentialSnapshot,
  credentialsMatch,
  requireAvailableBiometric,
  SecureStoreAuthentication,
} from './SecureStoreAuthentication';

const operations: Map<string, Promise<void>> = new Map();

export class ExpoSecureStoreModule extends ExpoModule {
  private destroyed: boolean = false;
  private readonly pending: Set<Promise<void>> = new Set();
  private readonly authentication: SecureStoreAuthentication = new SecureStoreAuthentication();

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoSecureStore')
      .constant('AFTER_FIRST_UNLOCK', KeychainAccessibility.AFTER_FIRST_UNLOCK)
      .constant('AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY', KeychainAccessibility.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY)
      .constant('ALWAYS', KeychainAccessibility.ALWAYS)
      .constant('WHEN_PASSCODE_SET_THIS_DEVICE_ONLY', KeychainAccessibility.WHEN_PASSCODE_SET_THIS_DEVICE_ONLY)
      .constant('ALWAYS_THIS_DEVICE_ONLY', KeychainAccessibility.ALWAYS_THIS_DEVICE_ONLY)
      .constant('WHEN_UNLOCKED', KeychainAccessibility.WHEN_UNLOCKED)
      .constant('WHEN_UNLOCKED_THIS_DEVICE_ONLY', KeychainAccessibility.WHEN_UNLOCKED_THIS_DEVICE_ONLY)
      .asyncFunction(
        'setValueWithKeyAsync',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          SECURE_STORE_OPTIONS,
          async (value: string, key: string, options?: SecureStoreOptions): Promise<void> => {
            const config = options ?? new SecureStoreOptions();
            const alias = assetAlias(key, config);

            await this.run(alias, async (): Promise<void> => this.setValue(alias, value, config));
          },
        ),
      )
      .asyncFunction(
        'getValueWithKeyAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          SECURE_STORE_OPTIONS,
          async (key: string, options?: SecureStoreOptions): Promise<string | null> => {
            const config = options ?? new SecureStoreOptions();
            const alias = assetAlias(key, config);

            return this.run(alias, async (): Promise<string | null> => this.getValue(alias, config));
          },
        ).returns(ExpoValueTypes.string().nullable()),
      )
      .asyncFunction(
        'deleteValueWithKeyAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), SECURE_STORE_OPTIONS, async (key: string, options?: SecureStoreOptions): Promise<void> => {
          const alias = assetAlias(key, options ?? new SecureStoreOptions());

          await this.run(alias, async (): Promise<void> => remove(alias));
        }),
      )
      .syncFunction(
        'setValueWithKeySync',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          SECURE_STORE_OPTIONS,
          (value: string, key: string, options?: SecureStoreOptions): void => {
            const config = options ?? new SecureStoreOptions();
            const alias = assetAlias(key, config);

            this.runSync(alias, (): void => this.setValueSync(alias, value, config));
          },
        ),
      )
      .syncFunction(
        'getValueWithKeySync',
        ExpoFunction.typed2(ExpoValueTypes.string(), SECURE_STORE_OPTIONS, (key: string, options?: SecureStoreOptions): string | null => {
          const alias = assetAlias(key, options ?? new SecureStoreOptions());

          return this.runSync(alias, (): string | null => this.getValueSync(alias));
        }).returns(ExpoValueTypes.string().nullable()),
      )
      .syncFunction('canUseBiometricAuthentication', (): boolean => {
        try {
          return availableBiometric() !== undefined;
        } catch (_) {
          return false;
        }
      })
      .onPrepareForReload(async (): Promise<void> => {
        this.destroy();
        await Promise.all(Array.from(this.pending));
      })
      .onAbilityDestroy((): void => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private async getValue(alias: Uint8Array, options: SecureStoreOptions): Promise<string | null> {
    const item = await query(alias, asset.ReturnType.ATTRIBUTES);

    this.assertActive();
    if (item === undefined) return null;

    if (!requiresAuthentication(item)) {
      const stored = await query(alias, asset.ReturnType.ALL);

      return stored === undefined ? null : decodeSecret(stored);
    }

    if (!credentialsMatch(item)) {
      await remove(alias);

      return null;
    }

    const result = await this.queryAuthenticated(alias, options.authenticationPrompt);

    this.assertActive();
    if (result === undefined) return null;

    if (!credentialsMatch(result)) {
      await remove(alias);

      return null;
    }

    return decodeSecret(result);
  }

  private getValueSync(alias: Uint8Array): string | null {
    const item = querySync(alias, asset.ReturnType.ATTRIBUTES);
    if (item === undefined) return null;

    if (requiresAuthentication(item)) {
      if (!credentialsMatch(item)) {
        removeSync(alias);

        return null;
      }

      throw new ExpoModuleError(
        'ERR_SECURE_STORE_SYNC_AUTH_UNSUPPORTED',
        'HarmonyOS biometric authentication is asynchronous. Use getItemAsync/setItemAsync for an existing authenticated item.',
      );
    }

    const stored = querySync(alias, asset.ReturnType.ALL);

    return stored === undefined ? null : decodeSecret(stored);
  }

  private async setValue(alias: Uint8Array, value: string, options: SecureStoreOptions): Promise<void> {
    const secret = encodeSecret(value);

    const item = await query(alias, asset.ReturnType.ATTRIBUTES);

    this.assertActive();
    if (options.requireAuthentication) requireAvailableBiometric();

    if (item !== undefined && requiresAuthentication(item) === options.requireAuthentication) {
      if (!options.requireAuthentication) {
        await asset.update(aliasQuery(alias), valueAttributes(secret));

        return;
      }

      if (credentialsMatch(item)) {
        const result = await this.queryAuthenticated(alias, options.authenticationPrompt);

        this.assertActive();

        if (result !== undefined && credentialsMatch(result)) {
          await asset.update(aliasQuery(alias), valueAttributes(secret));

          return;
        }
      }
    }

    this.assertActive();

    // OVERWRITE encrypts before replacing immutable access controls, avoiding a remove/add gap.
    await asset.add(newAttributes(alias, secret, options));
  }

  private setValueSync(alias: Uint8Array, value: string, options: SecureStoreOptions): void {
    const secret = encodeSecret(value);

    const item = querySync(alias, asset.ReturnType.ATTRIBUTES);

    if (options.requireAuthentication) requireAvailableBiometric();

    if (item !== undefined && requiresAuthentication(item) === options.requireAuthentication) {
      if (!options.requireAuthentication) {
        asset.updateSync(aliasQuery(alias), valueAttributes(secret));

        return;
      }

      if (credentialsMatch(item))
        throw new ExpoModuleError(
          'ERR_SECURE_STORE_SYNC_AUTH_UNSUPPORTED',
          'HarmonyOS biometric authentication is asynchronous. Use getItemAsync/setItemAsync for an existing authenticated item.',
        );
    }

    asset.addSync(newAttributes(alias, secret, options));
  }

  private async queryAuthenticated(alias: Uint8Array, prompt: string): Promise<asset.AssetMap | undefined> {
    this.assertAuthenticationForeground();

    let challenge: Uint8Array;
    try {
      challenge = await asset.preQuery(aliasQuery(alias));
    } catch (error) {
      if (isNotFound(error as Object)) return undefined;

      throw new ExpoSecureStoreError(error as Object);
    }

    let failure: Object | undefined;

    try {
      this.assertAuthenticationForeground();

      const token = await this.authentication.authenticate(challenge, prompt);

      try {
        this.assertActive();

        const request = readQuery(alias, asset.ReturnType.ALL);
        request.set(asset.Tag.AUTH_CHALLENGE, challenge);
        request.set(asset.Tag.AUTH_TOKEN, token);

        return singleResult(await asset.query(request));
      } finally {
        token.fill(0);
      }
    } catch (error) {
      failure = error as Object;
      if (isNotFound(failure)) return undefined;

      throw new ExpoSecureStoreError(failure);
    } finally {
      const handle: asset.AssetMap = new Map();
      handle.set(asset.Tag.AUTH_CHALLENGE, challenge);

      try {
        await asset.postQuery(handle);
      } catch (error) {
        if (failure === undefined || isNotFound(failure)) throw new ExpoSecureStoreError(error as Object);

        console.warn(`Unable to finish SecureStore authentication query: ${(error as BusinessError).code}`);
      }
    }
  }

  private async run<T>(alias: Uint8Array, operation: () => Promise<T>): Promise<T> {
    this.assertActive();

    const lock = new util.Base64Helper().encodeToStringSync(alias);
    const previous = operations.get(lock) ?? Promise.resolve();
    const task = previous.then(async (): Promise<T> => {
      this.assertActive();

      try {
        const result = await operation();

        this.assertActive();

        return result;
      } catch (error) {
        throw new ExpoSecureStoreError(error as Object);
      }
    });

    const settled = task.then(
      (): void => {},
      (): void => {},
    );
    operations.set(lock, settled);
    this.pending.add(settled);

    try {
      return await task;
    } finally {
      this.pending.delete(settled);
      if (operations.get(lock) === settled) operations.delete(lock);
    }
  }

  private runSync<T>(alias: Uint8Array, operation: () => T): T {
    this.assertActive();
    if (operations.has(new util.Base64Helper().encodeToStringSync(alias))) {
      throw new ExpoModuleError(
        'ERR_SECURE_STORE_BUSY',
        'An operation for this SecureStore key is pending. Await it before using the synchronous API.',
      );
    }

    try {
      return operation();
    } catch (error) {
      throw new ExpoSecureStoreError(error as Object);
    }
  }

  private assertActive(): void {
    if (this.destroyed) throw new ExpoModuleError('ERR_SECURE_STORE_DESTROYED', 'The SecureStore runtime has been destroyed.');
  }

  private assertAuthenticationForeground(): void {
    this.assertActive();
    if (this.context.isHeadless || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoModuleError('ERR_SECURE_STORE_AUTH_FAILED', 'Biometric authentication requires a foreground application.');
    }
  }

  private destroy(): void {
    this.destroyed = true;
    this.authentication.cancel();
  }
}

function aliasQuery(alias: Uint8Array): asset.AssetMap {
  const fields: asset.AssetMap = new Map();
  fields.set(asset.Tag.ALIAS, alias);
  return fields;
}

function readQuery(alias: Uint8Array, type: asset.ReturnType): asset.AssetMap {
  const fields = aliasQuery(alias);
  fields.set(asset.Tag.RETURN_TYPE, type);
  fields.set(asset.Tag.RETURN_LIMIT, 1);
  return fields;
}

function valueAttributes(secret: Uint8Array): asset.AssetMap {
  const fields: asset.AssetMap = new Map();
  fields.set(asset.Tag.SECRET, secret);
  return fields;
}

function newAttributes(alias: Uint8Array, secret: Uint8Array, options: SecureStoreOptions): asset.AssetMap {
  const fields = aliasQuery(alias);
  fields.set(asset.Tag.SECRET, secret);
  fields.set(asset.Tag.ACCESSIBILITY, accessibility(options.keychainAccessible));
  fields.set(
    asset.Tag.REQUIRE_PASSWORD_SET,
    options.requireAuthentication || options.keychainAccessible === KeychainAccessibility.WHEN_PASSCODE_SET_THIS_DEVICE_ONLY,
  );
  fields.set(asset.Tag.AUTH_TYPE, options.requireAuthentication ? asset.AuthType.ANY : asset.AuthType.NONE);
  fields.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
  fields.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);

  if (options.requireAuthentication) fields.set(asset.Tag.DATA_LABEL_CRITICAL_1, credentialSnapshot());

  return fields;
}

function requiresAuthentication(item: asset.AssetMap): boolean {
  const type = item.get(asset.Tag.AUTH_TYPE);
  if (type !== asset.AuthType.NONE && type !== asset.AuthType.ANY) {
    throw new ExpoModuleError('ERR_SECURE_STORE_DECODE', 'Invalid SecureStore authentication policy.');
  }

  return type === asset.AuthType.ANY;
}

async function query(alias: Uint8Array, type: asset.ReturnType): Promise<asset.AssetMap | undefined> {
  try {
    return singleResult(await asset.query(readQuery(alias, type)));
  } catch (error) {
    if (isNotFound(error as Object)) return undefined;

    throw new ExpoSecureStoreError(error as Object);
  }
}

function querySync(alias: Uint8Array, type: asset.ReturnType): asset.AssetMap | undefined {
  try {
    return singleResult(asset.querySync(readQuery(alias, type)));
  } catch (error) {
    if (isNotFound(error as Object)) return undefined;

    throw new ExpoSecureStoreError(error as Object);
  }
}

function singleResult(items: asset.AssetMap[]): asset.AssetMap {
  if (items.length !== 1) throw new ExpoModuleError('ERR_SECURE_STORE_DECODE', 'Asset Store returned an unexpected number of records.');
  return items[0];
}

async function remove(alias: Uint8Array): Promise<void> {
  try {
    // Always reach durable storage, including on retries after a failed delete (SDK 57).
    await asset.remove(aliasQuery(alias));
  } catch (error) {
    if (!isNotFound(error as Object)) throw new ExpoSecureStoreError(error as Object);
  }
}

function removeSync(alias: Uint8Array): void {
  try {
    asset.removeSync(aliasQuery(alias));
  } catch (error) {
    if (!isNotFound(error as Object)) throw new ExpoSecureStoreError(error as Object);
  }
}

function isNotFound(error: Object): boolean {
  return (error as BusinessError).code === asset.ErrorCode.NOT_FOUND;
}

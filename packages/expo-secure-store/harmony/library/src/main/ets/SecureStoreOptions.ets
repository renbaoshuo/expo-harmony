/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError, ExpoValueType } from '@expo-harmony/expo-modules-core';
import { asset } from '@kit.AssetStoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export enum KeychainAccessibility {
  AFTER_FIRST_UNLOCK = 0,
  AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY = 1,
  ALWAYS = 2,
  WHEN_PASSCODE_SET_THIS_DEVICE_ONLY = 3,
  ALWAYS_THIS_DEVICE_ONLY = 4,
  WHEN_UNLOCKED = 5,
  WHEN_UNLOCKED_THIS_DEVICE_ONLY = 6,
}

export class SecureStoreOptions {
  keychainService: string = 'app';
  requireAuthentication: boolean = false;
  authenticationPrompt: string = 'Authenticate to access secure data';
  keychainAccessible: KeychainAccessibility = KeychainAccessibility.WHEN_UNLOCKED;
}

export const SECURE_STORE_OPTIONS = new ExpoValueType<SecureStoreOptions>(
  'SecureStore options',
  (value: ESObject): SecureStoreOptions => {
    const options = new SecureStoreOptions();

    if (value === undefined || value === null) return options;
    if (typeof value !== 'object' || Array.isArray(value))
      throw new ExpoModuleError('ERR_SECURE_STORE_INVALID_ARGUMENT', 'options must be an object.');

    const fields = value as Record<string, ESObject>;
    options.keychainService = optionalString(fields.keychainService, 'keychainService') ?? options.keychainService;
    options.authenticationPrompt = optionalString(fields.authenticationPrompt, 'authenticationPrompt') ?? options.authenticationPrompt;

    if (fields.requireAuthentication !== undefined && fields.requireAuthentication !== null) {
      if (typeof fields.requireAuthentication !== 'boolean')
        throw new ExpoModuleError('ERR_SECURE_STORE_INVALID_ARGUMENT', 'requireAuthentication must be a boolean.');
      options.requireAuthentication = fields.requireAuthentication as boolean;
    }

    if (fields.keychainAccessible !== undefined && fields.keychainAccessible !== null) {
      const accessible: ESObject = fields.keychainAccessible;
      if (
        typeof accessible !== 'number' ||
        !Number.isInteger(accessible) ||
        accessible < KeychainAccessibility.AFTER_FIRST_UNLOCK ||
        accessible > KeychainAccessibility.WHEN_UNLOCKED_THIS_DEVICE_ONLY
      ) {
        throw new ExpoModuleError('ERR_SECURE_STORE_INVALID_ARGUMENT', 'keychainAccessible must be a SecureStore accessibility constant.');
      }

      options.keychainAccessible = accessible as KeychainAccessibility;
    }

    if (optionalString(fields.accessGroup, 'accessGroup') !== undefined) {
      throw new ExpoModuleError('ERR_SECURE_STORE_UNSUPPORTED_OPTION', 'accessGroup is only supported on iOS.');
    }

    return options;
  },
  (value: SecureStoreOptions): ESObject => value as ESObject,
).optional();

const STORAGE_NAMESPACE: string = 'expo-secure-store';
const STORAGE_VERSION: number = 1;
const MAX_SECRET_BYTES: number = 1024;
const VALUE_HEADER_BYTES: number = 1;

export function assetAlias(key: string, options: SecureStoreOptions): Uint8Array {
  if (!/^[\w.-]+$/.test(key))
    throw new ExpoModuleError(
      'ERR_SECURE_STORE_INVALID_ARGUMENT',
      'Keys must not be empty and may contain only alphanumeric characters, ".", "-", and "_".',
    );

  // Structured hashing avoids service/key collisions and the 256-byte ASSET alias limit.
  return sha256(encode(JSON.stringify([STORAGE_NAMESPACE, STORAGE_VERSION, options.keychainService, key])));
}

export function encode(value: string): Uint8Array {
  // HarmonyOS encodeInto returns undefined for an empty string.
  if (value.length === 0) return new Uint8Array(0);
  return new util.TextEncoder().encodeInto(value);
}

export function sha256(value: Uint8Array): Uint8Array {
  const digest = cryptoFramework.createMd('SHA256');
  digest.updateSync({ data: value });
  return digest.digestSync().data;
}

export function encodeSecret(value: string): Uint8Array {
  const bytes = encode(value);

  try {
    if (bytes.length + VALUE_HEADER_BYTES > MAX_SECRET_BYTES) {
      throw new ExpoModuleError(
        'ERR_SECURE_STORE_VALUE_TOO_LARGE',
        `HarmonyOS SecureStore supports at most ${MAX_SECRET_BYTES - VALUE_HEADER_BYTES} UTF-8 bytes per value.`,
      );
    }

    // ASSET disallows empty secrets, so the encrypted header also represents an empty string.
    const secret = new Uint8Array(bytes.length + VALUE_HEADER_BYTES);
    secret[0] = STORAGE_VERSION;
    secret.set(bytes, VALUE_HEADER_BYTES);

    return secret;
  } finally {
    bytes.fill(0);
  }
}

export function decodeSecret(item: asset.AssetMap): string {
  const secret = item.get(asset.Tag.SECRET);
  if (!(secret instanceof Uint8Array)) {
    throw new ExpoModuleError('ERR_SECURE_STORE_DECODE', 'The SecureStore record has an invalid or unsupported format.');
  }

  try {
    if (secret.length < VALUE_HEADER_BYTES || secret.length > MAX_SECRET_BYTES || secret[0] !== STORAGE_VERSION) {
      throw new ExpoModuleError('ERR_SECURE_STORE_DECODE', 'The SecureStore record has an invalid or unsupported format.');
    }

    if (secret.length === VALUE_HEADER_BYTES) return '';

    // HarmonyOS preserves the BOM when ignoreBOM is false.
    try {
      return util.TextDecoder.create('utf-8', { ignoreBOM: false, fatal: true }).decodeToString(secret.subarray(VALUE_HEADER_BYTES), { stream: false });
    } catch (error) {
      throw new ExpoModuleError('ERR_SECURE_STORE_DECODE', 'The SecureStore value is not valid UTF-8.', error as Object);
    }
  } finally {
    secret.fill(0);
  }
}

export function accessibility(value: KeychainAccessibility): asset.Accessibility {
  switch (value) {
    case KeychainAccessibility.ALWAYS:
    case KeychainAccessibility.ALWAYS_THIS_DEVICE_ONLY:
      return asset.Accessibility.DEVICE_POWERED_ON;
    case KeychainAccessibility.AFTER_FIRST_UNLOCK:
    case KeychainAccessibility.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY:
      return asset.Accessibility.DEVICE_FIRST_UNLOCKED;
    default:
      return asset.Accessibility.DEVICE_UNLOCKED;
  }
}

function optionalString(value: ESObject, name: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') throw new ExpoModuleError('ERR_SECURE_STORE_INVALID_ARGUMENT', `${name} must be a string.`);
  return value;
}

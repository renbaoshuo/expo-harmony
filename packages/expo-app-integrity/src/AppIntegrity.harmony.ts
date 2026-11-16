/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import ExpoAppIntegrity from '@expo/app-integrity/build/ExpoAppIntegrity';

export const isSupported = ExpoAppIntegrity.isSupported;
export const generateKeyAsync = ExpoAppIntegrity.generateKeyAsync.bind(ExpoAppIntegrity);
export const attestKeyAsync = ExpoAppIntegrity.attestKeyAsync.bind(ExpoAppIntegrity);
export const generateAssertionAsync = ExpoAppIntegrity.generateAssertionAsync.bind(ExpoAppIntegrity);
export const prepareIntegrityTokenProviderAsync
  = ExpoAppIntegrity.prepareIntegrityTokenProviderAsync.bind(ExpoAppIntegrity);
export const requestIntegrityCheckAsync = ExpoAppIntegrity.requestIntegrityCheckAsync.bind(ExpoAppIntegrity);
export const isHardwareAttestationSupportedAsync
  = ExpoAppIntegrity.isHardwareAttestationSupportedAsync.bind(ExpoAppIntegrity);

class ExpoAppIntegrityError extends Error {
  readonly code = 'ERR_APP_INTEGRITY_INVALID_INPUT';
}

function validateString(value: string, name: string): void {
  if (typeof value !== 'string') {
    throw new ExpoAppIntegrityError(`The ${name} must be a string.`);
  }

  // The native bridge encodes strings as UTF-8, which cannot preserve lone UTF-16 surrogates.
  if (/[\ud800-\udfff]/u.test(value)) {
    throw new ExpoAppIntegrityError(`The ${name} must contain valid Unicode characters.`);
  }
}

export async function generateHardwareAttestedKeyAsync(keyAlias: string, challenge: string): Promise<void> {
  validateString(keyAlias, 'key alias');
  validateString(challenge, 'challenge');

  return ExpoAppIntegrity.generateHardwareAttestedKeyAsync(keyAlias, challenge);
}

export async function getAttestationCertificateChainAsync(keyAlias: string): Promise<string[]> {
  validateString(keyAlias, 'key alias');
  return ExpoAppIntegrity.getAttestationCertificateChainAsync(keyAlias);
}

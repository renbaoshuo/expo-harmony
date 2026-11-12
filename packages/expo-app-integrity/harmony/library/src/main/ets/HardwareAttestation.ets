/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common } from '@kit.AbilityKit';
import { buffer, util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { cert } from '@kit.DeviceCertificateKit';
import { huks } from '@kit.UniversalKeystoreKit';

import { ExpoAppIntegrityError, IntegrityErrorCode } from './ExpoAppIntegrityError';

const KEY_PREFIX: string = 'expo.app-integrity.';
const PREFERENCES_NAME: string = 'expo.app-integrity.certificates';
const MAX_KEY_ALIAS_BYTES: number = 128;
const KEY_OPTIONS: huks.HuksOptions = { properties: [] };

// Shared across RN runtimes so a reload cannot overlap replacement and certificate reads.
let queue: Promise<void> = Promise.resolve();

function serialized<T>(operation: () => Promise<T>): Promise<T> {
  const result = queue.then(operation);
  queue = result.then(
    (): void => {},
    (): void => {},
  );

  return result;
}

export function isHardwareAttestationSupported(): boolean {
  return (
    canIUse('SystemCapability.Security.Huks.Core') &&
    canIUse('SystemCapability.Security.Huks.Extension') &&
    canIUse('SystemCapability.Security.Cert') &&
    canIUse('SystemCapability.DistributedDataManager.Preferences.Core')
  );
}

function checkedAlias(name: string): string {
  if (!isHardwareAttestationSupported()) {
    throw new ExpoAppIntegrityError(IntegrityErrorCode.HARDWARE_NOT_SUPPORTED, 'HUKS key attestation is not available.');
  }

  const alias = KEY_PREFIX + name;
  // Preferences persists aliases as XML attributes, where these characters cannot round-trip.
  const invalidXml = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/;
  if (
    name.length === 0 ||
    invalidXml.test(name) ||
    new util.TextEncoder().encodeInto(alias).length > MAX_KEY_ALIAS_BYTES
  ) {
    throw new ExpoAppIntegrityError(
      IntegrityErrorCode.INVALID_INPUT,
      'The key alias must be nonempty, contain only XML-compatible characters, and fit within the HUKS 128-byte limit including the module prefix.',
    );
  }

  return alias;
}

function keyGenerationOptions(): huks.HuksOptions {
  if (canIUse('SystemCapability.Security.Huks.Core') && canIUse('SystemCapability.Security.Huks.Extension')) {
    return {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_ECC },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_ECC_KEY_SIZE_256 },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_SIGN },
        { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_SHA256 },
      ],
    };
  }

  throw new ExpoAppIntegrityError(IntegrityErrorCode.HARDWARE_NOT_SUPPORTED, 'HUKS key generation is not available.');
}

async function certificatesToBase64(chain: string[] | undefined, encoding: buffer.BufferEncoding): Promise<string[]> {
  if (chain === undefined || chain.length === 0) {
    throw new ExpoAppIntegrityError(IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID, 'No attestation certificates are available.');
  }

  try {
    const result: string[] = [];
    for (const value of chain) {
      const bytes = buffer.from(value, encoding);
      const certificate = await cert.createX509Cert({
        data: Uint8Array.from(bytes.values()),
        encodingFormat: value.startsWith('-----BEGIN CERTIFICATE-----') ? cert.EncodingFormat.FORMAT_PEM : cert.EncodingFormat.FORMAT_DER,
      });

      const encoded = await certificate.getEncoded();
      result.push(buffer.from(encoded.data).toString('base64'));
    }

    return result;
  } catch (error) {
    throw new ExpoAppIntegrityError(IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID, 'Failed to read attestation certificates.', error as Object);
  }
}

export class HardwareAttestation {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context.getApplicationContext();
  }

  async generate(name: string, challenge: string): Promise<void> {
    const alias = checkedAlias(name);

    const bytes = new util.TextEncoder().encodeInto(challenge);
    const options = keyGenerationOptions();

    await serialized(async (): Promise<void> => {
      let stage = IntegrityErrorCode.KEY_GENERATION_FAILED;
      let store: preferences.Preferences | undefined;
      let attempted = false;

      try {
        store = await preferences.getPreferences(this.context, { name: PREFERENCES_NAME });

        // A failed flush can leave the cached alias absent while its old chain remains on disk.
        // Put and delete to make every invalidation dirty before changing the key.
        store.putSync(alias, '');
        store.deleteSync(alias);
        await store.flush();

        if (await huks.hasKeyItem(alias, KEY_OPTIONS)) {
          await huks.deleteKeyItem(alias, KEY_OPTIONS);
        }

        // IPC can reject after HUKS has created the key; include that case in cleanup.
        attempted = true;
        await huks.generateKeyItem(alias, options);

        stage = IntegrityErrorCode.ATTESTATION_FAILED;
        const attestation = await huks.anonAttestKeyItem(alias, {
          properties: [
            { tag: huks.HuksTag.HUKS_TAG_ATTESTATION_CHALLENGE, value: bytes },
            { tag: huks.HuksTag.HUKS_TAG_ATTESTATION_ID_ALIAS, value: new util.TextEncoder().encodeInto(alias) },
          ],
        });

        stage = IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID;
        // HUKS N-API transports certificate bytes as Latin-1 strings, including PEM output.
        const chain = await certificatesToBase64(attestation.certChains, 'latin1');

        stage = IntegrityErrorCode.ATTESTATION_FAILED;
        await store.put(alias, chain);
        await store.flush();
      } catch (error) {
        let message = 'Failed to generate or attest the key.';
        if (attempted) {
          try {
            if (await huks.hasKeyItem(alias, KEY_OPTIONS)) {
              await huks.deleteKeyItem(alias, KEY_OPTIONS);
            }
          } catch (cleanup) {
            message += ` Key cleanup failed: ${(cleanup as Error).message}`;
          }

          try {
            store?.deleteSync(alias);
          } catch (cleanup) {
            message += ` Certificate cleanup failed: ${(cleanup as Error).message}`;
          }

          try {
            await store?.flush();
          } catch (cleanup) {
            message += ` Certificate cleanup flush failed: ${(cleanup as Error).message}`;
          }
        }

        throw new ExpoAppIntegrityError(stage, message, error as Object);
      }
    });
  }

  async getCertificateChain(name: string): Promise<string[]> {
    const alias = checkedAlias(name);

    return serialized(async (): Promise<string[]> => {
      try {
        const store = await preferences.getPreferences(this.context, { name: PREFERENCES_NAME });
        const value = await store.get(alias, []);

        if (
          !(await huks.hasKeyItem(alias, KEY_OPTIONS)) ||
          !Array.isArray(value) ||
          value.length === 0 ||
          !value.every((item: Object): boolean => typeof item === 'string' && item.length > 0)
        ) {
          throw new ExpoAppIntegrityError(
            IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID,
            'No attestation certificate chain exists for this key alias.',
          );
        }

        return await certificatesToBase64(value as string[], 'base64');
      } catch (error) {
        throw new ExpoAppIntegrityError(IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID, 'Failed to read attestation certificates.', error as Object);
      }
    });
  }
}

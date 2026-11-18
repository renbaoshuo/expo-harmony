/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common } from '@kit.AbilityKit';
import { buffer, util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { cert } from '@kit.DeviceCertificateKit';
import { huks } from '@kit.UniversalKeystoreKit';

import { ExpoAppIntegrityError, IntegrityErrorCode } from './ExpoAppIntegrityError';

const KEY_PREFIX: string = 'expo.app-integrity.';
const PREFERENCES_NAME: string = 'expo.app-integrity.certificates';
const MAX_KEY_ALIAS_BYTES: number = 128;
const MAX_ATTESTATION_CHALLENGE_BYTES: number = 128;
const KEY_OPTIONS: huks.HuksOptions = { properties: [] };

interface StoredAttestation {
  // Older releases compare this field before reading the chain.
  publicKey: string;
  certificates: string[];
}

// Limit each ArkTS runtime to one waiting file lock so lock contention does not exhaust the I/O pool.
let queue: Promise<void> = Promise.resolve();

function serialized<T>(path: string, code: IntegrityErrorCode, operation: () => Promise<T>): Promise<T> {
  const result = queue.then(async (): Promise<T> => {
    try {
      const lock = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);

      try {
        await lock.lock(true);

        return await operation();
      } finally {
        await fileIo.close(lock);
      }
    } catch (error) {
      if (error instanceof ExpoAppIntegrityError) return Promise.reject(error);

      throw new ExpoAppIntegrityError(code, 'Could not access the attestation store.', error as Object);
    }
  });

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
    canIUse('SystemCapability.FileManagement.File.FileIO')
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
  return {
    properties: [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_ECC },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_ECC_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_SIGN },
      { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_SHA256 },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
    ],
  };
}

async function getPublicKey(alias: string): Promise<string> {
  const bytes = (await huks.exportKeyItem(alias, KEY_OPTIONS)).outData;
  if (!bytes?.length) {
    throw new ExpoAppIntegrityError(IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID, 'The attested key has no public key.');
  }

  return buffer.from(bytes).toString('base64');
}

async function writeAttestation(path: string, record: StoredAttestation | null): Promise<void> {
  const temp = path + '.tmp';
  let published = false;

  try {
    const file = await fileIo.open(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);

    try {
      const value = JSON.stringify(record);
      if (await fileIo.write(file.fd, value) !== value.length) {
        throw new Error('Could not write the complete attestation record.');
      }

      await fileIo.fsync(file.fd);
    } finally {
      await fileIo.close(file);
    }

    await fileIo.rename(temp, path);
    published = true;
  } finally {
    if (!published) {
      try {
        await fileIo.unlink(temp);
      } catch {}
    }
  }
}

async function readAttestation(path: string): Promise<StoredAttestation | null | undefined> {
  if (!(await fileIo.access(path))) return undefined;

  return JSON.parse(await fileIo.readText(path)) as StoredAttestation | null;
}

async function attestKey(alias: string, challenge: Uint8Array): Promise<huks.HuksReturnResult> {
  const params: huks.HuksParam[] = [
    { tag: huks.HuksTag.HUKS_TAG_ATTESTATION_CHALLENGE, value: challenge },
    { tag: huks.HuksTag.HUKS_TAG_ATTESTATION_ID_ALIAS, value: new util.TextEncoder().encodeInto(alias) },
  ];

  if (typeof huks.anonAttestKeyItemOffline === 'function') {
    try {
      return await huks.anonAttestKeyItemOffline(alias, params);
    } catch (error) {
      if ((error as BusinessError).code !== huks.HuksExceptionErrCode.HUKS_ERR_CODE_NOT_SUPPORTED_API) {
        throw new ExpoAppIntegrityError(IntegrityErrorCode.ATTESTATION_FAILED, 'Offline key attestation failed.', error as Object);
      }
    }
  }

  return await huks.anonAttestKeyItem(alias, { properties: params });
}

async function certificatesToBase64(
  chain: string[] | undefined,
  encoding: buffer.BufferEncoding,
  publicKey: string,
): Promise<string[]> {
  if (!Array.isArray(chain) || chain.length === 0) {
    throw new ExpoAppIntegrityError(IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID, 'No attestation certificates are available.');
  }

  try {
    const encoded: string[] = [];

    for (const value of chain) {
      const bytes = buffer.from(value, encoding);
      const certificate = await cert.createX509Cert({
        data: Uint8Array.from(bytes.values()),
        encodingFormat: value.startsWith('-----BEGIN CERTIFICATE-----') ? cert.EncodingFormat.FORMAT_PEM : cert.EncodingFormat.FORMAT_DER,
      });

      // HUKS returns the leaf first, including in legacy records.
      if (encoded.length === 0) {
        const key = certificate.getPublicKey().getEncoded()?.data;
        if (key === undefined || buffer.from(key).toString('base64') !== publicKey) {
          throw new Error('The leaf certificate does not match the attested public key.');
        }
      }

      const der = await certificate.getEncoded();
      encoded.push(buffer.from(der.data).toString('base64'));
    }

    return encoded;
  } catch (error) {
    throw new ExpoAppIntegrityError(IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID, 'Failed to read attestation certificates.', error as Object);
  }
}

export class HardwareAttestation {
  private readonly context: common.Context;
  private readonly lockPath: string;

  constructor(context: common.Context) {
    this.context = context.getApplicationContext();
    this.lockPath = this.context.filesDir + '/expo.app-integrity.lock';
  }

  async generate(name: string, challenge: string): Promise<void> {
    const alias = checkedAlias(name);
    const bytes = new util.TextEncoder().encodeInto(challenge);

    if (bytes.length === 0 || bytes.length > MAX_ATTESTATION_CHALLENGE_BYTES) {
      throw new ExpoAppIntegrityError(
        IntegrityErrorCode.INVALID_INPUT,
        `The attestation challenge must contain 1 to ${MAX_ATTESTATION_CHALLENGE_BYTES} UTF-8 bytes.`,
      );
    }

    const path = this.recordPath(alias);
    const options = keyGenerationOptions();

    await serialized(this.lockPath, IntegrityErrorCode.KEY_GENERATION_FAILED, async (): Promise<void> => {
      let stage = IntegrityErrorCode.KEY_GENERATION_FAILED;
      let attempted = false;

      try {
        const exists = await huks.hasKeyItem(alias, KEY_OPTIONS);

        // Persist invalidation before replacement so an interrupted write cannot expose the old chain.
        await writeAttestation(path, null);

        if (exists) {
          await huks.deleteKeyItem(alias, KEY_OPTIONS);
        }

        // IPC can reject after HUKS has created the key; include that case in cleanup.
        attempted = true;
        await huks.generateKeyItem(alias, options);

        const publicKey = await getPublicKey(alias);

        stage = IntegrityErrorCode.ATTESTATION_FAILED;
        const attestation = await attestKey(alias, bytes);

        stage = IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID;
        // HUKS N-API transports certificate bytes as Latin-1 strings, including PEM output.
        const chain = await certificatesToBase64(attestation.certChains, 'latin1', publicKey);

        stage = IntegrityErrorCode.ATTESTATION_FAILED;
        await writeAttestation(path, { publicKey, certificates: chain });
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
        }

        throw new ExpoAppIntegrityError(stage, message, error as Object);
      }
    });
  }

  async getCertificateChain(name: string): Promise<string[]> {
    const alias = checkedAlias(name);

    return serialized(this.lockPath, IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID, async (): Promise<string[]> => {
      const record = await readAttestation(this.recordPath(alias));

      if (record !== undefined) {
        if (record === null) {
          throw new ExpoAppIntegrityError(IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID, 'No attestation chain matches this key.');
        }

        return await certificatesToBase64(record.certificates, 'base64', await getPublicKey(alias));
      }

      // Older releases stored the chain in Preferences without a separate public key.
      if (!canIUse('SystemCapability.DistributedDataManager.Preferences.Core')) {
        throw new ExpoAppIntegrityError(IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID, 'No attestation chain exists for this key.');
      }

      const store = await preferences.getPreferences(this.context, { name: PREFERENCES_NAME });
      const legacy = await store.get(alias, []);
      if (!Array.isArray(legacy)) {
        throw new ExpoAppIntegrityError(IntegrityErrorCode.CERTIFICATE_CHAIN_INVALID, 'No attestation chain exists for this key.');
      }

      return await certificatesToBase64(legacy as string[], 'base64', await getPublicKey(alias));
    });
  }

  private recordPath(alias: string): string {
    return this.context.filesDir + '/expo.app-integrity.' + buffer.from(alias).toString('base64url') + '.json';
  }
}

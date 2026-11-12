/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import cert from '@ohos.security.cert';
import crypto from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { parseDictionary, serializeDictionary } from '@expo-harmony/expo-structured-headers';
import { UpdatesConfiguration } from './UpdatesConfiguration';
import { ExpoUpdatesError, SignatureResult } from './UpdatesProtocol';
import { decode, encode } from './UpdatesStorage';

const projectOid = '1.2.840.113556.1.8000.2554.43437.254.128.102.157.7894389.20439.2.1';

interface DerField { tag: number; value: Uint8Array; }

function der(bytes: Uint8Array): DerField[] {
  const fields: DerField[] = [];
  let offset = 0;
  while (offset < bytes.length) {
    if (offset + 2 > bytes.length) throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Incomplete certificate extension.');

    const tag = bytes[offset++];
    let length = bytes[offset++];
    if (length >= 128) {
      const count = length & 127;
      if (count === 0 || count > 4 || offset + count > bytes.length) throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Invalid certificate extension length.');

      length = 0;
      for (let index = 0; index < count; index++) length = length * 256 + bytes[offset++];
    }
    if (offset + length > bytes.length) throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Incomplete certificate extension value.');

    fields.push({ tag, value: bytes.subarray(offset, offset + length) });
    offset += length;
  }

  return fields;
}

function project(certificate: cert.X509Cert): string[] | undefined {
  // Some Harmony SDKs cannot enumerate Expo's long OID. Read its DER extension
  // directly; certificate-chain and signature verification remain native.
  const parts = projectOid.split('.').map(Number);
  const encoded = [parts[0] * 40 + parts[1]];
  for (const part of parts.slice(2)) {
    const bytes: number[] = [];
    let value = part;
    do { bytes.unshift(value % 128); value = Math.floor(value / 128); } while (value > 0);
    encoded.push(...bytes.map((byte, index) => index < bytes.length - 1 ? byte | 128 : byte));
  }

  const outer = der(certificate.getExtensionsObject().getEncoded().data);
  if (outer.length !== 1 || outer[0].tag !== 48) throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Invalid certificate extensions.');

  let result: string[] | undefined;
  for (const extension of der(outer[0].value)) {
    if (extension.tag !== 48) throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Invalid certificate extension sequence.');

    const fields = der(extension.value);
    if (fields[0]?.tag !== 6 || !equals(fields[0].value, new Uint8Array(encoded))) continue;
    if (result || (fields.length !== 2 && fields.length !== 3) || (fields.length === 3 && fields[1].tag !== 1) || fields[fields.length - 1].tag !== 4) {
      throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Invalid Expo project extension.');
    }

    const values = decode(fields[fields.length - 1].value).split(',').map(value => value.trim());
    if (values.length !== 2) throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Invalid Expo project information in certificate.');

    result = values;
  }

  return result;
}

function equals(a: Uint8Array, b: Uint8Array): boolean { return a.length === b.length && a.every((value, index) => value === b[index]); }

export class UpdatesSigning {
  constructor(private readonly configuration: UpdatesConfiguration) {}

  get expectation(): string | undefined {
    if (!this.configuration.certificate) return undefined;
    return serializeDictionary(new Map([['sig', [true, new Map()]], ['keyid', [this.configuration.key, new Map()]], ['alg', [this.configuration.algorithm, new Map()]]]));
  }

  async verify(body: string, signature?: string, response?: string): Promise<SignatureResult> {
    const config = this.configuration;
    if (!config.certificate) return { verified: false };
    if (signature === undefined) {
      if (config.unsigned) return { verified: false };
      throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'The update response is missing its required signature.');
    }

    let stage = 'signature header';

    try {
      const header = parseDictionary(signature);
      const signatureValue = header.get('sig')?.[0];
      if (typeof signatureValue !== 'string') throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Signature header requires a Base64 sig string.');

      const algorithm = header.get('alg')?.[0];
      if (typeof algorithm === 'string' && algorithm !== config.algorithm) {
        throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', `Unsupported signature algorithm: ${algorithm}.`);
      }

      const key = header.get('keyid')?.[0];
      if (!config.chain && (typeof key === 'string' ? key : 'root') !== config.key) {
        throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Signature keyid does not match the configured key.');
      }

      stage = 'certificate decoding';
      const pem = /-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g;
      const anchors = config.certificate.match(pem) ?? [];
      if (anchors.length !== 1) {
        throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'The app must provide one trusted PEM signing certificate.');
      }

      const intermediates = config.chain ? response?.match(pem) ?? [] : [];

      const chain = await Promise.all([...intermediates, anchors[0]].map(value =>
        cert.createX509Cert({ data: encode(value), encodingFormat: cert.EncodingFormat.FORMAT_PEM })));
      const now = new Date().toISOString().replace(/[-:T]/g, '').replace(/\.\d{3}Z$/, 'Z');

      for (let index = 0; index < chain.length; index++) {
        stage = `certificate ${index} validity and issuer signature`;
        const current = chain[index];
        const issuer = chain[Math.min(index + 1, chain.length - 1)];
        current.checkValidityWithDate(now);
        if (!equals(current.getIssuerName().data, issuer.getSubjectName().data)) {
          throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Signing certificates do not form a chain with a self-signed root.');
        }

        await current.verify(issuer.getPublicKey());
      }

      stage = 'leaf key usage';
      const leaf = chain[0];
      if (leaf.getKeyUsage().data[0] !== 1 || !leaf.getExtKeyUsage().data.some(value => decode(value).replace(/\0$/, '') === '1.3.6.1.5.5.7.3.3')) {
        throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'The leaf certificate must allow digital signatures and code signing.');
      }

      let constraint: string[] | undefined;
      let remaining = Number.MAX_SAFE_INTEGER;

      for (let index = chain.length - 1; index >= 0; index--) {
        const current = chain[index];
        stage = `certificate ${index} project extension`;
        const info = project(current);
        if (constraint && (constraint[0] !== info?.[0] || constraint[1] !== info?.[1])) {
          throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'A signing certificate expands its issuer project scope.');
        }

        constraint = info;
        if (index === 0) continue;
        if (index < chain.length - 1 && --remaining < 0) throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Signing certificate pathLenConstraint exceeded.');

        stage = `certificate ${index} CA constraints`;
        const limit = current.getExtensionsObject().checkCA();
        if (limit === -1 || current.getKeyUsage().data[5] !== 1) throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Every non-leaf certificate must be a certificate authority.');

        remaining = Math.min(remaining, limit === -2 ? Number.MAX_SAFE_INTEGER : limit);
      }

      stage = 'manifest signature';
      // X509Cert public keys only work with X509Cert.verify; import the encoded key for CryptoFramework.
      const imported = await crypto.createAsyKeyGenerator('RSA2048').convertKey(leaf.getPublicKey().getEncoded(), null);
      const verifier = crypto.createVerify('RSA|PKCS1|SHA256');
      await verifier.init(imported.pubKey);
      if (!await verifier.verify({ data: encode(body) }, { data: new util.Base64Helper().decodeSync(signatureValue) })) {
        throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', 'Update response signature verification failed.');
      }

      return { verified: true, projectId: constraint?.[0], scopeKey: constraint?.[1] };
    } catch (error) {
      throw new ExpoUpdatesError('ERR_UPDATES_CODE_SIGNING', `Unable to verify the update response (${stage}): ${String(error)}`);
    }
  }
}

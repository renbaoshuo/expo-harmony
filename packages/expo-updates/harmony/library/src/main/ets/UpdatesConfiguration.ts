/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import url from '@ohos.url';
import { isRecord } from './UpdatesJson';
import { ExpoUpdatesError, Headers, Json, normalizeHeaders } from './UpdatesProtocol';

export class UpdatesConfiguration {
  readonly enabled: boolean;
  readonly runtime: string;
  readonly url: string;
  readonly scope: string;
  readonly headers: Headers;
  readonly check: 'ALWAYS' | 'ERROR_RECOVERY_ONLY' | 'NEVER' | 'WIFI_ONLY';
  readonly wait: number;
  readonly embedded: boolean;
  readonly debug: boolean;
  readonly unsafe: boolean;
  readonly certificate?: string;
  readonly key: string;
  readonly algorithm: string;
  readonly chain: boolean;
  readonly unsigned: boolean;
  readonly compatibility: boolean;
  readonly enableBsdiffPatchSupport: boolean;

  constructor(readonly raw: Json, development: boolean) {
    if (!isRecord(raw)) throw new ExpoUpdatesError('ERR_UPDATES_CONFIGURATION', 'Updates configuration must be a JSON object.');

    this.runtime = typeof raw.runtimeVersion === 'string' ? raw.runtimeVersion : '';
    this.url = typeof raw.url === 'string' ? raw.url : '';
    this.debug = raw.useNativeDebug === true;
    this.enabled = raw.enabled !== false && (!development || this.debug) && !!this.url && !!this.runtime;
    if (this.url && !/^https?:\/\/[^/?#\s]+(?:[/?#]|$)/i.test(this.url)) {
      throw new ExpoUpdatesError('ERR_UPDATES_CONFIGURATION', 'Updates URL must use HTTP or HTTPS.');
    }
    if (raw.scopeKey !== undefined && (typeof raw.scopeKey !== 'string' || !raw.scopeKey)) {
      throw new ExpoUpdatesError('ERR_UPDATES_CONFIGURATION', 'scopeKey must be a nonempty string.');
    }

    this.scope = raw.scopeKey ?? (this.url ? new url.URL(this.url).origin : '');
    this.headers = UpdatesConfiguration.headers(raw.requestHeaders ?? {});
    this.check = raw.checkAutomatically === 'ON_LOAD' ? 'ALWAYS'
      : raw.checkAutomatically === 'ON_ERROR_RECOVERY' ? 'ERROR_RECOVERY_ONLY' : raw.checkAutomatically ?? 'ALWAYS';
    if (!['ALWAYS', 'ERROR_RECOVERY_ONLY', 'NEVER', 'WIFI_ONLY'].includes(this.check)) {
      throw new ExpoUpdatesError('ERR_UPDATES_CONFIGURATION', 'Invalid checkAutomatically value.');
    }

    this.wait = raw.fallbackToCacheTimeout ?? 0;
    if (!Number.isFinite(this.wait) || this.wait < 0) throw new ExpoUpdatesError('ERR_UPDATES_CONFIGURATION', 'fallbackToCacheTimeout must be nonnegative.');

    this.embedded = raw.useEmbeddedUpdate !== false;
    this.unsafe = raw.disableAntiBrickingMeasures === true;
    if (raw.codeSigningCertificate !== undefined && (typeof raw.codeSigningCertificate !== 'string' || !raw.codeSigningCertificate.trim())) {
      throw new ExpoUpdatesError('ERR_UPDATES_CONFIGURATION', 'The signing certificate must be nonempty PEM text.');
    }
    if (raw.codeSigningMetadata !== undefined && (!isRecord(raw.codeSigningMetadata)
      || Object.values(raw.codeSigningMetadata).some(value => typeof value !== 'string'))) {
      throw new ExpoUpdatesError('ERR_UPDATES_CONFIGURATION', 'Code signing metadata must contain string values.');
    }

    this.certificate = raw.codeSigningCertificate;
    this.key = raw.codeSigningMetadata?.keyid ?? 'root';
    this.algorithm = raw.codeSigningMetadata?.alg ?? 'rsa-v1_5-sha256';
    if (this.algorithm !== 'rsa-v1_5-sha256') throw new ExpoUpdatesError('ERR_UPDATES_CONFIGURATION', 'Only rsa-v1_5-sha256 code signing is supported by Expo Updates.');

    this.chain = raw.codeSigningIncludeManifestResponseCertificateChain === true;
    this.unsigned = raw.codeSigningAllowUnsignedManifests === true;
    this.compatibility = raw.enableExpoUpdatesProtocolV0CompatibilityMode === true;
    this.enableBsdiffPatchSupport = raw.enableBsdiffPatchSupport !== false;
  }

  static merge(base: Json, override: Json): Json { return { ...base, ...override }; }

  static headers(value: unknown): Headers {
    if (!isRecord(value) || !Object.entries(value).every(([key, item]) => /^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(key) && typeof item === 'string' && !/[\r\n\0]/.test(item))) {
      throw new ExpoUpdatesError('ERR_UPDATES_CONFIGURATION', 'Update request headers must have valid names and string values without newlines.');
    }

    return normalizeHeaders(value);
  }

  override(value: Json | null, development: boolean, persisted: boolean = false): UpdatesConfiguration {
    if (value === null) return new UpdatesConfiguration(this.raw, development);
    if (value.url !== undefined && !this.unsafe) throw new ExpoUpdatesError('ERR_UPDATES_CONFIGURATION', 'URL overrides require disableAntiBrickingMeasures.');

    let headers: Headers;
    try {
      headers = UpdatesConfiguration.headers(value.requestHeaders ?? this.headers);
    } catch (error) {
      if (!persisted) throw new ExpoUpdatesError('ERR_UPDATES_CONFIGURATION', 'Invalid request header override.', error instanceof Error ? error : undefined);
      console.warn('[ExpoUpdates] Invalid persisted request header override; using embedded request headers.');
      headers = this.headers;
    }

    if (!this.unsafe && Object.keys(headers).some(key => key.trim().toLowerCase() === 'host' ||
      !Object.prototype.hasOwnProperty.call(this.headers, key.trim().toLowerCase()))) {
      console.warn('[ExpoUpdates] Invalid request header override; using embedded request headers.');
      headers = this.headers;
    }

    return new UpdatesConfiguration({ ...this.raw, ...value, requestHeaders: headers,
      useEmbeddedUpdate: this.unsafe ? false : this.raw.useEmbeddedUpdate }, development);
  }
}

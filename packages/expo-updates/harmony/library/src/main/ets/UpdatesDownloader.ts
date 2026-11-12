/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

/// <reference path="./UpdatesNative.d.ts" />

import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import type common from '@ohos.app.ability.common';
import { applyPatch } from 'libexpo_updates.so';
import { ExpoUpdatesError, Headers, UpdateAsset, UpdateRecord, normalizeHeaders } from './UpdatesProtocol';
import { UpdatesStorage, decode, digest, encode, exists, hashFile, isVerifiedAsset, write } from './UpdatesStorage';
import { isSafeAssetFilename } from './UpdatesAssetPaths';

interface DownloadOptions {
  timeout?: number;
  base?: UpdateRecord;
  requested?: string;
  patch?: boolean;
  headers?: Headers;
}

export class UpdatesDownloader {
  constructor(private readonly storage: UpdatesStorage, private readonly context: common.ApplicationContext) {}

  async manifest(url: string, headers: Headers, timeout: number): Promise<{ status: number; headers: Headers; body: string }> {
    const request = http.createHttp();

    try {
      const result = await request.request(url, {
        method: http.RequestMethod.GET, header: headers, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false, connectTimeout: timeout, readTimeout: timeout,
      });

      return { status: result.responseCode, headers: normalizeHeaders(result.header as Record<string, ESObject>),
        body: decode(new Uint8Array(result.result as ArrayBuffer)) };
    } finally {
      request.destroy();
    }
  }

  private async stream(url: string, headers: Headers, path: string, timeout: number, progress: (received: number, total: number) => void): Promise<{ status: number; headers: Headers }> {
    const request = http.createHttp();
    let file: fs.File | undefined;
    let response: Headers = {};

    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);

      request.on('headersReceive', value => { response = normalizeHeaders(value as Record<string, ESObject>); });
      const completed = new Promise<void>((resolve, reject) => {
        request.on('dataReceive', bytes => {
          try { write(file!, bytes); }
          catch (error) {
            reject(new ExpoUpdatesError('ERR_UPDATES_ASSET', `Unable to write update asset: ${String(error)}`));
            request.destroy();
          }
        });
        request.on('dataEnd', resolve);
        request.on('dataReceiveProgress', value => progress(value.receiveSize, value.totalSize));
      });

      const pending = request.requestInStream(url, { method: http.RequestMethod.GET,
        header: headers, usingCache: false, connectTimeout: timeout, readTimeout: timeout });
      const [status] = await Promise.all([pending, completed]);
      if (status < 200 || status >= 300) throw new ExpoUpdatesError('ERR_UPDATES_ASSET', `Asset request returned HTTP ${status}.`);

      fs.fsyncSync(file.fd);

      return { status, headers: response };
    } finally {
      request.destroy();
      if (file) fs.closeSync(file);
    }
  }

  async asset(asset: UpdateAsset, headers: Headers, progress: (received: number, total: number) => void, options: DownloadOptions = {}): Promise<UpdateAsset> {
    if (!isSafeAssetFilename(asset.key, asset.extension)) {
      throw new ExpoUpdatesError('ERR_UPDATES_ASSET', 'Refusing to download an asset with an unsafe filename.');
    }

    const cached = await this.storage.asset(asset);
    const expected = asset.hash?.replace(/=+$/, '');
    const storedHash = cached?.hash?.replace(/=+$/, '') ?? cached?.digest;
    if (expected !== undefined && storedHash !== undefined && expected !== storedHash) {
      throw new ExpoUpdatesError('ERR_UPDATES_ASSET_HASH', `Asset key ${asset.key} already identifies different content.`);
    }

    const requiredHash = expected ?? storedHash;
    if (cached && isVerifiedAsset(this.storage.directory, cached, requiredHash)) {
      return { ...asset, id: cached.id, path: cached.path, digest: cached.digest };
    }

    const name = asset.key === null ? util.generateRandomUUID() : digest(encode(asset.key));
    const path = this.storage.directory + '/' + name + asset.extension;
    const temporary = this.storage.temporary + '/' + util.generateRandomUUID();
    const patched = this.storage.temporary + '/' + util.generateRandomUUID();
    const extracted = this.storage.temporary + '/' + util.generateRandomUUID();

    try {
      if (asset.embedded) {
        const size = await this.copyEmbeddedAsset(asset.embedded, temporary);
        progress(size, size);
      } else {
        // Normalize cached headers too: older database rows can retain mixed-case names.
        const extra: Headers = { ...normalizeHeaders(asset.headers), ...normalizeHeaders(headers), accept: '*/*' };
        const patch = asset.launch && options.patch === true && options.base !== undefined && options.requested !== undefined && options.base.id !== options.requested;
        if (patch) extra['a-im'] = 'bsdiff';
        else delete extra['a-im'];
        Object.assign(extra, normalizeHeaders(options.headers ?? {}));

        const response = await this.stream(asset.url, extra, temporary, options.timeout ?? 10000, progress);
        if (response.status === 226 || response.headers.im?.split(',').some(value => value.trim().toLowerCase() === 'bsdiff')) {
          try {
            const base = options.base?.assets.find(asset => asset.launch);
            if (!patch || !base || !options.requested || options.requested === options.base?.id
              || response.headers['expo-base-update-id']?.toLowerCase() !== options.base?.id) {
              throw new ExpoUpdatesError('ERR_UPDATES_PATCH', 'The patch response has no matching verified base update.');
            }

            const source = await this.resolvePatchBase(base, extracted);
            if (await applyPatch(source, patched, temporary) !== 0) throw new ExpoUpdatesError('ERR_UPDATES_PATCH', 'Unable to apply BSDIFF update.');
            if (requiredHash && hashFile(patched) !== requiredHash) throw new ExpoUpdatesError('ERR_UPDATES_PATCH', 'Patched bundle failed SHA-256 verification.');

            fs.renameSync(patched, temporary);
            this.storage.logger.log(`Applied BSDIFF for asset ${asset.key}.`, 'None', 'info', options.requested, asset.key ?? undefined);
          } catch (error) {
            this.storage.logger.log(`Patch failed; downloading the complete asset: ${String(error)}`, 'AssetsFailedToLoad', 'warn', options.requested, asset.key ?? undefined);
            delete extra['a-im'];

            const fallback = await this.stream(asset.url, extra, temporary, options.timeout ?? 10000, progress);
            if (fallback.status === 226 || fallback.headers.im?.split(',').some(value => value.trim().toLowerCase() === 'bsdiff')) {
              throw new ExpoUpdatesError('ERR_UPDATES_PATCH', 'The full asset retry returned another patch.');
            }
          }
        }
      }

      const actual = hashFile(temporary);
      if (requiredHash && actual !== requiredHash) throw new ExpoUpdatesError('ERR_UPDATES_ASSET_HASH', `SHA-256 mismatch for asset ${asset.key}.`);

      fs.renameSync(temporary, path);
      const result: UpdateAsset = { ...asset, path, digest: actual };
      await this.storage.save(result);

      return result;
    } finally {
      for (const file of [temporary, patched, extracted]) {
        try { if (exists(file)) fs.unlinkSync(file); }
        catch (error) { this.storage.logger.warn(`Unable to remove temporary update asset: ${String(error)}`, 'AssetsFailedToLoad'); }
      }
    }
  }

  private async copyEmbeddedAsset(name: string, destination: string): Promise<number> {
    if (name.startsWith('/') || /[\\\0]/.test(name) || name.split('/').some(part => part === '..')) {
      throw new ExpoUpdatesError('ERR_UPDATES_ASSET', 'Invalid embedded asset path.');
    }

    const bytes = await this.context.resourceManager.getRawFileContent(name);

    const file = fs.openSync(destination, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      write(file, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }

    return bytes.byteLength;
  }

  private async resolvePatchBase(base: UpdateAsset, temporary: string): Promise<string> {
    const expected = base.hash?.replace(/=+$/, '') ?? base.digest;
    if (base.path && isVerifiedAsset(this.storage.directory, base, expected)) return base.path;

    if (base.embedded && expected) {
      await this.copyEmbeddedAsset(base.embedded, temporary);
      if (hashFile(temporary) === expected) return temporary;
    }

    throw new ExpoUpdatesError('ERR_UPDATES_PATCH', 'The patch base is missing or failed SHA-256 verification.');
  }
}

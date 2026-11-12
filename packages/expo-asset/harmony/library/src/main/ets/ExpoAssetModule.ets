/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueTypes,
  fileUriFromPath,
  isRnohRawfileResourceUri,
  openRawResourceFile,
  rawResourcePathFromUri,
} from '@expo-harmony/expo-modules-core';
import { fileIo as fs, hash as fileHash } from '@kit.CoreFileKit';
import { request } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

type CancelRequest = (error: ExpoAssetError) => void;

class ExpoAssetError extends ExpoModuleError {
  readonly canRemoveTemporaryFile: boolean;

  constructor(code: string, message: string, canRemoveTemporaryFile: boolean = true) {
    super(code, message);
    this.name = 'ExpoAssetError';
    this.canRemoveTemporaryFile = canRemoveTemporaryFile;
  }
}

export class ExpoAssetModule extends ExpoModule {
  private readonly inflight: Map<string, Promise<string>> = new Map();
  private readonly requests: Map<request.DownloadTask, CancelRequest> = new Map();
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoAsset')
      .asyncFunction(
        'downloadAsync',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          ExpoValueTypes.string().nullable(),
          ExpoValueTypes.string(),
          async (uri: string, md5: string | null, type: string): Promise<string> => {
            this.assertActive();
            return await this.download(uri, md5, type);
          },
        ).returns(ExpoValueTypes.string()),
      )
      .onPrepareForReload(async (): Promise<void> => {
        await this.prepareForReload();
      })
      .onDestroy((): void => this.onDestroy());
  }

  onDestroy(): void {
    this.beginShutdown();
  }

  private async prepareForReload(): Promise<void> {
    const pending = Array.from(this.inflight.values());
    this.beginShutdown();

    await Promise.all(
      pending.map(async (task: Promise<string>): Promise<void> => {
        try {
          await task;
        } catch (_) {}
      }),
    );
  }

  private beginShutdown(): void {
    if (this.destroyed) return;

    this.destroyed = true;

    const error = new ExpoAssetError('ERR_ASSET_RUNTIME_DESTROYED', 'The Expo asset service was destroyed while a request was in progress.');
    this.requests.forEach((cancel: CancelRequest): void => cancel(error));
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoAssetError('ERR_ASSET_RUNTIME_DESTROYED', 'The Expo asset service was destroyed while a request was in progress.');
    }
  }

  private async download(uri: string, md5: string | null, type: string): Promise<string> {
    const scheme = uriScheme(uri);
    if (scheme === 'file') {
      this.context.fileSourceForRead(uri);
      return uri;
    }

    const resource = isRawResource(uri, scheme) ? rawResourceName(uri) : undefined;
    if (resource === undefined && scheme !== 'http' && scheme !== 'https') {
      throw new ExpoAssetError('ERR_ASSET_UNSUPPORTED_URI', sanitizedUri(uri));
    }

    const ext = safeAssetType(type);
    const hash = md5 === null ? null : safeMd5(md5);
    const key = hash ?? md5String(uri);
    const cache = this.context.cachePath.replace(/\/$/, '');
    const file = `${cache}/ExponentAsset-${key}.${ext}`;

    const pending = this.inflight.get(file);
    if (pending !== undefined) return await pending;

    const task = this.materialize(uri, resource, hash, file);
    this.inflight.set(file, task);

    try {
      return await task;
    } finally {
      this.inflight.delete(file);
    }
  }

  private async materialize(uri: string, resource: string | undefined, md5: string | null, file: string): Promise<string> {
    this.context.assertFileAccess(file, 'read');

    let cached = false;

    try {
      cached = (await fs.lstat(file)).isFile() && (await this.matches(file, md5));
    } catch (_) {}

    this.assertActive();

    if (cached) return fileUriFromPath(file);

    const temp = `${file}.expo-${util.generateRandomUUID()}.tmp`;
    this.context.assertFileAccess(file, 'write');
    this.context.assertFileAccess(temp, 'write');

    try {
      if (resource !== undefined) await this.copyRawResource(resource, temp);
      else await this.downloadHttp(uri, temp);

      this.assertActive();
      this.context.assertFileAccess(file, 'write');

      await fs.moveFile(temp, file, 0);

      return fileUriFromPath(file);
    } catch (error) {
      if (!(error instanceof ExpoAssetError) || error.canRemoveTemporaryFile) {
        try {
          await fs.unlink(temp);
        } catch (_) {}
      } else {
        this.context.logger.warn('Retaining an Expo asset temporary file because the native download could not be stopped.');
      }

      if (error instanceof ExpoAssetError) {
        throw new ExpoAssetError(error.code, error.message);
      }

      throw new ExpoAssetError('ERR_ASSET_DOWNLOAD_FAILED', cleanErrorMessage(error as Object));
    }
  }

  private async matches(path: string, md5: string | null): Promise<boolean> {
    return md5 === null || (await fileHash.hash(path, 'md5')).toLowerCase() === md5;
  }

  private async copyRawResource(name: string, file: string): Promise<void> {
    const resources = this.context.uiAbilityContext.resourceManager;

    try {
      this.assertActive();

      const input = openRawResourceFile(resources, name);

      try {
        const output = await fs.open(file, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        try {
          const buffer = new ArrayBuffer(64 * 1024);
          let written = 0;

          while (written < input.length) {
            this.assertActive();

            const size = Math.min(buffer.byteLength, input.length - written);
            const count = await fs.read(input.file.fd, buffer, { offset: input.offset + written, length: size });
            this.assertActive();
            if (count <= 0) {
              throw new ExpoAssetError('ERR_ASSET_RESOURCE_UNAVAILABLE', `Cannot read the complete packaged asset '${name}'.`);
            }

            await writeAllAsync(output.fd, count === buffer.byteLength ? buffer : buffer.slice(0, count));
            written += count;
          }
        } finally {
          await fs.close(output.fd);
        }
      } finally {
        await fs.close(input.file.fd);
      }
    } catch (error) {
      if (error instanceof ExpoAssetError) {
        throw new ExpoAssetError(error.code, error.message);
      }

      throw new ExpoAssetError('ERR_ASSET_RESOURCE_UNAVAILABLE', `Cannot read packaged asset '${name}': ${cleanErrorMessage(error as Object)}`);
    }
  }

  private async downloadHttp(uri: string, file: string): Promise<void> {
    this.assertActive();

    let task: request.DownloadTask;
    try {
      task = await request.downloadFile(this.context.uiAbilityContext, {
        url: uri,
        filePath: file,
        enableMetered: true,
        enableRoaming: true,
        background: false,
      });
    } catch (error) {
      throw new ExpoAssetError(
        'ERR_ASSET_DOWNLOAD_FAILED',
        `Unable to start asset download from '${sanitizedUri(uri)}': ${cleanErrorMessage(error as Object)}`,
      );
    }

    await this.waitForDownload(task, uri);
  }

  private async waitForDownload(task: request.DownloadTask, uri: string): Promise<void> {
    await new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
      let settled = false;

      const cleanup = (): void => {
        this.requests.delete(task);
        try {
          task.off('complete', complete);
          task.off('fail', fail);
        } catch (_) {}
      };

      const settle = (error?: ExpoAssetError): void => {
        if (settled) return;

        settled = true;
        cleanup();

        if (error === undefined) resolve();
        else reject(error as Error);
      };

      const complete = (): void => settle();
      const fail = (reason: number): void =>
        settle(new ExpoAssetError('ERR_ASSET_DOWNLOAD_FAILED', `Unable to download asset from '${sanitizedUri(uri)}' (Harmony reason ${reason}).`));

      const cancel = (error: ExpoAssetError): void => {
        if (settled) return;

        settled = true;
        cleanup();
        // Only confirmed deletion permits materialize to remove the temporary file.
        // Otherwise retain it: the native writer may still be using it.
        const cancelled = (deleted: boolean): void => reject(new ExpoAssetError(error.code, error.message, deleted) as Error);

        try {
          task.delete().then(
            (deleted: boolean): void => cancelled(deleted),
            (_: Object): void => cancelled(false),
          );
        } catch (_) {
          cancelled(false);
        }
      };

      this.requests.set(task, cancel);
      try {
        task.on('complete', complete);
        task.on('fail', fail);

        if (this.destroyed) {
          cancel(new ExpoAssetError('ERR_ASSET_RUNTIME_DESTROYED', 'The Expo asset service was destroyed while a request was in progress.'));
          return;
        }

        // The download may finish before its listeners are registered.
        task
          .getTaskInfo()
          .then((info: request.DownloadInfo): void => {
            if (info.status === request.SESSION_SUCCESSFUL) complete();
            else if (info.status === request.SESSION_FAILED) fail(info.failedReason);
          })
          .catch((error: Object): void => {
            cancel(new ExpoAssetError('ERR_ASSET_DOWNLOAD_FAILED', cleanErrorMessage(error)));
          });
      } catch (error) {
        cancel(new ExpoAssetError('ERR_ASSET_DOWNLOAD_FAILED', cleanErrorMessage(error as Object)));
      }
    });
  }
}

function isRawResource(uri: string, scheme: string | undefined): boolean {
  return scheme === 'asset' || scheme === 'rawfile' || scheme === undefined || isRnohRawfileResourceUri(uri);
}

function rawResourceName(uri: string): string {
  try {
    return rawResourcePathFromUri(uri);
  } catch (_) {
    throw new ExpoAssetError('ERR_ASSET_INVALID_RESOURCE', sanitizedUri(uri));
  }
}

async function writeAllAsync(fd: number, data: ArrayBuffer): Promise<number> {
  let written = 0;

  while (written < data.byteLength) {
    const end = Math.min(written + 64 * 1024, data.byteLength);
    const count = await fs.write(fd, data.slice(written, end), { length: end - written });
    if (count <= 0) {
      throw new ExpoAssetError('ERR_ASSET_WRITE_FAILED', 'Unable to write the complete asset.');
    }

    written += count;
  }

  return written;
}

function safeAssetType(type: string): string {
  if (type.length > 64 || (type.length > 0 && !/^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(type))) {
    throw new ExpoAssetError('ERR_ASSET_INVALID_TYPE', type);
  }

  return type;
}

function safeMd5(value: string): string {
  if (!/^[A-Fa-f0-9]{32}$/.test(value)) {
    throw new ExpoAssetError('ERR_ASSET_INVALID_HASH', 'Expo Asset expected a 32-character hexadecimal MD5 hash.');
  }

  return value.toLowerCase();
}

function uriScheme(value: string): string | undefined {
  const match = /^([A-Za-z][A-Za-z0-9+.-]*):/.exec(value);
  return match === null ? undefined : match[1].toLowerCase();
}

function sanitizedUri(value: string): string {
  const uri = value.split(/[?#]/, 1)[0];
  const scheme = uri.indexOf('://');
  if (scheme < 0) return uri;

  const start = scheme + 3;
  const slash = uri.indexOf('/', start);
  const end = slash < 0 ? uri.length : slash;
  const host = uri.slice(start, end);
  const at = host.lastIndexOf('@');

  return `${uri.slice(0, start)}${at < 0 ? host : host.slice(at + 1)}${uri.slice(end)}`;
}

function cleanErrorMessage(error: Object): string {
  if (error instanceof ExpoAssetError) return error.message;
  return String(error).replace(/^(?:Error:\s*)+/, '');
}

function md5String(text: string): string {
  const digest = cryptoFramework.createMd('MD5');
  if (text.length > 0) {
    digest.updateSync({ data: new util.TextEncoder('utf-8').encodeInto(text) });
  }

  const bytes = digest.digestSync().data;
  let result = '';
  for (let i = 0; i < bytes.length; i += 1) {
    result += bytes[i].toString(16).padStart(2, '0');
  }

  return result;
}

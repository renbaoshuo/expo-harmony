import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueTypes,
  fileUriFromPath,
} from '@expo-harmony/expo-modules-core';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import fileHash from '@ohos.file.hash';
import request from '@ohos.request';
import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';

type CancelRequest = (error: ExpoAssetError) => void;

class ExpoAssetError extends ExpoModuleError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoAssetError';
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
    if (scheme === 'file') return uri;

    const ext = safeAssetType(type);
    const key = md5 === null ? md5String(uri) : safeMd5(md5);
    const suffix = ext.length === 0 ? '' : `.${ext}`;
    const cachePath = new fileUri.FileUri(this.context.cacheDirectory).path.replace(/\/$/, '');
    const file = `${cachePath}/ExponentAsset-${key}${suffix}`;

    const pending = this.inflight.get(file);
    if (pending !== undefined) return await pending;

    const task = this.materialize(uri, md5, file);
    task.catch((_: Error): void => {});
    this.inflight.set(file, task);

    try {
      return await task;
    } finally {
      this.inflight.delete(file);
    }
  }

  private async materialize(uri: string, md5: string | null, file: string): Promise<string> {
    let cached = false;
    try {
      cached = (await fs.access(file)) && (await this.matches(file, md5));
    } catch (_) {}

    this.assertActive();

    if (cached) return fileUriFromPath(file);

    const temp = `${file}.expo-${Date.now()}-${Math.floor(Math.random() * 0x7fffffff)}.tmp`;
    try {
      if (isRawResource(uri)) await this.copyRawResource(uri, temp);
      else await this.downloadHttp(uri, temp);

      this.assertActive();

      await fs.moveFile(temp, file, 0);

      return fileUriFromPath(file);
    } catch (error) {
      try {
        await fs.unlink(temp);
      } catch (_) {}

      if (error instanceof ExpoAssetError) throw error;
      throw new ExpoAssetError('ERR_ASSET_DOWNLOAD_FAILED', cleanErrorMessage(error as Object));
    }
  }

  private async matches(path: string, md5: string | null): Promise<boolean> {
    return md5 === null || (await fileHash.hash(path, 'md5')).toLowerCase() === md5.toLowerCase();
  }

  private async copyRawResource(uri: string, file: string): Promise<void> {
    const name = rawResourceName(uri);
    const resources = this.context.uiAbilityContext.resourceManager;
    let opened = false;

    try {
      this.assertActive();

      const desc = await resources.getRawFd(name);
      opened = true;

      this.assertActive();

      const output = await fs.open(file, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        this.assertActive();

        fs.lseek(desc.fd, desc.offset, fs.WhenceType.SEEK_SET);
        fs.lseek(output.fd, 0, fs.WhenceType.SEEK_SET);

        const buffer = new ArrayBuffer(64 * 1024);
        let written = 0;
        while (written < desc.length) {
          const size = Math.min(buffer.byteLength, desc.length - written);
          const count = await fs.read(desc.fd, buffer, { length: size });

          this.assertActive();

          if (count <= 0) {
            throw new ExpoAssetError('ERR_ASSET_RESOURCE_UNAVAILABLE', `Cannot read the complete packaged asset '${name}'.`);
          }

          await writeAllAsync(output.fd, count === buffer.byteLength ? buffer : buffer.slice(0, count));

          this.assertActive();
          written += count;
        }
      } finally {
        await fs.close(output.fd);
      }
    } catch (error) {
      if (error instanceof ExpoAssetError) throw error;
      throw new ExpoAssetError('ERR_ASSET_RESOURCE_UNAVAILABLE', `Cannot read packaged asset '${name}': ${cleanErrorMessage(error as Object)}`);
    } finally {
      if (opened) {
        try {
          await resources.closeRawFd(name);
        } catch (error) {
          this.context.logger.warn(`Unable to close packaged Expo asset '${name}': ${cleanErrorMessage(error as Object)}`);
        }
      }
    }
  }

  private async downloadHttp(uri: string, file: string): Promise<void> {
    this.assertActive();

    const scheme = uriScheme(uri);
    if (scheme !== 'http' && scheme !== 'https') {
      throw new ExpoAssetError('ERR_ASSET_UNSUPPORTED_URI', sanitizedUri(uri));
    }

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

    this.assertActive();
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
        settle(error);
        task.delete().catch((_: Object): void => {});
      };

      this.requests.set(task, cancel);
      task.on('complete', complete);
      task.on('fail', fail);
      if (this.destroyed)
        cancel(new ExpoAssetError('ERR_ASSET_RUNTIME_DESTROYED', 'The Expo asset service was destroyed while a request was in progress.'));
    });
  }
}

function isRawResource(uri: string): boolean {
  const scheme = uriScheme(uri);
  return scheme === 'asset' || scheme === 'rawfile' || scheme === undefined;
}

function rawResourceName(uri: string): string {
  const scheme = uriScheme(uri);
  const rnoh = scheme === 'asset';
  let encoded = scheme === undefined ? uri : uri.slice(uri.indexOf(':') + 1).replace(/^\/{2}/, '');
  encoded = encoded.replace(/^\/+/, '').split(/[?#]/, 1)[0];
  if (/%(?:00|2f|5c)/i.test(encoded) || encoded.includes('\\')) {
    throw new ExpoAssetError('ERR_ASSET_INVALID_RESOURCE', sanitizedUri(uri));
  }

  let path: string;
  try {
    path = decodeURIComponent(encoded);
  } catch (_) {
    throw new ExpoAssetError('ERR_ASSET_INVALID_RESOURCE', sanitizedUri(uri));
  }
  const parts = path.split('/');

  if (parts.length === 0 || parts.some((part: string): boolean => part.length === 0 || part === '.' || part === '..' || part.includes('\0'))) {
    throw new ExpoAssetError('ERR_ASSET_INVALID_RESOURCE', sanitizedUri(uri));
  }

  const name = parts.join('/');
  return rnoh ? `assets/${name}` : name;
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
  const withoutQuery = value.split(/[?#]/, 1)[0];
  const authority = withoutQuery.indexOf('://');
  if (authority < 0) return withoutQuery;

  const start = authority + 3;
  const end = withoutQuery.indexOf('/', start);
  const hostEnd = end < 0 ? withoutQuery.length : end;
  const host = withoutQuery.slice(start, hostEnd);
  const userInfo = host.lastIndexOf('@');
  return `${withoutQuery.slice(0, start)}${userInfo < 0 ? host : host.slice(userInfo + 1)}${withoutQuery.slice(hostEnd)}`;
}

function cleanErrorMessage(error: Object): string {
  if (error instanceof ExpoAssetError) return error.message;
  return String(error).replace(/^(?:Error:\s*)+/, '');
}

function md5String(text: string): string {
  const digest = cryptoFramework.createMd('MD5');
  digest.updateSync({ data: new util.TextEncoder('utf-8').encode(text) });
  const bytes = digest.digestSync().data;

  let result = '';
  for (let i = 0; i < bytes.length; i += 1) {
    result += bytes[i].toString(16).padStart(2, '0');
  }

  return result;
}

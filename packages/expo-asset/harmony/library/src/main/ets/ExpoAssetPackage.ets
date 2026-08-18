import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import fs from '@ohos.file.fs';
import fileHash from '@ohos.file.hash';
import http from '@ohos.net.http';
import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';

const SERVICE_NAME: string = 'ExpoAssetService';
const NETSTACK_RESPONSE_LIMIT_BYTES: number = 100 * 1024 * 1024;
const NETSTACK_COMPLETION_FALLBACK_MS: number = 61_000;
let registered: boolean = false;
type CancelRequest = (error: Error) => void;

class ExpoAssetError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(`${code}: ${message}`);
    this.name = 'ExpoAssetError';
    this.code = code;
  }
}

class ExpoAssetService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;
  private readonly inflight: Map<string, Promise<string>> = new Map();
  private readonly requests: Map<http.HttpRequest, CancelRequest> = new Map();
  private destroyed: boolean = false;

  constructor(context: UITurboModuleContext) {
    this.context = context;
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (method === 'destroy') {
      this.onDestroy();
      return null;
    }

    this.assertActive();

    if (method === 'downloadAsync') {
      return await this.download(String(args[0]), args[1] === null ? null : String(args[1]), String(args[2]));
    }

    throw new ExpoAssetError('ERR_ASSET_UNKNOWN_METHOD', method);
  }

  onDestroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    const error = new ExpoAssetError('ERR_ASSET_RUNTIME_DESTROYED', 'The Expo asset service was destroyed while a request was in progress.');

    this.requests.forEach((cancel: CancelRequest): void => cancel(error as Error));
    this.requests.clear();
    this.inflight.clear();
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoAssetError('ERR_ASSET_RUNTIME_DESTROYED', 'The Expo asset service was destroyed while a request was in progress.');
    }
  }

  private async download(uri: string, md5: string | null, type: string): Promise<string> {
    if (uri.startsWith('file:') && !uri.startsWith('file:///android_res/')) return uri;

    const ext = safeAssetType(type);
    const key = md5 ?? md5String(uri);
    const file = `${this.context.uiAbilityContext.cacheDir}/ExponentAsset-${key}.${ext}`;

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

    if (cached) return toFileUri(file);

    const temp = `${file}.expo-${Date.now()}-${Math.floor(Math.random() * 0x7fffffff)}.tmp`;
    try {
      if (isRawResource(uri)) await this.copyRawResource(uri, temp);
      else await this.downloadHttp(uri, temp);

      this.assertActive();

      await fs.moveFile(temp, file, 0);

      return toFileUri(file);
    } catch (error) {
      try {
        await fs.unlink(temp);
      } catch (_) {}

      const message = cleanErrorMessage(error as Object);
      if (/^ERR_ASSET_[A-Z_]+:/.test(message)) {
        throw new ExpoAssetError(message.split(':')[0], message.split(':').slice(1).join(':'));
      }

      throw new ExpoAssetError('ERR_ASSET_DOWNLOAD_FAILED', message);
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
      const message = cleanErrorMessage(error as Object);
      if (message.startsWith('ERR_ASSET_')) {
        throw new ExpoAssetError(message.split(':')[0], message.split(':').slice(1).join(':'));
      }

      throw new ExpoAssetError('ERR_ASSET_RESOURCE_UNAVAILABLE', `Cannot read packaged asset '${name}': ${message}`);
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

    if (!uri.startsWith('http://') && !uri.startsWith('https://')) {
      throw new ExpoAssetError('ERR_ASSET_UNSUPPORTED_URI', uri);
    }

    const output = fs.openSync(file, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      const req = http.createHttp();
      let offset = 0;
      let failure = '';
      let resolveDone: () => void = (): void => {};
      let rejectDone: (error: Error) => void = (_: Error): void => {};
      let rejectCancel: (error: Error) => void = (_: Error): void => {};
      let settled = false;
      let deadline = -1;
      const done = new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
        resolveDone = resolve;
        rejectDone = reject;
      });
      const cancelled = new Promise<number>((_: (value: number) => void, reject: (error: Error) => void): void => {
        rejectCancel = reject;
      });

      done.catch((_: Error): void => {});
      cancelled.catch((_: Error): void => {});

      const cancel = (error: Error): void => {
        if (failure.length > 0) return;

        clearDeadline();
        failure = cleanErrorMessage(error);
        if (!settled) {
          settled = true;
          rejectDone(error);
        }

        rejectCancel(error);
        try {
          req.destroy();
        } catch (_) {}
      };

      const clearDeadline = (): void => {
        if (deadline < 0) return;

        clearTimeout(deadline);
        deadline = -1;
      };

      const armDeadline = (): void => {
        clearDeadline();
        deadline = setTimeout((): void => {
          cancel(
            new ExpoAssetError(
              'ERR_ASSET_DOWNLOAD_TIMEOUT',
              'Harmony did not complete the asset response within the platform read timeout.',
            ) as Error,
          );
        }, NETSTACK_COMPLETION_FALLBACK_MS);
      };

      this.requests.set(req, cancel);
      req.on('dataReceive', (chunk: ArrayBuffer): void => {
        if (settled) return;

        try {
          offset += writeAll(output.fd, chunk, offset);
          armDeadline();
        } catch (error) {
          const message = cleanErrorMessage(error as Object);
          if (/^ERR_ASSET_[A-Z_]+:/.test(message)) {
            cancel(new Error(message));
          } else {
            cancel(new ExpoAssetError('ERR_ASSET_WRITE_FAILED', message) as Error);
          }
        }
      });
      req.on('dataEnd', (): void => {
        if (settled) return;

        clearDeadline();
        settled = true;
        resolveDone();
      });

      try {
        armDeadline();

        let status: number;
        try {
          status = await Promise.race([
            req.requestInStream(uri, {
              method: http.RequestMethod.GET,
              connectTimeout: 60000,
              readTimeout: 60000,
              maxLimit: NETSTACK_RESPONSE_LIMIT_BYTES,
            }),
            cancelled,
          ]);
        } catch (error) {
          if (failure.length > 0) {
            throw new Error(failure);
          }

          const message = cleanErrorMessage(error as Object);
          if (/^ERR_ASSET_[A-Z_]+:/.test(message)) {
            throw new Error(message);
          }

          throw new ExpoAssetError('ERR_ASSET_DOWNLOAD_FAILED', message);
        }

        if (status < 200 || status >= 300) {
          throw new ExpoAssetError('ERR_ASSET_HTTP_STATUS', String(status));
        }

        await done;
      } finally {
        clearDeadline();
        this.requests.delete(req);

        try {
          req.destroy();
        } catch (_) {}
      }
    } finally {
      try {
        fs.closeSync(output.fd);
      } catch (_) {}
    }
  }
}

function isRawResource(uri: string): boolean {
  return uri.startsWith('asset://') || uri.startsWith('rawfile://') || !uri.includes(':');
}

function rawResourceName(uri: string): string {
  const rnoh = uri.startsWith('asset://');
  const path = uri
    .replace(/^(asset|rawfile):\/\//, '')
    .replace(/^\/+/, '')
    .split(/[?#]/, 1)[0]
    .replace(/\\/g, '/');
  const parts = path.split('/');

  if (parts.length === 0 || parts.some((part: string): boolean => part.length === 0 || part === '.' || part === '..')) {
    throw new ExpoAssetError('ERR_ASSET_INVALID_RESOURCE', uri);
  }

  const name = parts.join('/');
  return rnoh ? `assets/${name}` : name;
}

function writeAll(fd: number, data: ArrayBuffer, offset: number): number {
  fs.lseek(fd, offset, fs.WhenceType.SEEK_SET);

  let written = 0;
  while (written < data.byteLength) {
    const end = Math.min(written + 64 * 1024, data.byteLength);
    const count = fs.writeSync(fd, data.slice(written, end), { length: end - written });
    if (count <= 0) {
      throw new ExpoAssetError('ERR_ASSET_WRITE_FAILED', 'Unable to write the complete asset.');
    }

    written += count;
  }

  return written;
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

function toFileUri(path: string): string {
  return `file://${path}`;
}

function safeAssetType(type: string): string {
  if (type.includes('/') || type.includes('\\') || type.includes('\0')) {
    throw new ExpoAssetError('ERR_ASSET_INVALID_TYPE', type);
  }

  return type;
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

function registerService(): void {
  if (registered) return;
  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new ExpoAssetService(context),
  });
  registered = true;
}

export class ExpoAssetPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerService();
    super(context);
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-asset';
  }
}

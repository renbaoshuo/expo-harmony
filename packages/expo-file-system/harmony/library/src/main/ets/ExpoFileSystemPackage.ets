import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext } from '@rnoh/react-native-openharmony/ts';
import type { UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { EXPO_MODULE_EVENT, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import fs from '@ohos.file.fs';
import fileHash from '@ohos.file.hash';
import picker from '@ohos.file.picker';
import fileShare from '@ohos.fileshare';
import uniformTypeDescriptor from '@ohos.data.uniformTypeDescriptor';
import http from '@ohos.net.http';
import { ExpoFileSystemError, ProgressCadence, uploadMethodPolicy } from './NetworkPolicy';

const SERVICE_NAME: string = 'ExpoFileSystemService';
const NETSTACK_RESPONSE_LIMIT_BYTES: number = 100 * 1024 * 1024;
const NETSTACK_COMPLETION_FALLBACK_MS: number = 61_000;
let registered: boolean = false;

interface NetworkTask {
  request: http.HttpRequest;
  transferred: number;
  cancelled: boolean;
  paused: boolean;
  preservePartial: boolean;
  temporary?: string;
  complete?: () => Promise<void>;
  done?: Promise<void>;
  failure?: string;
  expectedTransfer?: number;
  progressCadence: ProgressCadence;
}

interface DownloadRequest {
  url: string;
  destination: string;
  headers?: Object;
  uuid?: string;
  emitProgress?: boolean;
  resumeFrom?: number;
  md5?: boolean;
  destinationIsDirectory?: boolean;
  rejectIfExists?: boolean;
  idempotent?: boolean;
  rejectHttpErrors?: boolean;
}

interface UploadRequest {
  url: string;
  source: string;
  headers?: Object;
  uuid?: string;
  emitProgress?: boolean;
  httpMethod?: string;
  uploadType?: number;
  fieldName?: string;
  mimeType?: string;
  parameters?: Object;
}

class UriRecord {
  uri: string;
  constructor(uri: string) {
    this.uri = uri;
  }
}

class PermissionRecord {
  granted: boolean;
  directoryUri?: string;
  constructor(granted: boolean, directoryUri?: string) {
    this.granted = granted;
    this.directoryUri = directoryUri;
  }
}

class ResumeRecord {
  resumeData: string;
  constructor(resumeData: string) {
    this.resumeData = resumeData;
  }
}

class DownloadResult {
  uri: string;
  status: number;
  headers: ESObject;
  md5?: string;
  constructor(uri: string, status: number, headers: ESObject, md5?: string) {
    this.uri = uri;
    this.status = status;
    this.headers = headers;
    this.md5 = md5;
  }
}

class RawDownloadResult {
  uri: string;
  md5?: string;
  constructor(uri: string, md5?: string) {
    this.uri = uri;
    this.md5 = md5;
  }
}

class UploadResult {
  body: string;
  status: number;
  headers: ESObject;
  constructor(body: string, status: number, headers: ESObject) {
    this.body = body;
    this.status = status;
    this.headers = headers;
  }
}

class ProgressValues {
  totalBytesWritten?: number;
  totalBytesExpectedToWrite?: number;
  totalBytesSent?: number;
  totalBytesExpectedToSend?: number;
}

class ProgressPayload {
  uuid: string;
  data: ProgressValues;
  constructor(uuid: string, data: ProgressValues) {
    this.uuid = uuid;
    this.data = data;
  }
}

class ModuleEventMessage {
  moduleName: string = 'ExponentFileSystem';
  eventName: string;
  arguments: ProgressPayload[];
  constructor(eventName: string, payload: ProgressPayload) {
    this.eventName = eventName;
    this.arguments = [payload];
  }
}

class ExpoFileSystemService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;
  private readonly tasks: Map<string, NetworkTask> = new Map();
  private destroyed: boolean = false;
  private destruction: Promise<void> = Promise.resolve();

  constructor(context: UITurboModuleContext) {
    this.context = context;
  }

  async invoke(methodName: string, args: ESObject[]): Promise<ESObject> {
    if (methodName === 'destroy') {
      this.onDestroy();
      await this.destruction;
      return null;
    }

    if (this.destroyed) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_RUNTIME_DESTROYED');
    }

    if (methodName === 'download') {
      return await this.download(args[0] as DownloadRequest);
    }

    if (methodName === 'upload') {
      return await this.upload(args[0] as UploadRequest);
    }

    if (methodName === 'cancel') {
      return await this.cancel(String(args[0]));
    }

    if (methodName === 'pause') {
      return await this.pause(String(args[0]));
    }

    if (methodName === 'pickFile') {
      return await this.pickFile(args[0] as string | undefined, args[1] as string | undefined);
    }

    if (methodName === 'pickDirectory') {
      return await this.pickDirectory(args[0] as string | undefined);
    }

    if (methodName === 'pickFileRecord') {
      return new UriRecord(await this.pickFile(args[0] as string | undefined, args[1] as string | undefined));
    }

    if (methodName === 'pickDirectoryRecord') {
      return new UriRecord(await this.pickDirectory(args[0] as string | undefined));
    }

    if (methodName === 'pickDirectoryPermission') {
      return await this.pickDirectoryPermission(args[0] as string | undefined);
    }

    if (methodName === 'downloadUri') {
      const result = await this.download(args[0] as DownloadRequest);
      if (result === null) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANCELLED');
      return result.uri;
    }

    if (methodName === 'readDirectory') {
      const directory = String(args[0]);
      const names = await fs.listFile(directory);
      const result: string[] = [];

      for (const name of names) {
        const target = joinPath(directory, name);
        const uri = toFileUri(target);
        const info = await fs.stat(target);
        result.push(info.isDirectory() && !uri.endsWith('/') ? `${uri}/` : uri);
      }

      return result;
    }

    if (methodName === 'makeDirectory') {
      await fs.mkdir(String(args[0]), true);
      return null;
    }

    if (methodName === 'makeSafDirectory') {
      const directory = String(args[0]);
      const name = safeName(String(args[1]));
      const target = joinPath(directory, name);

      await fs.mkdir(target, false);
      return toFileUri(target);
    }

    if (methodName === 'createFile') {
      const directory = String(args[0]);
      const name = String(args[1]);
      const separator = directory.endsWith('/') ? '' : '/';
      const target = `${directory}${separator}${name}`;

      const file = await fs.open(target, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      await fs.close(file.fd);
      return toFileUri(target);
    }

    if (methodName === 'createSafFile') {
      const directory = String(args[0]);
      const requested = String(args[1]);
      const mime = String(args[2]);
      const extension = requested.includes('.') ? null : extensionForMimeType(mime);
      const name = safeName(extension === null ? requested : `${requested}.${extension}`);
      const target = joinPath(directory, name);

      const file = await fs.open(target, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      await fs.close(file.fd);
      return toFileUri(target);
    }

    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNKNOWN_METHOD', methodName);
  }

  onDestroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    const tasks = Array.from(this.tasks.values());
    const terminations: Promise<void>[] = [];

    tasks.forEach((task: NetworkTask): void => {
      task.cancelled = true;
      if (task.complete !== undefined) terminations.push(task.complete());
      try {
        task.request.destroy();
      } catch (_) {}
      if (task.done !== undefined) terminations.push(task.done);
    });

    this.tasks.clear();
    this.destruction = Promise.all(terminations)
      .catch((_: Object): void => {})
      .then((): void => {
        tasks.forEach((task: NetworkTask): void => {
          if (!task.paused && !task.preservePartial && task.temporary !== undefined) {
            try {
              fs.unlinkSync(task.temporary);
            } catch (_) {}
          }
        });
      });

    this.destruction.catch((_: Object): void => {});
  }

  invokeSync(methodName: string, args: ESObject[]): ESObject {
    if (this.destroyed) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_RUNTIME_DESTROYED');
    }

    if (methodName === 'contentUri') {
      return toFileUri(String(args[0]));
    }
    if (methodName === 'mimeType') {
      return mimeTypeForPath(String(args[0]));
    }

    if (methodName === 'extensionForMimeType') {
      return extensionForMimeType(String(args[0]));
    }

    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNKNOWN_METHOD', methodName);
  }

  private async pickFile(initialUri?: string, mimeType?: string): Promise<string> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    if (initialUri) options.defaultFilePathUri = initialUri;

    const filter = mimeSuffixFilter(mimeType);
    if (filter !== null) options.fileSuffixFilters = [filter];
    const uris = await new picker.DocumentViewPicker(this.context.uiAbilityContext).select(options);

    if (uris.length === 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_PICKER_CANCELLED');
    if (!(await persistPickerPermission(uris[0]))) {
      this.context.logger.warn(`Unable to persist the selected Expo file URI permission: ${uris[0]}`);
    }

    return normalizePickerUri(uris[0]);
  }

  private async pickDirectory(initialUri?: string): Promise<string> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.selectMode = picker.DocumentSelectMode.FOLDER;
    if (initialUri) options.defaultFilePathUri = initialUri;

    const uris = await new picker.DocumentViewPicker(this.context.uiAbilityContext).select(options);

    if (uris.length === 0) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_PICKER_CANCELLED');
    }
    if (!(await persistPickerPermission(uris[0]))) {
      this.context.logger.warn(`Unable to persist the selected Expo directory URI permission: ${uris[0]}`);
    }

    return normalizePickerUri(uris[0]);
  }

  private async pickDirectoryPermission(initialUri?: string): Promise<PermissionRecord> {
    try {
      return new PermissionRecord(true, await this.pickDirectory(initialUri));
    } catch (error) {
      if (cleanErrorMessage(error as Object).includes('ERR_FILE_SYSTEM_PICKER_CANCELLED')) {
        return new PermissionRecord(false);
      }
      throw new ExpoFileSystemError(cleanErrorMessage(error as Object));
    }
  }

  private async cancel(uuid: string): Promise<null> {
    const task = this.tasks.get(uuid);

    if (task !== undefined) {
      task.cancelled = true;
      task.request.destroy();
      if (task.complete !== undefined) await task.complete();
      if (task.done !== undefined) await task.done;

      if (!task.preservePartial && task.temporary !== undefined) {
        try {
          fs.unlinkSync(task.temporary);
        } catch (_) {}
      }
      this.tasks.delete(uuid);
    }
    return null;
  }

  private async pause(uuid: string): Promise<ResumeRecord | null> {
    const task = this.tasks.get(uuid);
    if (task === undefined) return null;

    task.cancelled = true;
    task.paused = true;
    task.request.destroy();
    if (task.complete !== undefined) await task.complete();
    if (task.done !== undefined) await task.done;

    let transferred = task.transferred;
    if (task.temporary !== undefined && (await fs.access(task.temporary))) {
      transferred = Math.min(transferred, (await fs.stat(task.temporary)).size);
    }

    const resumeData = String(transferred);
    this.tasks.delete(uuid);
    return new ResumeRecord(resumeData);
  }

  private async download(input: DownloadRequest): Promise<DownloadResult | RawDownloadResult | null> {
    const uuid = input.uuid ?? `${Date.now()}-${Math.random()}`;

    if (isPackagedResource(input.url)) return await this.copyPackagedResource(input, uuid);

    const request = http.createHttp();
    let destination = input.destinationIsDirectory ? joinPath(input.destination, suggestedFilename(input.url, null)) : input.destination;
    let temporary = input.emitProgress ? destination : `${destination}.expo-${uuid.replace(/[^A-Za-z0-9_-]/g, '_')}.part`;

    const task: NetworkTask = {
      request,
      transferred: input.resumeFrom ?? 0,
      cancelled: false,
      paused: false,
      preservePartial: input.emitProgress === true,
      temporary,
      progressCadence: new ProgressCadence(),
    };

    let resolveTaskDone: () => void = (): void => {};
    task.done = new Promise<void>((resolve: () => void): void => {
      resolveTaskDone = resolve;
    });

    this.tasks.set(uuid, task);

    let output: fs.File | undefined;
    let headers: ESObject = null;
    let status: number = 0;
    let completionTimeout = -1;

    const clearCompletionTimeout = (): void => {
      if (completionTimeout < 0) return;
      clearTimeout(completionTimeout);
      completionTimeout = -1;
    };

    try {
      let resumeFrom = input.resumeFrom ?? 0;
      if (resumeFrom > 0 && (!fs.accessSync(temporary) || fs.statSync(temporary).size !== resumeFrom)) resumeFrom = 0;

      task.transferred = resumeFrom;
      let effectiveResumeFrom = resumeFrom;
      let offset = resumeFrom;
      let responseReady = false;
      let acceptingChunks = true;
      let bodyEnded = false;
      const pendingChunks: Array<ArrayBuffer> = [];
      let writeQueue: Promise<void> = Promise.resolve();

      let finish: () => void = (): void => {};
      let rejectRequestCancellation: (error: Error) => void = (_: Error): void => {};
      let settled = false;
      const completed = new Promise<void>((resolve: () => void): void => {
        finish = (): void => {
          if (settled) return;
          clearCompletionTimeout();
          settled = true;
          resolve();
        };
      });

      const requestCancellation = new Promise<number>((_: (value: number) => void, reject: (error: Error) => void): void => {
        rejectRequestCancellation = reject;
      });
      requestCancellation.catch((_: Error): void => {});

      const drainWrites = async (): Promise<void> => {
        try {
          await writeQueue;
        } catch (error) {
          if (task.failure === undefined) task.failure = cleanErrorMessage(error as Object);
        }
        finish();
      };

      const fail = (error: Object): void => {
        if (task.failure === undefined) task.failure = cleanErrorMessage(error);
        acceptingChunks = false;
        pendingChunks.length = 0;
        rejectRequestCancellation(new ExpoFileSystemError(task.failure) as Error);
        try {
          request.destroy();
        } catch (_) {}
        drainWrites().catch((_: Object): void => finish());
      };

      task.complete = async (): Promise<void> => {
        clearCompletionTimeout();
        acceptingChunks = false;
        pendingChunks.length = 0;
        rejectRequestCancellation(new ExpoFileSystemError('ERR_FILE_SYSTEM_CANCELLED') as Error);
        await drainWrites();
      };

      const armCompletionTimeout = (): void => {
        clearCompletionTimeout();
        completionTimeout = setTimeout((): void => {
          fail('ERR_UNABLE_TO_DOWNLOAD: Harmony did not complete the response within the platform read timeout');
        }, NETSTACK_COMPLETION_FALLBACK_MS);
      };

      const ensureOutput = (): fs.File => {
        if (output === undefined) {
          const mode = fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | (effectiveResumeFrom > 0 ? 0 : fs.OpenMode.TRUNC);
          output = fs.openSync(temporary, mode);
        }
        return output;
      };

      const writeChunk = (chunk: ArrayBuffer): void => {
        if (task.cancelled || task.failure !== undefined) return;
        writeQueue = writeQueue.then(async (): Promise<void> => {
          if (task.cancelled || task.failure !== undefined) return;
          const written = await writeAllAsync(ensureOutput().fd, chunk, offset);
          offset += written;
          task.transferred = offset;
        });
        writeQueue.catch((error: Object): void => fail(error));
      };

      const makeResponseReady = (resumeHonored: boolean): void => {
        if (responseReady) return;
        if (!resumeHonored) {
          effectiveResumeFrom = 0;
          offset = 0;
          task.transferred = 0;
        }
        responseReady = true;
        if (!task.cancelled && task.failure === undefined) {
          pendingChunks.forEach((chunk: ArrayBuffer): void => writeChunk(chunk));
        }
        pendingChunks.length = 0;
        if (bodyEnded) drainWrites().catch((_: Object): void => finish());
      };

      request.on('headersReceive', (value: Object): void => {
        if (settled || task.cancelled || task.failure !== undefined) return;
        try {
          headers = value;
          if (input.destinationIsDirectory && output === undefined) {
            destination = joinPath(input.destination, suggestedFilename(input.url, value));
            temporary = input.emitProgress ? destination : `${destination}.expo-${uuid.replace(/[^A-Za-z0-9_-]/g, '_')}.part`;
            task.temporary = temporary;
          }
          if (input.rejectIfExists && !input.idempotent && fs.accessSync(destination)) {
            fail('ERR_DESTINATION_ALREADY_EXISTS: Download destination already exists');
            return;
          }
          const contentRange = headerValue(value, 'content-range');
          makeResponseReady(resumeFrom === 0 || contentRange?.toLowerCase().startsWith(`bytes ${resumeFrom}-`) === true);
        } catch (error) {
          fail(error as Object);
        }
      });

      request.on('dataReceive', (chunk: ArrayBuffer): void => {
        if (!acceptingChunks || settled || task.cancelled || task.failure !== undefined) return;
        try {
          armCompletionTimeout();
          if (!responseReady) pendingChunks.push(chunk);
          else writeChunk(chunk);
        } catch (error) {
          fail(error as Object);
        }
      });

      request.on('dataEnd', (): void => {
        if (bodyEnded || settled || task.cancelled || task.failure !== undefined) return;
        bodyEnded = true;
        acceptingChunks = false;
        if (responseReady) drainWrites().catch((_: Object): void => finish());
      });

      request.on('dataReceiveProgress', (progress: http.DataReceiveProgressInfo): void => {
        if (!responseReady || settled || task.cancelled || task.failure !== undefined) return;
        task.expectedTransfer = progress.totalSize < 0 ? -1 : effectiveResumeFrom + progress.totalSize;
        if (input.emitProgress) this.emitDownloadProgress(task, uuid, false);
      });

      const requestHeaders = copyHeaders(input.headers);
      if (resumeFrom > 0) Reflect.set(requestHeaders, 'Range', `bytes=${resumeFrom}-`);

      armCompletionTimeout();
      try {
        status = await Promise.race([
          request.requestInStream(input.url, {
            method: http.RequestMethod.GET,
            header: requestHeaders,
            connectTimeout: 60000,
            readTimeout: 60000,
            maxLimit: NETSTACK_RESPONSE_LIMIT_BYTES,
          }),
          requestCancellation,
        ]);
      } catch (error) {
        if (!task.cancelled) fail(error as Object);
      }
      if (!task.cancelled && task.failure === undefined && !responseReady) {
        makeResponseReady(resumeFrom > 0 && status === 206);
      }

      await completed;
      if (task.failure !== undefined) throw new ExpoFileSystemError(task.failure);
      if (task.cancelled) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANCELLED');
      if (input.rejectHttpErrors && (status < 200 || status >= 300)) {
        throw new ExpoFileSystemError('ERR_UNABLE_TO_DOWNLOAD', `response has status: ${status}`);
      }

      ensureOutput();
      if (output === undefined) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANNOT_OPEN');
      task.transferred = offset;
      if (input.emitProgress) this.emitDownloadProgress(task, uuid, true);

      const outputFd = output.fd;
      output = undefined;
      fs.closeSync(outputFd);
      if (temporary !== destination) fs.moveFileSync(temporary, destination, 0);

      const md5 = input.md5 ? (await fileHash.hash(destination, 'md5')).toLowerCase() : undefined;
      return new DownloadResult(toFileUri(destination), status, headers, md5);
    } catch (error) {
      if (output !== undefined) {
        const outputFd = output.fd;
        output = undefined;
        try {
          fs.closeSync(outputFd);
        } catch (_) {}
      }
      if (!task.paused && !(task.cancelled && task.preservePartial)) {
        try {
          fs.unlinkSync(temporary);
        } catch (_) {}
      }

      if (task.failure !== undefined) throw new ExpoFileSystemError(task.failure);
      if (task.cancelled) return null;
      throw new ExpoFileSystemError(cleanErrorMessage(error));
    } finally {
      // Stop the platform request before releasing the task record.
      clearCompletionTimeout();
      request.destroy();
      this.tasks.delete(uuid);
      resolveTaskDone();
    }
  }

  private async copyPackagedResource(input: DownloadRequest, uuid: string): Promise<RawDownloadResult> {
    const resourceName = packagedResourceName(input.url);
    const destination = input.destinationIsDirectory ? joinPath(input.destination, safeLeafName(resourceName)) : input.destination;

    if (input.rejectIfExists && !input.idempotent && fs.accessSync(destination)) {
      throw new ExpoFileSystemError('ERR_DESTINATION_ALREADY_EXISTS', 'Download destination already exists');
    }

    const temporary = `${destination}.expo-${uuid.replace(/[^A-Za-z0-9_-]/g, '_')}.part`;
    const resourceManager = this.context.uiAbilityContext.resourceManager;
    let opened = false;

    try {
      const descriptor = await resourceManager.getRawFd(resourceName);
      opened = true;

      const output = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.lseek(descriptor.fd, descriptor.offset, fs.WhenceType.SEEK_SET);
        fs.lseek(output.fd, 0, fs.WhenceType.SEEK_SET);
        const buffer = new ArrayBuffer(64 * 1024);
        let copied = 0;

        while (copied < descriptor.length) {
          const length = Math.min(buffer.byteLength, descriptor.length - copied);
          const count = await fs.read(descriptor.fd, buffer, { length });
          if (count <= 0) {
            throw new ExpoFileSystemError('ERR_FILE_SYSTEM_RAW_RESOURCE', 'Unable to read the complete bundled resource');
          }
          await writeAllAsync(output.fd, count === buffer.byteLength ? buffer : buffer.slice(0, count));
          copied += count;
        }
      } finally {
        await fs.close(output.fd);
      }

      await resourceManager.closeRawFd(resourceName);
      opened = false;
      await fs.moveFile(temporary, destination, 0);

      const md5 = input.md5 ? (await fileHash.hash(destination, 'md5')).toLowerCase() : undefined;
      return new RawDownloadResult(toFileUri(destination), md5);
    } catch (error) {
      try {
        await fs.unlink(temporary);
      } catch (_) {}
      throw new ExpoFileSystemError(cleanErrorMessage(error));
    } finally {
      if (opened) {
        try {
          await resourceManager.closeRawFd(resourceName);
        } catch (_) {}
      }
    }
  }

  private async upload(input: UploadRequest): Promise<UploadResult | null> {
    const uuid = input.uuid ?? `${Date.now()}-${Math.random()}`;
    const request = http.createHttp();
    const task: NetworkTask = {
      request,
      transferred: 0,
      cancelled: false,
      paused: false,
      preservePartial: false,
      progressCadence: new ProgressCadence(),
    };

    this.tasks.set(uuid, task);
    try {
      const headers = copyHeaders(input.headers);
      const policy = uploadMethodPolicy(input.httpMethod);
      const options: http.HttpRequestOptions = {
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 60000,
        readTimeout: 60000,
      };

      if (policy.standard) options.method = policy.method as http.RequestMethod;
      else options.customMethod = policy.method;
      if (input.uploadType === 1) options.multiFormDataList = makeMultipartList(input);
      else {
        task.expectedTransfer = fs.statSync(input.source).size;
        options.extraData = readFileBuffer(input.source);
        if (input.mimeType) Reflect.set(headers, 'Content-Type', input.mimeType);
      }

      request.on('dataSendProgress', (progress: http.DataSendProgressInfo): void => {
        if (task.cancelled) return;
        task.transferred = progress.sendSize;
        task.expectedTransfer = progress.totalSize;
        if (input.emitProgress) this.emitUploadProgress(task, uuid, false);
      });

      const result = await request.request(input.url, options);
      if (task.cancelled) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANCELLED');
      if (task.expectedTransfer === undefined) task.expectedTransfer = task.transferred;
      if (task.expectedTransfer >= 0) task.transferred = task.expectedTransfer;
      if (input.emitProgress) this.emitUploadProgress(task, uuid, true);

      return new UploadResult(String(result.result), result.responseCode, result.header);
    } catch (error) {
      if (task.cancelled) return null;
      throw new ExpoFileSystemError(cleanErrorMessage(error));
    } finally {
      request.destroy();
      this.tasks.delete(uuid);
    }
  }

  private emitDownloadProgress(task: NetworkTask, uuid: string, force: boolean): void {
    const expected = task.expectedTransfer ?? task.transferred;
    if (!task.progressCadence.shouldEmit(Date.now(), task.transferred, expected, force)) return;
    const values = new ProgressValues();
    values.totalBytesWritten = task.transferred;
    values.totalBytesExpectedToWrite = expected;
    this.emitProgress('expo-file-system.downloadProgress', uuid, values);
  }

  private emitUploadProgress(task: NetworkTask, uuid: string, force: boolean): void {
    const expected = task.expectedTransfer ?? task.transferred;
    if (!task.progressCadence.shouldEmit(Date.now(), task.transferred, expected, force)) return;
    const values = new ProgressValues();
    values.totalBytesSent = task.transferred;
    values.totalBytesExpectedToSend = expected;
    this.emitProgress('expo-file-system.uploadProgress', uuid, values);
  }

  private emitProgress(eventName: string, uuid: string, data: ProgressValues): void {
    this.context.rnInstance.postMessageToCpp(EXPO_MODULE_EVENT, new ModuleEventMessage(eventName, new ProgressPayload(uuid, data)));
  }
}

function toFileUri(path: string): string {
  if (path.startsWith('file:')) return path;
  if (!path.startsWith('/')) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_PATH');

  return `file://${path
    .split('/')
    .map((segment: string): string =>
      encodeURIComponent(segment).replace(/[!'()*]/g, (character: string): string => `%${character.charCodeAt(0).toString(16).toUpperCase()}`),
    )
    .join('/')}`;
}

function normalizePickerUri(uri: string): string {
  // Picker returns a virtual URI such as file://docs/storage/.... Opening it
  // is the supported conversion route, and File.path exposes the POSIX path
  // needed by the native capability sandbox. Do not serialize that path with
  // FileUri again: it maps the path back to the original virtual authority.
  const selected = fs.openSync(uri, fs.OpenMode.READ_ONLY);

  try {
    if (!selected.path.startsWith('/')) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_PICKED_URI');
    return toFileUri(selected.path);
  } finally {
    fs.closeSync(selected.fd);
  }
}

function isPackagedResource(uri: string): boolean {
  return uri.startsWith('asset://') || uri.startsWith('rawfile://') || !uri.includes(':');
}

function packagedResourceName(uri: string): string {
  const raw = uri
    .replace(/^(asset|rawfile):\/\//, '')
    .replace(/^\/+/, '')
    .split(/[?#]/, 1)[0];
  const decoded = decodeURIComponent(raw).replace(/\\/g, '/');
  const segments = decoded.split('/');

  if (segments.length === 0 || segments.some((segment: string): boolean => segment.length === 0 || segment === '.' || segment === '..')) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESOURCE');
  }

  return segments.join('/');
}

function safeName(value: string): string {
  if (value.length === 0 || value === '.' || value === '..' || value.includes('/') || value.includes('\\')) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_NAME');
  }

  return value;
}

function joinPath(directory: string, name: string): string {
  return `${directory}${directory.endsWith('/') ? '' : '/'}${name}`;
}

function suggestedFilename(url: string, headers: Object | null): string {
  let filename: string | null = null;

  if (headers !== null) {
    const disposition = headerValue(headers, 'content-disposition');
    if (disposition !== null) {
      const encoded = /filename\*\s*=\s*(?:UTF-8'')?([^;]+)/i.exec(disposition);
      const plain = /filename\s*=\s*(?:"([^"]+)"|([^;]+))/i.exec(disposition);
      const candidate = encoded !== null ? encoded[1] : plain !== null ? (plain[1] ?? plain[2]) : '';
      if (candidate.length > 0) {
        try {
          filename = safeLeafName(decodeURIComponent(candidate.trim().replace(/^"|"$/g, '')));
        } catch (_) {}
      }
    }
  }

  if (filename === null) {
    const withoutFragment = url.split('#')[0].split('?')[0].replace(/\/+$/, '');
    const component = withoutFragment.slice(withoutFragment.lastIndexOf('/') + 1);
    if (component.length > 0) {
      try {
        filename = safeLeafName(decodeURIComponent(component));
      } catch (_) {}
    }
  }

  filename = filename ?? 'download';
  if (!filename.includes('.') && headers !== null) {
    const extension = extensionForMimeType(headerValue(headers, 'content-type'));
    if (extension !== null) filename = `${filename}.${extension}`;
  }

  return filename;
}

function extensionForMimeType(value: string | null): string | null {
  if (value === null) return null;
  const mime = value.split(';', 1)[0].trim().toLowerCase();
  if (mime.length === 0) return null;

  try {
    const typeId = uniformTypeDescriptor.getUniformDataTypeByMIMEType(mime);
    const extensions = uniformTypeDescriptor.getTypeDescriptor(typeId).filenameExtensions;
    if (extensions.length === 0) return null;
    return extensions[0].replace(/^\./, '');
  } catch (_) {
    return null;
  }
}

function mimeTypeForPath(path: string): string {
  const leaf = path.split(/[?#]/, 1)[0];
  const dot = leaf.lastIndexOf('.');
  if (dot < 0 || dot === leaf.length - 1) return '';

  try {
    const typeId = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(leaf.slice(dot + 1));
    const mimeTypes = uniformTypeDescriptor.getTypeDescriptor(typeId).mimeTypes;
    return mimeTypes.length > 0 ? mimeTypes[0] : '';
  } catch (_) {
    return '';
  }
}

function headerValue(headers: Object, expectedName: string): string | null {
  const name = Object.keys(headers).find((candidate: string): boolean => candidate.toLowerCase() === expectedName);

  return name === undefined ? null : String(Reflect.get(headers, name));
}

function safeLeafName(value: string): string {
  const normalized = value.replace(/\\/g, '/');
  const leaf = normalized.slice(normalized.lastIndexOf('/') + 1).trim();

  return safeName(leaf.length === 0 ? 'download' : leaf);
}

function mimeSuffixFilter(mimeType?: string): string | null {
  if (mimeType === undefined || mimeType === '*/*') return null;
  const normalized = mimeType.toLowerCase();
  if (normalized === 'image/*') {
    return `${mimeType}|.bmp,.gif,.heic,.jpeg,.jpg,.png,.svg,.webp`;
  }
  if (normalized === 'video/*') {
    return `${mimeType}|.3gp,.avi,.m4v,.mkv,.mov,.mp4,.webm`;
  }
  if (normalized === 'audio/*') {
    return `${mimeType}|.aac,.flac,.m4a,.mp3,.ogg,.wav,.webm`;
  }
  if (normalized === 'text/*') {
    return `${mimeType}|.csv,.html,.json,.md,.rtf,.text,.tsv,.txt,.xml,.yaml,.yml`;
  }

  try {
    const typeIds = uniformTypeDescriptor.getUniformDataTypesByMIMEType(normalized);
    const extensions: string[] = [];
    typeIds.forEach((typeId: string): void => {
      uniformTypeDescriptor.getTypeDescriptor(typeId).filenameExtensions.forEach((extension: string): void => {
        const normalized = extension.startsWith('.') ? extension : `.${extension}`;
        if (!extensions.includes(normalized)) extensions.push(normalized);
      });
    });
    return extensions.length === 0 ? null : `${mimeType}|${extensions.join(',')}`;
  } catch (_) {
    return null;
  }
}

function copyHeaders(input?: Object): Object {
  const output = new Object();

  if (input !== undefined) {
    Object.keys(input).forEach((name: string): void => {
      Reflect.set(output, name, String(Reflect.get(input, name)));
    });
  }

  return output;
}

function writeAll(fd: number, data: ArrayBuffer, offset: number): number {
  fs.lseek(fd, offset, fs.WhenceType.SEEK_SET);

  let written = 0;
  while (written < data.byteLength) {
    const end = Math.min(written + 64 * 1024, data.byteLength);
    const count = fs.writeSync(fd, data.slice(written, end), { length: end - written });
    if (count <= 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_WRITE_FAILED');
    written += count;
  }

  return written;
}

async function writeAllAsync(fd: number, data: ArrayBuffer, offset?: number): Promise<number> {
  if (offset !== undefined) fs.lseek(fd, offset, fs.WhenceType.SEEK_SET);

  let written = 0;
  while (written < data.byteLength) {
    const end = Math.min(written + 64 * 1024, data.byteLength);
    const count = await fs.write(fd, data.slice(written, end), { length: end - written });
    if (count <= 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_WRITE_FAILED');
    written += count;
  }

  return written;
}

function readFileBuffer(path: string): ArrayBuffer {
  const size = fs.statSync(path).size;
  const output = new ArrayBuffer(size);
  if (size === 0) return output;
  const bytes = new Uint8Array(output);
  const chunk = new ArrayBuffer(Math.min(size, 64 * 1024));
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  let read = 0;

  try {
    fs.lseek(file.fd, 0, fs.WhenceType.SEEK_SET);
    while (read < size) {
      const length = Math.min(chunk.byteLength, size - read);
      const count = fs.readSync(file.fd, chunk, { length });
      if (count <= 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_READ_FAILED');
      bytes.set(new Uint8Array(chunk, 0, count), read);
      read += count;
    }
  } finally {
    fs.closeSync(file.fd);
  }

  return output;
}

function makeMultipartList(input: UploadRequest): http.MultiFormData[] {
  const parts: http.MultiFormData[] = [];
  const parameters: Object | undefined = input.parameters;

  if (parameters !== undefined) {
    Object.keys(parameters).forEach((name: string): void => {
      parts.push({
        name,
        contentType: 'text/plain; charset=utf-8',
        data: String(Reflect.get(parameters, name)),
      });
    });
  }

  parts.push({
    name: input.fieldName ?? safeLeafName(input.source),
    contentType: input.mimeType ?? (mimeTypeForPath(input.source) || 'application/octet-stream'),
    remoteFileName: safeLeafName(input.source),
    filePath: input.source,
  });

  return parts;
}

async function persistPickerPermission(uri: string): Promise<boolean> {
  const policy: fileShare.PolicyInfo = {
    uri,
    operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE,
  };

  try {
    await fileShare.persistPermission([policy]);
    await fileShare.activatePermission([policy]);
    return true;
  } catch (_) {
    return false;
  }
}

function cleanErrorMessage(error: Object): string {
  return String(error).replace(/^(?:Error:\s*)+/, '');
}

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new ExpoFileSystemService(context),
  });
  registered = true;
}

export class ExpoFileSystemPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerService();

    super(context);
  }
  override getDebugName(): string {
    return '@expo-harmony/expo-file-system';
  }
}

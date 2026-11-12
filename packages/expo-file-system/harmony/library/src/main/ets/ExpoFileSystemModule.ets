/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFileAccessMode,
  ExpoFunction,
  ExpoEither,
  ExpoModule,
  ExpoModuleContext,
  ExpoNetworkInspection,
  ExpoRawResourceFile,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoSharedObject,
  ExpoSharedObjectClassDefinition,
  ExpoSharedObjectTypes,
  ExpoSharedRef,
  ExpoValueType,
  ExpoValueTypes,
  fileUriFromPath,
  isRnohRawfileResourceUri,
  openRawResourceFile,
  rawResourcePathFromUri,
  resolveFileReadSource,
} from '@expo-harmony/expo-modules-core';
import { fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import fs from '@ohos.file.fs';
import fileHash from '@ohos.file.hash';
import statvfs from '@ohos.file.statvfs';
import picker from '@ohos.file.picker';
import uniformTypeDescriptor from '@ohos.data.uniformTypeDescriptor';
import { rcp } from '@kit.RemoteCommunicationKit';
import url from '@ohos.url';
import util from '@ohos.util';
import atomicFileOperations from 'libexpo_file_system_atomic.so';
import { PickerPermissionStore } from './PickerPermissionStore';
import { DEFAULT_WATCH_DEBOUNCE_MS, FileSystemWatcher } from './FileSystemWatcher';
import { ExpoFileSystemError, ProgressCadence, normalizeUploadMethod, parseContentRange, isRedirectStatus } from './NetworkPolicy';

const NETWORK_FILE_BUFFER_BYTES: number = 64 * 1024;
// Match the system redirect limit, while handling each response before publishing a file.
const MAX_DOWNLOAD_REDIRECTS: number = 50;
const HTTP_RANGE_NOT_SATISFIABLE: number = 416;
const NETWORK_IDLE_TIMEOUT_MS: number = 60_000;
const FILE_NOT_FOUND_ERROR: number = 13900002;
const FILE_EXISTS_ERROR: number = 13900015;
const DOWNLOAD_RESUME_FORMAT_VERSION: number = 1;
const FILE_SYSTEM_LOG_DOMAIN: number = 0;
const FILE_SYSTEM_LOG_TAG: string = 'ExpoFileSystem';

interface NetworkTask {
  session?: rcp.Session;
  request?: rcp.Request;
  transferred: number;
  cancelled: boolean;
  committing: boolean;
  done: Promise<void>;
  finish: () => void;
  cancellation: Promise<never>;
  rejectCancellation: (error: Error) => void;
  pendingWrite: Promise<void>;
  failure?: ExpoModuleError;
  expectedTransfer: number;
  progressCadence: ProgressCadence;
  destination?: string;
}

interface DownloadRequest {
  url: string;
  destination: string;
  headers?: Object;
  emitProgress?: boolean;
  resumeFrom?: number;
  md5?: boolean;
  destinationIsDirectory?: boolean;
  validateDestination?: (path: string, mode: ExpoFileAccessMode) => void;
  idempotent?: boolean;
  rejectHttpErrors?: boolean;
  resumable?: boolean;
}

interface UploadRequest {
  url: string;
  source: string;
  headers?: Object;
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
  destination?: string;
  constructor(resumeData: string, destination?: string) {
    this.resumeData = resumeData;
    this.destination = destination;
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

class ExpoFileSystemService {
  // Modern and legacy FileSystem pickers share the same UIAbility modal slot.
  private static readonly pickingContexts: Set<common.UIAbilityContext> = new Set();
  private readonly context: ExpoModuleContext;
  private readonly progress: (eventName: string, payload: ProgressPayload) => void;
  private readonly pickerPermission?: (originalUri: string, normalizedUri: string, directory: boolean) => Promise<void>;
  private readonly tasks: Map<string, NetworkTask> = new Map();
  private destroyed: boolean = false;
  private destruction: Promise<void> = Promise.resolve();

  constructor(
    context: ExpoModuleContext,
    progress: (eventName: string, payload: ProgressPayload) => void,
    pickerPermission?: (originalUri: string, normalizedUri: string, directory: boolean) => Promise<void>,
  ) {
    this.context = context;
    this.progress = progress;
    this.pickerPermission = pickerPermission;
  }

  onDestroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    const tasks = Array.from(this.tasks.values());
    tasks.forEach((task: NetworkTask): void => this.cancelTask(task));
    this.destruction = Promise.all(tasks.map((task: NetworkTask): Promise<void> => task.done)).then((): void => {});
  }

  async destroy(): Promise<void> {
    this.onDestroy();
    await this.destruction;
  }

  private assertActive(): void {
    if (this.destroyed) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_RUNTIME_DESTROYED');
  }

  private beginPicking(): common.UIAbilityContext {
    this.assertActive();
    if (this.context.isHeadless) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_PICKER_UNAVAILABLE', 'File picking requires a UIAbility');

    const context = this.context.uiAbilityContext;
    if (ExpoFileSystemService.pickingContexts.has(context)) {
      throw new ExpoFileSystemError('ERR_PICKING_IN_PROGRESS', 'Await the current file or directory picker first');
    }

    ExpoFileSystemService.pickingContexts.add(context);

    return context;
  }

  async pickFiles(initialUri?: string, mimeTypes?: string[], multiple: boolean = false): Promise<string[]> {
    const context = this.beginPicking();

    try {
      const options = new picker.DocumentSelectOptions();
      // Leave the system's multi-selection limit in effect.
      if (!multiple) options.maxSelectNumber = 1;
      if (initialUri) options.defaultFilePathUri = initialUri;

      const filters: string[] = [];
      const unrestricted = mimeTypes === undefined || mimeTypes.length === 0 ||
        mimeTypes.some((mime: string): boolean => mime.trim() === '*/*');
      if (!unrestricted) mimeTypes?.forEach((mime: string): void => {
        const suffixes = mimeSuffixFilters(mime);
        suffixes?.forEach((suffix: string): void => {
          if (!filters.includes(suffix)) filters.push(suffix);
        });
      });
      // Expo MIME arrays are a union, rather than separate selectable filter groups.
      if (!unrestricted) options.fileSuffixFilters = [filters.join(',')];

      const uris = await new picker.DocumentViewPicker(context).select(options);
      this.assertActive();
      if (uris.length === 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_PICKER_CANCELLED');

      const sources = multiple ? uris : uris.slice(0, 1);
      const selected = sources.map((uri: string): string => normalizePickerUri(uri, false));

      for (let i = 0; i < sources.length; i++) {
        await this.rememberSelection(sources[i], selected[i], false);
      }

      return selected;
    } finally {
      ExpoFileSystemService.pickingContexts.delete(context);
    }
  }

  async pickDirectory(initialUri?: string): Promise<string> {
    if (!canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection')) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_PICKER_UNAVAILABLE', 'Directory picking is not supported on this device');
    }

    const context = this.beginPicking();

    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      if (initialUri) options.defaultFilePathUri = initialUri;

      const uris = await new picker.DocumentViewPicker(context).select(options);
      this.assertActive();
      if (uris.length === 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_PICKER_CANCELLED');

      const directory = normalizePickerUri(uris[0], true);
      await this.rememberSelection(uris[0], directory, true);

      return directory;
    } finally {
      ExpoFileSystemService.pickingContexts.delete(context);
    }
  }

  private async rememberSelection(originalUri: string, normalized: string, directory: boolean): Promise<void> {
    this.assertActive();
    if (this.pickerPermission !== undefined) await this.pickerPermission(originalUri, normalized, directory);
    this.assertActive();
  }

  async pickDirectoryPermission(initialUri?: string): Promise<PermissionRecord> {
    try {
      return new PermissionRecord(true, await this.pickDirectory(initialUri));
    } catch (error) {
      if (error instanceof ExpoModuleError && error.code === 'ERR_FILE_SYSTEM_PICKER_CANCELLED') return new PermissionRecord(false);
      throw new ExpoFileSystemError(
        error instanceof ExpoModuleError ? error.code : 'ERR_FILE_SYSTEM',
        error instanceof Error ? error.message : String(error),
        error instanceof ExpoModuleError ? error.cause : (error as Object),
        error instanceof ExpoModuleError ? error.path : undefined,
      );
    }
  }

  private beginTask(uuid: string, transferred: number = 0): NetworkTask {
    this.assertActive();
    if (this.tasks.has(uuid)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_TASK_ALREADY_RUNNING');
    let finish: () => void = (): void => {};
    const done = new Promise<void>((resolve: () => void): void => {
      finish = resolve;
    });
    let rejectCancellation: (error: Error) => void = (_: Error): void => {};
    const cancellation = new Promise<never>((_: (value: never) => void, reject: (error: Error) => void): void => {
      rejectCancellation = reject;
    });
    cancellation.catch((_: Object): void => {});
    const task: NetworkTask = {
      transferred,
      cancelled: false,
      committing: false,
      expectedTransfer: -1,
      progressCadence: new ProgressCadence(),
      done,
      finish,
      cancellation,
      rejectCancellation,
      pendingWrite: Promise.resolve(),
    };
    this.tasks.set(uuid, task);
    return task;
  }

  private cancelTask(task: NetworkTask): void {
    task.cancelled = true;
    task.rejectCancellation(new ExpoFileSystemError('ERR_FILE_SYSTEM_CANCELLED') as Error);
    try {
      task.session?.cancel(task.request);
    } catch (_) {}
  }

  private finishTask(uuid: string, task: NetworkTask): void {
    try {
      task.session?.close();
    } catch (_) {}
    if (this.tasks.get(uuid) === task) this.tasks.delete(uuid);
    task.finish();
  }

  async cancel(uuid: string): Promise<null> {
    const task = this.tasks.get(uuid);
    if (task !== undefined) {
      this.cancelTask(task);
      await task.done;
    }
    return null;
  }

  async pause(uuid: string): Promise<ResumeRecord | null> {
    const task = this.tasks.get(uuid);
    if (task === undefined) return null;
    // Once the final response arrives, pausing must await completion rather than
    // save a full-length offset that would produce an unsatisfiable HTTP Range.
    if (task.committing) {
      await task.done;
      return null;
    }

    this.cancelTask(task);
    await task.done;
    if (task.failure !== undefined) throw new ExpoFileSystemError(task.failure.code, task.failure.message, task.failure.cause, task.failure.path);
    return new ResumeRecord(String(task.transferred), task.destination);
  }

  private async fetch(task: NetworkTask, request: rcp.Request): Promise<rcp.Response> {
    assertNetworkTask(task);

    if (task.session === undefined) task.session = rcp.createSession();
    task.request = request;

    const content = request.content;
    const inspection = ExpoNetworkInspection.start(
      request.url.toString(),
      request.method,
      ExpoNetworkInspection.headers(request.headers ?? {}),
      typeof content === 'string' || content instanceof ArrayBuffer ? content : undefined,
    );
    const destination = request.destination;
    if (inspection !== undefined && typeof destination === 'function') {
      request.destination = async (chunk: ArrayBuffer): Promise<void> => {
        inspection.data(chunk);
        await destination(chunk);
      };
    }

    try {
      const response = await Promise.race([task.session.fetch(request), task.cancellation]);

      inspection?.response(response.statusCode, ExpoNetworkInspection.headers(response.headers));
      if (response.body !== undefined) inspection?.data(response.body);
      inspection?.finish();

      return response;
    } catch (error) {
      inspection?.fail(task.cancelled);

      throw new ExpoFileSystemError(
        error instanceof ExpoFileSystemError ? error.code : 'ERR_FILESYSTEM_NETWORK',
        error instanceof Error ? error.message : String(error),
        error as Object,
        error instanceof ExpoFileSystemError ? error.path : undefined,
      );
    }
  }

  async download(input: DownloadRequest): Promise<DownloadResult | RawDownloadResult | null> {
    return this.downloadTask(util.generateRandomUUID(), input.resumeFrom ?? 0, (): DownloadRequest => input);
  }

  async downloadTask(
    uuid: string,
    offset: number,
    prepare: () => DownloadRequest,
    ready?: Promise<void>,
  ): Promise<DownloadResult | RawDownloadResult | null> {
    const task = this.beginTask(uuid, offset);
    try {
      // Register the task before waiting for picker grants so pause or cancel
      // can settle it without opening a file or starting a network request.
      if (ready !== undefined) await Promise.race([ready, task.cancellation]);
      assertNetworkTask(task);

      const input = prepare();
      if (isPackagedResource(input.url)) return await this.copyPackagedResource(input, uuid, task);
      return await this.downloadHttp(input, uuid, task);
    } catch (error) {
      if (task.cancelled && task.failure === undefined) return null;
      if (task.failure !== undefined) throw new ExpoFileSystemError(task.failure.code, task.failure.message, task.failure.cause, task.failure.path);
      throw new ExpoFileSystemError(
        error instanceof ExpoModuleError ? error.code : 'ERR_UNABLE_TO_DOWNLOAD',
        error instanceof Error ? error.message : String(error),
        error instanceof ExpoModuleError ? error.cause : (error as Object),
        error instanceof ExpoModuleError ? error.path : undefined,
      );
    } finally {
      this.finishTask(uuid, task);
    }
  }

  private async downloadHttp(input: DownloadRequest, uuid: string, task: NetworkTask): Promise<DownloadResult> {
    let requestUrl = input.url;
    let requestHeaders = copyHeaders(input.headers);
    let resumeFrom = input.resumeFrom ?? 0;
    if (resumeFrom > 0) {
      input.validateDestination?.(input.destination, 'read');
      if (!(await fs.access(input.destination)) || (await fs.stat(input.destination)).size !== resumeFrom) resumeFrom = 0;
    }
    const callerRange = resumeFrom === 0 && headerValue(requestHeaders, 'range') !== null;
    task.transferred = resumeFrom;
    if (resumeFrom > 0) requestHeaders['range'] = `bytes=${resumeFrom}-`;
    // A byte range must address the bytes written to disk, not a compressed representation.
    if (resumeFrom > 0) requestHeaders['accept-encoding'] = 'identity';

    for (let redirects = 0; redirects <= MAX_DOWNLOAD_REDIRECTS;) {
      assertNetworkTask(task);
      let destination = input.destination;
      const parent = input.destinationIsDirectory ? destination : parentPath(destination);
      const temporaryDirectory = await fs.mkdtemp(joinPath(parent, '.expo-download-XXXXXX'));
      const temporary = joinPath(temporaryDirectory, 'body');
      let output: fs.File | undefined;
      let receivedHeaders: Object | null = null;
      let receivedStatus = 0;
      let receivedBytes = 0;
      let effectiveResumeFrom = 0;
      let responseComplete = false;
      let committed = false;
      let callbackFailure: ExpoModuleError | undefined;
      const resolveDestination = (): string => input.destinationIsDirectory
        ? joinPath(input.destination, suggestedFilename(requestUrl, receivedHeaders)) : input.destination;
      const ensureOutput = async (): Promise<fs.File> => {
        if (output !== undefined) return output;
        output = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        return output;
      };
      const closeOutput = async (): Promise<void> => {
        try {
          await task.pendingWrite;
        } catch (_) {}
        if (output !== undefined) {
          const fd = output.fd;
          output = undefined;
          await fs.close(fd);
        }
      };

      try {
        const request = new rcp.Request(requestUrl, 'GET', requestHeaders);
        request.configuration = networkConfiguration(
          {
            onHeaderReceive: (headers: rcp.ResponseHeaders): void => {
              receivedHeaders = headers;
            },
            onStatusCodeReceive: (status: number): void => {
              receivedStatus = status;
            },
          },
          false,
        );
        request.destination = async (chunk: ArrayBuffer): Promise<void> => {
          assertNetworkTask(task);
          const write = async (): Promise<void> => {
            try {
              const file = await ensureOutput();
              assertNetworkTask(task);
              await writeAllAsync(file.fd, chunk);
              receivedBytes += chunk.byteLength;
              const range = parseContentRange(receivedHeaders === null ? null : headerValue(receivedHeaders, 'content-range'));
              const progressPrefix = receivedStatus !== 200 && range?.start === resumeFrom ? resumeFrom : 0;
              task.transferred = progressPrefix + receivedBytes;
              task.expectedTransfer = expectedDownloadSize(receivedHeaders, progressPrefix, callerRange);
              if (input.emitProgress) this.emitDownloadProgress(task, uuid, false);
            } catch (error) {
              callbackFailure = new ExpoFileSystemError(
                error instanceof ExpoModuleError ? error.code : 'ERR_FILE_SYSTEM_WRITE_FAILED',
                error instanceof Error ? error.message : String(error),
                error instanceof ExpoModuleError ? error.cause : (error as Object),
                error instanceof ExpoModuleError ? error.path : undefined,
              );
              throw new ExpoFileSystemError(callbackFailure.code, callbackFailure.message, callbackFailure.cause, callbackFailure.path);
            }
          };
          // RCP awaits the destination promise before delivering the next chunk.
          task.pendingWrite = write();
          await task.pendingWrite;
        };
        const response = await this.fetch(task, request);
        responseComplete = true;
        receivedStatus = response.statusCode;
        receivedHeaders = response.headers;
        const location = headerValue(response.headers, 'location');
        const redirect = isRedirectStatus(response.statusCode) && location !== null;
        const restartRange = resumeFrom > 0 && response.statusCode === HTTP_RANGE_NOT_SATISFIABLE;
        // The final response is complete even while fs.close/atomic publication
        // is pending. Pause must wait for that result rather than discard it.
        task.committing = !redirect && !restartRange;
        await closeOutput();
        assertNetworkTask(task);

        if (restartRange) {
          // A prefix can already contain the entire body when pause wins the
          // last progress callback, or the remote resource can have shrunk.
          // Retry a full GET instead of trusting length alone as proof of identity.
          resumeFrom = 0;
          task.transferred = 0;
          requestHeaders = copyHeaders(requestHeaders, ['range']);
          continue;
        }
        if (redirect && location !== null) {
          if (redirects === MAX_DOWNLOAD_REDIRECTS) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_TOO_MANY_REDIRECTS');

          redirects += 1;
          const nextUrl = redirectedDownloadUrl(requestUrl, location);
          if (new url.URL(requestUrl).origin !== new url.URL(nextUrl).origin) {
            requestHeaders = copyHeaders(requestHeaders, ['authorization', 'proxy-authorization', 'cookie', 'cookie2']);
          }
          requestUrl = nextUrl;
          task.transferred = resumeFrom;
          continue;
        }
        if (input.rejectHttpErrors && (response.statusCode < 200 || response.statusCode >= 300)) {
          throw new ExpoFileSystemError('ERR_UNABLE_TO_DOWNLOAD', `response has status: ${response.statusCode}`);
        }
        // A caller's Range may select a suffix or several disjoint intervals.
        // Its response body is the requested file, not a prefix to merge.
        if (!callerRange) validateDownloadRange(resumeFrom, response.statusCode, response.headers, receivedBytes);
        effectiveResumeFrom = response.statusCode === 206 ? resumeFrom : 0;
        destination = resolveDestination();
        if (receivedBytes === 0) {
          await ensureOutput();
          await closeOutput();
        }
        assertNetworkTask(task);

        input.validateDestination?.(destination, 'write');
        await publishDownload(temporary, destination, effectiveResumeFrom, input.idempotent === true, task);
        committed = true;
        task.destination = destination;
        task.transferred = effectiveResumeFrom + receivedBytes;
        task.expectedTransfer = expectedDownloadSize(response.headers, effectiveResumeFrom, callerRange);
        if (input.emitProgress) this.emitDownloadProgress(task, uuid, true);
        const md5 = input.md5 ? (await fileHash.hash(destination, 'md5')).toLowerCase() : undefined;
        assertNetworkTask(task);
        return new DownloadResult(toFileUri(destination), response.statusCode, normalizedResponseHeaders(response.headers), md5);
      } catch (error) {
        await closeOutput();
        // Only the private staging path is disposable. Preserve a verified prefix on pause,
        // cancellation or a transport error, while leaving an existing destination untouched
        // when no response bytes were written or when the response was a redirect/error.
        const range = parseContentRange(receivedHeaders === null ? null : headerValue(receivedHeaders, 'content-range'));
        const encoding = receivedHeaders === null ? null : headerValue(receivedHeaders, 'content-encoding');
        const usableResponse = receivedHeaders !== null && (
          receivedStatus === 200 ||
          (receivedStatus === 206 &&
            range !== null &&
            (encoding === null || encoding.toLowerCase() === 'identity') &&
            range.start === resumeFrom &&
            receivedBytes <= range.end - range.start + 1));
        effectiveResumeFrom = receivedStatus === 206 ? resumeFrom : 0;
        // Custom ranges cannot be resumed using a byte offset into the full resource.
        if (
          !callerRange &&
          !responseComplete &&
          !this.destroyed &&
          input.resumable &&
          receivedBytes > 0 &&
          usableResponse &&
          (callbackFailure === undefined || task.cancelled)
        ) {
          try {
            destination = resolveDestination();
            input.validateDestination?.(destination, 'write');
            await publishDownload(temporary, destination, effectiveResumeFrom, true);
            committed = true;
            task.destination = destination;
            task.transferred = effectiveResumeFrom + receivedBytes;
          } catch (commitError) {
            task.failure = new ExpoFileSystemError(
              commitError instanceof ExpoModuleError ? commitError.code : 'ERR_FILE_SYSTEM_WRITE_FAILED',
              commitError instanceof Error ? commitError.message : String(commitError),
              commitError instanceof ExpoModuleError ? commitError.cause : (commitError as Object),
              commitError instanceof ExpoModuleError ? commitError.path : undefined,
            );
            task.transferred = resumeFrom;
          }
        } else if (callerRange) {
          // Even a published range is not a prefix of the full resource (e.g. pause during hashing).
          task.transferred = 0;
        } else if (!committed) task.transferred = resumeFrom;
        if (callbackFailure !== undefined && !task.cancelled) {
          throw new ExpoFileSystemError(callbackFailure.code, callbackFailure.message, callbackFailure.cause, callbackFailure.path);
        }
        throw new ExpoFileSystemError(
          error instanceof ExpoModuleError ? error.code : String(Reflect.get(error as Object, 'code') ?? 'ERR_FILE_SYSTEM'),
          error instanceof Error ? error.message : String(error),
          error instanceof ExpoModuleError ? error.cause : (error as Object),
          error instanceof ExpoModuleError ? error.path : undefined,
        );
      } finally {
        await closeOutput();
        try {
          await fs.unlink(temporary);
        } catch (_) {}
        try {
          await fs.rmdir(temporaryDirectory);
        } catch (_) {}
      }
    }

    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_TOO_MANY_REDIRECTS');
  }

  private async copyPackagedResource(input: DownloadRequest, uuid: string, task: NetworkTask): Promise<RawDownloadResult> {
    const resourceName = packagedResourceName(input.url);
    const destination = input.destinationIsDirectory ? joinPath(input.destination, safeLeafName(resourceName)) : input.destination;
    const parent = parentPath(destination);
    const temporaryDirectory = await fs.mkdtemp(joinPath(parent, '.expo-download-XXXXXX'));
    const temporary = joinPath(temporaryDirectory, 'body');
    const resources = this.context.uiAbilityContext.resourceManager;
    let descriptor: ExpoRawResourceFile | undefined;

    try {
      assertNetworkTask(task);

      descriptor = openRawResourceFile(resources, resourceName);
      assertNetworkTask(task);
      const output = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);

      try {
        const buffer = new ArrayBuffer(NETWORK_FILE_BUFFER_BYTES);
        let copied = 0;
        task.expectedTransfer = descriptor.length;
        while (copied < descriptor.length) {
          assertNetworkTask(task);

          const count = await fs.read(descriptor.file.fd, buffer, {
            offset: descriptor.offset + copied,
            length: Math.min(buffer.byteLength, descriptor.length - copied),
          });
          if (count <= 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_RAW_RESOURCE', 'Unable to read the complete bundled resource');
          assertNetworkTask(task);
          await writeAllAsync(output.fd, count === buffer.byteLength ? buffer : buffer.slice(0, count));
          copied += count;
          task.transferred = copied;
          if (input.emitProgress) this.emitDownloadProgress(task, uuid, false);
        }
      } finally {
        await fs.close(output.fd);
      }
      assertNetworkTask(task);

      task.committing = true;
      input.validateDestination?.(destination, 'write');
      if (input.idempotent) await fs.moveFile(temporary, destination, 0);
      else atomicFileOperations.publishNoReplace(temporary, destination);
      if (input.emitProgress) this.emitDownloadProgress(task, uuid, true);
      const md5 = input.md5 ? (await fileHash.hash(destination, 'md5')).toLowerCase() : undefined;
      assertNetworkTask(task);
      return new RawDownloadResult(toFileUri(destination), md5);
    } finally {
      if (task.cancelled) task.transferred = 0;
      try {
        if (descriptor !== undefined) await fs.close(descriptor.file.fd);
      } finally {
        try {
          await fs.unlink(temporary);
        } catch (_) {}
        try {
          await fs.rmdir(temporaryDirectory);
        } catch (_) {}
      }
    }
  }

  async upload(input: UploadRequest): Promise<UploadResult | null> {
    return this.uploadTask(util.generateRandomUUID(), (): UploadRequest => input);
  }

  async uploadTask(uuid: string, prepare: () => UploadRequest, ready?: Promise<void>): Promise<UploadResult | null> {
    const task = this.beginTask(uuid);
    try {
      if (ready !== undefined) await Promise.race([ready, task.cancellation]);
      assertNetworkTask(task);

      const input = prepare();
      const headers = copyHeaders(input.headers, input.uploadType === 1 ? ['content-type'] : []);
      const method = normalizeUploadMethod(input.httpMethod);
      let body: rcp.RequestContent;
      if (input.uploadType === 1) {
        // MultipartForm supplies the boundary and includes zero-length string fields.
        body = makeMultipartForm(input);
      } else {
        task.expectedTransfer = (await fs.stat(input.source)).size;
        body = new rcp.UploadFromFile(input.source);
        if (input.mimeType) headers['content-type'] = input.mimeType;
      }
      assertNetworkTask(task);
      const request = new rcp.Request(input.url, method, headers, body);
      request.configuration = networkConfiguration({
        onUploadProgress: (total: number, transferred: number): void => {
          if (task.cancelled) return;
          task.transferred = transferred;
          if (total > 0) task.expectedTransfer = total;
          else if (input.uploadType === 1) task.expectedTransfer = -1;
          if (input.emitProgress) this.emitUploadProgress(task, uuid, false);
        },
      });
      // Upload responses are strings in Expo's public API; native response streaming avoids
      // RCP's buffered-response size cap without buffering the uploaded file in ArkTS.
      const responseParts: string[] = [];
      const decoder = new util.TextDecoder('utf-8');
      request.destination = (chunk: ArrayBuffer): void => {
        assertNetworkTask(task);
        responseParts.push(decoder.decodeWithStream(new Uint8Array(chunk), { stream: true }));
      };
      const response = await this.fetch(task, request);
      assertNetworkTask(task);
      responseParts.push(decoder.decodeWithStream(new Uint8Array(0), { stream: false }));
      if (input.emitProgress) this.emitUploadProgress(task, uuid, true);
      return new UploadResult(responseParts.join(''), response.statusCode, normalizedResponseHeaders(response.headers));
    } catch (error) {
      if (task.cancelled) return null;
      throw new ExpoFileSystemError(
        error instanceof ExpoModuleError ? error.code : 'ERR_FILE_SYSTEM_UPLOAD_FAILED',
        error instanceof Error ? error.message : String(error),
        error instanceof ExpoModuleError ? error.cause : (error as Object),
        error instanceof ExpoModuleError ? error.path : undefined,
      );
    } finally {
      this.finishTask(uuid, task);
    }
  }

  private emitDownloadProgress(task: NetworkTask, uuid: string, force: boolean): void {
    if (!task.progressCadence.shouldEmit(Date.now(), task.transferred, task.expectedTransfer, force)) return;
    const values = new ProgressValues();
    values.totalBytesWritten = task.transferred;
    values.totalBytesExpectedToWrite = task.expectedTransfer;
    this.progress('expo-file-system.downloadProgress', new ProgressPayload(uuid, values));
  }

  private emitUploadProgress(task: NetworkTask, uuid: string, force: boolean): void {
    if (!task.progressCadence.shouldEmit(Date.now(), task.transferred, task.expectedTransfer, force)) return;
    const values = new ProgressValues();
    values.totalBytesSent = task.transferred;
    values.totalBytesExpectedToSend = task.expectedTransfer;
    this.progress('expo-file-system.uploadProgress', new ProgressPayload(uuid, values));
  }
}
function toFileUri(path: string, directory: boolean = false): string {
  if (path.startsWith('file:')) return path;
  if (!path.startsWith('/')) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_PATH');

  const uri = fileUriFromPath(path);
  return directory && !uri.endsWith('/') ? `${uri}/` : uri;
}

function normalizePickerUri(uri: string, directory: boolean): string {
  const mode = fs.OpenMode.READ_ONLY | fs.OpenMode.NONBLOCK;
  const selected = fs.openSync(uri, mode);

  try {
    const stat = fs.statSync(selected.fd);
    if (!(directory ? stat.isDirectory() : stat.isFile())) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_PICKED_URI');
    }

    // A provider's File.path can name a different file in this app's sandbox.
    try {
      const path = selected.path;
      if (path.startsWith('/')) {
        const local = fs.openSync(path, mode | fs.OpenMode.NOFOLLOW);
        try {
          if (atomicFileOperations.isSameFile(selected.fd, local.fd)) return toFileUri(path, directory);
        } finally {
          fs.closeSync(local.fd);
        }
      }
    } catch (_) {}
    if (!directory && isProviderFileUri(uri)) return uri;
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_PICKED_URI', 'The selected item has no equivalent local filesystem path.');
  } finally {
    fs.closeSync(selected.fd);
  }
}

function isPackagedResource(uri: string): boolean {
  return isRawUri(uri) || !uri.includes(':');
}

function packagedResourceName(uri: string): string {
  return rawPathFromUri(uri, true);
}

function safeName(value: string): string {
  if (value.length === 0 || value === '.' || value === '..' || value.includes('/') || value.includes('\\') || value.includes('\0')) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_NAME');
  }

  return value;
}

function joinPath(directory: string, name: string): string {
  return `${directory}${directory.endsWith('/') ? '' : '/'}${name}`;
}

function dispositionFilename(disposition: string): string | null {
  let plain: string | null = null;
  let extended: string | null = null;
  // Consume every parameter, including quoted semicolons and quoted-pair escapes.
  const parameter = /;\s*([^=;\s]+)\s*=\s*("(?:[^"\\]|\\.)*"|[^;]*)/g;
  let match: RegExpExecArray | null;
  while ((match = parameter.exec(disposition)) !== null) {
    const name = match[1].toLowerCase();
    const token = match[2].trim();
    const value = token.startsWith('"') ? token.slice(1, -1).replace(/\\(.)/g, '$1') : token;
    try {
      if (name === 'filename' && value.length > 0) plain = safeLeafName(value);
      if (name === 'filename*') {
        const parts = /^([^']+)'[^']*'(.*)$/.exec(value);
        if (parts === null || parts[2].length === 0 || /%(?![0-9a-f]{2})/i.test(parts[2])) continue;
        const charset = parts[1].toLowerCase();
        if (charset === 'utf-8') extended = safeLeafName(decodeURIComponent(parts[2]));
        else if (charset === 'iso-8859-1') {
          extended = safeLeafName(
            parts[2].replace(/%([0-9a-f]{2})/gi, (_escape: string, hex: string): string => String.fromCharCode(parseInt(hex, 16))),
          );
        }
      }
    } catch (_) {
      // An invalid extended value must not hide a valid plain filename.
    }
  }
  return extended ?? plain;
}

function suggestedFilename(requestUrl: string, headers: Object | null): string {
  let filename: string | null = null;

  if (headers !== null) {
    const disposition = headerValue(headers, 'content-disposition');
    if (disposition !== null) filename = dispositionFilename(disposition);
  }

  if (filename === null) {
    const pathname = new url.URL(requestUrl).pathname;
    const component = pathname.slice(pathname.lastIndexOf('/') + 1);
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
  try {
    const pathname = /^[a-z][a-z0-9+.-]*:/i.test(path) ? decodeURIComponent(new url.URL(path).pathname) : path;
    const leaf = pathname.slice(pathname.lastIndexOf('/') + 1);
    const dot = leaf.lastIndexOf('.');
    if (dot < 0 || dot === leaf.length - 1) return '';
    const typeId = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(leaf.slice(dot));
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
  const leaf = normalized.slice(normalized.lastIndexOf('/') + 1);

  return safeName(leaf.length === 0 ? 'download' : leaf);
}

function mimeSuffixFilters(mimeType?: string): string[] | null {
  if (mimeType === undefined || mimeType.trim() === '*/*') return null;
  const normalized = mimeType.trim().toLowerCase();
  if (!/^[a-z0-9!#$&^_.+-]+\/(?:[a-z0-9!#$&^_.+-]+|\*)$/.test(normalized)) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_MIME_TYPE', mimeType);
  }

  try {
    const extensions: string[] = [];
    const wildcard = normalized.endsWith('/*');
    const prefix = normalized.slice(0, -1);
    const types: string[] = wildcard ? Object.values(uniformTypeDescriptor.UniformDataType) :
      uniformTypeDescriptor.getUniformDataTypesByMIMEType(normalized);
    types.forEach((typeId: string): void => {
      try {
        const descriptor = uniformTypeDescriptor.getTypeDescriptor(typeId);
        if (wildcard && !descriptor.mimeTypes.some((mime: string): boolean => mime.toLowerCase().startsWith(prefix))) return;

        descriptor.filenameExtensions.forEach((extension: string): void => {
          if (!extension.startsWith('.') || extension.length < 2 || /[*,|/\\\s\0]/.test(extension)) return;
          if (!extensions.includes(extension)) extensions.push(extension);
        });
      } catch (_) {
        // Newer SDK enum entries need not have a descriptor on an older device.
      }
    });
    if (extensions.length === 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNSUPPORTED_MIME_TYPE', mimeType);
    return extensions;
  } catch (error) {
    throw new ExpoFileSystemError(
      error instanceof ExpoModuleError ? error.code : 'ERR_FILE_SYSTEM_UNSUPPORTED_MIME_TYPE',
      error instanceof Error ? error.message : String(error),
      error instanceof ExpoModuleError ? error.cause : (error as Object),
      error instanceof ExpoModuleError ? error.path : undefined,
    );
  }
}

function copyHeaders(input?: Object, excluded: string[] = []): rcp.RequestHeaders {
  const entries: [string, string][] = [];
  if (input !== undefined) {
    Object.keys(input).forEach((name: string): void => {
      if (!excluded.includes(name.toLowerCase())) entries.push([name.toLowerCase(), String(Reflect.get(input, name))]);
    });
  }
  const fields = entries.map((entry: [string, string]): string => `${JSON.stringify(entry[0])}:${JSON.stringify(entry[1])}`);
  return JSON.parse(`{${fields.join(',')}}`) as rcp.RequestHeaders;
}

function normalizedResponseHeaders(input: Object): Object {
  const entries: [string, string][] = [];
  Object.keys(input).forEach((name: string): void => {
    const value: ESObject = Reflect.get(input, name);
    if (value !== undefined) entries.push([name, Array.isArray(value) ? (value as string[]).join(', ') : String(value)]);
  });
  const fields = entries.map((entry: [string, string]): string => `${JSON.stringify(entry[0])}:${JSON.stringify(entry[1])}`);
  return JSON.parse(`{${fields.join(',')}}`) as Record<string, string>;
}

function assertNetworkTask(task: NetworkTask): void {
  if (task.cancelled) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANCELLED');
}

function networkConfiguration(events: rcp.HttpEventsHandler, autoRedirect: boolean = true): rcp.Configuration {
  return {
    transfer: {
      autoRedirect,
      timeout: { connectMs: NETWORK_IDLE_TIMEOUT_MS, transferMs: 0, inactivityMs: NETWORK_IDLE_TIMEOUT_MS },
    },
    tracing: { httpEventsHandler: events },
  };
}

function expectedDownloadSize(headers: Object | null, prefix: number, callerRange: boolean = false): number {
  if (headers === null) return -1;
  const range = parseContentRange(headerValue(headers, 'content-range'));
  if (range !== null && !callerRange && range.start === prefix) return range.total;
  // Content-Length describes the encoded representation; do not advertise it for decoded bytes.
  const encoding = headerValue(headers, 'content-encoding');
  if (encoding !== null && encoding.toLowerCase() !== 'identity') return -1;
  if (range !== null && callerRange) return range.end - range.start + 1;
  const length = headerValue(headers, 'content-length');
  if (length === null || !/^\d+$/.test(length.trim())) return -1;
  const value = Number(length);
  return Number.isSafeInteger(value) && value >= 0 && Number.isSafeInteger(prefix + value) ? prefix + value : -1;
}

function validateDownloadRange(requestedOffset: number, status: number, headers: Object, received: number): void {
  if (status === 200 || (requestedOffset === 0 && status !== 206)) return;
  const range = parseContentRange(headerValue(headers, 'content-range'));
  const encoding = headerValue(headers, 'content-encoding');
  if (
    status !== 206 ||
    range === null ||
    (encoding !== null && encoding.toLowerCase() !== 'identity') ||
    range.start !== requestedOffset ||
    range.end - range.start + 1 !== received
  ) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESUME_RESPONSE', 'The response does not match the requested byte range');
  }
}

// Keep the response body isolated until its status and byte range are final. Header/status
// notifications may arrive after the first body chunk, so they cannot select append mode.
async function publishDownload(body: string, destination: string, prefix: number, overwrite: boolean, task?: NetworkTask): Promise<void> {
  if (task !== undefined) assertNetworkTask(task);
  if (prefix === 0) {
    if (overwrite) await fs.moveFile(body, destination, 0);
    else atomicFileOperations.publishNoReplace(body, destination);
    return;
  }
  const combined = `${body}.combined`;
  try {
    if ((await fs.stat(destination)).size !== prefix) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESUME_DATA');
    await fs.copyFile(destination, combined);
    if (task !== undefined) assertNetworkTask(task);
    const input = await fs.open(body, fs.OpenMode.READ_ONLY);
    try {
      const output = await fs.open(combined, fs.OpenMode.READ_WRITE);
      try {
        fs.lseek(output.fd, prefix, fs.WhenceType.SEEK_SET);
        const buffer = new ArrayBuffer(NETWORK_FILE_BUFFER_BYTES);
        while (true) {
          if (task !== undefined) assertNetworkTask(task);
          const count = await fs.read(input.fd, buffer, { length: buffer.byteLength });
          if (count === 0) break;
          if (count < 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_READ_FAILED');
          await writeAllAsync(output.fd, count === buffer.byteLength ? buffer : buffer.slice(0, count));
        }
      } finally {
        await fs.close(output.fd);
      }
    } finally {
      await fs.close(input.fd);
    }
    if (task !== undefined) assertNetworkTask(task);
    if (overwrite) await fs.moveFile(combined, destination, 0);
    else atomicFileOperations.publishNoReplace(combined, destination);
  } finally {
    try {
      await fs.unlink(combined);
    } catch (_) {}
  }
}

function redirectedDownloadUrl(previous: string, location: string): string {
  const next = new url.URL(location, previous);
  if (next.protocol !== 'http:' && next.protocol !== 'https:') throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_URL');
  return next.toString();
}
function writeAll(fd: number, data: ArrayBuffer, offset: number, onWrite?: (count: number) => void): number {
  fs.lseek(fd, offset, fs.WhenceType.SEEK_SET);

  let written = 0;
  while (written < data.byteLength) {
    const end = Math.min(written + 64 * 1024, data.byteLength);
    const count = fs.writeSync(fd, data.slice(written, end), { length: end - written });
    if (count <= 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_WRITE_FAILED');
    written += count;
    if (onWrite !== undefined) onWrite(count);
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

function makeMultipartForm(input: UploadRequest): rcp.MultipartForm {
  const entries: [string, string | rcp.FormFieldFileValue | (string | rcp.FormFieldFileValue)[]][] = [];
  const name = input.fieldName ?? safeLeafName(input.source);
  if (input.parameters !== undefined) {
    Object.keys(input.parameters).forEach((parameter: string): void => {
      if (parameter !== name) entries.push([parameter, String(Reflect.get(input.parameters as Object, parameter))]);
    });
  }
  const file: rcp.FormFieldFileValue = {
    contentType: input.mimeType ?? (mimeTypeForPath(input.source) || 'application/octet-stream'),
    remoteFileName: safeLeafName(input.source),
    contentOrPath: input.source,
  };
  if (input.parameters !== undefined && Object.keys(input.parameters).includes(name)) {
    entries.push([name, [String(Reflect.get(input.parameters, name)), file]]);
  } else entries.push([name, file]);
  // JSON object parsing creates own properties even for field names such as __proto__.
  // ArkTS does not expose Object.fromEntries or property-descriptor mutation.
  const fields = entries.map(
    (entry: [string, string | rcp.FormFieldFileValue | (string | rcp.FormFieldFileValue)[]]): string =>
      `${JSON.stringify(entry[0])}:${JSON.stringify(entry[1])}`,
  );
  const form = new rcp.MultipartForm(JSON.parse(`{${fields.join(',')}}`) as rcp.MultipartFormFields);
  // RCP otherwise serializes keys in hash order. API 21+ supports explicit
  // ordering; this package's minimum SDK is 21. Always put the file part last.
  form.keys = entries.map((entry): string => entry[0]);
  return form;
}

function cleanErrorMessage(error: Object): string {
  return error instanceof Error ? error.message : String(error);
}

type FileSystemRecord = Record<string, ESObject>;

class Capability {
  path: string;
  directory: boolean;
  writable: boolean;

  constructor(path: string, directory: boolean, writable: boolean) {
    this.path = path;
    this.directory = directory;
    this.writable = writable;
  }
}

class FileSystemState {
  readonly documentPath: string;
  readonly cachePath: string;
  private readonly context: ExpoModuleContext;
  private readonly capabilities: Capability[] = [];
  private readonly permissions: PickerPermissionStore;
  private readonly permissionRestore: Promise<void>;

  constructor(context: ExpoModuleContext) {
    this.context = context;
    this.documentPath = decodeFileUri(context.persistentFilesDirectory);
    this.cachePath = decodeFileUri(context.cacheDirectory);
    this.ensureDirectory(this.documentPath);
    this.ensureDirectory(this.cachePath);
    this.permissions = new PickerPermissionStore(context);
    this.permissions.restoreActive((uri: string, directory: boolean, writable: boolean): void => {
      this.grant(normalizePickerUri(uri, directory), directory, writable);
    });
    this.permissionRestore = this.permissions
      .restore((uri: string, directory: boolean, writable: boolean): void => {
        this.grant(normalizePickerUri(uri, directory), directory, writable);
      })
      .catch((error: Object): void => {
        if (context.isValid) context.logger.warn(`Could not restore Expo file picker permissions: ${cleanErrorMessage(error)}`);
      });
  }

  // FileShare activation is asynchronous. Sync APIs see active grants only;
  // async APIs await this barrier before resolving persisted external paths.
  async ready(): Promise<void> {
    await this.permissionRestore;
  }

  async rememberPickerGrant(originalUri: string, uri: string, directory: boolean): Promise<void> {
    const writable = this.grant(uri, directory);
    try {
      await this.permissions.remember(originalUri, directory, writable);
    } catch (error) {
      if (this.context.isValid) this.context.logger.warn(`Could not save the Expo file picker grant: ${cleanErrorMessage(error as Object)}`);
    }
  }

  grant(uri: string, directory: boolean, writable: boolean = true): boolean {
    if (this.providerUri(uri) !== null) {
      this.context.grantFileAccess(uri, false, false);
      return false;
    }

    const path = decodeFileUri(uri);
    this.assertNoSymlinkSegments(path);

    this.context.grantFileAccess(path, directory, writable);

    const existing = this.capabilities.find((capability: Capability): boolean => capability.path === path && capability.directory === directory);
    if (existing === undefined) this.capabilities.push(new Capability(path, directory, writable));
    else existing.writable = existing.writable || writable;

    return writable;
  }

  resolve(uri: string, mustExist: boolean = false, mode: ExpoFileAccessMode = 'read'): string {
    const path = this.decodeLocalUri(uri);
    const granted = this.context.assertFileAccess(path, mode);
    const application = this.context.uiAbilityContext.getApplicationContext();

    let allowed =
      granted ||
      isInside(this.documentPath, path) ||
      isInside(this.cachePath, path) ||
      isInside(application.filesDir, path) ||
      isInside(application.cacheDir, path);

    if (!allowed) {
      allowed = this.capabilities.some((capability: Capability): boolean =>
        (mode === 'read' || capability.writable) && (capability.directory ? isInside(capability.path, path) : capability.path === path),
      );
    }
    if (!allowed) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_OUTSIDE_SCOPE', `The path '${path}' is outside the Expo file-system sandbox`);
    }

    this.assertNoSymlinkSegments(path);
    if (mustExist && !fs.accessSync(path)) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_FILE_NOT_FOUND', `Path '${path}' does not exist`);
    }

    return path;
  }

  providerUri(uri: string): string | null {
    if (!isProviderFileUri(uri)) return null;
    const source = resolveFileReadSource(uri, this.context.uiAbilityContext.cacheDir);
    return source.startsWith('/') ? null : source;
  }

  decodeLocalUri(uri: string): string {
    if (isProviderFileUri(uri)) {
      const source = resolveFileReadSource(uri, this.context.uiAbilityContext.cacheDir);
      if (source.startsWith('/')) return normalizeAbsolutePath(source);
    }
    return decodeFileUri(uri);
  }

  readSource(uri: string): string {
    const provider = this.providerUri(uri);
    return provider === null ? this.resolve(uri, true) : this.context.fileSourceForRead(provider);
  }

  probe(uri: string): string | null {
    try {
      return this.resolve(uri);
    } catch (_) {
      return null;
    }
  }

  rawBytes(uri: string, allowSchemeLess: boolean = false): Uint8Array {
    const name = rawPathFromUri(uri, allowSchemeLess);
    return this.context.uiAbilityContext.resourceManager.getRawFileContentSync(name);
  }

  async rawBytesAsync(uri: string, allowSchemeLess: boolean = false): Promise<Uint8Array> {
    return this.context.uiAbilityContext.resourceManager.getRawFileContent(rawPathFromUri(uri, allowSchemeLess));
  }

  async rawInfoAsync(uri: string, includeMd5: boolean): Promise<FileSystemInfo> {
    const name = rawPathFromUri(uri, true, true);
    const manager = this.context.uiAbilityContext.resourceManager;

    try {
      if (this.rawDirectoryExists(uri, true)) {
        const directory = new FileSystemInfo(true);
        directory.uri = uri;
        directory.isDirectory = true;
        return directory;
      }

      const descriptor = openRawResourceFile(manager, name);

      try {
        const result = new FileSystemInfo(true);
        result.uri = uri;
        result.isDirectory = false;
        result.size = descriptor.length;
        if (includeMd5) {
          const hash = fileHash.createHash('md5');
          let offset = 0;

          while (offset < descriptor.length) {
            const chunk = new ArrayBuffer(Math.min(64 * 1024, descriptor.length - offset));
            const count = await fs.read(descriptor.file.fd, chunk, { offset: descriptor.offset + offset, length: chunk.byteLength });
            if (count <= 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_READ_FAILED', 'Unexpected end of bundled resource');
            hash.update(count === chunk.byteLength ? chunk : chunk.slice(0, count));
            offset += count;
          }

          result.md5 = hash.digest().toLowerCase();
        }

        return result;
      } finally {
        await fs.close(descriptor.file.fd);
      }
    } catch (error) {
      if (!isMissingRawResource(error as Object)) {
        throw new ExpoFileSystemError(
          error instanceof ExpoModuleError ? error.code : String(Reflect.get(error as Object, 'code') ?? 'ERR_FILE_SYSTEM'),
          error instanceof Error ? error.message : String(error),
          error instanceof ExpoModuleError ? error.cause : (error as Object),
          error instanceof ExpoModuleError ? error.path : undefined,
        );
      }
      const missing = new FileSystemInfo(false);
      missing.isDirectory = false;
      return missing;
    }
  }

  rawSize(uri: string, allowSchemeLess: boolean = false): number {
    const name = rawPathFromUri(uri, allowSchemeLess);
    const manager = this.context.uiAbilityContext.resourceManager;
    const descriptor = manager.getRawFdSync(name);
    try {
      return descriptor.length;
    } finally {
      manager.closeRawFdSync(name);
    }
  }

  rawMd5(uri: string, allowSchemeLess: boolean = false): string {
    const name = rawPathFromUri(uri, allowSchemeLess);
    const manager = this.context.uiAbilityContext.resourceManager;
    const descriptor = manager.getRawFdSync(name);
    const hash = fileHash.createHash('md5');
    let offset = 0;
    try {
      while (offset < descriptor.length) {
        const chunk = new ArrayBuffer(Math.min(64 * 1024, descriptor.length - offset));
        const count = fs.readSync(descriptor.fd, chunk, { offset: descriptor.offset + offset, length: chunk.byteLength });
        if (count <= 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_READ_FAILED', 'Unexpected end of bundled resource');
        hash.update(count === chunk.byteLength ? chunk : chunk.slice(0, count));
        offset += count;
      }
      return hash.digest().toLowerCase();
    } finally {
      manager.closeRawFdSync(name);
    }
  }

  rawList(uri: string, allowSchemeLess: boolean = false): string[] {
    const name = rawPathFromUri(uri, allowSchemeLess, true);
    return this.context.uiAbilityContext.resourceManager.getRawFileListSync(name);
  }

  rawExists(uri: string, allowSchemeLess: boolean = false): boolean {
    const name = rawPathFromUri(uri, allowSchemeLess);
    try {
      if (this.context.uiAbilityContext.resourceManager.isRawDir(name)) return false;
      this.rawSize(uri, allowSchemeLess);
      return true;
    } catch (error) {
      if (isMissingRawResource(error as Object)) return false;
      throw new ExpoFileSystemError(
        error instanceof ExpoModuleError ? error.code : String(Reflect.get(error as Object, 'code') ?? 'ERR_FILE_SYSTEM'),
        error instanceof Error ? error.message : String(error),
        error instanceof ExpoModuleError ? error.cause : (error as Object),
        error instanceof ExpoModuleError ? error.path : undefined,
      );
    }
  }

  rawDirectoryExists(uri: string, allowSchemeLess: boolean = false): boolean {
    const name = rawPathFromUri(uri, allowSchemeLess, true);
    try {
      return name.length === 0 || this.context.uiAbilityContext.resourceManager.isRawDir(name);
    } catch (error) {
      if (isMissingRawResource(error as Object)) return false;
      throw new ExpoFileSystemError(
        error instanceof ExpoModuleError ? error.code : String(Reflect.get(error as Object, 'code') ?? 'ERR_FILE_SYSTEM'),
        error instanceof Error ? error.message : String(error),
        error instanceof ExpoModuleError ? error.cause : (error as Object),
        error instanceof ExpoModuleError ? error.path : undefined,
      );
    }
  }

  materializeRawContent(uri: string): string {
    const rawPath = rawPathFromUri(uri);
    const bytes = this.rawBytes(uri);
    const directory = joinPath(this.cachePath, 'expo_shared_assets');
    this.ensureDirectory(directory);
    const leaf = safeLeafName(rawPath);
    const digest = md5Bytes(bytes);
    const target = joinPath(directory, `${digest}-${leaf}`);
    this.assertNoSymlinkSegments(target);
    if (!fs.accessSync(target) || !fs.statSync(target).isFile() || fs.statSync(target).size !== bytes.byteLength || md5Path(target) !== digest) {
      const temporaryDirectory = fs.mkdtempSync(joinPath(directory, '.share-XXXXXX'));
      const temporary = joinPath(temporaryDirectory, leaf);
      try {
        writeBytesFile(temporary, bytes, false);
        fs.moveFileSync(temporary, target, 0);
      } finally {
        removePath(temporaryDirectory);
      }
    }
    return toFileUri(target);
  }

  private assertNoSymlinkSegments(path: string): void {
    const segments = path.split('/').filter((segment: string): boolean => segment.length > 0);
    let current = '';

    for (const segment of segments) {
      current = `${current}/${segment}`;
      let stat: fs.Stat;

      try {
        stat = fs.lstatSync(current);
      } catch (error) {
        // lstat can distinguish a missing path from a dangling symbolic link.
        if (Number(Reflect.get(error as Object, 'code')) === FILE_NOT_FOUND_ERROR) break;
        throw new ExpoFileSystemError('ERR_FILE_SYSTEM_PATH_CHECK_FAILED', cleanErrorMessage(error as Object), error as Object, current);
      }
      if (stat.isSymbolicLink()) {
        throw new ExpoFileSystemError('ERR_FILE_SYSTEM_SYMLINK', `Symbolic links are not accepted by the Harmony file-system sandbox: '${current}'`);
      }
    }
  }

  private ensureDirectory(path: string): void {
    try {
      this.assertNoSymlinkSegments(path);
    } catch (error) {
      throw new ExpoFileSystemError(
        'ERR_FILE_SYSTEM_DIRECTORY_CHECK_FAILED',
        `Could not inspect directory path '${path}' before creation: ${cleanErrorMessage(error as Object)}`,
        error as Object,
      );
    }

    let exists: boolean;
    try {
      exists = fs.accessSync(path);
    } catch (error) {
      throw new ExpoFileSystemError(
        'ERR_FILE_SYSTEM_DIRECTORY_CHECK_FAILED',
        `Could not check directory '${path}': ${cleanErrorMessage(error as Object)}`,
        error as Object,
      );
    }

    if (!exists) {
      try {
        fs.mkdirSync(path, true);
      } catch (error) {
        // Another Host may have created the same app-scoped directory after
        // accessSync. Only accept that race after validating the final node.
        if (!fs.accessSync(path)) {
          throw new ExpoFileSystemError(
            'ERR_FILE_SYSTEM_CANNOT_CREATE_DIRECTORY',
            `Could not create directory '${path}': ${cleanErrorMessage(error as Object)}`,
            error as Object,
          );
        }
      }
    }
    try {
      this.assertNoSymlinkSegments(path);
    } catch (error) {
      throw new ExpoFileSystemError(
        'ERR_FILE_SYSTEM_DIRECTORY_CHECK_FAILED',
        `Could not inspect directory path '${path}' after creation: ${cleanErrorMessage(error as Object)}`,
        error as Object,
      );
    }

    let stat: fs.Stat;
    try {
      stat = fs.lstatSync(path);
    } catch (error) {
      throw new ExpoFileSystemError(
        'ERR_FILE_SYSTEM_DIRECTORY_CHECK_FAILED',
        `Could not inspect directory '${path}': ${cleanErrorMessage(error as Object)}`,
        error as Object,
      );
    }
    if (stat.isSymbolicLink()) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_SYMLINK', `Symbolic link access is not allowed: ${path}`);
    }
    if (!stat.isDirectory()) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_DIRECTORY_TYPE', `The path '${path}' does not point to a directory`);
    }
  }
}

class FileSystemInfo {
  exists: boolean;
  isDirectory: boolean | null = null;
  uri?: string;
  size?: number;
  modificationTime?: number | null;
  creationTime?: number | null;
  md5?: string;
  files?: string[];

  constructor(exists: boolean) {
    this.exists = exists;
  }
}

class DirectoryEntryRecord {
  isDirectory: boolean;
  uri: string;

  constructor(isDirectory: boolean, uri: string) {
    this.isDirectory = isDirectory;
    this.uri = uri;
  }
}

class FileSystemFile extends ExpoSharedObject {
  readonly state: FileSystemState;
  private pathValue: string = '';
  private readonly rawPathValue: string;
  readonly bundled: boolean;
  readonly provider: string | null;

  constructor(context: ExpoModuleContext, state: FileSystemState, uri: string) {
    super(context);
    this.state = state;
    this.bundled = isRawUri(uri);
    this.rawPathValue = this.bundled ? rawPathFromUri(uri) : '';
    this.provider = this.bundled ? null : state.providerUri(uri);
    if (!this.bundled && this.provider === null) this.pathValue = state.decodeLocalUri(uri);
  }

  path(mode: ExpoFileAccessMode = 'read'): string {
    if (this.bundled) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME', 'Bundled resources are read-only');
    }
    if (this.provider !== null) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME', 'The provider URI has no local path');
    }
    return this.state.resolve(toFileUri(this.pathValue), false, mode);
  }

  probePath(): string | null {
    return this.bundled || this.provider !== null ? null : this.state.probe(toFileUri(this.pathValue));
  }

  uri(): string {
    return this.bundled ? toRawUri(this.rawPathValue, false) : this.provider ?? toFileUri(this.pathValue);
  }

  rawUri(): string {
    return toRawUri(this.rawPathValue, false);
  }

  setPath(path: string): void {
    this.pathValue = this.state.resolve(toFileUri(path), false, 'write');
  }
}

class FileSystemDirectory extends ExpoSharedObject {
  readonly state: FileSystemState;
  private pathValue: string = '';
  private readonly rawPathValue: string;
  readonly bundled: boolean;

  constructor(context: ExpoModuleContext, state: FileSystemState, uri: string) {
    super(context);
    this.state = state;
    this.bundled = isRawUri(uri);
    this.rawPathValue = this.bundled ? rawPathFromUri(uri, false, true) : '';
    if (!this.bundled) this.pathValue = state.decodeLocalUri(uri);
  }

  path(mode: ExpoFileAccessMode = 'read'): string {
    if (this.bundled) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME', 'Bundled resources are read-only');
    }
    return this.state.resolve(toFileUri(this.pathValue), false, mode);
  }

  probePath(): string | null {
    return this.bundled ? null : this.state.probe(toFileUri(this.pathValue));
  }

  rawPath(): string {
    return this.rawPathValue;
  }

  uri(): string {
    return this.bundled ? toRawUri(this.rawPathValue, true) : toFileUri(this.pathValue, true);
  }

  setPath(path: string): void {
    this.pathValue = this.state.resolve(toFileUri(path), false, 'write');
  }
}

enum FileMode {
  ReadOnly = 'r',
  ReadWrite = 'rw',
  WriteOnly = 'w',
  Append = 'wa',
  Truncate = 'wt',
}

class FileSystemFileHandle extends ExpoSharedRef<fs.File> {
  private file: fs.File | null;
  private offsetValue: number = 0;
  private readonly mode: FileMode;

  constructor(context: ExpoModuleContext, owner: FileSystemFile, mode: FileMode = FileMode.ReadWrite) {
    super(context, 'expo-file-system.file-handle', openFileHandle(owner, mode));
    this.file = this.value;
    this.mode = mode;
    if (mode === FileMode.Append) {
      try {
        this.offsetValue = fs.statSync(this.file.fd).size;
      } catch (error) {
        this.close();
        throw new ExpoFileSystemError('ERR_FILE_SYSTEM_HANDLE_OPEN_FAILED', cleanErrorMessage(error as Object), error as Object);
      }
    }
  }

  read(count: number): Uint8Array {
    requireSafeInteger(count, 'ERR_FILE_SYSTEM_INVALID_LENGTH', 'Read length');
    const file = this.requireOpen();
    if (this.mode !== FileMode.ReadOnly && this.mode !== FileMode.ReadWrite) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_HANDLE_WRITE_ONLY', 'File opened write-only');
    }

    const size = fs.statSync(file.fd).size;
    const length = Math.min(count, Math.max(0, size - this.offsetValue));
    const buffer = new ArrayBuffer(length);
    if (length === 0) return new Uint8Array(buffer);
    const output = new Uint8Array(buffer);
    const chunk = new ArrayBuffer(Math.min(length, 64 * 1024));
    fs.lseek(file.fd, this.offsetValue, fs.WhenceType.SEEK_SET);
    let total: number = 0;
    while (total < length) {
      const read: number = fs.readSync(file.fd, chunk, { length: Math.min(chunk.byteLength, length - total) });
      if (read <= 0) break;
      output.set(new Uint8Array(chunk, 0, read), total);
      total += read;
      this.offsetValue += read;
    }
    return new Uint8Array(total === length ? buffer : buffer.slice(0, total));
  }

  write(bytes: Uint8Array): void {
    const file = this.requireOpen();
    if (this.mode === FileMode.ReadOnly) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_HANDLE_READ_ONLY', 'File opened read-only');
    if (bytes.byteLength === 0) return;

    const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    let offset = Math.min(this.offsetValue, fs.statSync(file.fd).size);
    writeAll(file.fd, buffer, offset, (count: number): void => {
      offset += count;
      this.offsetValue = offset;
    });
  }

  close(): void {
    const file = this.file;
    this.file = null;
    if (file !== null) fs.closeSync(file.fd);
  }

  offset(): number | null {
    return this.file === null ? null : this.offsetValue;
  }

  setOffset(value: number | null): void {
    if (value === null) return;
    requireSafeInteger(value, 'ERR_FILE_SYSTEM_INVALID_OFFSET', 'Offset');
    this.requireOpen();
    this.offsetValue = value;
  }

  size(): number | null {
    return this.file === null ? null : fs.statSync(this.file.fd).size;
  }

  override sharedObjectWillRelease(): void {
    this.close();
  }

  private requireOpen(): fs.File {
    if (this.file === null) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_HANDLE_CLOSED', 'The file handle is closed');
    }
    return this.file;
  }
}

type FileSystemDestination = FileSystemFile | FileSystemDirectory;

class DownloadProgress {
  bytesWritten: number;
  totalBytes: number;
  constructor(bytesWritten: number, totalBytes: number) {
    this.bytesWritten = bytesWritten;
    this.totalBytes = totalBytes;
  }
}

class UploadProgress {
  bytesSent: number;
  totalBytes: number;
  constructor(bytesSent: number, totalBytes: number) {
    this.bytesSent = bytesSent;
    this.totalBytes = totalBytes;
  }
}

class ModernDownloadProgress {
  uuid: string;
  data: DownloadProgress;
  constructor(payload: ProgressPayload) {
    this.uuid = payload.uuid;
    this.data = new DownloadProgress(payload.data.totalBytesWritten ?? 0, payload.data.totalBytesExpectedToWrite ?? -1);
  }
}

class FileSystemNetworkTask extends ExpoSharedObject {
  protected readonly uuid: string = util.generateRandomUUID();
  protected readonly state: FileSystemState;
  protected readonly service: ExpoFileSystemService;
  protected cancelled: boolean = false;
  private readonly services: Set<ExpoFileSystemService>;

  constructor(context: ExpoModuleContext, state: FileSystemState, services: Set<ExpoFileSystemService>) {
    super(context);
    this.state = state;
    this.services = services;
    this.service = new ExpoFileSystemService(context, (_name: string, payload: ProgressPayload): void => {
      if (this.cancelled) return;
      if (payload.data.totalBytesWritten !== undefined) {
        this.sendEvent('progress', new DownloadProgress(payload.data.totalBytesWritten, payload.data.totalBytesExpectedToWrite ?? -1));
      } else {
        this.sendEvent('progress', new UploadProgress(payload.data.totalBytesSent ?? 0, payload.data.totalBytesExpectedToSend ?? -1));
      }
    });
    services.add(this.service);
  }

  cancel(): void {
    this.cancelled = true;
    this.service.cancel(this.uuid);
  }

  protected assertNotCancelled(): void {
    if (this.cancelled) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANCELLED', 'The operation was cancelled');
  }

  override sharedObjectWillRelease(): void {
    this.cancelled = true;
    this.service.onDestroy();
    this.services.delete(this.service);
  }
}

class FileSystemUploadTask extends FileSystemNetworkTask {
  private started: boolean = false;

  async start(url: string, file: FileSystemFile, options: FileSystemRecord): Promise<UploadResult> {
    this.assertNotCancelled();
    if (this.started) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_TASK_ALREADY_RUNNING', 'Upload tasks can only be started once');

    this.started = true;
    const result = await this.service.uploadTask(this.uuid, (): UploadRequest => {
      const request = legacyUploadRequest(file.state, url, file.uri(), options);
      request.emitProgress = true;
      return request;
    }, file.state.ready());
    this.assertNotCancelled();
    if (result === null) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANCELLED');
    return result;
  }
}

// Resume data belongs to this platform and binds the partial file to its source and destination.
class SavedDownload {
  version: number = DOWNLOAD_RESUME_FORMAT_VERSION;
  url: string;
  destinationUri: string;
  isDirectory: boolean;
  offset: number = 0;
  fileUri?: string;

  constructor(url: string, destination: FileSystemDestination) {
    this.url = url;
    this.destinationUri = destination.uri();
    this.isDirectory = destination instanceof FileSystemDirectory;
  }
}

class FileSystemDownloadTask extends FileSystemNetworkTask {
  private started: boolean = false;
  private running: boolean = false;
  private pausing: boolean = false;
  private operation?: Promise<string | null>;
  private saved?: SavedDownload;

  start(url: string, destination: FileSystemDestination, options?: FileSystemRecord): Promise<string | null> {
    if (this.started) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_TASK_ALREADY_RUNNING', 'Download task has already started');
    this.started = true;
    return this.begin(url, destination, options);
  }

  resume(url: string, destination: FileSystemDestination, data: string, options?: FileSystemRecord): Promise<string | null> {
    let record: FileSystemRecord;
    try {
      record = requireRecord(JSON.parse(data), 'resumeData');
    } catch (_) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESUME_DATA');
    }

    const saved = new SavedDownload(url, destination);
    if (record['version'] !== saved.version || record['url'] !== url || record['destinationUri'] !== saved.destinationUri ||
      record['isDirectory'] !== saved.isDirectory) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESUME_DATA');

    saved.offset = recordNumber(record, 'offset') ?? -1;
    requireSafeInteger(saved.offset, 'ERR_FILE_SYSTEM_INVALID_RESUME_DATA', 'Resume offset');

    saved.fileUri = recordString(record, 'fileUri');
    if (saved.fileUri !== undefined) {
      // Syntax and destination binding can be checked before async picker grants restore.
      const path = decodeFileUri(saved.fileUri);
      const original = decodeFileUri(saved.destinationUri);
      if (saved.isDirectory ? parentPath(path) !== original : path !== original) {
        throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESUME_DATA', 'Resume path does not match the destination');
      }
    } else if (saved.offset !== 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESUME_DATA');

    this.started = true;

    return this.begin(url, destination, options, saved);
  }

  private begin(url: string, destination: FileSystemDestination, options?: FileSystemRecord, saved?: SavedDownload): Promise<string | null> {
    this.assertNotCancelled();
    if (this.running) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_TASK_ALREADY_RUNNING');

    this.running = true;
    this.pausing = false;
    const state = saved ?? new SavedDownload(url, destination);
    this.saved = state;
    const operation = this.run(url, destination, state, options).finally((): void => { this.running = false; });
    this.operation = operation;

    return operation;
  }

  private async run(url: string, destination: FileSystemDestination, saved: SavedDownload, options?: FileSystemRecord): Promise<string | null> {
    const result = await this.service.downloadTask(this.uuid, saved.offset, (): DownloadRequest => {
      const request = modernDownloadRequest(url, destination, options, true);
      if (saved.fileUri !== undefined) {
        request.destination = this.state.resolve(saved.fileUri, false, 'write');
        request.destinationIsDirectory = false;
      }
      request.emitProgress = true;
      request.resumable = true;
      request.resumeFrom = saved.offset;

      return request;
    }, destination.state.ready());
    this.assertNotCancelled();
    if (result === null) {
      if (this.pausing) return null;
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANCELLED');
    }
    return result.uri;
  }

  async pause(): Promise<ResumeRecord | null> {
    if (!this.running || this.operation === undefined || this.saved === undefined) return null;

    this.pausing = true;
    const record = await this.service.pause(this.uuid);
    if (record !== null) {
      this.saved.offset = parseResumeOffset(record.resumeData);
      if (this.saved.offset === 0) this.saved.fileUri = undefined;
      else if (record.destination !== undefined) this.saved.fileUri = toFileUri(record.destination);
    }
    const result = await this.operation;
    this.assertNotCancelled();
    if (result !== null) return null;
    return new ResumeRecord(JSON.stringify(this.saved));
  }
}

const RECORD_TYPE: ExpoValueType<FileSystemRecord> = new ExpoValueType<FileSystemRecord>(
  'plain object',
  (value: ESObject, path: string): FileSystemRecord => requireRecord(value, path),
  (value: FileSystemRecord): ESObject => value,
);

const FILE_TYPE: ExpoValueType<FileSystemFile> = ExpoSharedObjectTypes.named<FileSystemFile>('FileSystem', 'FileSystemFile');

const DIRECTORY_TYPE: ExpoValueType<FileSystemDirectory> = ExpoSharedObjectTypes.named<FileSystemDirectory>('FileSystem', 'FileSystemDirectory');

const DESTINATION_TYPE: ExpoValueType<FileSystemDestination> = FILE_TYPE.or(DIRECTORY_TYPE);

const FILE_CONTENT_TYPE = ExpoValueTypes.either(ExpoValueTypes.string(), ExpoValueTypes.uint8Array());

export class ExpoFileSystemModule extends ExpoModule {
  private readonly state: FileSystemState;
  private readonly service: ExpoFileSystemService;
  private readonly taskServices: Set<ExpoFileSystemService> = new Set();
  private readonly watchers: Set<FileSystemWatcher> = new Set();

  constructor(context: ExpoModuleContext) {
    super(context);
    this.state = new FileSystemState(context);
    this.service = new ExpoFileSystemService(
      context,
      (_eventName: string, payload: ProgressPayload): void => this.sendEvent('downloadProgress', new ModernDownloadProgress(payload)),
      (original: string, uri: string, directory: boolean): Promise<void> =>
        this.state.rememberPickerGrant(original, uri, directory),
    );
  }

  fileSystemState(): FileSystemState {
    return this.state;
  }

  override definition(): ExpoModuleDefinition {
    const handleClass = new ExpoSharedObjectClassDefinition<FileSystemFileHandle>('FileSystemFileHandle')
      .sharedRef('expo-file-system.file-handle')
      .construct(
        ExpoFunction.ownedTyped2(
          FILE_TYPE,
          ExpoValueTypes.string().optional(),
          (context: ExpoModuleContext, owner: FileSystemFile, mode?: string): FileSystemFileHandle =>
            new FileSystemFileHandle(context, owner, parseFileMode(owner, mode)),
        ),
      )
      .syncFunction(
        'readBytes',
        ExpoFunction.ownedTyped1(ExpoValueTypes.number(), (owner: FileSystemFileHandle, count: number): Uint8Array => owner.read(count)).returns(
          ExpoValueTypes.uint8Array(),
        ),
      )
      .syncFunction(
        'writeBytes',
        ExpoFunction.ownedTyped1(ExpoValueTypes.uint8Array(), (owner: FileSystemFileHandle, bytes: Uint8Array): void => owner.write(bytes)),
      )
      .syncFunction('close', (owner: FileSystemFileHandle): void => owner.close())
      .property(
        'offset',
        ExpoValueTypes.number().nullable(),
        (owner: FileSystemFileHandle): number | null => owner.offset(),
        (owner: FileSystemFileHandle, value: number | null): void => owner.setOffset(value),
      )
      .property('size', ExpoValueTypes.number().nullable(), (owner: FileSystemFileHandle): number | null => owner.size());

    const fileClass = new ExpoSharedObjectClassDefinition<FileSystemFile>('FileSystemFile');
    fileClass
      .construct(
        ExpoFunction.ownedTyped1(
          ExpoValueTypes.string(),
          (context: ExpoModuleContext, uri: string): FileSystemFile => new FileSystemFile(context, this.state, uri),
        ),
      )
      .syncFunction('validatePath', (owner: FileSystemFile): void => {
        // Construction validates syntax. Every operation checks scope in path(),
        // after asynchronous permission restoration for Promise-based operations.
        if (!owner.bundled && owner.provider === null) decodeFileUri(owner.uri());
      })
      .syncFunction(
        'create',
        ExpoFunction.ownedTyped1(RECORD_TYPE.optional(), (owner: FileSystemFile, options?: FileSystemRecord): void => createFile(owner, options)),
      )
      .syncFunction(
        'write',
        ExpoFunction.ownedTyped2(FILE_CONTENT_TYPE, RECORD_TYPE.optional(), (owner: FileSystemFile, content, options?: FileSystemRecord): void =>
          writeFileContent(owner, content, options),
        ),
      )
      .asyncFunction('text', async (owner: FileSystemFile): Promise<string> => new util.TextDecoder('utf-8').decode(await readOwnerBytesAsync(owner)))
      .syncFunction('textSync', (owner: FileSystemFile): string => readFileText(owner))
      .asyncFunction('base64', async (owner: FileSystemFile): Promise<string> => base64Encode(await readOwnerBytesAsync(owner)))
      .syncFunction('base64Sync', (owner: FileSystemFile): string => base64Encode(readOwnerBytes(owner)))
      .asyncFunction(
        'bytes',
        ExpoFunction.ownedTyped0(async (owner: FileSystemFile): Promise<Uint8Array> => readOwnerBytesAsync(owner)).returns(
          ExpoValueTypes.uint8Array(),
        ),
      )
      .syncFunction(
        'bytesSync',
        ExpoFunction.ownedTyped0((owner: FileSystemFile): Uint8Array => readOwnerBytes(owner)).returns(ExpoValueTypes.uint8Array()),
      )
      .syncFunction(
        'info',
        ExpoFunction.ownedTyped1(
          RECORD_TYPE.optional(),
          (owner: FileSystemFile, options?: FileSystemRecord): FileSystemInfo => fileInfo(owner, recordBoolean(options, 'md5')),
        ),
      )
      .syncFunction('delete', (owner: FileSystemFile): void => deleteFile(owner))
      .asyncFunction(
        'copy',
        ExpoFunction.ownedTyped2(DESTINATION_TYPE, RECORD_TYPE.optional(),
          async (owner: FileSystemFile, destination: FileSystemDestination, options?: FileSystemRecord): Promise<void> =>
            relocateAsync(owner, destination, options, false),
        ),
      )
      .syncFunction(
        'copySync',
        ExpoFunction.ownedTyped2(DESTINATION_TYPE, RECORD_TYPE.optional(),
          (owner: FileSystemFile, destination: FileSystemDestination, options?: FileSystemRecord): void => copyFile(owner, destination, options),
        ),
      )
      .asyncFunction(
        'move',
        ExpoFunction.ownedTyped2(DESTINATION_TYPE, RECORD_TYPE.optional(),
          async (owner: FileSystemFile, destination: FileSystemDestination, options?: FileSystemRecord): Promise<void> =>
            relocateAsync(owner, destination, options, true),
        ),
      )
      .syncFunction(
        'moveSync',
        ExpoFunction.ownedTyped2(DESTINATION_TYPE, RECORD_TYPE.optional(),
          (owner: FileSystemFile, destination: FileSystemDestination, options?: FileSystemRecord): void => moveFile(owner, destination, options),
        ),
      )
      .syncFunction(
        'rename',
        ExpoFunction.ownedTyped1(ExpoValueTypes.string(), (owner: FileSystemFile, name: string): void => renameFile(owner, name)),
      )
      .syncFunction(
        'open',
        ExpoFunction.ownedTyped1(
          ExpoValueTypes.string().optional(),
          (owner: FileSystemFile, mode?: string): FileSystemFileHandle =>
            handleClass.instance(new FileSystemFileHandle(this.context, owner, parseFileMode(owner, mode))),
        ).returns(handleClass.valueType()),
      )
      .property('exists', ExpoValueTypes.boolean(), (owner: FileSystemFile): boolean => fileExists(owner))
      .property('modificationTime', ExpoValueTypes.number().nullable(), (owner: FileSystemFile): number | null => fileTimestamp(owner, false))
      .property('lastModified', ExpoValueTypes.number().nullable(), (owner: FileSystemFile): number | null => fileTimestamp(owner, false))
      .property('creationTime', ExpoValueTypes.number().nullable(), (owner: FileSystemFile): number | null => fileTimestamp(owner, true))
      .property('uri', ExpoValueTypes.string(), (owner: FileSystemFile): string => owner.uri())
      .property('contentUri', ExpoValueTypes.string(), (owner: FileSystemFile): string =>
        owner.provider !== null ? providerContentUri(owner) :
          fileUri.getUriFromPath(owner.bundled ? decodeFileUri(owner.state.materializeRawContent(owner.rawUri())) : owner.path()),
      )
      .property('md5', ExpoValueTypes.string().nullable(), (owner: FileSystemFile): string | null => fileMd5OrNull(owner))
      .property('size', ExpoValueTypes.number(), (owner: FileSystemFile): number => fileSize(owner))
      .property('type', ExpoValueTypes.string(), (owner: FileSystemFile): string => fileExists(owner) ? mimeTypeForPath(owner.uri()) : '');

    const directoryClass = new ExpoSharedObjectClassDefinition<FileSystemDirectory>('FileSystemDirectory');
    directoryClass
      .construct(
        ExpoFunction.ownedTyped1(
          ExpoValueTypes.string(),
          (context: ExpoModuleContext, uri: string): FileSystemDirectory => new FileSystemDirectory(context, this.state, uri),
        ),
      )
      .syncFunction('validatePath', (owner: FileSystemDirectory): void => {
        if (!owner.bundled) decodeFileUri(owner.uri());
      })
      .syncFunction('info', (owner: FileSystemDirectory): FileSystemInfo => directoryInfo(owner))
      .syncFunction('delete', (owner: FileSystemDirectory): void => deleteDirectory(owner))
      .syncFunction(
        'create',
        ExpoFunction.ownedTyped1(RECORD_TYPE.optional(), (owner: FileSystemDirectory, options?: FileSystemRecord): void =>
          createDirectory(owner, options),
        ),
      )
      .syncFunction(
        'createDirectory',
        ExpoFunction.ownedTyped1(ExpoValueTypes.string(), (owner: FileSystemDirectory, name: string): FileSystemDirectory => {
          const target = joinPath(requireDirectory(owner.path('write')), safeName(name));
          fs.mkdirSync(target, false);
          return directoryClass.instance(new FileSystemDirectory(this.context, owner.state, toFileUri(target, true)));
        }).returns(directoryClass.valueType()),
      )
      .syncFunction(
        'createFile',
        ExpoFunction.ownedTyped2(
          ExpoValueTypes.string(),
          ExpoValueTypes.string().nullable(),
          (owner: FileSystemDirectory, name: string, _mimeType: string | null): FileSystemFile => {
            const target = joinPath(requireDirectory(owner.path('write')), safeName(name));
            if (fs.accessSync(target)) throw new ExpoFileSystemError('ERR_UNABLE_TO_CREATE', 'Child file already exists');

            atomicFileOperations.exclusiveCreate(target);

            return fileClass.instance(new FileSystemFile(this.context, owner.state, toFileUri(target)));
          },
        ).returns(fileClass.valueType()),
      )
      .asyncFunction(
        'copy',
        ExpoFunction.ownedTyped2(DESTINATION_TYPE, RECORD_TYPE.optional(),
          async (owner: FileSystemDirectory, destination: FileSystemDestination, options?: FileSystemRecord): Promise<void> =>
            relocateAsync(owner, destination, options, false),
        ),
      )
      .syncFunction(
        'copySync',
        ExpoFunction.ownedTyped2(DESTINATION_TYPE, RECORD_TYPE.optional(),
          (owner: FileSystemDirectory, destination: FileSystemDestination, options?: FileSystemRecord): void => copyDirectory(owner, destination, options),
        ),
      )
      .asyncFunction(
        'move',
        ExpoFunction.ownedTyped2(DESTINATION_TYPE, RECORD_TYPE.optional(),
          async (owner: FileSystemDirectory, destination: FileSystemDestination, options?: FileSystemRecord): Promise<void> =>
            relocateAsync(owner, destination, options, true),
        ),
      )
      .syncFunction(
        'moveSync',
        ExpoFunction.ownedTyped2(DESTINATION_TYPE, RECORD_TYPE.optional(),
          (owner: FileSystemDirectory, destination: FileSystemDestination, options?: FileSystemRecord): void => moveDirectory(owner, destination, options),
        ),
      )
      .syncFunction(
        'rename',
        ExpoFunction.ownedTyped1(ExpoValueTypes.string(), (owner: FileSystemDirectory, name: string): void => renameDirectory(owner, name)),
      )
      .syncFunction('listAsRecords', (owner: FileSystemDirectory): DirectoryEntryRecord[] => listDirectoryRecords(owner))
      .property('exists', ExpoValueTypes.boolean(), (owner: FileSystemDirectory): boolean => directoryExists(owner))
      .property('uri', ExpoValueTypes.string(), (owner: FileSystemDirectory): string => owner.uri())
      .property('size', ExpoValueTypes.number().nullable(), (owner: FileSystemDirectory): number | null => directorySizeOrNull(owner));

    const uploadClass = new ExpoSharedObjectClassDefinition<FileSystemUploadTask>('FileSystemUploadTask')
      .construct(ExpoFunction.ownedTyped0((context: ExpoModuleContext): FileSystemUploadTask =>
        new FileSystemUploadTask(context, this.state, this.taskServices),
      ))
      .events(['progress'])
      .asyncFunction('start', ExpoFunction.ownedTyped3(ExpoValueTypes.string(), FILE_TYPE, RECORD_TYPE,
        async (owner: FileSystemUploadTask, url: string, file: FileSystemFile, options: FileSystemRecord): Promise<UploadResult> =>
          owner.start(url, file, options),
      ))
      .syncFunction('cancel', (owner: FileSystemUploadTask): void => owner.cancel());

    const downloadClass = new ExpoSharedObjectClassDefinition<FileSystemDownloadTask>('FileSystemDownloadTask')
      .construct(ExpoFunction.ownedTyped0((context: ExpoModuleContext): FileSystemDownloadTask =>
        new FileSystemDownloadTask(context, this.state, this.taskServices),
      ))
      .events(['progress'])
      .asyncFunction('start', ExpoFunction.ownedTyped3(ExpoValueTypes.string(), DESTINATION_TYPE, RECORD_TYPE.optional(),
        async (owner: FileSystemDownloadTask, url: string, destination: FileSystemDestination, options?: FileSystemRecord): Promise<string | null> =>
          owner.start(url, destination, options),
      ))
      .asyncFunction('resume', ExpoFunction.ownedTyped4(ExpoValueTypes.string(), DESTINATION_TYPE, ExpoValueTypes.string(), RECORD_TYPE.optional(),
        async (owner: FileSystemDownloadTask, url: string, destination: FileSystemDestination, data: string, options?: FileSystemRecord): Promise<string | null> =>
          owner.resume(url, destination, data, options),
      ))
      .asyncFunction('pause', async (owner: FileSystemDownloadTask): Promise<ResumeRecord | null> => owner.pause())
      .syncFunction('cancel', (owner: FileSystemDownloadTask): void => owner.cancel());

    const watcherClass = new ExpoSharedObjectClassDefinition<FileSystemWatcher>('FileSystemWatcher')
      .construct(ExpoFunction.ownedTyped2(ExpoValueTypes.string(), RECORD_TYPE.optional(),
        (context: ExpoModuleContext, uri: string, options?: FileSystemRecord): FileSystemWatcher => {
          const path = this.state.resolve(uri, true);
          return new FileSystemWatcher(context, path, recordNumber(options, 'debounce') ?? DEFAULT_WATCH_DEBOUNCE_MS,
            recordStrings(options, 'events'), this.watchers);
        },
      ))
      .events(['change'])
      .syncFunction('start', (owner: FileSystemWatcher): void => {
        this.state.resolve(toFileUri(owner.path), true);
        owner.start();
      })
      .syncFunction('stop', (owner: FileSystemWatcher): void => owner.stop());

    return new ExpoModuleDefinition()
      .name('FileSystem')
      .events(['downloadProgress'])
      .constant('documentDirectory', (): string => toFileUri(this.state.documentPath, true))
      .constant('cacheDirectory', (): string => toFileUri(this.state.cachePath, true))
      .constant('bundleDirectory', 'rawfile:///')
      .constant('appleSharedContainers', new Object())
      .property('totalDiskSpace', ExpoValueTypes.number(), (): number => statvfs.getTotalSizeSync(this.state.documentPath))
      .property('availableDiskSpace', ExpoValueTypes.number(), (): number => statvfs.getFreeSizeSync(this.state.documentPath))
      .syncFunction(
        'info',
        ExpoFunction.typed1(ExpoValueTypes.string(), (uri: string): FileSystemInfo => pathInfo(this.state, uri)),
      )
      .asyncFunction(
        'downloadFileAsync',
        ExpoFunction.typed4(
          ExpoValueTypes.string(), DESTINATION_TYPE, RECORD_TYPE.optional(), ExpoValueTypes.string().optional(),
          async (url: string, destination: FileSystemDestination, options?: FileSystemRecord, uuid?: string): Promise<string> => {
            const taskUuid = uuid ?? util.generateRandomUUID();
            const result = await this.service.downloadTask(taskUuid, 0, (): DownloadRequest => {
              const request = modernDownloadRequest(url, destination, options);
              request.emitProgress = uuid !== undefined;
              return request;
            }, destination.state.ready());
            if (result === null) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANCELLED');
            return result.uri;
          },
        ),
      )
      .syncFunction('cancelDownloadAsync', ExpoFunction.typed1(ExpoValueTypes.string(), (uuid: string): void => {
        this.service.cancel(uuid);
      }))
      .asyncFunction(
        'pickDirectoryAsync',
        ExpoFunction.typed1(ExpoValueTypes.string().optional(), async (initialUri?: string): Promise<UriRecord> =>
          new UriRecord(await this.service.pickDirectory(initialUri)),
        ),
      )
      .asyncFunction(
        'pickFileAsync',
        ExpoFunction.typed1(RECORD_TYPE.optional(), async (options?: FileSystemRecord): Promise<UriRecord | UriRecord[]> => {
          const multiple = recordBoolean(options, 'multipleFiles');
          const uris = await this.service.pickFiles(recordString(options, 'initialUri'), recordStrings(options, 'mimeTypes', true), multiple);
          const files = uris.map((uri: string): UriRecord => new UriRecord(uri));
          return multiple ? files : files[0];
        }),
      )
      .sharedObjectClass(fileClass)
      .sharedObjectClass(handleClass)
      .sharedObjectClass(directoryClass)
      .sharedObjectClass(uploadClass)
      .sharedObjectClass(downloadClass)
      .sharedObjectClass(watcherClass)
      .onPrepareForReload(async (): Promise<void> => {
        this.stopWatchers();
        await Promise.all([this.service.destroy(), ...Array.from(this.taskServices).map((service: ExpoFileSystemService): Promise<void> => service.destroy())]);
      })
      .onDestroy((): void => this.destroyRuntime())
      .onAbilityDestroy((): void => this.destroyRuntime());
  }

  private stopWatchers(): void {
    this.watchers.forEach((watcher: FileSystemWatcher): void => {
      try { watcher.stop(); } catch (error) {
        this.context.logger.warn(`Could not stop Expo file watcher: ${cleanErrorMessage(error as Object)}`);
      }
    });
    this.watchers.clear();
  }

  private destroyRuntime(): void {
    this.stopWatchers();
    this.service.onDestroy();
    this.taskServices.forEach((service: ExpoFileSystemService): void => service.onDestroy());
    this.taskServices.clear();
  }
}

export class ExponentFileSystemModule extends ExpoModule {
  private readonly service: ExpoFileSystemService;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.service = new ExpoFileSystemService(
      context,
      (eventName: string, payload: ProgressPayload): void => this.sendEvent(eventName, payload),
      (original: string, uri: string, directory: boolean): Promise<void> =>
        this.fileState().rememberPickerGrant(original, uri, directory),
    );
  }

  private fileState(): FileSystemState {
    const module = this.context.requireModule('FileSystem');
    if (!(module instanceof ExpoFileSystemModule)) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_RUNTIME', 'FileSystem module is not available in this runtime');
    }
    return module.fileSystemState();
  }

  override definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExponentFileSystem')
      .constant('documentDirectory', (): string => this.context.persistentFilesDirectory)
      .constant('cacheDirectory', (): string => this.context.cacheDirectory)
      .constant('bundleDirectory', 'rawfile:///')
      .events(['expo-file-system.downloadProgress', 'expo-file-system.uploadProgress'])
      .asyncFunction(
        'getInfoAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          RECORD_TYPE.optional(),
          async (uri: string, options?: FileSystemRecord): Promise<FileSystemInfo> =>
            legacyInfoAsync(this.fileState(), uri, recordBoolean(options, 'md5')),
        ),
      )
      .asyncFunction(
        'readAsStringAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          RECORD_TYPE.optional(),
          async (uri: string, options?: FileSystemRecord): Promise<string> => legacyReadAsync(this.fileState(), uri, options),
        ),
      )
      .asyncFunction(
        'writeAsStringAsync',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          RECORD_TYPE.optional(),
          async (uri: string, value: string, options?: FileSystemRecord): Promise<void> => {
            const state = this.fileState();
            await state.ready();
            const bytes = recordEncoding(options) === 'base64' ? base64Decode(value) : new util.TextEncoder('utf-8').encode(value);
            await writeBytesFileAsync(state.resolve(uri, false, 'write'), bytes, recordBoolean(options, 'append'));
          },
        ),
      )
      .asyncFunction(
        'deleteAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), RECORD_TYPE.optional(), async (uri: string, options?: FileSystemRecord): Promise<void> => {
          const state = this.fileState();
          await state.ready();
          const path = state.resolve(uri, false, 'write');
          if (!(await fs.access(path))) {
            if (recordBoolean(options, 'idempotent')) return;
            throw new ExpoFileSystemError('ERR_FILE_SYSTEM_FILE_NOT_FOUND', 'Path does not exist');
          }
          await removePathAsync(path);
        }),
      )
      .asyncFunction(
        'moveAsync',
        ExpoFunction.typed1(RECORD_TYPE, async (options: FileSystemRecord): Promise<void> => {
          const state = this.fileState();
          await state.ready();
          const sourceUri = requiredRecordString(options, 'from');
          if (isPackagedResource(sourceUri)) {
            throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME', 'Bundled resources are read-only and cannot be moved');
          }
          await movePathAsync(state.resolve(sourceUri, true, 'write'), state.resolve(requiredRecordString(options, 'to'), false, 'write'));
        }),
      )
      .asyncFunction(
        'copyAsync',
        ExpoFunction.typed1(RECORD_TYPE, async (options: FileSystemRecord): Promise<void> => {
          const state = this.fileState();
          await state.ready();

          const source = requiredRecordString(options, 'from');
          const target = state.resolve(requiredRecordString(options, 'to'), false, 'write');

          if (isPackagedResource(source)) {
            await this.service.download({ url: source, destination: target, idempotent: true });
            return;
          }

          await copyFileSourceAsync(state.readSource(source), target, true);
        }),
      )
      .asyncFunction(
        'makeDirectoryAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), RECORD_TYPE.optional(), async (uri: string, options?: FileSystemRecord): Promise<void> => {
          const state = this.fileState();
          await state.ready();
          await makeDirectoryPathAsync(state.resolve(uri, false, 'write'), recordBoolean(options, 'intermediates'));
        }),
      )
      .asyncFunction(
        'readDirectoryAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (uri: string): Promise<string[]> => {
          const state = this.fileState();
          await state.ready();
          const path = requireDirectory(state.resolve(uri, true));
          return fs.listFile(path);
        }),
      )
      .asyncFunction('getTotalDiskCapacityAsync', async (): Promise<number> => statvfs.getTotalSize(this.fileState().documentPath))
      .asyncFunction('getFreeDiskStorageAsync', async (): Promise<number> => statvfs.getFreeSize(this.fileState().documentPath))
      .asyncFunction(
        'getContentUriAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (uri: string): Promise<string> => {
          const state = this.fileState();
          await state.ready();
          const provider = state.providerUri(uri);
          if (provider === null) return fileUri.getUriFromPath(state.resolve(uri, true));

          const file = await fs.open(state.readSource(provider), fs.OpenMode.READ_ONLY | fs.OpenMode.NONBLOCK);

          try {
            if (!(await fs.stat(file.fd)).isFile()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_FILE_TYPE', 'The selected URI is not a file');
            return provider;
          } finally {
            await fs.close(file);
          }
        }),
      )
      .asyncFunction(
        'downloadAsync',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          RECORD_TYPE.optional(),
          async (url: string, destinationUri: string, options?: FileSystemRecord): Promise<DownloadResult | RawDownloadResult | null> => {
            await this.fileState().ready();
            return this.service.download(legacyDownloadRequest(this.fileState(), url, destinationUri, options));
          },
        ),
      )
      .asyncFunction(
        'downloadResumableStartAsync',
        ExpoFunction.typed5(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          RECORD_TYPE,
          ExpoValueTypes.string().optional(),
          async (
            url: string,
            destinationUri: string,
            uuid: string,
            options: FileSystemRecord,
            resumeData?: string,
          ): Promise<DownloadResult | RawDownloadResult | null> => {
            const state = this.fileState();
            const offset = parseResumeOffset(resumeData);
            return this.service.downloadTask(uuid, offset, (): DownloadRequest => {
              const request = legacyDownloadRequest(state, url, destinationUri, options);
              request.emitProgress = true;
              request.resumeFrom = offset;
              request.resumable = true;

              return request;
            }, state.ready());
          },
        ),
      )
      .asyncFunction(
        'downloadResumablePauseAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (uuid: string): Promise<ResumeRecord | null> => this.service.pause(uuid)),
      )
      .asyncFunction(
        'networkTaskCancelAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (uuid: string): Promise<null> => this.service.cancel(uuid)),
      )
      .asyncFunction(
        'uploadAsync',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          RECORD_TYPE,
          async (url: string, sourceUri: string, options: FileSystemRecord): Promise<UploadResult | null> => {
            await this.fileState().ready();
            return this.service.upload(legacyUploadRequest(this.fileState(), url, sourceUri, options));
          },
        ),
      )
      .asyncFunction(
        'uploadTaskStartAsync',
        ExpoFunction.typed4(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          RECORD_TYPE,
          async (url: string, sourceUri: string, uuid: string, options: FileSystemRecord): Promise<UploadResult | null> => {
            const state = this.fileState();
            return this.service.uploadTask(uuid, (): UploadRequest => {
              const request = legacyUploadRequest(state, url, sourceUri, options);
              request.emitProgress = true;
              return request;
            }, state.ready());
          },
        ),
      )
      .asyncFunction(
        'requestDirectoryPermissionsAsync',
        ExpoFunction.typed1(ExpoValueTypes.string().nullable().optional(), async (initialUri?: string | null): Promise<PermissionRecord> =>
          this.service.pickDirectoryPermission(initialUri ?? undefined),
        ),
      )
      .asyncFunction(
        'readSAFDirectoryAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (uri: string): Promise<string[]> => {
          const state = this.fileState();
          await state.ready();
          const path = requireDirectory(state.resolve(uri, true));
          const results: string[] = [];

          for (const name of await fs.listFile(path)) {
            const target = joinPath(path, name);
            results.push(toFileUri(target, (await fs.lstat(target)).isDirectory()));
          }

          return results;
        }),
      )
      .asyncFunction(
        'makeSAFDirectoryAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), ExpoValueTypes.string(), async (uri: string, name: string): Promise<string> => {
          const state = this.fileState();
          await state.ready();
          const target = joinPath(requireDirectory(state.resolve(uri, true, 'write')), safeName(name));
          await fs.mkdir(target, false);
          return toFileUri(target, true);
        }),
      )
      .asyncFunction(
        'createSAFFileAsync',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          async (uri: string, requested: string, mime: string): Promise<string> => {
            await this.fileState().ready();
            const extension = requested.includes('.') ? null : extensionForMimeType(mime);
            const name = safeName(extension === null ? requested : `${requested}.${extension}`);
            const target = joinPath(requireDirectory(this.fileState().resolve(uri, true, 'write')), name);
            atomicFileOperations.exclusiveCreate(target);

            return toFileUri(target);
          },
        ),
      )
      .onPrepareForReload(async (): Promise<void> => this.service.destroy())
      .onDestroy((): void => this.service.onDestroy())
      .onAbilityDestroy((): void => this.service.onDestroy());
  }
}

function isProviderFileUri(uri: string): boolean {
  if (!uri.startsWith('file://')) return false;

  try {
    const authority = new url.URL(uri).hostname;
    return authority.length > 0 && authority !== 'localhost';
  } catch (error) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_URI', 'The file URI is malformed', error as Object);
  }
}

function decodeFileUri(uri: string): string {
  if (!uri.startsWith('file:')) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME', `Unsupported URI '${uri}'`);
  }

  let encoded = uri.slice(5);
  if (encoded.startsWith('//')) {
    encoded = encoded.slice(2);
    if (/^localhost\//i.test(encoded)) encoded = encoded.slice('localhost'.length);
    else if (!encoded.startsWith('/')) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_URI', 'Only an empty or localhost file authority is allowed');
    }
  }

  const suffix = encoded.search(/[?#]/);
  if (suffix >= 0) encoded = encoded.slice(0, suffix);

  let decoded: string;
  try {
    decoded = decodeURIComponent(encoded);
  } catch (_) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_URI', 'The file URI has invalid percent encoding');
  }
  if (decoded.includes('\0') || !decoded.startsWith('/')) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_URI', 'The file URI must contain an absolute path');
  }

  return normalizeAbsolutePath(decoded);
}

function normalizeAbsolutePath(value: string): string {
  const output: string[] = [];
  value.split('/').forEach((segment: string): void => {
    if (segment.length === 0 || segment === '.') return;
    if (segment === '..') {
      if (output.length === 0) {
        throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_PATH', 'The path escapes its root');
      }
      output.pop();
      return;
    }
    output.push(segment);
  });
  return `/${output.join('/')}`;
}

function isInside(root: string, path: string): boolean {
  return root.length > 0 && (path === root || path.startsWith(root.endsWith('/') ? root : `${root}/`));
}

function isRawUri(uri: string): boolean {
  return uri.startsWith('asset://') || uri.startsWith('rawfile://') || isRnohRawfileResourceUri(uri);
}

function rawPathFromUri(uri: string, relative: boolean = false, root: boolean = false): string {
  // Metro and split bundles use literal paths. The legacy asset:/// form is root-relative.
  const metro = uri.startsWith('asset://') && !uri.startsWith('asset:///');
  if (metro || isRnohRawfileResourceUri(uri)) {
    if (root && uri === 'asset://') return 'assets';
    if (root && uri === 'resource://RAWFILE/') return '';

    try {
      return rawResourcePathFromUri(uri.endsWith('/') ? uri.slice(0, -1) : uri);
    } catch (_) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESOURCE', 'Invalid bundled resource path');
    }
  }

  let path: string;

  if (uri.startsWith('asset://')) path = uri.slice('asset://'.length);
  else if (uri.startsWith('rawfile://')) path = uri.slice('rawfile://'.length);
  else if (relative && !uri.includes(':')) path = uri;
  else throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME', `Unsupported bundled URI '${uri}'`);

  path = path.replace(/^\/+/, '').split(/[?#]/, 1)[0];

  try {
    path = decodeURIComponent(path);
  } catch (_) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESOURCE', 'Invalid bundled resource URI');
  }

  if (path.endsWith('/')) path = path.slice(0, -1);

  if (path.includes('\0') || path.includes('\\')) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESOURCE', 'Invalid bundled resource path');
  }
  if (path.length === 0 && root) return '';

  const parts = path.split('/');

  if (parts.some((part: string): boolean => part.length === 0 || part === '.' || part === '..')) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESOURCE', 'Invalid bundled resource path');
  }

  return path;
}

function toRawUri(path: string, directory: boolean): string {
  const encoded = path
    .split('/')
    .map((part: string): string => encodeURIComponent(part))
    .join('/');
  const uri = `rawfile:///${encoded}`;

  return directory && !uri.endsWith('/') ? `${uri}/` : uri;
}

function parentPath(path: string): string {
  const slash = path.lastIndexOf('/');
  return slash <= 0 ? '/' : path.slice(0, slash);
}

function leafName(path: string): string {
  const normalized = path.replace(/\/+$/, '');
  return normalized.slice(normalized.lastIndexOf('/') + 1);
}

function requireFile(path: string): string {
  if (!fs.accessSync(path) || !fs.statSync(path).isFile()) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_FILE_TYPE', 'The path does not point to a file');
  }
  return path;
}

function requireDirectory(path: string): string {
  if (!fs.accessSync(path) || !fs.statSync(path).isDirectory()) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_DIRECTORY_TYPE', 'The path does not point to a directory');
  }
  return path;
}

function requireSafeInteger(value: number, code: string, label: string): void {
  if (!Number.isFinite(value) || !Number.isSafeInteger(value) || value < 0) {
    throw new ExpoFileSystemError(code, `${label} must be a finite, non-negative safe integer`);
  }
}

function ensureDirectoryExists(path: string): void {
  try {
    fs.mkdirSync(path, true);
  } catch (error) {
    if (Number(Reflect.get(error as Object, 'code')) !== FILE_EXISTS_ERROR) {
      throw new ExpoFileSystemError(
        error instanceof ExpoModuleError ? error.code : String(Reflect.get(error as Object, 'code') ?? 'ERR_FILE_SYSTEM'),
        error instanceof Error ? error.message : String(error),
        error instanceof ExpoModuleError ? error.cause : (error as Object),
        error instanceof ExpoModuleError ? error.path : undefined,
      );
    }
  }
  // Recursive mkdir still reports EEXIST on Harmony. Only an actual directory
  // may satisfy an ensure operation, including when another Host created it.
  if (!fs.lstatSync(path).isDirectory()) throw new ExpoModuleError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected directory`);
}

async function makeDirectoryPathAsync(path: string, intermediates: boolean): Promise<void> {
  try {
    await fs.mkdir(path, intermediates);
  } catch (error) {
    if (!intermediates || Number(Reflect.get(error as Object, 'code')) !== FILE_EXISTS_ERROR) {
      throw new ExpoFileSystemError(
        error instanceof ExpoModuleError ? error.code : String(Reflect.get(error as Object, 'code') ?? 'ERR_FILE_SYSTEM'),
        error instanceof Error ? error.message : String(error),
        error instanceof ExpoModuleError ? error.cause : (error as Object),
        error instanceof ExpoModuleError ? error.path : undefined,
      );
    }
  }
  if (!(await fs.lstat(path)).isDirectory()) throw new ExpoModuleError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected directory`);
}

function writeBytesFile(path: string, bytes: Uint8Array, append: boolean): void {
  const mode = fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.NOFOLLOW | (append ? fs.OpenMode.APPEND : fs.OpenMode.TRUNC);
  const file = fs.openSync(path, mode);
  try {
    const offset = append ? fs.statSync(file.fd).size : 0;
    writeAll(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength), offset);
  } finally {
    fs.closeSync(file.fd);
  }
}

function readBytesFromFile(file: fs.File): Uint8Array {
  const length: number = requireRegularFile(fs.statSync(file.fd)).size;
  const buffer = new ArrayBuffer(length);
  const output = new Uint8Array(buffer);
  const chunk = new ArrayBuffer(Math.min(length, 64 * 1024));
  let total: number = 0;

  while (total < length) {
    const count: number = fs.readSync(file.fd, chunk, { length: Math.min(chunk.byteLength, length - total) });
    if (count <= 0) break;
    output.set(new Uint8Array(chunk, 0, count), total);
    total += count;
  }

  return new Uint8Array(total === length ? buffer : buffer.slice(0, total));
}

function readOwnerBytes(owner: FileSystemFile): Uint8Array {
  if (owner.bundled) return owner.state.rawBytes(owner.rawUri());
  return withFileRead(owner.state.readSource(owner.uri()), readBytesFromFile);
}

function readFileText(owner: FileSystemFile): string {
  return new util.TextDecoder('utf-8').decode(readOwnerBytes(owner));
}

function base64Encode(bytes: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(bytes);
}

function base64Decode(value: string): Uint8Array {
  try {
    return new util.Base64Helper().decodeSync(value);
  } catch (_) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_BASE64', 'The supplied value is not valid base64');
  }
}

function md5Bytes(bytes: Uint8Array): string {
  const stream = fileHash.createHash('md5');
  stream.update(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  return stream.digest().toLowerCase();
}

function withFileRead<T>(source: string, read: (file: fs.File) => T): T {
  const file = fs.openSync(source, fileReadFlags(source));
  try {
    return read(file);
  } finally {
    fs.closeSync(file.fd);
  }
}

function requireRegularFile(stat: fs.Stat): fs.Stat {
  if (!stat.isFile()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_FILE_TYPE', 'Path is not a file');
  return stat;
}

function fileReadFlags(source: string): number {
  return fs.OpenMode.READ_ONLY | fs.OpenMode.NONBLOCK | (source.startsWith('/') ? fs.OpenMode.NOFOLLOW : 0);
}

function md5File(file: fs.File): string {
  requireRegularFile(fs.statSync(file.fd));

  const stream = fileHash.createHash('md5');
  const buffer = new ArrayBuffer(64 * 1024);

  while (true) {
    const count = fs.readSync(file.fd, buffer, { length: buffer.byteLength });
    if (count <= 0) break;
    stream.update(count === buffer.byteLength ? buffer : buffer.slice(0, count));
  }

  return stream.digest().toLowerCase();
}

function md5Path(path: string): string {
  return withFileRead(path, md5File);
}

function pathSize(path: string): number {
  const stat = fs.lstatSync(path);
  if (stat.isSymbolicLink()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_SYMLINK', 'Symbolic link encountered');
  if (stat.isFile()) return stat.size;
  if (!stat.isDirectory()) return 0;
  let size = 0;
  fs.listFileSync(path).forEach((name: string): void => {
    size += pathSize(joinPath(path, name));
  });
  return size;
}

function removePath(path: string): void {
  const stat = fs.lstatSync(path);
  if (stat.isSymbolicLink()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_SYMLINK', 'Symbolic link encountered');
  if (stat.isDirectory()) {
    fs.listFileSync(path).forEach((name: string): void => removePath(joinPath(path, name)));
    fs.rmdirSync(path);
  } else {
    fs.unlinkSync(path);
  }
}

function reportCommittedCleanupFailure(staging: string, error: Object): void {
  hilog.warn(FILE_SYSTEM_LOG_DOMAIN, FILE_SYSTEM_LOG_TAG,
    'File operation committed; temporary backup could not be fully removed at %{public}s: %{public}s',
    staging, cleanErrorMessage(error));
}

function cleanupStaging(staging: string, committed: boolean): void {
  try { removePath(staging); } catch (error) {
    if (!committed) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CLEANUP_FAILED', `Temporary data retained at '${staging}'`, error as Object);
    reportCommittedCleanupFailure(staging, error as Object);
  }
}

async function cleanupStagingAsync(staging: string, committed: boolean): Promise<void> {
  try { await removePathAsync(staging); } catch (error) {
    if (!committed) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CLEANUP_FAILED', `Temporary data retained at '${staging}'`, error as Object);
    reportCommittedCleanupFailure(staging, error as Object);
  }
}

function copyPath(source: string, target: string): void {
  assertSeparatePaths(source, target);
  const stat = fs.lstatSync(source);
  if (stat.isSymbolicLink()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_SYMLINK', 'Symbolic link encountered');
  if (stat.isFile()) {
    fs.copyFileSync(source, target, 0);
    return;
  }
  if (!stat.isDirectory()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_PATH', 'Unsupported file type');
  fs.mkdirSync(target, false);
  fs.listFileSync(source).forEach((name: string): void => copyPath(joinPath(source, name), joinPath(target, name)));
}

function copyPathOverwrite(source: string | number, target: string): void {
  if (typeof source === 'string') assertSeparatePaths(source, target);
  // The staging directory is on the destination volume so both commit and
  // rollback can use rename without copying or truncating the previous target.
  const staging = fs.mkdtempSync(joinPath(parentPath(target), '.expo-copy-XXXXXX'));
  const replacement = joinPath(staging, 'replacement');
  const previous = joinPath(staging, 'previous');
  let preservePrevious: boolean = false;
  let committed = false;

  try {
    if (typeof source === 'number') fs.copyFileSync(source, replacement);
    else copyPath(source, replacement);

    const hadTarget = fs.accessSync(target);
    if (hadTarget) fs.renameSync(target, previous);

    try {
      atomicFileOperations.publishNoReplace(replacement, target);
      committed = true;
    } catch (error) {
      if (hadTarget) {
        try {
          atomicFileOperations.publishNoReplace(previous, target);
        } catch (restoreError) {
          preservePrevious = true;
          throw new ExpoFileSystemError(
            'ERR_FILE_SYSTEM_COPY_ROLLBACK_FAILED',
            `Unable to restore the destination; its previous contents are retained at '${previous}': ${cleanErrorMessage(restoreError as Object)}`,
            restoreError as Object,
          );
        }
      }
      throw new ExpoFileSystemError(
        error instanceof ExpoModuleError ? error.code : String(Reflect.get(error as Object, 'code') ?? 'ERR_FILE_SYSTEM'),
        error instanceof Error ? error.message : String(error),
        error instanceof ExpoModuleError ? error.cause : (error as Object),
        error instanceof ExpoModuleError ? error.path : undefined,
      );
    }
  } finally {
    if (!preservePrevious) cleanupStaging(staging, committed);
  }
}

function copyPathNoReplace(source: string | number, target: string): void {
  if (typeof source === 'string') assertSeparatePaths(source, target);
  if (fs.accessSync(target)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_DESTINATION_EXISTS', 'Copy destination exists');

  const staging = fs.mkdtempSync(joinPath(parentPath(target), '.expo-copy-XXXXXX'));
  let committed = false;

  try {
    const replacement = joinPath(staging, 'replacement');
    if (typeof source === 'number') fs.copyFileSync(source, replacement);
    else copyPath(source, replacement);

    atomicFileOperations.publishNoReplace(replacement, target);
    committed = true;
  } finally {
    cleanupStaging(staging, committed);
  }
}

function movePathNoReplace(source: string, target: string): void {
  assertSeparatePaths(source, target);
  try {
    atomicFileOperations.publishNoReplace(source, target);
    return;
  } catch (error) {
    if (Reflect.get(error as Object, 'code') !== 'ERR_FILE_SYSTEM_CROSS_DEVICE') {
      throw new ExpoFileSystemError(
        error instanceof ExpoModuleError ? error.code : String(Reflect.get(error as Object, 'code') ?? 'ERR_FILE_SYSTEM'),
        error instanceof Error ? error.message : String(error),
        error instanceof ExpoModuleError ? error.cause : (error as Object),
        error instanceof ExpoModuleError ? error.path : undefined,
      );
    }
  }
  // Stage on the destination volume and retain the same no-replace contract.
  copyPathNoReplace(source, target);
  try {
    removePath(source);
  } catch (error) {
    throw new ExpoFileSystemError(
      'ERR_FILE_SYSTEM_MOVE_SOURCE_RETAINED',
      `The destination was created, but the source could not be removed: ${cleanErrorMessage(error as Object)}`,
      error as Object,
    );
  }
}

function movePathReplacing(source: string, target: string): void {
  assertSeparatePaths(source, target);
  if (!fs.accessSync(target)) {
    movePathNoReplace(source, target);
    return;
  }

  const staging = fs.mkdtempSync(joinPath(parentPath(target), '.expo-move-XXXXXX'));
  const previous = joinPath(staging, 'previous');
  let preserve = false;
  let committed = false;

  try {
    fs.renameSync(target, previous);
    try {
      movePathNoReplace(source, target);
      committed = true;
    } catch (error) {
      if (fs.accessSync(target)) {
        preserve = true;
        throw new ExpoFileSystemError('ERR_FILE_SYSTEM_MOVE_FAILED', `Move did not finish; previous destination retained at '${previous}': ${cleanErrorMessage(error as Object)}`, error as Object);
      } else {
        try { atomicFileOperations.publishNoReplace(previous, target); } catch (cause) {
          preserve = true;
          throw new ExpoFileSystemError('ERR_FILE_SYSTEM_MOVE_ROLLBACK_FAILED', `Previous destination retained at '${previous}'`, cause as Object);
        }
      }
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_MOVE_FAILED', cleanErrorMessage(error as Object), error as Object);
    }
  } finally {
    if (!preserve) cleanupStaging(staging, committed);
  }
}

function movePath(source: string, target: string): void {
  assertSeparatePaths(source, target);
  try {
    fs.renameSync(source, target);
    return;
  } catch (error) {
    const code = Number(Reflect.get(error as Object, 'code'));
    if (code !== 13900016) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_MOVE_FAILED', cleanErrorMessage(error as Object), error as Object);
    }
  }
  try {
    copyPathOverwrite(source, target);
  } catch (error) {
    throw new ExpoFileSystemError(
      'ERR_FILE_SYSTEM_MOVE_FAILED',
      `Unable to copy a cross-volume move target: ${cleanErrorMessage(error as Object)}`,
      error as Object,
    );
  }
  try {
    removePath(source);
  } catch (error) {
    throw new ExpoFileSystemError(
      'ERR_FILE_SYSTEM_MOVE_SOURCE_RETAINED',
      `The destination was created, but the source could not be removed: ${cleanErrorMessage(error as Object)}`,
      error as Object,
    );
  }
}

function assertSeparatePaths(source: string, target: string): void {
  const from = normalizeAbsolutePath(source);
  const to = normalizeAbsolutePath(target);
  if (isInside(from, to) || isInside(to, from)) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_OVERLAPPING_PATHS', 'Source and destination paths must not overlap');
  }
}

function assertOutsideDirectory(source: string, target: string): void {
  if (isInside(source, target)) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_RECURSIVE_COPY', 'A directory cannot be copied or moved into itself');
  }
}

function requireRecord(value: ESObject, path: string): FileSystemRecord {
  if (value === null || typeof value !== 'object' || Array.isArray(value) || value instanceof ArrayBuffer) {
    throw new ExpoModuleError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected plain object`);
  }
  return value as FileSystemRecord;
}

function parseFileMode(owner: FileSystemFile, mode?: string): FileMode {
  switch (mode) {
    case undefined: return owner.provider === null ? FileMode.ReadWrite : FileMode.ReadOnly;
    case FileMode.ReadOnly: return FileMode.ReadOnly;
    case FileMode.ReadWrite: return FileMode.ReadWrite;
    case FileMode.WriteOnly: return FileMode.WriteOnly;
    case FileMode.Append: return FileMode.Append;
    case FileMode.Truncate: return FileMode.Truncate;
    default: throw new ExpoFileSystemError('ERR_INVALID_ARGUMENT_TYPE', `Unknown file mode '${mode}'`);
  }
}

function openFileHandle(owner: FileSystemFile, mode: FileMode): fs.File {
  if (owner.provider !== null && mode === FileMode.ReadOnly) {
    const source = owner.state.readSource(owner.provider);
    const file = fs.openSync(source, fileReadFlags(source));

    try {
      requireRegularFile(fs.statSync(file.fd));
      return file;
    } catch (error) {
      fs.closeSync(file.fd);
      throw error as Error;
    }
  }
  if (mode === FileMode.ReadWrite) owner.path('read');
  const path = requireFile(owner.path(mode === FileMode.ReadOnly ? 'read' : 'write'));
  const flags = mode === FileMode.ReadOnly ? fs.OpenMode.READ_ONLY : mode === FileMode.ReadWrite
    ? fs.OpenMode.READ_WRITE : fs.OpenMode.WRITE_ONLY;
  return fs.openSync(path, flags | fs.OpenMode.NOFOLLOW | (mode === FileMode.Truncate ? fs.OpenMode.TRUNC : 0));
}

function recordBoolean(record: FileSystemRecord | undefined, key: string): boolean {
  if (record === undefined || record[key] === undefined) return false;
  if (typeof record[key] !== 'boolean') {
    throw new ExpoFileSystemError('ERR_INVALID_ARGUMENT_TYPE', `Option '${key}' must be a boolean`);
  }
  return record[key] as boolean;
}

function recordString(record: FileSystemRecord | undefined, key: string): string | undefined {
  const value: ESObject = record === undefined ? undefined : record[key];
  if (value === undefined) return undefined;
  if (typeof value !== 'string') {
    throw new ExpoFileSystemError('ERR_INVALID_ARGUMENT_TYPE', `Option '${key}' must be a string`);
  }
  return value;
}

function recordStrings(record: FileSystemRecord | undefined, key: string, acceptSingle: boolean = false): string[] | undefined {
  const value: ESObject = record === undefined ? undefined : record[key];
  if (value === undefined) return undefined;
  if (acceptSingle && typeof value === 'string') return [value];
  if (!Array.isArray(value) || value.some((entry: ESObject): boolean => typeof entry !== 'string')) {
    throw new ExpoFileSystemError('ERR_INVALID_ARGUMENT_TYPE', `Option '${key}' must be an array of strings`);
  }
  return value as string[];
}

function recordEncoding(record?: FileSystemRecord): string {
  const encoding = recordString(record, 'encoding') ?? 'utf8';
  if (encoding !== 'utf8' && encoding !== 'base64') {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_ENCODING', `Unsupported encoding '${encoding}'`);
  }
  return encoding;
}

function recordUploadType(record: FileSystemRecord): number {
  const type = recordNumber(record, 'uploadType') ?? 0;
  if (type !== 0 && type !== 1) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_UPLOAD_TYPE', 'uploadType must be BINARY_CONTENT (0) or MULTIPART (1)');
  }
  return type;
}

function isMissingRawResource(error: Object): boolean {
  // ResourceManager documents 9001005 for a missing/invalid raw relative path.
  // URI syntax is validated before calls so other errors must remain observable.
  return (error as Record<string, ESObject>)['code'] === 9001005;
}

function recordNumber(record: FileSystemRecord | undefined, key: string): number | undefined {
  const value: ESObject = record === undefined ? undefined : record[key];
  if (value === undefined) return undefined;
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new ExpoFileSystemError('ERR_INVALID_ARGUMENT_TYPE', `Option '${key}' must be a finite number`);
  }
  return value;
}

function recordObject(record: FileSystemRecord | undefined, key: string): Object | undefined {
  const value: ESObject = record === undefined ? undefined : record[key];
  if (value === undefined) return undefined;
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoFileSystemError('ERR_INVALID_ARGUMENT_TYPE', `Option '${key}' must be an object`);
  }
  return value as Object;
}

function requiredRecordString(record: FileSystemRecord, key: string): string {
  const value = recordString(record, key);
  if (value === undefined) throw new ExpoFileSystemError('ERR_INVALID_ARGUMENT_TYPE', `Option '${key}' must be a string`);
  return value;
}

function createFile(owner: FileSystemFile, options?: FileSystemRecord): void {
  const path = owner.path('write');
  const overwrite = recordBoolean(options, 'overwrite');

  if (recordBoolean(options, 'intermediates')) ensureDirectoryExists(parentPath(path));
  if (fs.accessSync(path)) {
    if (!fs.statSync(path).isFile()) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_FILE_TYPE', 'Cannot replace a directory with a file');
    }
    if (!overwrite) throw new ExpoFileSystemError('ERR_UNABLE_TO_CREATE', 'File already exists');
  }

  if (!overwrite) {
    atomicFileOperations.exclusiveCreate(path);
    return;
  }

  const staging = fs.mkdtempSync(joinPath(parentPath(path), '.expo-create-XXXXXX'));
  let committed = false;

  try {
    const replacement = joinPath(staging, 'replacement');
    atomicFileOperations.exclusiveCreate(replacement);
    fs.renameSync(replacement, path);
    committed = true;
  } finally {
    cleanupStaging(staging, committed);
  }
}

function writeFileContent(owner: FileSystemFile, content: ExpoEither<string, Uint8Array>, options?: FileSystemRecord): void {
  const encoding: string | undefined = recordString(options, 'encoding');
  if (encoding !== undefined && encoding !== 'utf8' && encoding !== 'base64') {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_ENCODING', `Unsupported file encoding '${encoding}'`);
  }

  const bytes = content.isFirst
    ? encoding === 'base64'
      ? base64Decode(content.first as string)
      : new util.TextEncoder('utf-8').encode(content.first as string)
    : (content.second as Uint8Array);

  writeBytesFile(owner.path('write'), bytes, recordBoolean(options, 'append'));
}

function fileExists(owner: FileSystemFile): boolean {
  if (owner.bundled) return owner.state.rawExists(owner.rawUri());
  if (owner.provider !== null) return providerStat(owner) !== null;

  const path = owner.probePath();
  if (path === null || !fs.accessSync(path)) return false;
  return fs.statSync(path).isFile();
}

function modifiedMilliseconds(stat: fs.Stat): number {
  if (deviceInfo.sdkApiVersion >= 15) {
    try {
      const nanoseconds = stat.mtimeNs;
      if (typeof nanoseconds === 'bigint') return Number(nanoseconds / BigInt(1000000));
    } catch (_) {}
  }
  return stat.mtime * 1000;
}

function fileTimestamp(owner: FileSystemFile, creation: boolean): number | null {
  if (owner.bundled) return null;
  if (owner.provider !== null) {
    const stat = providerStat(owner);
    return stat === null || creation ? null : modifiedMilliseconds(stat);
  }

  const path = owner.probePath();
  if (path === null || !fs.accessSync(path)) return null;
  const stat = fs.statSync(path);
  if (!stat.isFile()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_FILE_TYPE', 'Path points to a directory');
  return creation ? null : modifiedMilliseconds(stat);
}

function fileMd5(owner: FileSystemFile): string | null {
  if (!fileExists(owner)) return null;
  return owner.bundled ? owner.state.rawMd5(owner.rawUri()) : md5Path(owner.state.readSource(owner.uri()));
}

function fileMd5OrNull(owner: FileSystemFile): string | null {
  try {
    return fileMd5(owner);
  } catch (_) {
    return null;
  }
}

function fileSize(owner: FileSystemFile): number {
  if (owner.provider !== null) return providerStat(owner)?.size ?? 0;
  if (!fileExists(owner)) return 0;
  return owner.bundled ? owner.state.rawSize(owner.rawUri()) : fs.statSync(owner.path()).size;
}

function fileInfo(owner: FileSystemFile, includeMd5: boolean): FileSystemInfo {
  if (owner.provider !== null) {
    try {
      return withFileRead(owner.state.readSource(owner.provider), (file: fs.File): FileSystemInfo => {
        const stat = requireRegularFile(fs.statSync(file.fd));
        const result = new FileSystemInfo(true);
        result.uri = owner.provider as string;
        result.isDirectory = false;
        result.size = stat.size;
        result.modificationTime = modifiedMilliseconds(stat);
        result.creationTime = null;
        if (includeMd5) result.md5 = md5File(file);

        return result;
      });
    } catch (error) {
      if (Number(Reflect.get(error as Object, 'code')) !== FILE_NOT_FOUND_ERROR) throw error as Error;
      const missing = new FileSystemInfo(false);
      missing.uri = owner.provider;

      return missing;
    }
  }
  if (!owner.bundled && fs.accessSync(owner.path())) requireFile(owner.path());
  const exists = fileExists(owner);
  const result = new FileSystemInfo(exists);
  result.uri = owner.uri();
  result.isDirectory = exists ? false : null;
  if (!exists) return result;
  result.size = fileSize(owner);
  result.modificationTime = fileTimestamp(owner, false);
  result.creationTime = fileTimestamp(owner, true);
  if (includeMd5) result.md5 = fileMd5(owner) ?? undefined;
  return result;
}

function providerStat(owner: FileSystemFile): fs.Stat | null {
  try {
    return withFileRead(owner.state.readSource(owner.uri()), (file: fs.File): fs.Stat => requireRegularFile(fs.statSync(file.fd)));
  } catch (_) {
    return null;
  }
}

function providerContentUri(owner: FileSystemFile): string {
  const uri = owner.uri();
  return withFileRead(owner.state.readSource(uri), (file: fs.File): string => {
    requireRegularFile(fs.statSync(file.fd));
    return uri;
  });
}

function deleteFile(owner: FileSystemFile): void {
  const path = owner.path('write');
  if (!fs.accessSync(path)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANNOT_DELETE', 'File does not exist');
  requireFile(path);

  fs.unlinkSync(path);
}

function fileTarget(owner: FileSystemFile, destination: FileSystemDestination): string {
  if (destination instanceof FileSystemDirectory) {
    const name = owner.provider === null ? leafName(decodeFileUri(owner.uri())) :
      withFileRead(owner.state.readSource(owner.provider), (file: fs.File): string => safeName(file.name));
    const target = joinPath(requireDirectory(destination.path('write')), name);
    return destination.state.resolve(toFileUri(target), false, 'write');
  }
  requireDirectory(parentPath(destination.path('write')));
  return destination.path('write');
}

function copyFile(owner: FileSystemFile, destination: FileSystemDestination, options?: FileSystemRecord): void {
  const target = fileTarget(owner, destination);
  const overwrite = recordBoolean(options, 'overwrite');
  const source = owner.state.readSource(owner.uri());
  if (owner.provider !== null) {
    withFileRead(source, (file: fs.File): void => {
      requireRegularFile(fs.statSync(file.fd));
      if (overwrite) copyPathOverwrite(file.fd, target);
      else copyPathNoReplace(file.fd, target);
    });
  } else if (overwrite) copyPathOverwrite(requireFile(source), target);
  else copyPathNoReplace(requireFile(source), target);
}

function moveFile(owner: FileSystemFile, destination: FileSystemDestination, options?: FileSystemRecord): void {
  const source = requireFile(owner.path('write'));
  const target = fileTarget(owner, destination);
  if (recordBoolean(options, 'overwrite')) movePathReplacing(source, target);
  else movePathNoReplace(source, target);
  owner.setPath(target);
}

function renameFile(owner: FileSystemFile, name: string): void {
  const source = requireFile(owner.path('write'));
  const target = joinPath(parentPath(source), safeName(name));
  if (source === target) return;
  if (fs.accessSync(target)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_DESTINATION_EXISTS', 'Rename destination exists');
  owner.state.resolve(toFileUri(target), false, 'write');

  atomicFileOperations.publishNoReplace(source, target);
  owner.setPath(target);
}

function createDirectory(owner: FileSystemDirectory, options?: FileSystemRecord): void {
  const path = owner.path('write');
  if (fs.accessSync(path)) {
    if (!fs.statSync(path).isDirectory()) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_DIRECTORY_TYPE', 'Path points to a file');
    }
    if (recordBoolean(options, 'idempotent')) return;
    if (!recordBoolean(options, 'overwrite')) {
      throw new ExpoFileSystemError('ERR_UNABLE_TO_CREATE', 'Directory already exists');
    }
    // Match iOS: creating an existing directory with overwrite preserves its children.
    return;
  }

  fs.mkdirSync(path, recordBoolean(options, 'intermediates'));
}

function deleteDirectory(owner: FileSystemDirectory): void {
  const path = owner.path('write');
  if (!fs.accessSync(path)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANNOT_DELETE', 'Directory does not exist');
  requireDirectory(path);

  removePath(path);
}

function directoryTarget(owner: FileSystemDirectory, destination: FileSystemDestination): string {
  if (!(destination instanceof FileSystemDirectory)) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_DESTINATION', 'A directory cannot be copied or moved to a File');
  }

  const path = destination.path('write');
  if (fs.accessSync(path) && fs.statSync(path).isDirectory()) {
    return destination.state.resolve(toFileUri(joinPath(path, leafName(decodeFileUri(owner.uri())))), false, 'write');
  }
  requireDirectory(parentPath(path));
  return path;
}

function copyDirectory(owner: FileSystemDirectory, destination: FileSystemDestination, options?: FileSystemRecord): void {
  const source = requireDirectory(owner.path());
  const target = directoryTarget(owner, destination);
  assertOutsideDirectory(source, target);

  if (recordBoolean(options, 'overwrite')) copyPathOverwrite(source, target);
  else copyPathNoReplace(source, target);
}

function moveDirectory(owner: FileSystemDirectory, destination: FileSystemDestination, options?: FileSystemRecord): void {
  const source = requireDirectory(owner.path('write'));
  const target = directoryTarget(owner, destination);
  assertOutsideDirectory(source, target);

  if (recordBoolean(options, 'overwrite')) movePathReplacing(source, target);
  else movePathNoReplace(source, target);
  owner.setPath(target);
}

function renameDirectory(owner: FileSystemDirectory, name: string): void {
  const source = requireDirectory(owner.path('write'));
  const target = joinPath(parentPath(source), safeName(name));
  if (source === target) return;
  if (fs.accessSync(target)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_DESTINATION_EXISTS', 'Rename destination exists');
  owner.state.resolve(toFileUri(target), false, 'write');

  atomicFileOperations.publishNoReplace(source, target);
  owner.setPath(target);
}

function directoryExists(owner: FileSystemDirectory): boolean {
  if (owner.bundled) return owner.state.rawDirectoryExists(toRawUri(owner.rawPath(), true));
  const path = owner.probePath();
  if (path === null || !fs.accessSync(path)) return false;
  return fs.statSync(path).isDirectory();
}

function rawDirectorySize(state: FileSystemState, uri: string): number {
  let size = 0;
  state.rawList(uri).forEach((name: string): void => {
    const child = `${uri.replace(/\/$/, '')}/${encodeURIComponent(name)}`;
    if (state.rawDirectoryExists(child)) size += rawDirectorySize(state, child);
    else size += state.rawSize(child);
  });
  return size;
}

function directorySizeOrNull(owner: FileSystemDirectory): number | null {
  try {
    if (owner.bundled) return rawDirectorySize(owner.state, toRawUri(owner.rawPath(), true));
    const path = owner.probePath();
    return path === null || !fs.accessSync(path) || !fs.statSync(path).isDirectory() ? null : pathSize(path);
  } catch (_) {
    return null;
  }
}

function directoryInfo(owner: FileSystemDirectory): FileSystemInfo {
  if (!owner.bundled && fs.accessSync(owner.path())) requireDirectory(owner.path());

  const exists = directoryExists(owner);
  const result = new FileSystemInfo(exists);
  result.uri = owner.uri();
  result.isDirectory = exists ? true : null;
  if (!exists) return result;

  result.files = owner.bundled ? owner.state.rawList(toRawUri(owner.rawPath(), true)) : fs.listFileSync(owner.path());
  result.size = owner.bundled ? rawDirectorySize(owner.state, toRawUri(owner.rawPath(), true)) : pathSize(owner.path());

  if (!owner.bundled) {
    const stat = fs.statSync(owner.path());
    result.modificationTime = modifiedMilliseconds(stat);
    result.creationTime = null;
  } else {
    result.modificationTime = null;
    result.creationTime = null;
  }

  return result;
}

function listDirectoryRecords(owner: FileSystemDirectory): DirectoryEntryRecord[] {
  if (owner.bundled) {
    const base = toRawUri(owner.rawPath(), true);

    return owner.state.rawList(base).map((name: string): DirectoryEntryRecord => {
      const child = `${base}${encodeURIComponent(name)}`;
      const directory = owner.state.rawDirectoryExists(child);
      return new DirectoryEntryRecord(directory, directory ? `${child}/` : child);
    });
  }

  return fs.listFileSync(requireDirectory(owner.path())).map((name: string): DirectoryEntryRecord => {
    const target = joinPath(owner.path(), name);
    const directory = fs.lstatSync(target).isDirectory();
    return new DirectoryEntryRecord(directory, toFileUri(target, directory));
  });
}

function pathInfo(state: FileSystemState, uri: string): FileSystemInfo {
  if (isRawUri(uri)) {
    const directory = state.rawDirectoryExists(uri);
    const result = new FileSystemInfo(directory || state.rawExists(uri));
    result.isDirectory = result.exists ? directory : null;

    return result;
  }

  if (state.providerUri(uri) !== null) {
    try {
      return withFileRead(state.readSource(uri), (file: fs.File): FileSystemInfo => {
        const stat = fs.statSync(file.fd);
        const result = new FileSystemInfo(true);
        result.isDirectory = stat.isDirectory();

        return result;
      });
    } catch (_) {
      return new FileSystemInfo(false);
    }
  }
  const path = state.probe(uri);
  if (path === null || !fs.accessSync(path)) return new FileSystemInfo(false);
  const result = new FileSystemInfo(true);
  result.isDirectory = fs.statSync(path).isDirectory();
  return result;
}

function modernDownloadRequest(url: string, destination: FileSystemDestination, options?: FileSystemRecord, overwrite: boolean = false): DownloadRequest {
  const directory = destination instanceof FileSystemDirectory;
  const path = directory ? requireDirectory(destination.path('write')) : destination.path('write');
  if (!directory && fs.accessSync(path) && !overwrite && !recordBoolean(options, 'idempotent')) {
    throw new ExpoFileSystemError('ERR_DESTINATION_ALREADY_EXISTS', 'Download destination already exists');
  }

  return {
    url,
    destination: path,
    destinationIsDirectory: directory,
    validateDestination: (target: string, mode: ExpoFileAccessMode): void => { destination.state.resolve(toFileUri(target), false, mode); },
    rejectHttpErrors: true,
    idempotent: overwrite || recordBoolean(options, 'idempotent'),
    headers: recordObject(options, 'headers'),
  };
}

function legacyDownloadRequest(state: FileSystemState, url: string, destinationUri: string, options?: FileSystemRecord): DownloadRequest {
  return {
    url,
    destination: state.resolve(destinationUri, false, 'write'),
    validateDestination: (target: string, mode: ExpoFileAccessMode): void => { state.resolve(toFileUri(target), false, mode); },
    headers: recordObject(options, 'headers'),
    md5: recordBoolean(options, 'md5'),
    idempotent: true,
  };
}

function parseResumeOffset(value?: string): number {
  if (value === undefined || value.length === 0) return 0;
  const offset = Number(value);
  requireSafeInteger(offset, 'ERR_FILE_SYSTEM_INVALID_RESUME_DATA', 'Resume offset');
  return offset;
}

async function readFileRangeAsync(path: string, position: number = 0, requestedLength?: number): Promise<Uint8Array> {
  requireSafeInteger(position, 'ERR_FILE_SYSTEM_INVALID_OFFSET', 'Read position');
  if (requestedLength !== undefined) requireSafeInteger(requestedLength, 'ERR_FILE_SYSTEM_INVALID_LENGTH', 'Read length');
  const file = await fs.open(path, fileReadFlags(path));

  try {
    const stat = requireRegularFile(await fs.stat(file.fd));
    const available = Math.max(0, stat.size - position);
    const length = Math.min(requestedLength ?? available, available);
    const result = new Uint8Array(length);
    let total = 0;
    while (total < length) {
      const chunk = new ArrayBuffer(Math.min(64 * 1024, length - total));
      const count = await fs.read(file.fd, chunk, { offset: position + total, length: chunk.byteLength });
      if (count === 0) break;
      if (count < 0 || count > chunk.byteLength) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_READ_FAILED', 'Invalid native read count');
      result.set(new Uint8Array(chunk, 0, count), total);
      total += count;
    }
    return total === length ? result : result.slice(0, total);
  } finally {
    await fs.close(file);
  }
}

async function readOwnerBytesAsync(owner: FileSystemFile): Promise<Uint8Array> {
  await owner.state.ready();
  return owner.bundled ? owner.state.rawBytesAsync(owner.rawUri()) : readFileRangeAsync(owner.state.readSource(owner.uri()));
}

async function writeBytesFileAsync(path: string, bytes: Uint8Array, append: boolean): Promise<void> {
  const mode = fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.NOFOLLOW | (append ? fs.OpenMode.APPEND : fs.OpenMode.TRUNC);
  const file = await fs.open(path, mode);
  try {
    let total = 0;
    while (total < bytes.byteLength) {
      const chunk = bytes.slice(total, Math.min(total + 64 * 1024, bytes.byteLength));
      const count = await fs.write(file.fd, chunk.buffer, { length: chunk.byteLength });
      if (count <= 0 || count > chunk.byteLength) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_WRITE_FAILED', 'Invalid native write count');
      total += count;
    }
  } finally {
    await fs.close(file);
  }
}

async function removePathAsync(path: string): Promise<void> {
  const stat = await fs.lstat(path);
  if (stat.isSymbolicLink()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_SYMLINK', 'Symbolic link encountered');
  if (stat.isDirectory()) {
    for (const name of await fs.listFile(path)) await removePathAsync(joinPath(path, name));
    await fs.rmdir(path);
  } else {
    await fs.unlink(path);
  }
}

async function copyPathAsync(source: string, target: string): Promise<void> {
  assertSeparatePaths(source, target);
  const stat = await fs.lstat(source);
  if (stat.isSymbolicLink()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_SYMLINK', 'Symbolic link encountered');
  if (stat.isFile()) {
    await fs.copyFile(source, target, 0);
    return;
  }
  if (!stat.isDirectory()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_PATH', 'Unsupported file type');
  await fs.mkdir(target, false);
  for (const name of await fs.listFile(source)) await copyPathAsync(joinPath(source, name), joinPath(target, name));
}

async function copyPathOverwriteAsync(source: string | number, target: string): Promise<void> {
  if (typeof source === 'string') assertSeparatePaths(source, target);

  const staging = await fs.mkdtemp(joinPath(parentPath(target), '.expo-copy-XXXXXX'));
  const replacement = joinPath(staging, 'replacement');
  const previous = joinPath(staging, 'previous');
  let preserve = false;
  let committed = false;

  try {
    if (typeof source === 'number') await fs.copyFile(source, replacement);
    else await copyPathAsync(source, replacement);

    const exists = await fs.access(target);
    if (exists) await fs.rename(target, previous);

    try {
      atomicFileOperations.publishNoReplace(replacement, target);
      committed = true;
    } catch (error) {
      if (exists) {
        try {
          atomicFileOperations.publishNoReplace(previous, target);
        } catch (cause) {
          preserve = true;

          throw new ExpoFileSystemError(
            'ERR_FILE_SYSTEM_COPY_ROLLBACK_FAILED',
            `The previous destination is retained at '${previous}': ${cleanErrorMessage(cause as Object)}`,
            cause as Object,
          );
        }
      }

      throw new ExpoFileSystemError(
        error instanceof ExpoModuleError ? error.code : String(Reflect.get(error as Object, 'code') ?? 'ERR_FILE_SYSTEM'),
        error instanceof Error ? error.message : String(error),
        error instanceof ExpoModuleError ? error.cause : (error as Object),
        error instanceof ExpoModuleError ? error.path : undefined,
      );
    }
  } finally {
    if (!preserve) await cleanupStagingAsync(staging, committed);
  }
}

async function copyPathNoReplaceAsync(source: string | number, target: string): Promise<void> {
  if (typeof source === 'string') assertSeparatePaths(source, target);
  if (await fs.access(target)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_DESTINATION_EXISTS', 'Copy destination exists');

  const staging = await fs.mkdtemp(joinPath(parentPath(target), '.expo-copy-XXXXXX'));
  let committed = false;

  try {
    const replacement = joinPath(staging, 'replacement');
    if (typeof source === 'number') await fs.copyFile(source, replacement);
    else await copyPathAsync(source, replacement);
    atomicFileOperations.publishNoReplace(replacement, target);
    committed = true;
  } finally {
    await cleanupStagingAsync(staging, committed);
  }
}

async function copyFileSourceAsync(source: string, target: string, overwrite: boolean): Promise<void> {
  if (source.startsWith('/')) {
    if (overwrite) await copyPathOverwriteAsync(source, target);
    else await copyPathNoReplaceAsync(source, target);
    return;
  }

  const file = await fs.open(source, fileReadFlags(source));

  try {
    requireRegularFile(await fs.stat(file.fd));
    if (overwrite) await copyPathOverwriteAsync(file.fd, target);
    else await copyPathNoReplaceAsync(file.fd, target);
  } finally {
    await fs.close(file);
  }
}

async function movePathNoReplaceAsync(source: string, target: string): Promise<void> {
  assertSeparatePaths(source, target);
  try {
    atomicFileOperations.publishNoReplace(source, target);
    return;
  } catch (error) {
    if (Reflect.get(error as Object, 'code') !== 'ERR_FILE_SYSTEM_CROSS_DEVICE') {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_MOVE_FAILED', cleanErrorMessage(error as Object), error as Object);
    }
  }

  await copyPathNoReplaceAsync(source, target);
  try {
    await removePathAsync(source);
  } catch (error) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_MOVE_SOURCE_RETAINED', 'Destination created; source could not be removed', error as Object);
  }
}

async function movePathReplacingAsync(source: string, target: string): Promise<void> {
  assertSeparatePaths(source, target);
  if (!(await fs.access(target))) {
    await movePathNoReplaceAsync(source, target);
    return;
  }

  const staging = await fs.mkdtemp(joinPath(parentPath(target), '.expo-move-XXXXXX'));
  const previous = joinPath(staging, 'previous');
  let preserve = false;
  let committed = false;

  try {
    await fs.rename(target, previous);
    try {
      await movePathNoReplaceAsync(source, target);
      committed = true;
    } catch (error) {
      if (await fs.access(target)) {
        preserve = true;
        throw new ExpoFileSystemError('ERR_FILE_SYSTEM_MOVE_FAILED', `Move did not finish; previous destination retained at '${previous}': ${cleanErrorMessage(error as Object)}`, error as Object);
      } else {
        try { atomicFileOperations.publishNoReplace(previous, target); } catch (cause) {
          preserve = true;
          throw new ExpoFileSystemError('ERR_FILE_SYSTEM_MOVE_ROLLBACK_FAILED', `Previous destination retained at '${previous}'`, cause as Object);
        }
      }
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_MOVE_FAILED', cleanErrorMessage(error as Object), error as Object);
    }
  } finally {
    if (!preserve) await cleanupStagingAsync(staging, committed);
  }
}

async function relocateAsync(owner: FileSystemDestination, destination: FileSystemDestination, options: FileSystemRecord | undefined, move: boolean): Promise<void> {
  await owner.state.ready();
  await destination.state.ready();
  const overwrite = recordBoolean(options, 'overwrite');
  if (!move && owner instanceof FileSystemFile && owner.provider !== null) {
    await copyFileSourceAsync(owner.state.readSource(owner.provider), fileTarget(owner, destination), overwrite);
    return;
  }

  const path = owner.path(move ? 'write' : 'read');
  const source = owner instanceof FileSystemDirectory ? requireDirectory(path) : requireFile(path);
  const target = owner instanceof FileSystemDirectory ? directoryTarget(owner, destination) : fileTarget(owner, destination);
  if (move) {
    if (overwrite) await movePathReplacingAsync(source, target);
    else await movePathNoReplaceAsync(source, target);
    owner.setPath(target);
  } else if (overwrite) await copyPathOverwriteAsync(source, target);
  else await copyPathNoReplaceAsync(source, target);
}

async function movePathAsync(source: string, target: string): Promise<void> {
  assertSeparatePaths(source, target);
  try {
    await fs.rename(source, target);
    return;
  } catch (error) {
    // The platform documents this code as EXDEV: the source is on another volume.
    if (Number(Reflect.get(error as Object, 'code')) !== 13900016) {
      throw new ExpoFileSystemError(
        error instanceof ExpoModuleError ? error.code : String(Reflect.get(error as Object, 'code') ?? 'ERR_FILE_SYSTEM'),
        error instanceof Error ? error.message : String(error),
        error instanceof ExpoModuleError ? error.cause : (error as Object),
        error instanceof ExpoModuleError ? error.path : undefined,
      );
    }
  }
  await copyPathOverwriteAsync(source, target);
  try {
    await removePathAsync(source);
  } catch (error) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_MOVE_SOURCE_RETAINED', 'Destination created; source could not be removed', error as Object);
  }
}

async function pathSizeAsync(path: string): Promise<number> {
  const stat = await fs.lstat(path);
  if (stat.isSymbolicLink()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_SYMLINK', 'Symbolic link encountered');
  if (stat.isFile()) return stat.size;
  if (!stat.isDirectory()) return 0;
  let size = 0;
  for (const name of await fs.listFile(path)) size += await pathSizeAsync(joinPath(path, name));
  return size;
}

async function legacyInfoAsync(state: FileSystemState, uri: string, includeMd5: boolean): Promise<FileSystemInfo> {
  await state.ready();
  if (isPackagedResource(uri)) return state.rawInfoAsync(uri, includeMd5);

  const provider = state.providerUri(uri);
  if (provider !== null) {
    let file: fs.File;
    try {
      file = await fs.open(state.readSource(provider), fileReadFlags(provider));
    } catch (error) {
      if (Number(Reflect.get(error as Object, 'code')) !== FILE_NOT_FOUND_ERROR) throw error as Error;
      const missing = new FileSystemInfo(false);
      missing.isDirectory = false;

      return missing;
    }

    try {
      const stat = requireRegularFile(await fs.stat(file.fd));
      const result = new FileSystemInfo(true);
      result.uri = provider;
      result.isDirectory = false;
      result.size = stat.size;
      result.modificationTime = modifiedMilliseconds(stat) / 1000;
      if (includeMd5) {
        const hash = fileHash.createHash('md5');
        const chunk = new ArrayBuffer(NETWORK_FILE_BUFFER_BYTES);

        while (true) {
          const count = await fs.read(file.fd, chunk, { length: chunk.byteLength });
          if (count <= 0) break;
          hash.update(count === chunk.byteLength ? chunk : chunk.slice(0, count));
        }

        result.md5 = hash.digest().toLowerCase();
      }

      return result;
    } finally {
      await fs.close(file);
    }
  }
  const path = state.resolve(uri);
  let stat: fs.Stat;
  try {
    stat = await fs.stat(path);
  } catch (error) {
    if (Number(Reflect.get(error as Object, 'code')) !== 13900002) {
      throw new ExpoFileSystemError(
        error instanceof ExpoModuleError ? error.code : String(Reflect.get(error as Object, 'code') ?? 'ERR_FILE_SYSTEM'),
        error instanceof Error ? error.message : String(error),
        error instanceof ExpoModuleError ? error.cause : (error as Object),
        error instanceof ExpoModuleError ? error.path : undefined,
      );
    }
    const missing = new FileSystemInfo(false);
    missing.isDirectory = false;
    return missing;
  }
  const result = new FileSystemInfo(true);
  result.isDirectory = stat.isDirectory();
  result.uri = toFileUri(path, result.isDirectory);
  result.size = result.isDirectory ? await pathSizeAsync(path) : stat.size;
  result.modificationTime = modifiedMilliseconds(stat) / 1000;
  if (includeMd5 && !result.isDirectory) result.md5 = (await fileHash.hash(path, 'md5')).toLowerCase();
  return result;
}

async function legacyReadAsync(state: FileSystemState, uri: string, options?: FileSystemRecord): Promise<string> {
  const encoding = recordEncoding(options);
  await state.ready();
  const position = recordNumber(options, 'position') ?? 0;
  const length = recordNumber(options, 'length');
  requireSafeInteger(position, 'ERR_FILE_SYSTEM_INVALID_OFFSET', 'Read position');
  if (length !== undefined) requireSafeInteger(length, 'ERR_FILE_SYSTEM_INVALID_LENGTH', 'Read length');
  let bytes: Uint8Array;
  if (isPackagedResource(uri)) {
    bytes = await state.rawBytesAsync(uri, true);
    bytes = bytes.slice(position, length === undefined ? undefined : position + length);
  } else {
    bytes = await readFileRangeAsync(state.readSource(uri), position, length);
  }

  return encoding === 'base64' ? base64Encode(bytes) : new util.TextDecoder('utf-8').decode(bytes);
}

function legacyUploadRequest(state: FileSystemState, url: string, sourceUri: string, options: FileSystemRecord): UploadRequest {
  return {
    url,
    source: requireFile(state.resolve(sourceUri, true)),
    headers: recordObject(options, 'headers'),
    httpMethod: recordString(options, 'httpMethod'),
    uploadType: recordUploadType(options),
    fieldName: recordString(options, 'fieldName'),
    mimeType: recordString(options, 'mimeType'),
    parameters: recordObject(options, 'parameters'),
  };
}

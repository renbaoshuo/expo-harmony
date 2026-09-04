import {
  ExpoFunction,
  ExpoEither,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoSharedObject,
  ExpoSharedObjectClassDefinition,
  ExpoSharedObjectTypes,
  ExpoSharedRef,
  ExpoValueType,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { fileUri } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import fileHash from '@ohos.file.hash';
import statvfs from '@ohos.file.statvfs';
import picker from '@ohos.file.picker';
import fileShare from '@ohos.fileshare';
import uniformTypeDescriptor from '@ohos.data.uniformTypeDescriptor';
import { rcp } from '@kit.RemoteCommunicationKit';
import url from '@ohos.url';
import util from '@ohos.util';
import atomicFileOperations from 'libexpo_file_system_atomic.so';
import { PickerPermissionStore } from './PickerPermissionStore';
import { ExpoFileSystemError, ProgressCadence, uploadMethodPolicy, asFileSystemError, parseContentRange, isRedirectStatus } from './NetworkPolicy';

const NETWORK_FILE_BUFFER_BYTES: number = 64 * 1024;
// Match the system redirect limit, while handling each response before publishing a file.
const MAX_DOWNLOAD_REDIRECTS: number = 50;
const NETWORK_IDLE_TIMEOUT_MS: number = 60_000;
const FILE_EXISTS_ERROR: number = 13900015;

interface NetworkTask {
  session?: rcp.Session;
  request?: rcp.Request;
  transferred: number;
  cancelled: boolean;
  paused: boolean;
  done: Promise<void>;
  finish: () => void;
  cancellation: Promise<rcp.Response>;
  rejectCancellation: (error: Error) => void;
  pendingWrite: Promise<void>;
  failure?: ExpoModuleError;
  expectedTransfer: number;
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

class ExpoFileSystemService {
  private readonly context: ExpoModuleContext;
  private readonly progress: (eventName: string, payload: ProgressPayload) => void;
  private readonly pickerPermission?: (originalUri: string, normalizedUri: string, directory: boolean, persisted: boolean) => Promise<void>;
  private readonly tasks: Map<string, NetworkTask> = new Map();
  private destroyed: boolean = false;
  private destruction: Promise<void> = Promise.resolve();

  constructor(
    context: ExpoModuleContext,
    progress: (eventName: string, payload: ProgressPayload) => void,
    pickerPermission?: (originalUri: string, normalizedUri: string, directory: boolean, persisted: boolean) => Promise<void>,
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

  async pickFile(initialUri?: string, mimeType?: string): Promise<string> {
    this.assertActive();
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    if (initialUri) options.defaultFilePathUri = initialUri;
    const filters = mimeSuffixFilters(mimeType);
    if (filters !== null) options.fileSuffixFilters = filters;
    const uris = await new picker.DocumentViewPicker(this.context.uiAbilityContext).select(options);
    this.assertActive();
    if (uris.length === 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_PICKER_CANCELLED');
    return this.selectedUri(uris[0], false);
  }

  async pickDirectory(initialUri?: string): Promise<string> {
    this.assertActive();
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.selectMode = picker.DocumentSelectMode.FOLDER;
    if (initialUri) options.defaultFilePathUri = initialUri;
    const uris = await new picker.DocumentViewPicker(this.context.uiAbilityContext).select(options);
    this.assertActive();
    if (uris.length === 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_PICKER_CANCELLED');
    return this.selectedUri(uris[0], true);
  }

  private async selectedUri(originalUri: string, directory: boolean): Promise<string> {
    const persisted = await persistPickerPermission(originalUri);
    const normalized = normalizePickerUri(originalUri);
    this.assertActive();
    if (this.pickerPermission !== undefined) await this.pickerPermission(originalUri, normalized, directory, persisted);
    return normalized;
  }

  async pickDirectoryPermission(initialUri?: string): Promise<PermissionRecord> {
    try {
      return new PermissionRecord(true, await this.pickDirectory(initialUri));
    } catch (error) {
      if (error instanceof ExpoModuleError && error.code === 'ERR_FILE_SYSTEM_PICKER_CANCELLED') return new PermissionRecord(false);
      throw asFileSystemError(error as Object);
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
    const cancellation = new Promise<rcp.Response>((_: (response: rcp.Response) => void, reject: (error: Error) => void): void => {
      rejectCancellation = reject;
    });
    cancellation.catch((_: Object): void => {});
    const task: NetworkTask = {
      transferred,
      cancelled: false,
      paused: false,
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
    task.paused = true;
    this.cancelTask(task);
    await task.done;
    if (task.failure !== undefined) throw task.failure;
    return new ResumeRecord(String(task.transferred));
  }

  private async fetch(task: NetworkTask, request: rcp.Request): Promise<rcp.Response> {
    assertNetworkTask(task);
    if (task.session === undefined) task.session = rcp.createSession();
    task.request = request;
    return Promise.race([task.session.fetch(request), task.cancellation]);
  }

  async download(input: DownloadRequest): Promise<DownloadResult | RawDownloadResult | null> {
    const uuid = input.uuid ?? util.generateRandomUUID();
    const task = this.beginTask(uuid, input.resumeFrom ?? 0);
    try {
      if (isPackagedResource(input.url)) return await this.copyPackagedResource(input, uuid, task);
      return await this.downloadHttp(input, uuid, task);
    } catch (error) {
      if (task.cancelled && task.failure === undefined) return null;
      throw task.failure ?? asFileSystemError(error as Object, 'ERR_UNABLE_TO_DOWNLOAD');
    } finally {
      this.finishTask(uuid, task);
    }
  }

  private async downloadHttp(input: DownloadRequest, uuid: string, task: NetworkTask): Promise<DownloadResult> {
    let requestUrl = input.url;
    let requestHeaders = copyHeaders(input.headers);
    let resumeFrom = input.resumeFrom ?? 0;
    if (resumeFrom > 0 && (!(await fs.access(input.destination)) || (await fs.stat(input.destination)).size !== resumeFrom)) resumeFrom = 0;
    const callerRange = resumeFrom === 0 && headerValue(requestHeaders, 'range') !== null;
    task.transferred = resumeFrom;
    if (resumeFrom > 0) requestHeaders['range'] = `bytes=${resumeFrom}-`;
    // A byte range must address the bytes written to disk, not a compressed representation.
    if (resumeFrom > 0) requestHeaders['accept-encoding'] = 'identity';

    for (let redirects = 0; redirects <= MAX_DOWNLOAD_REDIRECTS; redirects += 1) {
      assertNetworkTask(task);
      let destination = input.destination;
      const parent = input.destinationIsDirectory ? destination : destination.slice(0, destination.lastIndexOf('/'));
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
              callbackFailure = asFileSystemError(error as Object, 'ERR_FILE_SYSTEM_WRITE_FAILED');
              throw callbackFailure;
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
        await closeOutput();
        assertNetworkTask(task);
        const location = headerValue(response.headers, 'location');
        if (isRedirectStatus(response.statusCode) && location !== null) {
          if (redirects === MAX_DOWNLOAD_REDIRECTS) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_TOO_MANY_REDIRECTS');
          const nextUrl = redirectedDownloadUrl(requestUrl, location);
          if (new url.URL(requestUrl).origin !== new url.URL(nextUrl).origin) {
            requestHeaders = copyHeaders(requestHeaders, ['authorization', 'proxy-authorization', 'cookie']);
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
        if (input.destinationIsDirectory) destination = joinPath(input.destination, suggestedFilename(requestUrl, response.headers));
        if (receivedBytes === 0) {
          await ensureOutput();
          await closeOutput();
        }
        assertNetworkTask(task);
        await publishDownload(temporary, destination, effectiveResumeFrom, input.idempotent === true, task);
        committed = true;
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
        const usableResponse =
          receivedStatus === 200 ||
          (receivedStatus === 206 &&
            range !== null &&
            (encoding === null || encoding.toLowerCase() === 'identity') &&
            range.start === resumeFrom &&
            receivedBytes <= range.end - range.start + 1);
        effectiveResumeFrom = receivedStatus === 206 ? resumeFrom : 0;
        // Custom ranges cannot be resumed using a byte offset into the full resource.
        if (
          !callerRange &&
          !responseComplete &&
          !this.destroyed &&
          input.emitProgress &&
          receivedBytes > 0 &&
          usableResponse &&
          (callbackFailure === undefined || task.cancelled)
        ) {
          try {
            await publishDownload(temporary, input.destination, effectiveResumeFrom, true);
            committed = true;
            task.transferred = effectiveResumeFrom + receivedBytes;
          } catch (commitError) {
            task.failure = asFileSystemError(commitError as Object, 'ERR_FILE_SYSTEM_WRITE_FAILED');
            task.transferred = resumeFrom;
          }
        } else if (callerRange) {
          // Even a published range is not a prefix of the full resource (e.g. pause during hashing).
          task.transferred = 0;
        } else if (!committed) task.transferred = resumeFrom;
        if (callbackFailure !== undefined && !task.cancelled) throw callbackFailure;
        throw error as Error;
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
    const parent = destination.slice(0, destination.lastIndexOf('/'));
    const temporaryDirectory = await fs.mkdtemp(joinPath(parent, '.expo-download-XXXXXX'));
    const temporary = joinPath(temporaryDirectory, 'body');
    const resources = this.context.uiAbilityContext.resourceManager;
    let opened = false;
    try {
      assertNetworkTask(task);
      const descriptor = await resources.getRawFd(resourceName);
      opened = true;
      assertNetworkTask(task);
      const output = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.lseek(descriptor.fd, descriptor.offset, fs.WhenceType.SEEK_SET);
        const buffer = new ArrayBuffer(NETWORK_FILE_BUFFER_BYTES);
        let copied = 0;
        task.expectedTransfer = descriptor.length;
        while (copied < descriptor.length) {
          assertNetworkTask(task);
          const count = await fs.read(descriptor.fd, buffer, { length: Math.min(buffer.byteLength, descriptor.length - copied) });
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
      if (input.idempotent) await fs.moveFile(temporary, destination, 0);
      else atomicFileOperations.publishNoReplace(temporary, destination);
      if (input.emitProgress) this.emitDownloadProgress(task, uuid, true);
      const md5 = input.md5 ? (await fileHash.hash(destination, 'md5')).toLowerCase() : undefined;
      assertNetworkTask(task);
      return new RawDownloadResult(toFileUri(destination), md5);
    } finally {
      if (task.cancelled) task.transferred = 0;
      try {
        if (opened) await resources.closeRawFd(resourceName);
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
    const uuid = input.uuid ?? util.generateRandomUUID();
    const task = this.beginTask(uuid);
    try {
      const headers = copyHeaders(input.headers, input.uploadType === 1 ? ['content-type'] : []);
      const method = uploadMethodPolicy(input.httpMethod).method;
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
      throw asFileSystemError(error as Object, 'ERR_FILE_SYSTEM_UPLOAD_FAILED');
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

  const uri = `file://${path
    .split('/')
    .map((segment: string): string =>
      encodeURIComponent(segment).replace(/[!'()*]/g, (character: string): string => `%${character.charCodeAt(0).toString(16).toUpperCase()}`),
    )
    .join('/')}`;
  return directory && !uri.endsWith('/') ? `${uri}/` : uri;
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
    uniformTypeDescriptor.getUniformDataTypesByMIMEType(normalized).forEach((typeId: string): void => {
      uniformTypeDescriptor.getTypeDescriptor(typeId).filenameExtensions.forEach((extension: string): void => {
        if (!extension.startsWith('.') || extension.includes(',') || extension.includes('|')) return;
        if (!extensions.includes(extension)) extensions.push(extension);
      });
    });
    if (extensions.length === 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNSUPPORTED_MIME_TYPE', mimeType);
    return [`${normalized}|${extensions.join(',')}`];
  } catch (error) {
    throw asFileSystemError(error as Object, 'ERR_FILE_SYSTEM_UNSUPPORTED_MIME_TYPE');
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
      // Request no whole-transfer deadline; validate the platform's zero-timeout behavior
      // with the long-transfer device scenario. Keep connection/inactivity limits separate.
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
  // ordering; this package's minimum SDK is 23. Always put the file part last.
  form.keys = entries.map((entry): string => entry[0]);
  return form;
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
  return error instanceof Error ? error.message : String(error);
}

type FileSystemRecord = Record<string, ESObject>;

class Capability {
  path: string;
  directory: boolean;

  constructor(path: string, directory: boolean) {
    this.path = path;
    this.directory = directory;
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
    this.permissions.restoreActive((uri: string, directory: boolean): void => {
      this.grant(normalizePickerUri(uri), directory);
    });
    this.permissionRestore = this.permissions
      .restore((uri: string, directory: boolean): void => {
        this.grant(normalizePickerUri(uri), directory);
      })
      .catch((error: Object): void => {
        context.logger.warn(`Could not restore Expo file picker permissions: ${cleanErrorMessage(error)}`);
      });
  }

  async ready(): Promise<void> {
    await this.permissionRestore;
  }

  async rememberPickerGrant(originalUri: string, uri: string, directory: boolean, persisted: boolean): Promise<void> {
    await this.ready();
    this.grant(uri, directory);
    if (persisted) await this.permissions.remember(originalUri, directory);
  }

  grant(uri: string, directory: boolean): void {
    const path = decodeFileUri(uri);
    this.assertNoSymlinkSegments(path);
    if (!this.capabilities.some((capability: Capability): boolean => capability.path === path && capability.directory === directory)) {
      this.capabilities.push(new Capability(path, directory));
    }
  }

  resolve(uri: string, mustExist: boolean = false): string {
    const path = decodeFileUri(uri);
    let allowed = isInside(this.documentPath, path) || isInside(this.cachePath, path);

    if (!allowed) {
      allowed = this.capabilities.some((capability: Capability): boolean =>
        capability.directory ? isInside(capability.path, path) : capability.path === path,
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
      const descriptor = await manager.getRawFd(name);
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
            const count = await fs.read(descriptor.fd, chunk, { offset: descriptor.offset + offset, length: chunk.byteLength });
            if (count <= 0) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_READ_FAILED', 'Unexpected end of bundled resource');
            hash.update(count === chunk.byteLength ? chunk : chunk.slice(0, count));
            offset += count;
          }
          result.md5 = hash.digest().toLowerCase();
        }
        return result;
      } finally {
        await manager.closeRawFd(name);
      }
    } catch (error) {
      if (!isMissingRawResource(error as Object)) throw error as Error;
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
      throw error as Error;
    }
  }

  rawDirectoryExists(uri: string, allowSchemeLess: boolean = false): boolean {
    const name = rawPathFromUri(uri, allowSchemeLess, true);
    try {
      return name.length === 0 || this.context.uiAbilityContext.resourceManager.isRawDir(name);
    } catch (error) {
      if (isMissingRawResource(error as Object)) return false;
      throw error as Error;
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
      if (!fs.accessSync(current)) break;
      if (fs.lstatSync(current).isSymbolicLink()) {
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

  constructor(context: ExpoModuleContext, state: FileSystemState, uri: string) {
    super(context);
    this.state = state;
    this.bundled = isRawUri(uri);
    this.rawPathValue = this.bundled ? rawPathFromUri(uri) : '';
    if (!this.bundled) this.pathValue = decodeFileUri(uri);
  }

  path(): string {
    if (this.bundled) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME', 'Bundled resources are read-only');
    }
    return this.state.resolve(toFileUri(this.pathValue));
  }

  probePath(): string | null {
    return this.bundled ? null : this.state.probe(toFileUri(this.pathValue));
  }

  uri(): string {
    return this.bundled ? toAssetUri(this.rawPathValue, false) : toFileUri(this.pathValue);
  }

  rawUri(): string {
    return toAssetUri(this.rawPathValue, false);
  }

  setPath(path: string): void {
    this.pathValue = this.state.resolve(toFileUri(path));
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
    if (!this.bundled) this.pathValue = decodeFileUri(uri);
  }

  path(): string {
    if (this.bundled) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME', 'Bundled resources are read-only');
    }
    return this.state.resolve(toFileUri(this.pathValue));
  }

  probePath(): string | null {
    return this.bundled ? null : this.state.probe(toFileUri(this.pathValue));
  }

  rawPath(): string {
    return this.rawPathValue;
  }

  uri(): string {
    return this.bundled ? toAssetUri(this.rawPathValue, true) : toFileUri(this.pathValue, true);
  }

  setPath(path: string): void {
    this.pathValue = this.state.resolve(toFileUri(path));
  }
}

class FileSystemFileHandle extends ExpoSharedRef<fs.File> {
  private file: fs.File | null;
  private offsetValue: number = 0;

  constructor(context: ExpoModuleContext, owner: FileSystemFile) {
    super(context, 'expo-file-system.file-handle', openFileHandle(owner));
    this.file = this.value;
  }

  read(count: number): Uint8Array {
    requireSafeInteger(count, 'ERR_FILE_SYSTEM_INVALID_LENGTH', 'Read length');
    const file = this.requireOpen();
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
    const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    writeAll(file.fd, buffer, this.offsetValue, (count: number): void => {
      this.offsetValue += count;
    });
  }

  close(): void {
    if (this.file === null) return;
    fs.closeSync(this.file.fd);
    this.file = null;
  }

  offset(): number | null {
    return this.file === null ? null : this.offsetValue;
  }

  setOffset(value: number | null): void {
    if (value === null) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_OFFSET', 'Offset cannot be null');
    }
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

  constructor(context: ExpoModuleContext) {
    super(context);
    this.state = new FileSystemState(context);
    this.service = new ExpoFileSystemService(
      context,
      (_eventName: string, _payload: ProgressPayload): void => {},
      (original: string, uri: string, directory: boolean, persisted: boolean): Promise<void> =>
        this.state.rememberPickerGrant(original, uri, directory, persisted),
    );
  }

  fileSystemState(): FileSystemState {
    return this.state;
  }

  override definition(): ExpoModuleDefinition {
    const handleClass = new ExpoSharedObjectClassDefinition<FileSystemFileHandle>('FileSystemFileHandle')
      .sharedRef('expo-file-system.file-handle')
      .construct(
        ExpoFunction.ownedTyped1(
          FILE_TYPE,
          (context: ExpoModuleContext, owner: FileSystemFile): FileSystemFileHandle => new FileSystemFileHandle(context, owner),
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
        if (!owner.bundled) decodeFileUri(owner.uri());
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
      .syncFunction(
        'copy',
        ExpoFunction.ownedTyped1(DESTINATION_TYPE, (owner: FileSystemFile, destination: FileSystemDestination): void => copyFile(owner, destination)),
      )
      .syncFunction(
        'move',
        ExpoFunction.ownedTyped1(DESTINATION_TYPE, (owner: FileSystemFile, destination: FileSystemDestination): void => moveFile(owner, destination)),
      )
      .syncFunction(
        'rename',
        ExpoFunction.ownedTyped1(ExpoValueTypes.string(), (owner: FileSystemFile, name: string): void => renameFile(owner, name)),
      )
      .syncFunction(
        'open',
        ExpoFunction.ownedTyped0(
          (owner: FileSystemFile): FileSystemFileHandle => handleClass.instance(new FileSystemFileHandle(this.context, owner)),
        ).returns(handleClass.valueType()),
      )
      .property('exists', ExpoValueTypes.boolean(), (owner: FileSystemFile): boolean => fileExists(owner))
      .property('modificationTime', ExpoValueTypes.number().nullable(), (owner: FileSystemFile): number | null => fileTimestamp(owner, false))
      .property('creationTime', ExpoValueTypes.number().nullable(), (owner: FileSystemFile): number | null => fileTimestamp(owner, true))
      .property('uri', ExpoValueTypes.string(), (owner: FileSystemFile): string => owner.uri())
      .property('contentUri', ExpoValueTypes.string(), (owner: FileSystemFile): string =>
        fileUri.getUriFromPath(decodeFileUri(owner.bundled ? owner.state.materializeRawContent(owner.rawUri()) : owner.uri())),
      )
      .property('md5', ExpoValueTypes.string().nullable(), (owner: FileSystemFile): string | null => fileMd5OrNull(owner))
      .property('size', ExpoValueTypes.number(), (owner: FileSystemFile): number => fileSize(owner))
      .property('type', ExpoValueTypes.string(), (owner: FileSystemFile): string => mimeTypeForPath(owner.uri()));

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
          const target = joinPath(requireDirectory(owner.path()), safeName(name));
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
            const target = joinPath(requireDirectory(owner.path()), safeName(name));
            if (fs.accessSync(target)) throw new ExpoFileSystemError('ERR_UNABLE_TO_CREATE', 'Child file already exists');
            createEmptyFile(target, true);
            return fileClass.instance(new FileSystemFile(this.context, owner.state, toFileUri(target)));
          },
        ).returns(fileClass.valueType()),
      )
      .syncFunction(
        'copy',
        ExpoFunction.ownedTyped1(DESTINATION_TYPE, (owner: FileSystemDirectory, destination: FileSystemDestination): void =>
          copyDirectory(owner, destination),
        ),
      )
      .syncFunction(
        'move',
        ExpoFunction.ownedTyped1(DESTINATION_TYPE, (owner: FileSystemDirectory, destination: FileSystemDestination): void =>
          moveDirectory(owner, destination),
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

    return new ExpoModuleDefinition()
      .name('FileSystem')
      .constant('documentDirectory', (): string => toFileUri(this.state.documentPath, true))
      .constant('cacheDirectory', (): string => toFileUri(this.state.cachePath, true))
      .constant('bundleDirectory', 'asset:///')
      .constant('appleSharedContainers', new Object())
      .property('totalDiskSpace', ExpoValueTypes.number(), (): number => statvfs.getTotalSizeSync(this.state.documentPath))
      .property('availableDiskSpace', ExpoValueTypes.number(), (): number => statvfs.getFreeSizeSync(this.state.documentPath))
      .syncFunction(
        'info',
        ExpoFunction.typed1(ExpoValueTypes.string(), (uri: string): FileSystemInfo => pathInfo(this.state, uri)),
      )
      .asyncFunction(
        'downloadFileAsync',
        ExpoFunction.typed3(
          ExpoValueTypes.string(),
          DESTINATION_TYPE,
          RECORD_TYPE.optional(),
          async (url: string, destination: FileSystemDestination, options?: FileSystemRecord): Promise<string> => {
            await destination.state.ready();
            const request = modernDownloadRequest(url, destination, options);
            const result = await this.service.download(request);
            if (result === null) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANCELLED');
            return result.uri;
          },
        ),
      )
      .asyncFunction(
        'pickDirectoryAsync',
        ExpoFunction.typed1(ExpoValueTypes.string().optional(), async (initialUri?: string): Promise<UriRecord> => {
          const uri = await this.service.pickDirectory(initialUri);
          this.state.grant(uri, true);
          return new UriRecord(uri);
        }),
      )
      .asyncFunction(
        'pickFileAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string().optional(),
          ExpoValueTypes.string().optional(),
          async (initialUri?: string, mimeType?: string): Promise<UriRecord> => {
            const uri = await this.service.pickFile(initialUri, mimeType);
            this.state.grant(uri, false);
            return new UriRecord(uri);
          },
        ),
      )
      .sharedObjectClass(fileClass)
      .sharedObjectClass(handleClass)
      .sharedObjectClass(directoryClass)
      .onPrepareForReload(async (): Promise<void> => this.service.destroy())
      .onDestroy((): void => this.service.onDestroy())
      .onAbilityDestroy((): void => this.service.onDestroy());
  }
}

export class ExponentFileSystemModule extends ExpoModule {
  private readonly service: ExpoFileSystemService;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.service = new ExpoFileSystemService(
      context,
      (eventName: string, payload: ProgressPayload): void => this.sendEvent(eventName, payload),
      (original: string, uri: string, directory: boolean, persisted: boolean): Promise<void> =>
        this.fileState().rememberPickerGrant(original, uri, directory, persisted),
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
      .constant('bundleDirectory', 'asset:///')
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
            await writeBytesFileAsync(state.resolve(uri), bytes, recordBoolean(options, 'append'));
          },
        ),
      )
      .asyncFunction(
        'deleteAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), RECORD_TYPE.optional(), async (uri: string, options?: FileSystemRecord): Promise<void> => {
          const state = this.fileState();
          await state.ready();
          const path = state.resolve(uri);
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
          await movePathAsync(state.resolve(sourceUri, true), state.resolve(requiredRecordString(options, 'to')));
        }),
      )
      .asyncFunction(
        'copyAsync',
        ExpoFunction.typed1(RECORD_TYPE, async (options: FileSystemRecord): Promise<void> => {
          const state = this.fileState();
          await state.ready();
          const sourceUri = requiredRecordString(options, 'from');
          const target = state.resolve(requiredRecordString(options, 'to'));
          if (isPackagedResource(sourceUri)) {
            await this.service.download({ url: sourceUri, destination: target, idempotent: true });
            return;
          }
          await copyPathOverwriteAsync(state.resolve(sourceUri, true), target);
        }),
      )
      .asyncFunction(
        'makeDirectoryAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), RECORD_TYPE.optional(), async (uri: string, options?: FileSystemRecord): Promise<void> => {
          const state = this.fileState();
          await state.ready();
          await makeDirectoryPathAsync(state.resolve(uri), recordBoolean(options, 'intermediates'));
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
          await this.fileState().ready();
          return fileUri.getUriFromPath(this.fileState().resolve(uri, true));
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
            await this.fileState().ready();
            const request = legacyDownloadRequest(this.fileState(), url, destinationUri, options);
            request.uuid = uuid;
            request.emitProgress = true;
            request.resumeFrom = parseResumeOffset(resumeData);
            return this.service.download(request);
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
            await this.fileState().ready();
            const request = legacyUploadRequest(this.fileState(), url, sourceUri, options);
            request.uuid = uuid;
            request.emitProgress = true;
            return this.service.upload(request);
          },
        ),
      )
      .asyncFunction(
        'requestDirectoryPermissionsAsync',
        ExpoFunction.typed1(ExpoValueTypes.string().nullable().optional(), async (initialUri?: string | null): Promise<PermissionRecord> => {
          const result = await this.service.pickDirectoryPermission(initialUri ?? undefined);
          if (result.granted && result.directoryUri !== undefined) {
            this.fileState().grant(result.directoryUri, true);
          }
          return result;
        }),
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
            results.push(toFileUri(target, (await fs.stat(target)).isDirectory()));
          }
          return results;
        }),
      )
      .asyncFunction(
        'makeSAFDirectoryAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), ExpoValueTypes.string(), async (uri: string, name: string): Promise<string> => {
          const state = this.fileState();
          await state.ready();
          const target = joinPath(requireDirectory(state.resolve(uri, true)), safeName(name));
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
            const target = joinPath(requireDirectory(this.fileState().resolve(uri, true)), name);
            createEmptyFile(target, true);
            return toFileUri(target);
          },
        ),
      )
      .onPrepareForReload(async (): Promise<void> => this.service.destroy())
      .onDestroy((): void => this.service.onDestroy())
      .onAbilityDestroy((): void => this.service.onDestroy());
  }
}

function decodeFileUri(uri: string): string {
  if (!uri.startsWith('file:')) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME', `Unsupported URI '${uri}'`);
  }
  let encoded = uri.slice(5);
  if (encoded.startsWith('//')) {
    encoded = encoded.slice(2);
    if (encoded.startsWith('localhost/')) encoded = encoded.slice('localhost'.length);
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
  return path === root || path.startsWith(`${root}/`);
}

function isRawUri(uri: string): boolean {
  return uri.startsWith('asset://') || uri.startsWith('rawfile://');
}

function rawPathFromUri(uri: string, allowSchemeLess: boolean = false, allowRoot: boolean = false): string {
  let value: string;
  if (uri.startsWith('asset://')) value = uri.slice('asset://'.length);
  else if (uri.startsWith('rawfile://')) value = uri.slice('rawfile://'.length);
  else if (allowSchemeLess && !uri.includes(':')) value = uri;
  else throw new ExpoFileSystemError('ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME', `Unsupported bundled URI '${uri}'`);
  value = value.replace(/^\/+/, '').split(/[?#]/, 1)[0];
  try {
    value = decodeURIComponent(value);
  } catch (_) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESOURCE', 'Invalid bundled resource URI');
  }
  if (value.endsWith('/')) value = value.slice(0, -1);
  if (value.includes('\0') || value.includes('\\')) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESOURCE', 'Invalid bundled resource path');
  }
  if (value.length === 0 && allowRoot) return '';
  const segments = value.split('/');
  if (segments.length === 0 || segments.some((segment: string): boolean => segment.length === 0 || segment === '.' || segment === '..')) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_RESOURCE', 'Invalid bundled resource path');
  }
  return segments.join('/');
}

function toAssetUri(path: string, directory: boolean): string {
  const encoded = path
    .split('/')
    .map((segment: string): string => encodeURIComponent(segment))
    .join('/');
  const uri = `asset:///${encoded}`;
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
    if (Number(Reflect.get(error as Object, 'code')) !== FILE_EXISTS_ERROR) throw error as Error;
  }
  // Recursive mkdir still reports EEXIST on Harmony. Only an actual directory
  // may satisfy an ensure operation, including when another Host created it.
  if (!fs.lstatSync(path).isDirectory()) throw invalidType(path, 'directory');
}

async function makeDirectoryPathAsync(path: string, intermediates: boolean): Promise<void> {
  try {
    await fs.mkdir(path, intermediates);
  } catch (error) {
    if (!intermediates || Number(Reflect.get(error as Object, 'code')) !== FILE_EXISTS_ERROR) throw error as Error;
  }
  if (!(await fs.lstat(path)).isDirectory()) throw invalidType(path, 'directory');
}

function createEmptyFile(path: string, exclusive: boolean = false): void {
  if (exclusive) {
    atomicFileOperations.exclusiveCreate(path);
    return;
  }
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC | fs.OpenMode.NOFOLLOW);
  fs.closeSync(file.fd);
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

function readBytesPath(path: string): Uint8Array {
  return readFileRange(path, 0, Number.MAX_SAFE_INTEGER);
}

function readFileRange(path: string, position: number, requestedLength: number): Uint8Array {
  requireSafeInteger(position, 'ERR_FILE_SYSTEM_INVALID_OFFSET', 'Read position');
  requireSafeInteger(requestedLength, 'ERR_FILE_SYSTEM_INVALID_LENGTH', 'Read length');
  const required: string = requireFile(path);
  const size: number = fs.statSync(required).size;
  if (position > size) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_OFFSET', 'Read position is beyond the file');
  }
  const length: number = Math.min(requestedLength, size - position);
  const buffer = new ArrayBuffer(length);
  const output = new Uint8Array(buffer);
  const chunk = new ArrayBuffer(Math.min(length, 64 * 1024));
  const file = fs.openSync(required, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
  let total: number = 0;
  try {
    fs.lseek(file.fd, position, fs.WhenceType.SEEK_SET);
    while (total < length) {
      const count: number = fs.readSync(file.fd, chunk, { length: Math.min(chunk.byteLength, length - total) });
      if (count <= 0) break;
      output.set(new Uint8Array(chunk, 0, count), total);
      total += count;
    }
  } finally {
    fs.closeSync(file.fd);
  }
  return new Uint8Array(total === length ? buffer : buffer.slice(0, total));
}

function readOwnerBytes(owner: FileSystemFile): Uint8Array {
  return owner.bundled ? owner.state.rawBytes(owner.rawUri()) : readBytesPath(owner.path());
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

function md5Path(path: string): string {
  const stream = fileHash.createHash('md5');
  const file = fs.openSync(requireFile(path), fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
  const buffer = new ArrayBuffer(64 * 1024);
  try {
    while (true) {
      const count = fs.readSync(file.fd, buffer, { length: buffer.byteLength });
      if (count <= 0) break;
      stream.update(count === buffer.byteLength ? buffer : buffer.slice(0, count));
    }
  } finally {
    fs.closeSync(file.fd);
  }
  return stream.digest().toLowerCase();
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

function copyPathOverwrite(source: string, target: string): void {
  assertSeparatePaths(source, target);
  // The staging directory is on the destination volume so both commit and
  // rollback can use rename without copying or truncating the previous target.
  const staging = fs.mkdtempSync(joinPath(parentPath(target), '.expo-copy-XXXXXX'));
  const replacement = joinPath(staging, 'replacement');
  const previous = joinPath(staging, 'previous');
  let preservePrevious: boolean = false;
  try {
    copyPath(source, replacement);
    const hadTarget = fs.accessSync(target);
    if (hadTarget) fs.renameSync(target, previous);
    try {
      fs.renameSync(replacement, target);
    } catch (error) {
      if (hadTarget) {
        try {
          fs.renameSync(previous, target);
        } catch (restoreError) {
          preservePrevious = true;
          throw new ExpoFileSystemError(
            'ERR_FILE_SYSTEM_COPY_ROLLBACK_FAILED',
            `Unable to restore the destination; its previous contents are retained at '${previous}': ${cleanErrorMessage(restoreError as Object)}`,
            restoreError as Object,
          );
        }
      }
      throw error as Error;
    }
  } finally {
    if (!preservePrevious) removePath(staging);
  }
}

function copyPathNoReplace(source: string, target: string): void {
  assertSeparatePaths(source, target);
  const staging = fs.mkdtempSync(joinPath(parentPath(target), '.expo-copy-XXXXXX'));
  try {
    const replacement = joinPath(staging, 'replacement');
    copyPath(source, replacement);
    atomicFileOperations.publishNoReplace(replacement, target);
  } finally {
    removePath(staging);
  }
}

function movePathNoReplace(source: string, target: string): void {
  assertSeparatePaths(source, target);
  try {
    atomicFileOperations.publishNoReplace(source, target);
    return;
  } catch (error) {
    if (Reflect.get(error as Object, 'code') !== 'ERR_FILE_SYSTEM_CROSS_DEVICE') throw error as Error;
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
    throw invalidType(path, 'plain object');
  }
  return value as FileSystemRecord;
}

function openFileHandle(owner: FileSystemFile): fs.File {
  const path = requireFile(owner.path());
  return fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.NOFOLLOW);
}

function invalidType(path: string, expected: string): ExpoModuleError {
  return new ExpoModuleError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected ${expected}`);
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
  const path = owner.path();
  const overwrite = recordBoolean(options, 'overwrite');
  if (recordBoolean(options, 'intermediates')) ensureDirectoryExists(parentPath(path));
  if (fs.accessSync(path)) {
    if (!fs.statSync(path).isFile()) {
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_FILE_TYPE', 'Cannot replace a directory with a file');
    }
    if (!overwrite) throw new ExpoFileSystemError('ERR_UNABLE_TO_CREATE', 'File already exists');
    fs.unlinkSync(path);
  }
  createEmptyFile(path, !overwrite);
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
  writeBytesFile(owner.path(), bytes, recordBoolean(options, 'append'));
}

function fileExists(owner: FileSystemFile): boolean {
  if (owner.bundled) return owner.state.rawExists(owner.rawUri());
  const path = owner.probePath();
  if (path === null || !fs.accessSync(path)) return false;
  return fs.statSync(path).isFile();
}

function fileTimestamp(owner: FileSystemFile, creation: boolean): number | null {
  if (owner.bundled) return null;
  const path = owner.probePath();
  if (path === null || !fs.accessSync(path)) return null;
  const stat = fs.statSync(path);
  if (!stat.isFile()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_FILE_TYPE', 'Path points to a directory');
  return creation ? null : stat.mtime * 1000;
}

function fileMd5(owner: FileSystemFile): string | null {
  if (!fileExists(owner)) return null;
  return owner.bundled ? owner.state.rawMd5(owner.rawUri()) : md5Path(owner.path());
}

function fileMd5OrNull(owner: FileSystemFile): string | null {
  try {
    return fileMd5(owner);
  } catch (_) {
    return null;
  }
}

function fileSize(owner: FileSystemFile): number {
  if (!fileExists(owner)) return 0;
  return owner.bundled ? owner.state.rawSize(owner.rawUri()) : fs.statSync(owner.path()).size;
}

function fileInfo(owner: FileSystemFile, includeMd5: boolean): FileSystemInfo {
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

function deleteFile(owner: FileSystemFile): void {
  const path = owner.path();
  if (!fs.accessSync(path)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANNOT_DELETE', 'File does not exist');
  requireFile(path);
  fs.unlinkSync(path);
}

function fileTarget(owner: FileSystemFile, destination: FileSystemDestination): string {
  if (destination instanceof FileSystemDirectory) {
    return joinPath(requireDirectory(destination.path()), leafName(owner.path()));
  }
  requireDirectory(parentPath(destination.path()));
  return destination.path();
}

function copyFile(owner: FileSystemFile, destination: FileSystemDestination): void {
  const source = requireFile(owner.path());
  const target = fileTarget(owner, destination);
  if (fs.accessSync(target)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_DESTINATION_EXISTS', 'Copy destination exists');
  copyPathNoReplace(source, target);
}

function moveFile(owner: FileSystemFile, destination: FileSystemDestination): void {
  const source = requireFile(owner.path());
  const target = fileTarget(owner, destination);
  if (fs.accessSync(target)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_DESTINATION_EXISTS', 'Move destination exists');
  movePathNoReplace(source, target);
  owner.setPath(target);
}

function renameFile(owner: FileSystemFile, name: string): void {
  const source = requireFile(owner.path());
  const target = joinPath(parentPath(source), safeName(name));
  if (source === target) return;
  if (fs.accessSync(target)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_DESTINATION_EXISTS', 'Rename destination exists');
  owner.state.resolve(toFileUri(target));
  atomicFileOperations.publishNoReplace(source, target);
  owner.setPath(target);
}

function createDirectory(owner: FileSystemDirectory, options?: FileSystemRecord): void {
  const path = owner.path();
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
  const path = owner.path();
  if (!fs.accessSync(path)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_CANNOT_DELETE', 'Directory does not exist');
  requireDirectory(path);
  removePath(path);
}

function directoryTarget(owner: FileSystemDirectory, destination: FileSystemDestination): string {
  if (!(destination instanceof FileSystemDirectory)) {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_DESTINATION', 'A directory cannot be copied or moved to a File');
  }
  const path = destination.path();
  if (fs.accessSync(path) && fs.statSync(path).isDirectory()) return joinPath(path, leafName(owner.path()));
  requireDirectory(parentPath(path));
  return path;
}

function copyDirectory(owner: FileSystemDirectory, destination: FileSystemDestination): void {
  const source = requireDirectory(owner.path());
  const target = directoryTarget(owner, destination);
  assertOutsideDirectory(source, target);
  if (fs.accessSync(target)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_DESTINATION_EXISTS', 'Copy destination exists');
  copyPathNoReplace(source, target);
}

function moveDirectory(owner: FileSystemDirectory, destination: FileSystemDestination): void {
  const source = requireDirectory(owner.path());
  const target = directoryTarget(owner, destination);
  assertOutsideDirectory(source, target);
  if (fs.accessSync(target)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_DESTINATION_EXISTS', 'Move destination exists');
  movePathNoReplace(source, target);
  owner.setPath(target);
}

function renameDirectory(owner: FileSystemDirectory, name: string): void {
  const source = requireDirectory(owner.path());
  const target = joinPath(parentPath(source), safeName(name));
  if (source === target) return;
  if (fs.accessSync(target)) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_DESTINATION_EXISTS', 'Rename destination exists');
  owner.state.resolve(toFileUri(target));
  atomicFileOperations.publishNoReplace(source, target);
  owner.setPath(target);
}

function directoryExists(owner: FileSystemDirectory): boolean {
  if (owner.bundled) return owner.state.rawDirectoryExists(toAssetUri(owner.rawPath(), true));
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
    if (owner.bundled) return rawDirectorySize(owner.state, toAssetUri(owner.rawPath(), true));
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
  result.files = owner.bundled ? owner.state.rawList(toAssetUri(owner.rawPath(), true)) : fs.listFileSync(owner.path());
  result.size = owner.bundled ? rawDirectorySize(owner.state, toAssetUri(owner.rawPath(), true)) : pathSize(owner.path());
  if (!owner.bundled) {
    const stat = fs.statSync(owner.path());
    result.modificationTime = stat.mtime * 1000;
    result.creationTime = null;
  } else {
    result.modificationTime = null;
    result.creationTime = null;
  }
  return result;
}

function listDirectoryRecords(owner: FileSystemDirectory): DirectoryEntryRecord[] {
  if (owner.bundled) {
    const base = toAssetUri(owner.rawPath(), true);
    return owner.state.rawList(base).map((name: string): DirectoryEntryRecord => {
      const child = `${base}${encodeURIComponent(name)}`;
      const directory = owner.state.rawDirectoryExists(child);
      return new DirectoryEntryRecord(directory, directory ? `${child}/` : child);
    });
  }
  return fs.listFileSync(requireDirectory(owner.path())).map((name: string): DirectoryEntryRecord => {
    const target = joinPath(owner.path(), name);
    const directory = fs.statSync(target).isDirectory();
    return new DirectoryEntryRecord(directory, toFileUri(target, directory));
  });
}

function pathInfo(state: FileSystemState, uri: string): FileSystemInfo {
  const path = state.probe(uri);
  if (path === null || !fs.accessSync(path)) return new FileSystemInfo(false);
  const result = new FileSystemInfo(true);
  result.isDirectory = fs.statSync(path).isDirectory();
  return result;
}

function modernDownloadRequest(url: string, destination: FileSystemDestination, options?: FileSystemRecord): DownloadRequest {
  const directory = destination instanceof FileSystemDirectory;
  const path = directory ? requireDirectory(destination.path()) : destination.path();
  if (!directory && fs.accessSync(path) && !recordBoolean(options, 'idempotent')) {
    throw new ExpoFileSystemError('ERR_DESTINATION_ALREADY_EXISTS', 'Download destination already exists');
  }
  return {
    url,
    destination: path,
    destinationIsDirectory: directory,
    rejectIfExists: true,
    rejectHttpErrors: true,
    idempotent: recordBoolean(options, 'idempotent'),
    headers: recordObject(options, 'headers'),
  };
}

function legacyDownloadRequest(state: FileSystemState, url: string, destinationUri: string, options?: FileSystemRecord): DownloadRequest {
  return {
    url,
    destination: state.resolve(destinationUri),
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
  const file = await fs.open(path, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
  try {
    const stat = await fs.stat(file.fd);
    if (!stat.isFile()) throw new ExpoFileSystemError('ERR_FILE_SYSTEM_INVALID_FILE_TYPE', 'Path is not a file');
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
  return owner.bundled ? owner.state.rawBytesAsync(owner.rawUri()) : readFileRangeAsync(owner.path());
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

async function copyPathOverwriteAsync(source: string, target: string): Promise<void> {
  assertSeparatePaths(source, target);
  const staging = await fs.mkdtemp(joinPath(parentPath(target), '.expo-copy-XXXXXX'));
  const replacement = joinPath(staging, 'replacement');
  const previous = joinPath(staging, 'previous');
  let preservePrevious = false;
  try {
    await copyPathAsync(source, replacement);
    const hadTarget = await fs.access(target);
    if (hadTarget) await fs.rename(target, previous);
    try {
      await fs.rename(replacement, target);
    } catch (error) {
      if (hadTarget) {
        try {
          await fs.rename(previous, target);
        } catch (restoreError) {
          preservePrevious = true;
          throw new ExpoFileSystemError(
            'ERR_FILE_SYSTEM_COPY_ROLLBACK_FAILED',
            `The previous destination is retained at '${previous}': ${cleanErrorMessage(restoreError as Object)}`,
            restoreError as Object,
          );
        }
      }
      throw error as Error;
    }
  } finally {
    if (!preservePrevious) await removePathAsync(staging);
  }
}

async function movePathAsync(source: string, target: string): Promise<void> {
  assertSeparatePaths(source, target);
  try {
    await fs.rename(source, target);
    return;
  } catch (error) {
    // The platform documents this code as EXDEV: the source is on another volume.
    if (Number(Reflect.get(error as Object, 'code')) !== 13900016) throw error as Error;
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
  const path = state.resolve(uri);
  let stat: fs.Stat;
  try {
    stat = await fs.stat(path);
  } catch (error) {
    if (Number(Reflect.get(error as Object, 'code')) !== 13900002) throw error as Error;
    const missing = new FileSystemInfo(false);
    missing.isDirectory = false;
    return missing;
  }
  const result = new FileSystemInfo(true);
  result.isDirectory = stat.isDirectory();
  result.uri = toFileUri(path, result.isDirectory);
  result.size = result.isDirectory ? await pathSizeAsync(path) : stat.size;
  result.modificationTime = stat.mtime;
  if (includeMd5 && !result.isDirectory) result.md5 = (await fileHash.hash(path, 'md5')).toLowerCase();
  return result;
}

async function legacyReadAsync(state: FileSystemState, uri: string, options?: FileSystemRecord): Promise<string> {
  const encoding = recordEncoding(options);
  await state.ready();
  const position = encoding === 'base64' ? (recordNumber(options, 'position') ?? 0) : 0;
  const length = encoding === 'base64' ? recordNumber(options, 'length') : undefined;
  requireSafeInteger(position, 'ERR_FILE_SYSTEM_INVALID_OFFSET', 'Read position');
  if (length !== undefined) requireSafeInteger(length, 'ERR_FILE_SYSTEM_INVALID_LENGTH', 'Read length');
  let bytes: Uint8Array;
  if (isPackagedResource(uri)) {
    bytes = await state.rawBytesAsync(uri, true);
    bytes = bytes.slice(position, length === undefined ? undefined : position + length);
  } else {
    bytes = await readFileRangeAsync(state.resolve(uri, true), position, length);
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

import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import util from '@ohos.util';
import url from '@ohos.url';
import webview from '@ohos.web.webview';
import uniformTypeDescriptor from '@ohos.data.uniformTypeDescriptor';

import { collectRequestHeaders, filePathFromUrl, headersForDecodedResponse, mergeCookieHeaders, requestMethodPolicy } from './FetchHeaderPolicy';
import { ExpoFetchError } from './ExpoFetchError';

const SERVICE_NAME: string = 'ExpoFetchService';
const NETSTACK_RESPONSE_LIMIT_BYTES: number = 100 * 1024 * 1024;
const NETSTACK_COMPLETION_FALLBACK_MS: number = 61_000;
let registered: boolean = false;

interface FetchInit {
  credentials?: string;
  headers?: string[][];
  method?: string;
  redirect?: string;
}

interface FetchDescription {
  id: string;
  url: string;
  init: FetchInit;
  bodyBase64?: string | null;
}

class FetchResult {
  status: number;
  statusText: string;
  url: string;
  redirected: boolean;
  headers: string[][];

  constructor(status: number, url: string, redirected: boolean, headers: string[][], text: string | null = null) {
    this.status = status;
    this.statusText = text ?? statusText(status);
    this.url = url;
    this.redirected = redirected;
    this.headers = headers;
  }
}

class StreamPacket {
  data: string;
  done: boolean;
  completed: boolean;
  error: string | null;

  constructor(data: string, done: boolean, completed: boolean, error: string | null = null) {
    this.data = data;
    this.done = done;
    this.completed = completed;
    this.error = error;
  }
}

class FetchTask {
  request: http.HttpRequest | null;
  url: string;
  queued: ArrayBuffer[] = [];
  readers: Array<(packet: StreamPacket) => void> = [];
  completionWaiters: Array<() => void> = [];
  headers: string[][] = [];
  completed: boolean = false;
  streaming: boolean = false;
  error: string | null = null;
  localFilePath: string | null = null;
  localFile: fs.File | null = null;
  localFileOffset: number = 0;
  localFileSize: number = 0;
  activeAttempt: FetchAttempt | null = null;
  completionTimeout: number = -1;

  constructor(request: http.HttpRequest | null, url: string) {
    this.request = request;
    this.url = url;
  }
}

class FetchAttempt {
  request: http.HttpRequest;
  headers: string[][] = [];
  chunks: ArrayBuffer[] = [];
  accepted: boolean = false;
  discarded: boolean = false;
  ended: boolean = false;
  metadataReady: Promise<void>;
  private metadataSettled: boolean = false;
  private resolveMetadata: () => void = (): void => {};
  private rejectMetadata: (error: Error) => void = (_: Error): void => {};

  constructor(request: http.HttpRequest) {
    this.request = request;
    this.metadataReady = new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
      this.resolveMetadata = resolve;
      this.rejectMetadata = reject;
    });
    this.metadataReady.catch((_: Error): void => {});
  }

  settleMetadata(): void {
    if (this.metadataSettled) return;

    this.metadataSettled = true;
    this.resolveMetadata();
  }

  failMetadata(error: string): void {
    if (this.metadataSettled) return;

    this.metadataSettled = true;
    this.rejectMetadata(new Error(error));
  }
}

class ExpoFetchService {
  readonly name: string = SERVICE_NAME;
  private readonly tasks: Map<string, FetchTask> = new Map();
  private destroyed: boolean = false;

  async invoke(name: string, args: ESObject[]): Promise<ESObject> {
    if (name === 'destroy') {
      this.onDestroy();
      return null;
    }
    if (this.destroyed) {
      throw new ExpoFetchError('ERR_FETCH_RUNTIME_DESTROYED', 'The Harmony fetch runtime has been destroyed');
    }

    if (name === 'start') {
      return await this.start(args[0] as FetchDescription);
    }
    if (name === 'startStreaming') return await this.startStreaming(String(args[0]));
    if (name === 'readChunk') return await this.readChunk(String(args[0]));
    if (name === 'consumeArrayBuffer') return await this.consumeArrayBuffer(String(args[0]));
    if (name === 'consumeText') return await this.consumeText(String(args[0]));
    if (name === 'waitForCompletion') return await this.waitForCompletion(String(args[0]));
    if (name === 'cancelStreaming') {
      this.cancelStreaming(String(args[0]));
      return null;
    }
    if (name === 'cancel') {
      this.cancel(String(args[0]), 'ERR_FETCH_REQUEST_CANCELED: Fetch request has been canceled');
      return null;
    }
    if (name === 'discard') {
      this.discard(String(args[0]));
      return null;
    }

    throw new ExpoFetchError('ERR_FETCH_UNKNOWN_METHOD', name);
  }

  onDestroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;

    const error = 'ERR_FETCH_RUNTIME_DESTROYED: The Harmony fetch runtime has been destroyed';
    Array.from(this.tasks.keys()).forEach((id: string): void => this.cancel(id, error));

    this.tasks.clear();
  }

  private async start(input: FetchDescription): Promise<FetchResult> {
    if (isFileURL(input.url)) return this.startLocalFile(input);
    if (!isHttpURL(input.url)) {
      throw new ExpoFetchError('ERR_FETCH_INVALID_URL', `Invalid fetch URL: ${input.url}`);
    }

    const task = new FetchTask(http.createHttp(), input.url);
    this.tasks.set(input.id, task);

    let target = input.url;
    let method = input.init.method ?? 'GET';
    let body = input.bodyBase64 === null || input.bodyBase64 === undefined ? null : new util.Base64Helper().decodeSync(input.bodyBase64).buffer;
    let headers = makeHeaders(input.init);
    let redirects = 0;

    try {
      while (true) {
        const request = redirects === 0 && task.request !== null ? task.request : http.createHttp();
        task.request = request;

        const attempt = new FetchAttempt(request);
        task.activeAttempt = attempt;
        this.attachAttempt(task, attempt);

        const sent = await withStoredCookies(headers, target, input.init.credentials);
        if (task.error !== null || this.destroyed) {
          throw new ExpoFetchError('ERR_FETCH_RUNTIME_DESTROYED', 'The Harmony fetch runtime has been destroyed');
        }

        const options: http.HttpRequestOptions = {
          header: sent,
          maxRedirects: 0,
          maxLimit: NETSTACK_RESPONSE_LIMIT_BYTES,
        };
        applyRequestMethod(options, method);
        if (body !== null) options.extraData = body;
        else if (requestMethodRequiresBody(method)) options.extraData = new ArrayBuffer(0);

        const status = await request.requestInStream(target, options);
        // requestInStream returns the status separately from response metadata.
        // Wait until headersReceive (or dataEnd for a headerless response) so
        // redirects, cookies and the public Response headers never race it.
        await attempt.metadataReady;

        if (task.error !== null) throw new Error(task.error);
        if (input.init.credentials === 'include') {
          await storeResponseCookies(target, attempt.headers);
        }

        if (task.error !== null || this.destroyed) {
          throw new ExpoFetchError('ERR_FETCH_RUNTIME_DESTROYED', 'The Harmony fetch runtime has been destroyed');
        }

        const location = headerFromPairs(attempt.headers, 'location');
        const redirect = isRedirectStatus(status) && location !== null;

        if (redirect && input.init.redirect === 'error') {
          attempt.discarded = true;
          const error = new ExpoFetchError('ERR_FETCH_REDIRECT', "Redirect is not allowed when redirect mode is 'error'");
          this.failTask(task, error.message);

          throw error;
        }
        if (redirect && input.init.redirect === 'follow') {
          redirects += 1;
          if (redirects > 20) {
            attempt.discarded = true;
            const error = new ExpoFetchError('ERR_FETCH_TOO_MANY_REDIRECTS', 'The fetch request exceeded 20 redirects');
            this.failTask(task, error.message);

            throw error;
          }

          attempt.discarded = true;
          this.destroyRequest(task);
          const next = url.URL.parseURL(location ?? '', target).toString();
          if (!isHttpURL(next)) {
            throw new ExpoFetchError('ERR_FETCH_INVALID_URL', `Invalid redirect URL: ${next}`);
          }

          if (!sameOrigin(target, next)) {
            headers = withoutHeaders(headers, ['authorization', 'proxy-authorization', 'cookie', 'cookie2']);
          }
          if (((status === 301 || status === 302) && method === 'POST') || (status === 303 && method !== 'HEAD')) {
            method = 'GET';
            body = null;
            headers = withoutHeaders(headers, [
              'content-encoding',
              'content-language',
              'content-location',
              'content-type',
              'content-length',
              'transfer-encoding',
            ]);
          }

          target = next;
          continue;
        }

        task.url = target;
        // NetStack transparently decodes compressed bodies but leaves the
        // original content-encoding and compressed content-length in place.
        // Remove only those stale headers; keep uncompressed metadata intact.
        task.headers = headersForDecodedResponse(attempt.headers);
        attempt.accepted = true;

        this.armCompletionFallback(task);
        attempt.chunks.forEach((chunk: ArrayBuffer): void => this.receiveChunk(task, chunk));
        attempt.chunks = [];
        if (attempt.ended) this.finishAttempt(task, attempt);

        return new FetchResult(status, target, redirects > 0, task.headers);
      }
    } catch (error) {
      const raw = errorMessage(error);
      const message = task.error ?? (/^ERR_[A-Z0-9_]+(?::|$)/.test(raw) ? raw : `ERR_FETCH_UNKNOWN: ${raw}`);

      if (!task.completed) this.failTask(task, message);
      else this.disposeTask(task);
      this.tasks.delete(input.id);

      throw new Error(message);
    }
  }

  private attachAttempt(task: FetchTask, attempt: FetchAttempt): void {
    attempt.request.on('headersReceive', (value: Object): void => {
      attempt.headers = headerPairs(value);

      attempt.settleMetadata();
    });
    attempt.request.on('dataReceive', (chunk: ArrayBuffer): void => {
      if (attempt.discarded || task.completed) return;

      if (attempt.accepted) this.receiveChunk(task, chunk);
      else attempt.chunks.push(chunk);
    });
    attempt.request.on('dataEnd', (): void => {
      attempt.ended = true;
      attempt.settleMetadata();

      if (attempt.accepted && !attempt.discarded) this.finishAttempt(task, attempt);
    });
  }

  private receiveChunk(task: FetchTask, values: ArrayBuffer): void {
    if (task.completed) return;

    this.armCompletionFallback(task);
    if (task.streaming && task.readers.length > 0) {
      const resolve = task.readers.shift();
      if (resolve !== undefined) {
        resolve(new StreamPacket(bufferToBase64(values), false, false));
        return;
      }
    }

    task.queued.push(values);
  }

  private startLocalFile(input: FetchDescription): FetchResult {
    const path = filePathFromUrl(input.url);
    const task = new FetchTask(null, input.url);
    task.headers = [['content-type', mimeType(path)]];

    try {
      if (!fs.accessSync(path)) {
        const body = encodeString('File not found');
        task.headers = [
          ['content-type', 'text/plain'],
          ['content-length', String(body.byteLength)],
        ];
        task.queued = [body.buffer as ArrayBuffer];
        task.completed = true;
        this.tasks.set(input.id, task);

        return new FetchResult(404, input.url, false, task.headers, 'File not found');
      }

      const stat = fs.statSync(path);
      if (!stat.isFile()) {
        throw new Error(`Path is not a regular file: ${path}`);
      }
      task.localFilePath = path;
      task.localFileSize = stat.size;
      task.headers.push(['content-length', String(task.localFileSize)]);
      task.completed = true;
      this.tasks.set(input.id, task);

      return new FetchResult(200, input.url, false, task.headers);
    } catch (error) {
      throw new ExpoFetchError('ERR_FETCH_FILE_READ', `${path}: ${errorMessage(error as Object)}`);
    }
  }

  private async startStreaming(id: string): Promise<StreamPacket> {
    const task = this.requireTask(id);
    task.streaming = true;

    if (task.localFilePath !== null) {
      try {
        const data = this.readLocalFileChunk(task);
        const completed = task.localFileOffset >= task.localFileSize;

        if (completed) {
          this.closeLocalFile(task);
          this.tasks.delete(id);
        }

        return new StreamPacket(bufferToBase64(data), completed, completed);
      } catch (error) {
        this.closeLocalFile(task);
        this.tasks.delete(id);

        const message = errorMessage(error as Object);
        if (/^ERR_FETCH_FILE_READ(?::|$)/.test(message)) throw new Error(message);
        throw new ExpoFetchError('ERR_FETCH_FILE_READ', `${task.localFilePath}: ${message}`);
      }
    }

    const queued = task.queued.shift() ?? new ArrayBuffer(0);
    if (task.completed && task.queued.length === 0) {
      this.tasks.delete(id);

      return new StreamPacket(bufferToBase64(queued), true, true, task.error);
    }

    return new StreamPacket(bufferToBase64(queued), false, false);
  }

  private async readChunk(id: string): Promise<StreamPacket> {
    const task = this.requireTask(id);

    if (task.localFilePath !== null) {
      if (task.localFileOffset >= task.localFileSize) {
        this.closeLocalFile(task);
        this.tasks.delete(id);

        return new StreamPacket('', true, false, task.error);
      }
      try {
        const data = this.readLocalFileChunk(task);

        return new StreamPacket(bufferToBase64(data), false, false);
      } catch (error) {
        this.closeLocalFile(task);
        this.tasks.delete(id);

        const message = errorMessage(error as Object);
        if (/^ERR_FETCH_FILE_READ(?::|$)/.test(message)) throw new Error(message);
        throw new ExpoFetchError('ERR_FETCH_FILE_READ', `${task.localFilePath}: ${message}`);
      }
    }

    if (task.queued.length > 0) {
      const data = task.queued.shift();

      return new StreamPacket(bufferToBase64(data ?? new ArrayBuffer(0)), false, false);
    }
    if (task.completed) {
      this.tasks.delete(id);

      return new StreamPacket('', true, false, task.error);
    }

    return await new Promise<StreamPacket>((resolve: (packet: StreamPacket) => void): void => {
      task.readers.push(resolve);
    });
  }

  private async consumeArrayBuffer(id: string): Promise<string[]> {
    const task = this.requireTask(id);

    try {
      await this.awaitCompletion(task);

      if (this.destroyed) {
        throw new ExpoFetchError('ERR_FETCH_RUNTIME_DESTROYED', 'The Harmony fetch runtime has been destroyed');
      }
      if (task.error !== null) throw new Error(task.error);
      // RNOH's ArkTS TurboModule boundary is copy-value-only. Returning an
      // ArrayBuffer through it can produce a zero-length JS ArrayBuffer, while
      // number[] expands every byte into a boxed bridge value. Base64 chunks
      // keep the bridge copy bounded without joining the complete body here.
      const chunks =
        task.localFilePath === null
          ? task.queued.map((chunk: ArrayBuffer): string => bufferToBase64(chunk))
          : readFileBase64Chunks(task.localFilePath, task.localFileSize);

      return chunks;
    } catch (error) {
      const message = errorMessage(error as Object);
      if (task.localFilePath !== null) {
        if (/^ERR_FETCH_FILE_READ(?::|$)/.test(message)) throw new Error(message);
        throw new ExpoFetchError('ERR_FETCH_FILE_READ', `${task.localFilePath}: ${message}`);
      }
      throw new Error(message);
    } finally {
      this.closeLocalFile(task);
      this.tasks.delete(id);
    }
  }

  private async consumeText(id: string): Promise<string> {
    const task = this.requireTask(id);

    try {
      await this.awaitCompletion(task);

      if (this.destroyed) {
        throw new ExpoFetchError('ERR_FETCH_RUNTIME_DESTROYED', 'The Harmony fetch runtime has been destroyed');
      }
      if (task.error !== null) throw new Error(task.error);
      const buffer = task.localFilePath === null ? chunksToBuffer(task.queued) : readFileBuffer(task.localFilePath, task.localFileSize);
      const text = new util.TextDecoder('utf-8').decode(new Uint8Array(buffer));

      return text;
    } catch (error) {
      const message = errorMessage(error as Object);
      if (task.localFilePath !== null) {
        if (/^ERR_FETCH_FILE_READ(?::|$)/.test(message)) throw new Error(message);
        throw new ExpoFetchError('ERR_FETCH_FILE_READ', `${task.localFilePath}: ${message}`);
      }
      throw new Error(message);
    } finally {
      this.closeLocalFile(task);
      this.tasks.delete(id);
    }
  }

  private async waitForCompletion(id: string): Promise<boolean> {
    const task = this.requireTask(id);

    await this.awaitCompletion(task);

    if (this.destroyed) {
      throw new ExpoFetchError('ERR_FETCH_RUNTIME_DESTROYED', 'The Harmony fetch runtime has been destroyed');
    }
    return true;
  }

  private async awaitCompletion(task: FetchTask): Promise<void> {
    if (task.completed) return;
    await new Promise<void>((resolve: () => void): void => {
      task.completionWaiters.push(resolve);
    });
  }

  private requireTask(id: string): FetchTask {
    const task = this.tasks.get(id);
    if (task === undefined) {
      throw new ExpoFetchError('ERR_FETCH_TASK_NOT_FOUND', id);
    }

    return task;
  }

  private readLocalFileChunk(task: FetchTask): ArrayBuffer {
    if (task.localFilePath === null) return new ArrayBuffer(0);

    const remaining = task.localFileSize - task.localFileOffset;
    if (remaining <= 0) return new ArrayBuffer(0);

    const buffer = new ArrayBuffer(Math.min(64 * 1024, remaining));
    if (task.localFile === null) {
      task.localFile = fs.openSync(task.localFilePath, fs.OpenMode.READ_ONLY);
    }

    fs.lseek(task.localFile.fd, task.localFileOffset, fs.WhenceType.SEEK_SET);
    const count = fs.readSync(task.localFile.fd, buffer, {
      length: buffer.byteLength,
    });
    if (count <= 0) throw new Error(`Unable to read file: ${task.localFilePath}`);

    task.localFileOffset += count;
    return count === buffer.byteLength ? buffer : buffer.slice(0, count);
  }

  private closeLocalFile(task: FetchTask): void {
    if (task.localFile === null) return;

    try {
      fs.closeSync(task.localFile.fd);
    } catch (_) {}
    task.localFile = null;
  }

  private completeTask(task: FetchTask): void {
    if (task.completed) return;

    this.clearCompletionFallback(task);
    task.completed = true;
    this.destroyRequest(task);

    while (task.readers.length > 0) {
      const resolve = task.readers.shift();
      if (resolve !== undefined) {
        resolve(new StreamPacket('', true, false, task.error));
      }
    }
    while (task.completionWaiters.length > 0) {
      const resolve = task.completionWaiters.shift();
      if (resolve !== undefined) resolve();
    }
  }

  private failTask(task: FetchTask, error: string): void {
    if (task.completed) return;

    task.error = error;
    task.activeAttempt?.failMetadata(error);
    this.completeTask(task);
  }

  private finishAttempt(task: FetchTask, _: FetchAttempt): void {
    this.completeTask(task);
  }

  private armCompletionFallback(task: FetchTask): void {
    this.clearCompletionFallback(task);

    task.completionTimeout = setTimeout((): void => {
      this.failTask(task, 'ERR_FETCH_TIMEOUT: Harmony fetch response did not complete within the platform read timeout');
    }, NETSTACK_COMPLETION_FALLBACK_MS);
  }

  private clearCompletionFallback(task: FetchTask): void {
    if (task.completionTimeout < 0) return;

    clearTimeout(task.completionTimeout);
    task.completionTimeout = -1;
  }

  private cancel(id: string, error: string): void {
    const task = this.tasks.get(id);
    if (task === undefined) return;

    if (!task.completed) this.failTask(task, error);
    else this.disposeTask(task);
  }

  private cancelStreaming(id: string): void {
    const task = this.tasks.get(id);
    if (task === undefined) return;

    task.error = null;
    this.completeTask(task);
    this.disposeTask(task);
    this.tasks.delete(id);
  }

  private discard(id: string): void {
    const task = this.tasks.get(id);
    if (task === undefined) return;

    this.completeTask(task);
    this.disposeTask(task);
    this.tasks.delete(id);
  }

  private destroyRequest(task: FetchTask): void {
    const request = task.request;
    task.request = null;
    if (request === null) return;

    try {
      request.destroy();
    } catch (_) {}
  }

  private disposeTask(task: FetchTask): void {
    this.clearCompletionFallback(task);
    this.destroyRequest(task);

    this.closeLocalFile(task);
  }
}

function makeHeaders(init: FetchInit): Object {
  const values = collectRequestHeaders(init.headers ?? []);
  const headers = new Object();

  values.forEach((value: string, name: string): void => {
    Reflect.set(headers, name, value);
  });

  return headers;
}

function headerPairs(headers: Object): string[][] {
  const result: string[][] = [];

  Object.keys(headers).forEach((name: string): void => {
    const value: ESObject = Reflect.get(headers, name);
    if (Array.isArray(value)) {
      (value as ESObject[]).forEach((item: ESObject): void => {
        result.push([name, String(item)]);
      });
    } else {
      String(value)
        .split(/\r?\n/)
        .forEach((item: string): void => {
          result.push([name, item]);
        });
    }
  });

  return result;
}

function headerFromPairs(headers: string[][], name: string): string | null {
  const pair = headers.find((candidate: string[]): boolean => candidate.length >= 2 && candidate[0].toLowerCase() === name);

  return pair === undefined ? null : pair[1];
}

function isRedirectStatus(status: number): boolean {
  return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
}

function isFileURL(value: string): boolean {
  return /^file:\/\//i.test(value);
}

function isHttpURL(value: string): boolean {
  return /^https?:\/\//i.test(value);
}

function requestMethodRequiresBody(method: string): boolean {
  const normalized = method.toUpperCase();

  return normalized === 'POST' || normalized === 'PUT' || normalized === 'PATCH';
}

function sameOrigin(left: string, right: string): boolean {
  try {
    return url.URL.parseURL(left).origin === url.URL.parseURL(right).origin;
  } catch (_) {
    return false;
  }
}

function withoutHeaders(headers: Object, names: string[]): Object {
  const result = new Object();

  Object.keys(headers).forEach((name: string): void => {
    if (!names.includes(name.toLowerCase())) Reflect.set(result, name, Reflect.get(headers, name));
  });

  return result;
}

function applyRequestMethod(options: http.HttpRequestOptions, method: string): void {
  const policy = requestMethodPolicy(method);

  if (policy.standard) {
    options.method = policy.method as http.RequestMethod;
    return;
  }
  options.customMethod = policy.method;
}

function statusText(status: number): string {
  const values: Map<number, string> = new Map([
    [100, 'Continue'],
    [101, 'Switching Protocols'],
    [102, 'Processing'],
    [103, 'Early Hints'],
    [200, 'OK'],
    [201, 'Created'],
    [202, 'Accepted'],
    [203, 'Non-Authoritative Information'],
    [204, 'No Content'],
    [205, 'Reset Content'],
    [206, 'Partial Content'],
    [207, 'Multi-Status'],
    [208, 'Already Reported'],
    [226, 'IM Used'],
    [300, 'Multiple Choices'],
    [301, 'Moved Permanently'],
    [302, 'Found'],
    [303, 'See Other'],
    [304, 'Not Modified'],
    [305, 'Use Proxy'],
    [307, 'Temporary Redirect'],
    [308, 'Permanent Redirect'],
    [400, 'Bad Request'],
    [401, 'Unauthorized'],
    [402, 'Payment Required'],
    [403, 'Forbidden'],
    [404, 'Not Found'],
    [405, 'Method Not Allowed'],
    [406, 'Not Acceptable'],
    [407, 'Proxy Authentication Required'],
    [408, 'Request Timeout'],
    [409, 'Conflict'],
    [410, 'Gone'],
    [411, 'Length Required'],
    [412, 'Precondition Failed'],
    [413, 'Content Too Large'],
    [414, 'URI Too Long'],
    [415, 'Unsupported Media Type'],
    [416, 'Range Not Satisfiable'],
    [417, 'Expectation Failed'],
    [418, "I'm a Teapot"],
    [421, 'Misdirected Request'],
    [422, 'Unprocessable Content'],
    [423, 'Locked'],
    [424, 'Failed Dependency'],
    [425, 'Too Early'],
    [426, 'Upgrade Required'],
    [428, 'Precondition Required'],
    [429, 'Too Many Requests'],
    [431, 'Request Header Fields Too Large'],
    [451, 'Unavailable For Legal Reasons'],
    [500, 'Internal Server Error'],
    [501, 'Not Implemented'],
    [502, 'Bad Gateway'],
    [503, 'Service Unavailable'],
    [504, 'Gateway Timeout'],
    [505, 'HTTP Version Not Supported'],
    [506, 'Variant Also Negotiates'],
    [507, 'Insufficient Storage'],
    [508, 'Loop Detected'],
    [510, 'Not Extended'],
    [511, 'Network Authentication Required'],
  ]);
  return values.get(status) ?? '';
}

function mimeType(path: string): string {
  const dot = path.lastIndexOf('.');
  if (dot < 0 || dot === path.length - 1) return 'application/octet-stream';

  try {
    const typeId = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(path.slice(dot));
    const mimeTypes = uniformTypeDescriptor.getTypeDescriptor(typeId).mimeTypes;
    if (mimeTypes.length > 0) return mimeTypes[0];
  } catch (_) {}
  return 'application/octet-stream';
}

function encodeString(value: string): Uint8Array {
  return new util.TextEncoder('utf-8').encode(value);
}
function bufferToBase64(buffer: ArrayBuffer): string {
  if (buffer.byteLength === 0) return '';
  return new util.Base64Helper().encodeToStringSync(new Uint8Array(buffer));
}

function chunksToBuffer(chunks: ArrayBuffer[]): ArrayBuffer {
  const size = chunks.reduce((total: number, chunk: ArrayBuffer): number => total + chunk.byteLength, 0);
  const buffer = new ArrayBuffer(size);
  const output = new Uint8Array(buffer);
  let offset = 0;

  chunks.forEach((chunk: ArrayBuffer): void => {
    output.set(new Uint8Array(chunk), offset);
    offset += chunk.byteLength;
  });
  return buffer;
}

function readFileBuffer(path: string, size: number): ArrayBuffer {
  const output = new ArrayBuffer(size);
  if (size === 0) return output;

  const outputBytes = new Uint8Array(output);
  const chunk = new ArrayBuffer(Math.min(64 * 1024, size));
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);

  try {
    fs.lseek(file.fd, 0, fs.WhenceType.SEEK_SET);
    let consumed = 0;

    while (consumed < size) {
      const count = fs.readSync(file.fd, chunk, {
        length: Math.min(chunk.byteLength, size - consumed),
      });
      if (count <= 0) throw new ExpoFetchError('ERR_FETCH_FILE_READ', path);
      outputBytes.set(new Uint8Array(chunk, 0, count), consumed);
      consumed += count;
    }

    return output;
  } finally {
    fs.closeSync(file.fd);
  }
}

function readFileBase64Chunks(path: string, size: number): string[] {
  if (size === 0) return [];

  const chunks: string[] = [];
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);

  try {
    fs.lseek(file.fd, 0, fs.WhenceType.SEEK_SET);
    let consumed = 0;

    while (consumed < size) {
      const buffer = new ArrayBuffer(Math.min(64 * 1024, size - consumed));
      const count = fs.readSync(file.fd, buffer, { length: buffer.byteLength });
      if (count <= 0) throw new ExpoFetchError('ERR_FETCH_FILE_READ', path);
      chunks.push(bufferToBase64(count === buffer.byteLength ? buffer : buffer.slice(0, count)));
      consumed += count;
    }

    return chunks;
  } finally {
    fs.closeSync(file.fd);
  }
}

async function withStoredCookies(headers: Object, target: string, credentials?: string): Promise<Object> {
  if (credentials !== 'include') return headers;

  let stored = '';
  try {
    stored = await webview.WebCookieManager.fetchCookie(target, false);
  } catch (_) {
    // Cookie storage is auxiliary to the network request. If WebView's store
    // is unavailable, continue without automatic cookies just like a disabled
    // native cookie jar.
  }
  if (stored.length === 0) return headers;

  const result = withoutHeaders(headers, ['cookie']);
  const explicit = headerValue(headers, 'cookie');
  Reflect.set(result, 'cookie', mergeCookieHeaders(explicit, stored));

  return result;
}

async function storeResponseCookies(target: string, headers: string[][]): Promise<void> {
  const cookies = headers
    .filter((pair: string[]): boolean => pair.length >= 2 && pair[0].toLowerCase() === 'set-cookie')
    .map((pair: string[]): string => pair[1]);
  if (cookies.length === 0) return;

  try {
    for (const cookie of cookies) {
      await webview.WebCookieManager.configCookie(target, cookie, false, true);
    }
    await webview.WebCookieManager.saveCookieAsync();
  } catch (_) {
    // A cookie persistence failure must not turn a completed HTTP exchange
    // into a failed fetch.
  }
}

function headerValue(headers: Object, name: string): string | null {
  const key = Object.keys(headers).find((candidate: string): boolean => candidate.toLowerCase() === name);

  return key === undefined ? null : String(Reflect.get(headers, key));
}

function errorMessage(error: Object): string {
  if (error instanceof ExpoFetchError) return error.message;

  try {
    if (error !== null && typeof error === 'object') {
      const message: ESObject = Reflect.get(error, 'message');
      const code: ESObject = Reflect.get(error, 'code');
      if (typeof message === 'string' && message.length > 0) {
        return typeof code === 'number' || typeof code === 'string' ? `${message} (Harmony code ${String(code)})` : message;
      }
    }
  } catch (_) {}
  return String(error).replace(/^(?:Error:\s*)+/, '');
}

function registerService(): void {
  if (registered) return;
  ExpoPlatformServiceRegistry.register({ name: SERVICE_NAME, create: (_: UITurboModuleContext) => new ExpoFetchService() });
  registered = true;
}

export class ExpoFetchPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerService();
    super(context);
  }
  override getDebugName(): string {
    return '@expo-harmony/expo-fetch';
  }
}

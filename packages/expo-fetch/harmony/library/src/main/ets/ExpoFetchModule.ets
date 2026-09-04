import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoSharedObject,
  ExpoSharedObjectClassDefinition,
  ExpoValueType,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import util from '@ohos.util';
import url from '@ohos.url';
import webview from '@ohos.web.webview';
import uniformTypeDescriptor from '@ohos.data.uniformTypeDescriptor';

import { collectRequestHeaders, filePathFromUrl, headersForDecodedResponse, mergeCookieHeaders, requestMethodPolicy } from './FetchHeaderPolicy';
import { ExpoFetchError } from './ExpoFetchError';

const NETSTACK_RESPONSE_LIMIT_BYTES: number = 100 * 1024 * 1024;
const EMPTY_BYTES: Uint8Array = new Uint8Array(0);

class FetchInit {
  credentials: string = 'include';
  headers: string[][] = [];
  method: string = 'GET';
  redirect: string = 'follow';
}

class FetchResult {
  status: number;
  statusText: string;
  url: string;
  redirected: boolean;
  headers: string[][];

  constructor(status: number, urlValue: string, redirected: boolean, headers: string[][], text: string | null = null) {
    this.status = status;
    this.statusText = text ?? statusText(status);
    this.url = urlValue;
    this.redirected = redirected;
    this.headers = headers;
  }
}

class StreamPacket {
  data: Uint8Array;
  done: boolean;
  completed: boolean;
  error: ExpoFetchError | null;

  constructor(data: Uint8Array, done: boolean, completed: boolean, error: ExpoFetchError | null = null) {
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
  error: ExpoFetchError | null = null;
  localFilePath: string | null = null;
  localFile: fs.File | null = null;
  localFileOffset: number = 0;
  localFileSize: number = 0;
  activeAttempt: FetchAttempt | null = null;

  constructor(request: http.HttpRequest | null, urlValue: string) {
    this.request = request;
    this.url = urlValue;
  }
}

class FetchAttempt {
  request: http.HttpRequest;
  headers: string[][] = [];
  chunks: ArrayBuffer[] = [];
  bufferedBytes: number = 0;
  accepted: boolean = false;
  discarded: boolean = false;
  ended: boolean = false;
  metadataReady: Promise<void>;
  private metadataSettled: boolean = false;
  private resolveMetadata: () => void = (): void => {};
  private rejectMetadata: (error: Error) => void = (_error: Error): void => {};

  constructor(request: http.HttpRequest) {
    this.request = request;
    this.metadataReady = new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
      this.resolveMetadata = resolve;
      this.rejectMetadata = reject;
    });
    this.metadataReady.catch((_error: Error): void => {});
  }

  settleMetadata(): void {
    if (this.metadataSettled) return;
    this.metadataSettled = true;
    this.resolveMetadata();
  }

  failMetadata(error: ExpoFetchError): void {
    if (this.metadataSettled) return;
    this.metadataSettled = true;
    this.rejectMetadata(new Error(formatError(error)));
  }
}

class ExpoFetchRuntime {
  private readonly tasks: Map<string, FetchTask> = new Map<string, FetchTask>();
  private destroyed: boolean = false;
  private nextRequestId: number = 1;

  allocateRequestId(): string {
    this.assertActive();
    const id = `expo-fetch-${this.nextRequestId}`;
    this.nextRequestId += 1;
    return id;
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;

    Array.from(this.tasks.keys()).forEach((id: string): void => {
      this.cancel(id, new ExpoFetchError('ERR_FETCH_RUNTIME_DESTROYED', 'The Harmony fetch runtime has been destroyed'));
    });
    this.tasks.clear();
  }

  async start(id: string, inputUrl: string, init: FetchInit, requestBody: Uint8Array | null): Promise<FetchResult> {
    this.assertActive();
    if (isFileURL(inputUrl)) {
      return await this.startLocalFile(id, inputUrl, init, requestBody);
    }
    if (!isHttpURL(inputUrl)) {
      throw new ExpoFetchError('ERR_FETCH_INVALID_URL', `Invalid fetch URL: ${inputUrl}`);
    }

    const task = new FetchTask(http.createHttp(), inputUrl);
    this.tasks.set(id, task);

    let target = inputUrl;
    let method = init.method ?? 'GET';
    let body: ArrayBuffer | null = requestBody === null ? null : copyBytes(requestBody);
    let headers = makeHeaders(init);
    let redirects = 0;

    try {
      while (true) {
        const request = redirects === 0 && task.request !== null ? task.request : http.createHttp();
        task.request = request;

        const attempt = new FetchAttempt(request);
        task.activeAttempt = attempt;
        this.attachAttempt(task, attempt);

        const sent = await withStoredCookies(headers, target, init.credentials);
        this.assertTaskActive(task);

        const options: http.HttpRequestOptions = {
          connectTimeout: 0,
          header: sent,
          maxRedirects: 0,
          maxLimit: NETSTACK_RESPONSE_LIMIT_BYTES,
          readTimeout: 0,
        };
        applyRequestMethod(options, method);
        if (body !== null) options.extraData = body;
        else if (requestMethodRequiresBody(method)) options.extraData = new ArrayBuffer(0);

        const status = await request.requestInStream(target, options);
        // NetStack exposes the status only when requestInStream settles. Its
        // header/data events may already have fired, so keep the bounded
        // pre-accept buffer until redirect and cookie policy can be applied.
        await attempt.metadataReady;

        if (task.error !== null) throw task.error;
        if (init.credentials === 'include') {
          await storeResponseCookies(target, attempt.headers);
        }
        this.assertTaskActive(task);

        const location = headerFromPairs(attempt.headers, 'location');
        const redirect = isRedirectStatus(status) && location !== null;
        if (redirect && init.redirect === 'error') {
          attempt.discarded = true;
          const error = new ExpoFetchError('ERR_FETCH_REDIRECT', "Redirect is not allowed when redirect mode is 'error'");
          this.failTask(task, error);
          throw error;
        }
        if (redirect && init.redirect === 'follow') {
          redirects += 1;
          if (redirects > 20) {
            attempt.discarded = true;
            const error = new ExpoFetchError('ERR_FETCH_TOO_MANY_REDIRECTS', 'The fetch request exceeded 20 redirects');
            this.failTask(task, error);
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
          if (((status === 301 || status === 302) && method === 'POST') || (status === 303 && method !== 'GET' && method !== 'HEAD')) {
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
        task.headers = headersForDecodedResponse(attempt.headers);
        attempt.accepted = true;

        attempt.chunks.forEach((chunk: ArrayBuffer): void => this.receiveChunk(task, chunk));
        attempt.chunks = [];
        if (attempt.ended) this.finishAttempt(task);

        return new FetchResult(status, target, redirects > 0, task.headers);
      }
    } catch (error) {
      const failure = task.error ?? asFetchError(error as Object);
      if (!task.completed) this.failTask(task, failure);
      else this.disposeTask(task);
      this.tasks.delete(id);
      throw failure;
    }
  }

  async startStreaming(id: string): Promise<StreamPacket> {
    this.assertActive();
    const task = this.requireTask(id);
    task.streaming = true;

    if (task.localFilePath !== null) {
      try {
        const data = await this.readLocalFileChunk(task);
        const completed = task.localFileOffset >= task.localFileSize;
        if (completed) {
          await this.closeLocalFile(task);
          this.tasks.delete(id);
        }
        return new StreamPacket(new Uint8Array(data), completed, completed);
      } catch (error) {
        await this.closeLocalFile(task);
        this.tasks.delete(id);
        throw asFileReadError(task.localFilePath, error as Object);
      }
    }

    const queued = task.queued.shift() ?? new ArrayBuffer(0);
    if (task.completed && task.queued.length === 0) {
      this.tasks.delete(id);
      return new StreamPacket(new Uint8Array(queued), true, true, task.error);
    }
    return new StreamPacket(new Uint8Array(queued), false, false);
  }

  async readChunk(id: string): Promise<StreamPacket> {
    this.assertActive();
    const task = this.requireTask(id);

    if (task.localFilePath !== null) {
      if (task.localFileOffset >= task.localFileSize) {
        await this.closeLocalFile(task);
        this.tasks.delete(id);
        return new StreamPacket(EMPTY_BYTES, true, false, task.error);
      }
      try {
        return new StreamPacket(new Uint8Array(await this.readLocalFileChunk(task)), false, false);
      } catch (error) {
        await this.closeLocalFile(task);
        this.tasks.delete(id);
        throw asFileReadError(task.localFilePath, error as Object);
      }
    }

    if (task.queued.length > 0) {
      const data = task.queued.shift() ?? new ArrayBuffer(0);
      return new StreamPacket(new Uint8Array(data), false, false);
    }
    if (task.completed) {
      this.tasks.delete(id);
      return new StreamPacket(EMPTY_BYTES, true, false, task.error);
    }

    return await new Promise<StreamPacket>((resolve: (packet: StreamPacket) => void): void => {
      task.readers.push(resolve);
    });
  }

  async consumeArrayBuffer(id: string): Promise<ArrayBuffer> {
    this.assertActive();
    const task = this.requireTask(id);

    try {
      await this.awaitCompletion(task);
      this.assertActive();
      if (task.error !== null) throw task.error;
      return task.localFilePath === null ? chunksToBuffer(task.queued) : await readFileBuffer(task.localFilePath, task.localFileSize);
    } catch (error) {
      if (task.localFilePath !== null) {
        throw asFileReadError(task.localFilePath, error as Object);
      }
      throw asFetchError(error as Object);
    } finally {
      await this.closeLocalFile(task);
      this.tasks.delete(id);
    }
  }

  async consumeText(id: string): Promise<string> {
    this.assertActive();
    const task = this.requireTask(id);

    try {
      await this.awaitCompletion(task);
      this.assertActive();
      if (task.error !== null) throw task.error;
      const buffer = task.localFilePath === null ? chunksToBuffer(task.queued) : await readFileBuffer(task.localFilePath, task.localFileSize);
      return new util.TextDecoder('utf-8').decode(new Uint8Array(buffer));
    } catch (error) {
      if (task.localFilePath !== null) {
        throw asFileReadError(task.localFilePath, error as Object);
      }
      throw asFetchError(error as Object);
    } finally {
      await this.closeLocalFile(task);
      this.tasks.delete(id);
    }
  }

  async waitForCompletion(id: string): Promise<void> {
    const task = this.requireTask(id);
    await this.awaitCompletion(task);
    this.assertActive();
  }

  cancel(id: string, error: ExpoFetchError): void {
    const task = this.tasks.get(id);
    if (task === undefined) return;
    if (!task.completed) this.failTask(task, error);
    else this.disposeTask(task);
  }

  cancelStreaming(id: string): void {
    const task = this.tasks.get(id);
    if (task === undefined) return;
    task.error = null;
    this.completeTask(task);
    this.disposeTask(task);
    this.tasks.delete(id);
  }

  discard(id: string): void {
    const task = this.tasks.get(id);
    if (task === undefined) return;
    this.completeTask(task);
    this.disposeTask(task);
    this.tasks.delete(id);
  }

  private async startLocalFile(id: string, inputUrl: string, init: FetchInit, requestBody: Uint8Array | null): Promise<FetchResult> {
    const path = filePathFromUrl(inputUrl);
    const task = new FetchTask(null, inputUrl);
    task.headers = [['content-type', mimeType(path)]];
    const method = init.method.toUpperCase();
    if (method !== 'GET' && method !== 'HEAD') {
      throw new ExpoFetchError('ERR_FETCH_METHOD', `The ${method} method is not supported for file URLs`);
    }
    if (requestBody !== null) {
      throw new ExpoFetchError('ERR_FETCH_BODY', 'A file URL request cannot have a body');
    }

    try {
      if (!(await fs.access(path))) {
        const body = encodeString('File not found');
        task.headers = [
          ['content-type', 'text/plain'],
          ['content-length', String(body.byteLength)],
        ];
        if (method !== 'HEAD') task.queued = [copyBytes(body)];
        task.completed = true;
        this.tasks.set(id, task);
        return new FetchResult(404, inputUrl, false, task.headers, 'File not found');
      }

      const stat = await fs.stat(path);
      if (!stat.isFile()) throw new Error(`Path is not a regular file: ${path}`);
      task.localFilePath = path;
      task.localFileSize = stat.size;
      task.headers.push(['content-length', String(task.localFileSize)]);
      if (method === 'HEAD') task.localFilePath = null;
      task.completed = true;
      this.tasks.set(id, task);
      return new FetchResult(200, inputUrl, false, task.headers);
    } catch (error) {
      throw asFileReadError(path, error as Object);
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
      else {
        attempt.bufferedBytes += chunk.byteLength;
        if (attempt.bufferedBytes > NETSTACK_RESPONSE_LIMIT_BYTES) {
          this.failTask(
            task,
            new ExpoFetchError(
              'ERR_FETCH_RESPONSE_TOO_LARGE',
              `The response exceeded ${NETSTACK_RESPONSE_LIMIT_BYTES} bytes before it could be streamed`,
            ),
          );
          return;
        }
        attempt.chunks.push(chunk);
      }
    });
    attempt.request.on('dataEnd', (): void => {
      attempt.ended = true;
      attempt.settleMetadata();
      if (attempt.accepted && !attempt.discarded) this.finishAttempt(task);
    });
  }

  private receiveChunk(task: FetchTask, values: ArrayBuffer): void {
    if (task.completed) return;
    if (task.streaming && task.readers.length > 0) {
      const resolve = task.readers.shift();
      if (resolve !== undefined) {
        resolve(new StreamPacket(new Uint8Array(values), false, false));
        return;
      }
    }
    task.queued.push(values);
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoFetchError('ERR_FETCH_RUNTIME_DESTROYED', 'The Harmony fetch runtime has been destroyed');
    }
  }

  private assertTaskActive(task: FetchTask): void {
    this.assertActive();
    if (task.error !== null) throw task.error;
  }

  private requireTask(id: string): FetchTask {
    const task = this.tasks.get(id);
    if (task === undefined) {
      throw new ExpoFetchError('ERR_FETCH_TASK_NOT_FOUND', id);
    }
    return task;
  }

  private async awaitCompletion(task: FetchTask): Promise<void> {
    if (task.completed) return;
    await new Promise<void>((resolve: () => void): void => {
      task.completionWaiters.push(resolve);
    });
  }

  private async readLocalFileChunk(task: FetchTask): Promise<ArrayBuffer> {
    if (task.localFilePath === null) return new ArrayBuffer(0);
    const remaining = task.localFileSize - task.localFileOffset;
    if (remaining <= 0) return new ArrayBuffer(0);

    const buffer = new ArrayBuffer(Math.min(64 * 1024, remaining));
    if (task.localFile === null) {
      task.localFile = await fs.open(task.localFilePath, fs.OpenMode.READ_ONLY);
    }
    const count = await fs.read(task.localFile.fd, buffer, { length: buffer.byteLength });
    if (count <= 0) throw new Error(`Unable to read file: ${task.localFilePath}`);

    task.localFileOffset += count;
    return count === buffer.byteLength ? buffer : buffer.slice(0, count);
  }

  private async closeLocalFile(task: FetchTask): Promise<void> {
    if (task.localFile === null) return;
    const file = task.localFile;
    task.localFile = null;
    try {
      await fs.close(file.fd);
    } catch (_error) {}
  }

  private completeTask(task: FetchTask): void {
    if (task.completed) return;
    task.completed = true;
    this.destroyRequest(task);

    while (task.readers.length > 0) {
      const resolve = task.readers.shift();
      if (resolve !== undefined) {
        resolve(new StreamPacket(EMPTY_BYTES, true, false, task.error));
      }
    }
    while (task.completionWaiters.length > 0) {
      const resolve = task.completionWaiters.shift();
      if (resolve !== undefined) resolve();
    }
  }

  private failTask(task: FetchTask, error: ExpoFetchError): void {
    if (task.completed) return;
    task.error = error;
    task.activeAttempt?.failMetadata(error);
    this.completeTask(task);
  }

  private finishAttempt(task: FetchTask): void {
    this.completeTask(task);
  }

  private destroyRequest(task: FetchTask): void {
    const request = task.request;
    task.request = null;
    if (request === null) return;
    try {
      request.destroy();
    } catch (_error) {}
  }

  private disposeTask(task: FetchTask): void {
    this.destroyRequest(task);
    this.closeLocalFile(task).catch((_error: Object): void => {});
  }
}

class NativeResponse extends ExpoSharedObject {
  private readonly runtime: ExpoFetchRuntime;
  private requestId?: string;
  private responseStatus: number = -1;
  private responseStatusText: string = '';
  private responseUrl: string = '';
  private responseRedirected: boolean = false;
  private responseHeaders: string[][] = [];
  private used: boolean = false;
  private streamingCancelled: boolean = false;
  private finalized: boolean = false;
  private released: boolean = false;

  constructor(context: ExpoModuleContext, runtime: ExpoFetchRuntime) {
    super(context);
    this.runtime = runtime;
  }

  attach(id: string): void {
    if (this.requestId !== undefined) {
      throw new ExpoFetchError('ERR_FETCH_REQUEST', 'The response is already attached to a request.');
    }
    this.requestId = id;
  }

  complete(result: FetchResult): void {
    this.responseStatus = result.status;
    this.responseStatusText = result.statusText;
    this.responseUrl = result.url;
    this.responseRedirected = result.redirected;
    this.responseHeaders = result.headers;
  }

  watchCompletion(): void {
    const id = this.requireRequestId();
    this.runtime
      .waitForCompletion(id)
      .then((): void => this.notifyUnusedCompletion())
      .catch((_error: Object): void => this.notifyUnusedCompletion());
  }

  async startStreaming(): Promise<Uint8Array | null> {
    this.beginBodyUse();
    try {
      const packet = await this.runtime.startStreaming(this.requireRequestId());
      if (this.streamingCancelled || this.released) {
        this.finalize();
        return null;
      }
      if (packet.error !== null) {
        this.emitStreamFailure(packet.error);
        return null;
      }
      if (packet.completed) {
        this.finalize();
        return packet.data;
      }
      if (packet.data.byteLength > 0) {
        this.sendEvent('didReceiveResponseData', packet.data);
      }
      this.pumpStream().catch((error: Object): void => {
        this.emitStreamFailure(asFetchError(error));
      });
      return null;
    } catch (error) {
      this.emitStreamFailure(asFetchError(error as Object));
      return null;
    }
  }

  cancelStreaming(_reason: string): void {
    if (this.streamingCancelled) return;
    this.streamingCancelled = true;
    const id = this.requestId;
    if (id !== undefined) this.runtime.cancelStreaming(id);
    this.finalize();
  }

  async arrayBuffer(): Promise<ArrayBuffer> {
    this.beginBodyUse();
    try {
      return await this.runtime.consumeArrayBuffer(this.requireRequestId());
    } finally {
      this.finalize();
    }
  }

  async text(): Promise<string> {
    this.beginBodyUse();
    try {
      return await this.runtime.consumeText(this.requireRequestId());
    } finally {
      this.finalize();
    }
  }

  bodyUsed(): boolean {
    return this.used;
  }

  rawHeaders(): string[][] {
    return this.responseHeaders;
  }

  status(): number {
    return this.responseStatus;
  }

  statusText(): string {
    return this.responseStatusText;
  }

  url(): string {
    return this.responseUrl;
  }

  redirected(): boolean {
    return this.responseRedirected;
  }

  override sharedObjectWillRelease(): void {
    if (this.released) return;
    this.released = true;
    const id = this.requestId;
    if (id !== undefined) this.runtime.discard(id);
  }

  private beginBodyUse(): void {
    if (this.used) {
      throw new ExpoFetchError('ERR_FETCH_BODY_USED', 'The response body has already been consumed.');
    }
    this.used = true;
  }

  private async pumpStream(): Promise<void> {
    while (!this.streamingCancelled && !this.released) {
      const packet = await this.runtime.readChunk(this.requireRequestId());
      if (this.streamingCancelled || this.released) {
        this.finalize();
        return;
      }
      if (packet.error !== null) {
        this.emitStreamFailure(packet.error);
        return;
      }
      if (packet.done) {
        this.sendEvent('didComplete');
        this.finalize();
        return;
      }
      if (packet.data.byteLength > 0) {
        this.sendEvent('didReceiveResponseData', packet.data);
      }
    }
    this.finalize();
  }

  private notifyUnusedCompletion(): void {
    if (!this.used) this.finalize();
  }

  private emitStreamFailure(error: ExpoFetchError): void {
    if (this.released) return;
    this.sendEvent('didFailWithError', formatError(error));
    this.finalize();
  }

  private finalize(): void {
    if (this.finalized || this.released) return;
    this.finalized = true;
    this.sendEvent('readyForJSFinalization');
  }

  private requireRequestId(): string {
    if (this.requestId === undefined) {
      throw new ExpoFetchError('ERR_FETCH_REQUEST', 'The response is not attached to a request.');
    }
    return this.requestId;
  }
}

class NativeRequest extends ExpoSharedObject {
  private readonly runtime: ExpoFetchRuntime;
  private readonly response: NativeResponse;
  private readonly id: string;
  private cancelled: boolean = false;

  constructor(context: ExpoModuleContext, runtime: ExpoFetchRuntime, response: NativeResponse) {
    super(context);
    this.runtime = runtime;
    this.response = response;
    this.id = runtime.allocateRequestId();
    response.attach(this.id);
  }

  async start(inputUrl: string, init: FetchInit, body: Uint8Array | null): Promise<void> {
    try {
      const result = await this.runtime.start(this.id, inputUrl, init, body);
      this.response.complete(result);
      this.response.watchCompletion();
    } catch (error) {
      this.response.watchCompletion();
      throw asFetchError(error as Object);
    }
  }

  cancel(): void {
    if (this.cancelled) return;
    this.cancelled = true;
    this.runtime.cancel(this.id, new ExpoFetchError('ERR_FETCH_REQUEST_CANCELED', 'Fetch request has been canceled'));
  }
}

export class ExpoFetchModule extends ExpoModule {
  private readonly runtime: ExpoFetchRuntime = new ExpoFetchRuntime();

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  override definition(): ExpoModuleDefinition {
    const responseClass = new ExpoSharedObjectClassDefinition<NativeResponse>('NativeResponse')
      .construct((context: ExpoModuleContext): NativeResponse => {
        return new NativeResponse(context, this.runtime);
      })
      .asyncFunction(
        'startStreaming',
        ExpoFunction.ownedTyped0(async (response: NativeResponse): Promise<Uint8Array | null> => {
          return await response.startStreaming();
        }).returns(ExpoValueTypes.uint8Array().nullable()),
      )
      .syncFunction(
        'cancelStreaming',
        ExpoFunction.ownedTyped1(ExpoValueTypes.string(), (response: NativeResponse, reason: string): void => response.cancelStreaming(reason)),
      )
      .asyncFunction(
        'arrayBuffer',
        ExpoFunction.ownedTyped0(async (response: NativeResponse): Promise<ArrayBuffer> => response.arrayBuffer()).returns(
          ExpoValueTypes.arrayBuffer(),
        ),
      )
      .asyncFunction(
        'text',
        ExpoFunction.ownedTyped0(async (response: NativeResponse): Promise<string> => response.text()).returns(ExpoValueTypes.string()),
      )
      .property('bodyUsed', ExpoValueTypes.boolean(), (response: NativeResponse): boolean => response.bodyUsed())
      .property('_rawHeaders', HEADER_PAIRS_TYPE, (response: NativeResponse): string[][] => response.rawHeaders())
      .property('status', ExpoValueTypes.number(), (response: NativeResponse): number => response.status())
      .property('statusText', ExpoValueTypes.string(), (response: NativeResponse): string => response.statusText())
      .property('url', ExpoValueTypes.string(), (response: NativeResponse): string => response.url())
      .property('redirected', ExpoValueTypes.boolean(), (response: NativeResponse): boolean => response.redirected())
      .event('didReceiveResponseData', ExpoValueTypes.uint8Array())
      .event('didFailWithError', ExpoValueTypes.string())
      .events(['didComplete', 'readyForJSFinalization']);

    const requestClass = new ExpoSharedObjectClassDefinition<NativeRequest>('NativeRequest')
      .construct(
        ExpoFunction.ownedTyped1(responseClass.valueType(), (context: ExpoModuleContext, response: NativeResponse): NativeRequest => {
          return new NativeRequest(context, this.runtime, response);
        }),
      )
      .asyncFunction(
        'start',
        ExpoFunction.ownedTyped3(
          ExpoValueTypes.string(),
          FETCH_INIT_TYPE,
          ExpoValueTypes.uint8Array().nullable(),
          async (request: NativeRequest, inputUrl: string, init: FetchInit, body: Uint8Array | null): Promise<void> =>
            request.start(inputUrl, init, body),
        ),
      )
      .syncFunction('cancel', (request: NativeRequest): void => request.cancel());

    return new ExpoModuleDefinition()
      .name('ExpoFetchModule')
      .sharedObjectClass(responseClass)
      .sharedObjectClass(requestClass)
      .onDestroy((): void => this.runtime.destroy());
  }
}

const HEADER_PAIRS_TYPE: ExpoValueType<string[][]> = ExpoValueTypes.array(ExpoValueTypes.array(ExpoValueTypes.string()));

const FETCH_INIT_TYPE: ExpoValueType<FetchInit> = new ExpoValueType<FetchInit>(
  'fetch request init object',
  (value: ESObject, path: string): FetchInit => parseFetchInit(value, path),
  (value: FetchInit): ESObject => encodeFetchInit(value),
);

function parseFetchInit(value: ESObject, path: string): FetchInit {
  const input = requireRecord(value, path);
  const result = new FetchInit();
  const credentials = optionalString(input['credentials'], `${path}.credentials`);
  if (credentials !== undefined) {
    if (credentials !== 'include' && credentials !== 'omit') {
      throw new ExpoModuleError('ERR_INVALID_ARGUMENT', `${path}.credentials expected 'include' or 'omit'.`);
    }
    result.credentials = credentials;
  }
  result.method = optionalString(input['method'], `${path}.method`) ?? 'GET';
  const redirect = optionalString(input['redirect'], `${path}.redirect`);
  if (redirect !== undefined) {
    if (redirect !== 'follow' && redirect !== 'error' && redirect !== 'manual') {
      throw new ExpoModuleError('ERR_INVALID_ARGUMENT', `${path}.redirect expected 'follow', 'error', or 'manual'.`);
    }
    result.redirect = redirect;
  }
  result.headers = optionalHeaderPairs(input['headers'], `${path}.headers`) ?? [];
  return result;
}

function encodeFetchInit(value: FetchInit): ESObject {
  const result = new Object();
  if (value.credentials !== undefined) Reflect.set(result, 'credentials', value.credentials);
  if (value.method !== undefined) Reflect.set(result, 'method', value.method);
  if (value.redirect !== undefined) Reflect.set(result, 'redirect', value.redirect);
  if (value.headers !== undefined) Reflect.set(result, 'headers', value.headers);
  return result;
}

function requireRecord(value: ESObject, path: string): Record<string, ESObject> {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoModuleError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected a fetch request init object.`);
  }
  return value as Record<string, ESObject>;
}

function optionalString(value: ESObject, path: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') {
    throw new ExpoModuleError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected a string.`);
  }
  return value;
}

function optionalHeaderPairs(value: ESObject, path: string): string[][] | undefined {
  if (value === undefined || value === null) return undefined;
  const pairs = HEADER_PAIRS_TYPE.decode(value, path);
  pairs.forEach((pair: string[], index: number): void => {
    if (pair.length !== 2) {
      throw new ExpoModuleError('ERR_INVALID_ARGUMENT', `${path}[${index}] expected exactly two strings.`);
    }
  });
  return pairs;
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
  const pair = headers.find((candidate: string[]): boolean => {
    return candidate.length >= 2 && candidate[0].toLowerCase() === name;
  });
  return pair === undefined ? null : pair[1];
}

function isRedirectStatus(status: number): boolean {
  return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
}

function isFileURL(value: string): boolean {
  return /^file:/i.test(value);
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
  } catch (_error) {
    return false;
  }
}

function withoutHeaders(headers: Object, names: string[]): Object {
  const result = new Object();
  Object.keys(headers).forEach((name: string): void => {
    if (!names.includes(name.toLowerCase())) {
      Reflect.set(result, name, Reflect.get(headers, name));
    }
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

const STATUS_TEXT: Map<number, string> = new Map<number, string>([
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

function statusText(status: number): string {
  return STATUS_TEXT.get(status) ?? '';
}

function mimeType(path: string): string {
  const dot = path.lastIndexOf('.');
  if (dot < 0 || dot === path.length - 1) return 'application/octet-stream';
  try {
    const typeId = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(path.slice(dot));
    const mimeTypes = uniformTypeDescriptor.getTypeDescriptor(typeId).mimeTypes;
    if (mimeTypes.length > 0) return mimeTypes[0];
  } catch (_error) {}
  return 'application/octet-stream';
}

function encodeString(value: string): Uint8Array {
  return new util.TextEncoder('utf-8').encode(value);
}

function copyBytes(bytes: Uint8Array): ArrayBuffer {
  const buffer = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(buffer).set(bytes);
  return buffer;
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

async function readFileBuffer(path: string, size: number): Promise<ArrayBuffer> {
  const output = new ArrayBuffer(size);
  if (size === 0) return output;

  const outputBytes = new Uint8Array(output);
  const chunk = new ArrayBuffer(Math.min(64 * 1024, size));
  const file = await fs.open(path, fs.OpenMode.READ_ONLY);
  try {
    let consumed = 0;
    while (consumed < size) {
      const count = await fs.read(file.fd, chunk, {
        length: Math.min(chunk.byteLength, size - consumed),
      });
      if (count <= 0) throw new ExpoFetchError('ERR_FETCH_FILE_READ', path);
      outputBytes.set(new Uint8Array(chunk, 0, count), consumed);
      consumed += count;
    }
    return output;
  } finally {
    await fs.close(file.fd);
  }
}

async function withStoredCookies(headers: Object, target: string, credentials?: string): Promise<Object> {
  if (credentials !== 'include') return headers;

  let stored = '';
  try {
    stored = await webview.WebCookieManager.fetchCookie(target, false);
  } catch (error) {
    throw new ExpoFetchError('ERR_FETCH_COOKIE_READ', `Unable to read cookies for ${target}: ${errorMessage(error as Object)}`, error as Object);
  }
  if (stored.length === 0) return headers;

  const result = withoutHeaders(headers, ['cookie']);
  const explicit = headerValue(headers, 'cookie');
  Reflect.set(result, 'cookie', mergeCookieHeaders(explicit, stored));
  return result;
}

async function storeResponseCookies(target: string, headers: string[][]): Promise<void> {
  const cookies = headers
    .filter((pair: string[]): boolean => {
      return pair.length >= 2 && pair[0].toLowerCase() === 'set-cookie';
    })
    .map((pair: string[]): string => pair[1]);
  if (cookies.length === 0) return;

  for (const cookie of cookies) {
    try {
      await webview.WebCookieManager.configCookie(target, cookie, false, true);
    } catch (error) {
      console.warn(`[expo-fetch] Ignoring an invalid Set-Cookie value for ${target}: ${errorMessage(error as Object)}`);
    }
  }
  try {
    await webview.WebCookieManager.saveCookieAsync();
  } catch (error) {
    console.warn(`[expo-fetch] Unable to persist cookies for ${target}: ${errorMessage(error as Object)}`);
  }
}

function headerValue(headers: Object, name: string): string | null {
  const key = Object.keys(headers).find((candidate: string): boolean => {
    return candidate.toLowerCase() === name;
  });
  return key === undefined ? null : String(Reflect.get(headers, key));
}

function asFetchError(error: Object): ExpoFetchError {
  if (error instanceof ExpoFetchError) return error;
  return new ExpoFetchError('ERR_FETCH_UNKNOWN', errorMessage(error), error);
}

function asFileReadError(path: string, error: Object): ExpoFetchError {
  if (error instanceof ExpoFetchError) return error;
  return new ExpoFetchError('ERR_FETCH_FILE_READ', `${path}: ${errorMessage(error)}`, error);
}

function formatError(error: ExpoFetchError): string {
  return `${error.code}: ${error.message}`;
}

function errorMessage(error: Object): string {
  try {
    if (error !== null && typeof error === 'object') {
      const message: ESObject = Reflect.get(error, 'message');
      const code: ESObject = Reflect.get(error, 'code');
      if (typeof message === 'string' && message.length > 0) {
        return typeof code === 'number' || typeof code === 'string' ? `${message} (Harmony code ${String(code)})` : message;
      }
    }
  } catch (_error) {}
  return String(error).replace(/^(?:Error:\s*)+/, '');
}

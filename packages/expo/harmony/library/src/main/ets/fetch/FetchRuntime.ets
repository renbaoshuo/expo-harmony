/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoNetworkInspection, ExpoNetworkObservation } from '@expo-harmony/expo-modules-core';
import deviceInfo from '@ohos.deviceInfo';
import fs from '@ohos.file.fs';
import connection from '@ohos.net.connection';
import { rcp } from '@kit.RemoteCommunicationKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import util from '@ohos.util';
import url from '@ohos.url';
import legacyFetch, { LegacyFetchEvent } from 'libexpo_fetch_legacy.so';
import { ExpoFetchError } from './ExpoFetchError';
import { FetchInit, FetchResult, StreamPacket, EMPTY_BYTES } from './FetchTypes';
import {
  copyBytes,
  chunksToBuffer,
  encodeString,
  errorMessage,
  formatError,
  headerFromPairs,
  headerPairs,
  isFileURL,
  isHttpURL,
  isRedirectStatus,
  makeHeaders,
  mimeType,
  requestMethodRequiresBody,
  sameOrigin,
  storeResponseCookies,
  withStoredCookies,
  withoutHeaders,
} from './FetchUtils';
import { filePathFromUrl, headersForDecodedResponse, requestMethodPolicy } from './FetchHeaderPolicy';

const LOCAL_FILE_CHUNK_SIZE = 64 * 1024;
const FILE_NOT_FOUND = 13900002;
const PATH_COMPONENT_NOT_DIRECTORY = 13900018;
const RCP_STATUS_CALLBACK_API = 20;

class FetchTask {
  observation?: ExpoNetworkObservation;
  queued: ArrayBuffer[] = [];
  readers: Array<(packet: StreamPacket) => void> = [];
  completionWaiters: Array<() => void> = [];
  completed: boolean = false;
  streaming: boolean = false;
  error: ExpoFetchError | null = null;
  localFilePath: string | null = null;
  localFile: fs.File | null = null;
  localFileRead: Promise<number> | null = null;
  localFileOffset: number = 0;
  localFileSize: number = 0;
  activeAttempt: FetchAttempt | null = null;
}

class FetchAttempt {
  inspection?: ExpoNetworkInspection;
  cancel?: () => void;
  status: number = 0;
  statusText: string | null = null;
  headers: string[][] = [];
  chunks: ArrayBuffer[] = [];
  accepted: boolean = false;
  discarded: boolean = false;
  ended: boolean = false;
  metadataReady: Promise<void>;
  private metadataSettled: boolean = false;
  private headersReceived: boolean = false;
  private resolveMetadata: () => void = (): void => {};
  private rejectMetadata: (error: Error) => void = (_error: Error): void => {};

  constructor() {
    this.metadataReady = new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
      this.resolveMetadata = resolve;
      this.rejectMetadata = reject;
    });
    this.metadataReady.catch((_error: Error): void => {});
  }

  receiveStatus(status: number): void {
    if (this.metadataSettled) return;

    this.status = status;
    this.settleMetadata();
  }

  receiveHeaders(headers: string[][]): void {
    if (this.metadataSettled) return;

    this.headers = headers;
    this.headersReceived = true;
    this.settleMetadata();
  }

  receiveCompletedResponse(response: rcp.Response): void {
    if (response.reasonPhrase !== undefined) this.statusText = response.reasonPhrase;
    if (this.metadataSettled) return;

    if (response.statusCode < 200) {
      throw new ExpoFetchError('ERR_FETCH_REQUEST', `Fetch received no final response (HTTP ${response.statusCode}).`);
    }

    // Status callbacks can arrive late or pair with informational headers.
    this.status = response.statusCode;
    this.receiveHeaders(headerPairs(response.headers));
  }

  receiveLegacyResponse(status: number, headers: string[][], statusText?: string): void {
    this.statusText = statusText ?? null;
    this.receiveStatus(status);
    this.receiveHeaders(headers);
  }

  private settleMetadata(): void {
    if (!this.headersReceived || this.status === 0) return;

    if (this.status < 200) {
      this.status = 0;
      this.headers = [];
      this.headersReceived = false;

      return;
    }

    this.metadataSettled = true;
    const headers: Record<string, string> = {};
    this.headers.forEach((pair: string[]): void => {
      headers[pair[0]] = pair[1];
    });

    this.inspection?.response(this.status, headers);
    this.resolveMetadata();
  }

  failMetadata(error: ExpoFetchError): void {
    if (this.metadataSettled) return;

    this.metadataSettled = true;
    this.rejectMetadata(new Error(formatError(error)));
  }
}

export class ExpoFetchRuntime {
  private readonly context: ExpoModuleContext;

  private readonly tasks: Map<string, FetchTask> = new Map<string, FetchTask>();
  private session?: rcp.Session;
  private destroyed: boolean = false;
  private nextRequestId: number = 1;

  constructor(context: ExpoModuleContext) {
    this.context = context;
  }

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

    const session = this.session;
    this.session = undefined;
    session?.close();
  }

  async start(id: string, input: string, init: FetchInit, data: Uint8Array | null): Promise<FetchResult> {
    this.assertActive();

    if (isFileURL(input)) {
      return await this.startLocalFile(id, input, init, data);
    }
    if (!isHttpURL(input)) {
      throw new ExpoFetchError('ERR_FETCH_INVALID_URL', `Invalid fetch URL: ${input}`);
    }

    let method = requestMethodPolicy(init.method);
    if (data !== null && (method === 'GET' || method === 'HEAD')) {
      throw new ExpoFetchError('ERR_FETCH_BODY', `The ${method} method cannot have a body`);
    }

    let target = input;
    let body: ArrayBuffer | null = data === null ? null : copyBytes(data);
    let headers = makeHeaders(init);
    let redirects = 0;

    const task = new FetchTask();
    task.observation = ExpoNetworkObservation.start(this.context.runtimeId, input, method);
    this.tasks.set(id, task);

    try {
      while (true) {
        const sent = await withStoredCookies(headers, target, init.credentials);
        this.assertTaskActive(task);

        const attempt = new FetchAttempt();
        attempt.inspection = ExpoNetworkInspection.start(target, method, ExpoNetworkInspection.headers(sent), body ?? undefined);
        task.activeAttempt = attempt;

        const payload = body ?? (requestMethodRequiresBody(method) ? new ArrayBuffer(0) : null);
        this.startAttempt(task, attempt, target, method, sent, payload);

        await attempt.metadataReady;
        const status = attempt.status;
        this.assertNotCancelled(task);

        if (init.credentials === 'include') {
          await storeResponseCookies(target, attempt.headers);
        }

        this.assertNotCancelled(task);

        const location = headerFromPairs(attempt.headers, 'location');
        const redirect = isRedirectStatus(status);

        if (redirect && init.redirect === 'error') {
          attempt.discarded = true;

          throw new ExpoFetchError('ERR_FETCH_REDIRECT', "Redirect is not allowed when redirect mode is 'error'");
        }

        if (redirect && init.redirect === 'follow' && location !== null) {
          this.assertTaskActive(task);
          redirects += 1;

          if (redirects > 20) {
            attempt.discarded = true;

            throw new ExpoFetchError('ERR_FETCH_TOO_MANY_REDIRECTS', 'The fetch request exceeded 20 redirects');
          }

          attempt.inspection?.finish(false);
          attempt.discarded = true;
          this.cancelAttempt(task);

          const next = url.URL.parseURL(location, target).toString();
          if (!isHttpURL(next)) {
            throw new ExpoFetchError('ERR_FETCH_INVALID_URL', `Invalid redirect URL: ${next}`);
          }

          task.observation?.redirect(target, next, status);

          if (!sameOrigin(target, next)) {
            headers = withoutHeaders(headers, ['authorization', 'proxy-authorization', 'cookie', 'cookie2', 'host']);
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

        const received = headersForDecodedResponse(attempt.headers, method, status);
        attempt.accepted = true;

        attempt.chunks.forEach((chunk: ArrayBuffer): void => this.receiveChunk(task, chunk));
        attempt.chunks = [];
        if (attempt.ended) this.completeTask(task);

        return new FetchResult(status, target, redirects > 0, received, attempt.statusText);
      }
    } catch (error) {
      const failure =
        task.error ??
        new ExpoFetchError(
          error instanceof ExpoFetchError ? error.code : 'ERR_FETCH_UNKNOWN',
          error instanceof ExpoFetchError ? error.message : errorMessage(error as Object),
          error instanceof ExpoFetchError ? error.cause : (error as Object),
        );

      if (!task.completed) this.failTask(task, failure);
      this.tasks.delete(id);

      throw new ExpoFetchError(failure.code, failure.message, failure.cause);
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
          this.completeTask(task);
          await this.closeLocalFile(task);
          this.tasks.delete(id);
        }

        return new StreamPacket(new Uint8Array(data), completed);
      } catch (error) {
        return await this.failLocalFile(id, task, error as Object);
      }
    }

    if (task.error !== null) {
      this.tasks.delete(id);

      return new StreamPacket(EMPTY_BYTES, true, task.error);
    }

    // Drain the prefix synchronously to preserve chunk order.
    const data = chunksToBuffer(task.queued);
    task.queued = [];

    if (task.completed) {
      this.tasks.delete(id);

      return new StreamPacket(new Uint8Array(data), true);
    }

    return new StreamPacket(new Uint8Array(data), false);
  }

  async readChunk(id: string): Promise<StreamPacket> {
    this.assertActive();

    const task = this.requireTask(id);

    if (task.localFilePath !== null) {
      if (task.localFileOffset >= task.localFileSize) {
        this.completeTask(task);
        await this.closeLocalFile(task);
        this.tasks.delete(id);

        return new StreamPacket(EMPTY_BYTES, true, task.error);
      }

      try {
        return new StreamPacket(new Uint8Array(await this.readLocalFileChunk(task)), false);
      } catch (error) {
        return await this.failLocalFile(id, task, error as Object);
      }
    }

    if (task.queued.length > 0) {
      const data = task.queued.shift() ?? new ArrayBuffer(0);

      return new StreamPacket(new Uint8Array(data), false);
    }

    if (task.completed) {
      this.tasks.delete(id);

      return new StreamPacket(EMPTY_BYTES, true, task.error);
    }

    const packet = await new Promise<StreamPacket>((resolve: (packet: StreamPacket) => void): void => {
      task.readers.push(resolve);
    });

    if (packet.done) this.tasks.delete(id);

    return packet;
  }

  async consumeArrayBuffer(id: string): Promise<ArrayBuffer> {
    this.assertActive();

    const task = this.requireTask(id);

    try {
      if (task.localFilePath !== null) {
        const data = new Uint8Array(task.localFileSize);
        const chunk = new ArrayBuffer(Math.min(LOCAL_FILE_CHUNK_SIZE, data.byteLength));

        while (task.localFileOffset < data.byteLength) {
          const offset = task.localFileOffset;
          const count = await this.readLocalFileInto(task, chunk);
          data.set(new Uint8Array(chunk, 0, count), offset);
        }

        this.assertTaskActive(task);
        this.completeTask(task);

        return data.buffer;
      }

      await this.awaitCompletion(task);
      this.assertActive();
      if (task.error !== null) throw new ExpoFetchError(task.error.code, task.error.message, task.error.cause);

      return chunksToBuffer(task.queued);
    } catch (error) {
      if (task.localFilePath !== null) {
        return await this.failLocalFile(id, task, error as Object);
      }

      throw new ExpoFetchError(
        error instanceof ExpoFetchError ? error.code : 'ERR_FETCH_UNKNOWN',
        error instanceof ExpoFetchError ? error.message : errorMessage(error as Object),
        error instanceof ExpoFetchError ? error.cause : (error as Object),
      );
    } finally {
      await this.closeLocalFile(task);
      this.tasks.delete(id);
    }
  }

  async consumeText(id: string): Promise<string> {
    const buffer = await this.consumeArrayBuffer(id);
    return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
  }

  async waitForCompletion(id: string): Promise<void> {
    const task = this.requireTask(id);
    await this.awaitCompletion(task);
    this.assertActive();
  }

  cancel(id: string, error: ExpoFetchError): void {
    const task = this.tasks.get(id);
    if (task === undefined) return;

    if (task.completed) {
      task.error = task.error ?? error;
      task.queued = [];
    } else {
      this.failTask(task, error);
    }

    this.closeLocalFile(task).catch((_error: Object): void => {});
  }

  discard(id: string): void {
    this.cancel(id, new ExpoFetchError('ERR_FETCH_REQUEST_CANCELED', 'Fetch request has been canceled'));
    this.tasks.delete(id);
  }

  private async startLocalFile(id: string, input: string, init: FetchInit, data: Uint8Array | null): Promise<FetchResult> {
    const path = filePathFromUrl(input);
    this.context.assertFileAccess(path);

    const method = init.method.toUpperCase();

    if (method !== 'GET' && method !== 'HEAD') {
      throw new ExpoFetchError('ERR_FETCH_METHOD', `The ${method} method is not supported for file URLs`);
    }
    if (data !== null) {
      throw new ExpoFetchError('ERR_FETCH_BODY', 'A file URL request cannot have a body');
    }

    const task = new FetchTask();
    this.tasks.set(id, task);

    let file: fs.File | undefined;

    try {
      try {
        file = await fs.open(path, fs.OpenMode.READ_ONLY | fs.OpenMode.NONBLOCK);
      } catch (error) {
        this.assertTaskActive(task);

        const code = (error as BusinessError).code;
        if (code !== FILE_NOT_FOUND && code !== PATH_COMPONENT_NOT_DIRECTORY) {
          throw new ExpoFetchError('ERR_FETCH_FILE_READ', `${path}: ${errorMessage(error as Object)}`, error as Object);
        }

        const body = encodeString('File not found');
        const headers = [
          ['content-type', 'text/plain'],
          ['content-length', String(body.byteLength)],
        ];

        if (method !== 'HEAD') task.queued = [copyBytes(body)];
        this.completeTask(task);

        return new FetchResult(404, input, false, headers, 'File not found');
      }

      this.assertTaskActive(task);

      const stat = await fs.stat(file.fd);

      this.assertTaskActive(task);
      if (!stat.isFile()) throw new Error(`Path is not a regular file: ${path}`);

      if (method === 'HEAD' || stat.size === 0) {
        this.completeTask(task);
      } else {
        // Retain the same descriptor used to determine the body size.
        task.localFilePath = path;
        task.localFileSize = stat.size;
        task.localFile = file;
        file = undefined;
      }

      return new FetchResult(200, input, false, [['content-type', mimeType(path)], ['content-length', String(stat.size)]]);
    } catch (error) {
      this.tasks.delete(id);

      throw new ExpoFetchError(
        error instanceof ExpoFetchError ? error.code : 'ERR_FETCH_FILE_READ',
        error instanceof ExpoFetchError ? error.message : `${path}: ${errorMessage(error as Object)}`,
        error instanceof ExpoFetchError ? error.cause : (error as Object),
      );
    } finally {
      if (file !== undefined) {
        try {
          await fs.close(file.fd);
        } catch (_error) {}
      }
    }
  }

  private startAttempt(
    task: FetchTask,
    attempt: FetchAttempt,
    target: string,
    method: string,
    headers: rcp.RequestHeaders,
    body: ArrayBuffer | null,
  ): void {
    const transfer = deviceInfo.sdkApiVersion >= RCP_STATUS_CALLBACK_API
      ? this.startRcpAttempt(task, attempt, target, method, headers, body)
      : this.startLegacyAttempt(task, attempt, target, method, headers, body);

    transfer
      .then((): void => {
        if (attempt.discarded || task.completed) return;

        attempt.ended = true;
        attempt.inspection?.finish();
        if (attempt.accepted) this.completeTask(task);
      })
      .catch((error: Object): void => {
        attempt.inspection?.fail(false);

        if (attempt.discarded || task.completed) return;

        this.failTask(
          task,
          error instanceof ExpoFetchError ? error : new ExpoFetchError('ERR_FETCH_UNKNOWN', errorMessage(error), error),
        );
      });
  }

  private async startRcpAttempt(
    task: FetchTask,
    attempt: FetchAttempt,
    target: string,
    method: string,
    headers: rcp.RequestHeaders,
    body: ArrayBuffer | null,
  ): Promise<void> {
    const session = this.session ?? rcp.createSession();
    this.session = session;

    const request = new rcp.Request(target, method, headers);
    if (body !== null) request.content = body;
    attempt.cancel = (): void => {
      session.cancel(request);
    };

    request.configuration = {
      transfer: {
        autoRedirect: false,
        timeout: { connectMs: 0, transferMs: 0 },
      },
      tracing: {
        httpEventsHandler: {
          onStatusCodeReceive: (status: number): void => {
            if (attempt.discarded || task.completed) return;

            attempt.receiveStatus(status);
          },
          onHeaderReceive: (headers: rcp.ResponseHeaders): void => {
            if (attempt.discarded || task.completed) return;

            attempt.receiveHeaders(headerPairs(headers));
          },
          // Supplying onDataReceive also disables RCP's whole-body buffering.
          onDataReceive: (chunk: ArrayBuffer): void => {
            this.receiveAttemptChunk(task, attempt, chunk);
          },
        },
      },
    };

    const response = await session.fetch(request);

    if (!attempt.discarded && !task.completed) attempt.receiveCompletedResponse(response);
  }

  private async startLegacyAttempt(
    task: FetchTask,
    attempt: FetchAttempt,
    target: string,
    method: string,
    headers: rcp.RequestHeaders,
    body: ArrayBuffer | null,
  ): Promise<void> {
    const proxy = await connection.getDefaultHttpProxy();

    if (attempt.discarded || task.completed) return;

    const host = url.URL.parseURL(target).hostname.toLowerCase();
    const bypass = proxy.exclusionList.some((entry: string): boolean => {
      const pattern = entry.toLowerCase().trim().replace(/[.+?^$\x7b\x7d()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
      return new RegExp(`^${pattern}$`).test(host);
    });

    return new Promise<void>((resolve: () => void, reject: (error: Object) => void): void => {
      attempt.cancel = legacyFetch.start({
        url: target,
        method,
        headers: headerPairs(headers),
        body,
        proxyHost: bypass ? '' : proxy.host,
        proxyPort: proxy.port,
        proxyUsername: proxy.username ?? '',
        proxyPassword: proxy.password ?? '',
      }, (event: LegacyFetchEvent): void => {
        if (event.error !== undefined) {
          reject(new ExpoFetchError('ERR_FETCH_REQUEST', event.error));
        } else if (event.status !== undefined && event.headers !== undefined) {
          if (!attempt.discarded && !task.completed) {
            attempt.receiveLegacyResponse(event.status, event.headers, event.statusText);
          }
        } else if (event.data !== undefined) {
          this.receiveAttemptChunk(task, attempt, event.data);
        } else {
          resolve();
        }
      });
    });
  }

  private receiveAttemptChunk(task: FetchTask, attempt: FetchAttempt, chunk: ArrayBuffer): void {
    if (attempt.discarded || task.completed) return;

    attempt.inspection?.data(chunk);
    if (attempt.accepted) this.receiveChunk(task, chunk);
    else attempt.chunks.push(chunk);
  }

  private receiveChunk(task: FetchTask, data: ArrayBuffer): void {
    if (task.completed) return;

    if (task.streaming && task.readers.length > 0) {
      const resolve = task.readers.shift();
      if (resolve !== undefined) {
        resolve(new StreamPacket(new Uint8Array(data), false));

        return;
      }
    }

    task.queued.push(data);
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoFetchError('ERR_FETCH_RUNTIME_DESTROYED', 'The Harmony fetch runtime has been destroyed');
    }
  }

  private assertTaskActive(task: FetchTask): void {
    this.assertActive();
    if (task.error !== null) throw new ExpoFetchError(task.error.code, task.error.message, task.error.cause);
    if (task.completed) throw new ExpoFetchError('ERR_FETCH_REQUEST_CANCELED', 'Fetch request has been canceled');
  }

  private assertNotCancelled(task: FetchTask): void {
    // After headers, transfer errors belong to the body.
    this.assertActive();
    const error = task.error;
    if (error?.code === 'ERR_FETCH_REQUEST_CANCELED') {
      throw new ExpoFetchError(error.code, error.message, error.cause);
    }
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
    const buffer = new ArrayBuffer(Math.min(LOCAL_FILE_CHUNK_SIZE, task.localFileSize - task.localFileOffset));
    const count = await this.readLocalFileInto(task, buffer);

    return count === buffer.byteLength ? buffer : buffer.slice(0, count);
  }

  private async readLocalFileInto(task: FetchTask, buffer: ArrayBuffer): Promise<number> {
    const pending = this.readLocalFile(task, buffer);
    task.localFileRead = pending;

    try {
      return await pending;
    } finally {
      task.localFileRead = null;
    }
  }

  private async readLocalFile(task: FetchTask, buffer: ArrayBuffer): Promise<number> {
    this.assertTaskActive(task);

    const length = Math.min(buffer.byteLength, task.localFileSize - task.localFileOffset);
    if (length <= 0) return 0;
    if (task.localFile === null) throw new Error('The response file is closed.');

    const count = await fs.read(task.localFile.fd, buffer, { length });

    this.assertTaskActive(task);
    if (count <= 0) throw new Error(`Unable to read file: ${task.localFilePath}`);

    task.localFileOffset += count;

    return count;
  }

  private async closeLocalFile(task: FetchTask): Promise<void> {
    if (task.localFileRead !== null) {
      // An in-flight read still owns the descriptor.
      try {
        await task.localFileRead;
      } catch (_error) {}
    }

    if (task.localFile === null) return;

    const file = task.localFile;
    task.localFile = null;

    try {
      await fs.close(file.fd);
    } catch (_error) {}
  }

  private async failLocalFile(id: string, task: FetchTask, error: Object): Promise<never> {
    const failure = error instanceof ExpoFetchError
      ? error
      : new ExpoFetchError('ERR_FETCH_FILE_READ', `${task.localFilePath}: ${errorMessage(error)}`, error);

    this.failTask(task, failure);
    await this.closeLocalFile(task);
    this.tasks.delete(id);

    throw new ExpoFetchError(failure.code, failure.message, failure.cause);
  }

  private completeTask(task: FetchTask): void {
    if (task.completed) return;

    task.completed = true;
    task.observation?.finish(task.activeAttempt?.status || null, task.error?.message ?? null);
    this.cancelAttempt(task);

    while (task.readers.length > 0) {
      const resolve = task.readers.shift();
      if (resolve !== undefined) {
        resolve(new StreamPacket(EMPTY_BYTES, true, task.error));
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
    task.queued = [];
    task.activeAttempt?.inspection?.fail(error.code === 'ERR_FETCH_REQUEST_CANCELED');
    task.activeAttempt?.failMetadata(error);
    this.completeTask(task);
  }

  private cancelAttempt(task: FetchTask): void {
    const attempt = task.activeAttempt;
    if (attempt === null) return;

    attempt.inspection?.fail(true);
    attempt.discarded = true;
    attempt.chunks = [];
    attempt.failMetadata(task.error ?? new ExpoFetchError('ERR_FETCH_REQUEST_CANCELED', 'Fetch request has been canceled'));

    if (!attempt.ended) {
      try {
        attempt.cancel?.();
      } catch (_error) {}
    }
  }
}

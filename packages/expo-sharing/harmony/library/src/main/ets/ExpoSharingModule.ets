/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoAbilityLifecycleSubscriber,
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueType,
  ExpoValueTypes,
  copyWant,
  fileUriFromPath,
} from '@expo-harmony/expo-modules-core';
import { util } from '@kit.ArkTS';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { systemShare } from '@kit.ShareKit';
import { wantConstant } from '@kit.AbilityKit';
import type { Want, common } from '@kit.AbilityKit';
import uri from '@ohos.uri';
import urls from '@ohos.url';

const SHARE_CAPABILITY: string = 'SystemCapability.Collaboration.SystemShare';
const SEND_ACTION: string = 'ohos.want.action.sendData';
const SEND_MULTIPLE_ACTION: string = 'ohos.want.action.sendMultipleData';
const URL_TIMEOUT_MS: number = 5000;
const MODULE_NAME: string = 'ExpoSharing';
const INCOMING_SHARE_EVENT: string = 'onSharedPayloadsChanged';
const SHARE_SCHEME_METADATA: string = 'expo.sharing.scheme';
const MAX_FILE_NAME_BYTES: number = 255;
const MAX_SHARED_RECORDS: number = 500;
const FILE_GRANT_FLAGS: number =
  wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION | wantConstant.Flags.FLAG_AUTH_WRITE_URI_PERMISSION;

interface ShareFile {
  uri: string;
  name: string;
}

interface SharePreview {
  utd: string;
  mode: systemShare.SharePreviewMode;
}

type ShareType = 'text' | 'url' | 'audio' | 'image' | 'video' | 'file';
type ContentType = 'text' | 'audio' | 'image' | 'video' | 'file' | 'website';
type HeaderValue = string | number | Array<string> | undefined;

interface SharePayload {
  value: string;
  shareType: ShareType;
  mimeType?: string;
}

interface ResolvedSharePayload extends SharePayload {
  contentUri: string | null;
  contentType: ContentType | null;
  contentMimeType: string | null;
  originalName: string | null;
  contentSize: number | null;
}

interface ShareSession {
  cancellation?: ExpoSharingError;
  cancelPanel?: (error: ExpoSharingError) => void;
}

class SharingAnchor {
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
}

class SharingOptions {
  mimeType?: string = undefined;
  UTI?: string = undefined;
  dialogTitle?: string = undefined;
  anchor?: SharingAnchor = undefined;
}

const SHARING_OPTIONS_TYPE: ExpoValueType<SharingOptions> = new ExpoValueType<SharingOptions>(
  'SharingOptions object',
  (value: ESObject, path: string): SharingOptions => decodeSharingOptions(value, path),
  (value: SharingOptions): ESObject => encodeSharingOptions(value),
);

class ExpoSharingError extends ExpoModuleError {
  constructor(code: string, message: string, cause?: Object) {
    super(code, message, cause);
    this.name = 'ExpoSharingError';
  }
}

interface ErrorLike {
  message?: string;
}

interface ResolvedRecord {
  payload: ResolvedSharePayload;
  file?: string;
}

interface IncomingRecord {
  payload: SharePayload;
  originalName?: string;
}

class IncomingGeneration {
  records: IncomingRecord[] = [];
  resolved?: ResolvedSharePayload[] = undefined;
  failure?: string = undefined;
  loading: Promise<void> = Promise.resolve();
  resolving?: Promise<void> = undefined;
  ready: boolean = false;
  cancelled: boolean = false;
  cancelRequest?: () => void;
  readonly files: Set<string> = new Set<string>();
}

const states: WeakMap<Object, IncomingShareState> = new WeakMap<Object, IncomingShareState>();

class IncomingShareState {
  private readonly cache: string;
  private destroyed: boolean = false;
  private generation: IncomingGeneration = new IncomingGeneration();
  private readonly listeners: Set<() => void> = new Set<() => void>();

  constructor(cache: string) {
    this.cache = cache;
    this.generation.ready = true;
  }

  receive(want: Want): void {
    if (this.destroyed || !isShareWant(want)) return;

    const generation = new IncomingGeneration();

    this.replaceGeneration(generation);
    generation.loading = this.load(want, generation);
  }

  getPayloads(): SharePayload[] {
    const generation = this.generation;

    if (generation.failure !== undefined) {
      throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', `Failed to read incoming share data: ${generation.failure}`);
    }

    if (!generation.ready) return [];

    return generation.records.map((record: IncomingRecord): SharePayload => record.payload);
  }

  async getResolvedPayloads(): Promise<ResolvedSharePayload[]> {
    while (true) {
      const generation = this.generation;

      await generation.loading;

      if (generation !== this.generation || generation.cancelled) continue;
      if (generation.failure !== undefined) {
        throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', `Failed to read incoming share data: ${generation.failure}`);
      }

      if (generation.resolved !== undefined) return generation.resolved;

      if (generation.resolving === undefined) {
        generation.resolving = this.resolve(generation).finally((): void => {
          generation.resolving = undefined;
        });
      }

      try {
        await generation.resolving;
      } catch (error) {
        if (generation !== this.generation || generation.cancelled) continue;

        throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', `Failed to resolve incoming share data: ${errorMessage(error as Object)}`);
      }

      if (generation !== this.generation || generation.cancelled) continue;

      if (generation.resolved !== undefined) return generation.resolved;
    }
  }

  clear(): void {
    const generation = new IncomingGeneration();

    generation.ready = true;
    generation.resolved = [];
    this.replaceGeneration(generation);

    this.notify();
  }

  addListener(listener: () => void): void {
    this.listeners.add(listener);
  }

  removeListener(listener: () => void): void {
    this.listeners.delete(listener);
  }

  destroy(): void {
    this.destroyed = true;
    this.listeners.clear();

    const generation = new IncomingGeneration();

    generation.ready = true;
    this.replaceGeneration(generation);
  }

  private async load(want: Want, generation: IncomingGeneration): Promise<void> {
    try {
      const records = await readIncomingRecords(want);

      if (!this.isCurrent(generation)) return;

      generation.records = records;
    } catch (error) {
      if (!this.isCurrent(generation)) return;

      generation.failure = errorMessage(error as Object);
    } finally {
      if (!this.isCurrent(generation)) return;

      generation.ready = true;
      this.notify();
    }
  }

  private async resolve(generation: IncomingGeneration): Promise<void> {
    const resolved: ResolvedSharePayload[] = [];

    try {
      for (const record of generation.records) {
        this.assertCurrent(generation);

        const result = await resolvedPayloadFromRecord(record, this.cache, generation);

        if (result.file !== undefined) generation.files.add(result.file);
        this.assertCurrent(generation);

        resolved.push(result.payload);
      }

      this.assertCurrent(generation);
      generation.resolved = resolved;
    } catch (error) {
      await this.cleanup(generation);

      throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', errorMessage(error as Object), error as Object);
    }
  }

  private replaceGeneration(generation: IncomingGeneration): void {
    const previous = this.generation;

    previous.cancelled = true;
    this.generation = generation;
    previous.cancelRequest?.();

    // Keep returned cache URIs usable after another share or clear.
    if (previous.resolved === undefined) this.cleanup(previous).catch((): void => {});
  }

  private isCurrent(generation: IncomingGeneration): boolean {
    return !generation.cancelled && generation === this.generation;
  }

  private assertCurrent(generation: IncomingGeneration): void {
    if (!this.isCurrent(generation)) {
      throw new ExpoSharingError('ERR_SHARING_REQUEST_CANCELLED', 'Incoming share resolution was superseded by a newer payload.');
    }
  }

  private async cleanup(generation: IncomingGeneration): Promise<void> {
    const files = Array.from(generation.files);

    generation.files.clear();

    for (const file of files) {
      try {
        await fileIo.unlink(file);
      } catch (_) {}
    }
  }

  private notify(): void {
    this.listeners.forEach((listener: () => void): void => {
      try {
        listener();
      } catch (error) {
        console.warn(`Unable to deliver Expo Sharing payloads: ${String(error)}`);
      }
    });
  }
}

export class ExpoSharingLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  private readonly incoming: IncomingShareState;
  private readonly route?: string;

  constructor(context: common.UIAbilityContext) {
    super(context);
    this.incoming = new IncomingShareState(context.cacheDir);
    const scheme = context.abilityInfo.metadata?.find((entry): boolean => entry.name === SHARE_SCHEME_METADATA)?.value;
    if (scheme !== undefined && /^[a-z][a-z0-9+.-]*$/i.test(scheme)) {
      this.route = `${scheme}://expo-sharing`;
    }
    states.set(context, this.incoming);
  }

  override onWillReceiveWant(want: Want): void {
    if (!isShareWant(want)) return;

    // Linking receives only the app's share route. Share Kit reads the original Want.
    this.incoming.receive(copyWant(want));
    want.uri = this.route;
  }

  override onDestroy(): void {
    this.incoming.destroy();
    states.delete(this.context);
  }
}

function incomingState(context: ExpoModuleContext): IncomingShareState {
  const session = context.session;
  const existing = session === undefined ? undefined : states.get(session);

  if (existing !== undefined) return existing;

  const state = new IncomingShareState(context.cachePath);
  if (context.initialWant !== undefined) state.receive(context.initialWant);

  if (session === undefined) return state;

  states.set(session, state);
  session.onClose((): void => {
    state.destroy();
    states.delete(session);
  });

  return state;
}

export class ExpoSharingModule extends ExpoModule {
  private readonly incoming?: IncomingShareState;
  private readonly receivesModuleWants: boolean;
  private observing: boolean = false;
  private destroyed: boolean = false;
  private session: ShareSession | undefined = undefined;
  private readonly onIncomingChange = (): void => {
    if (!this.destroyed && this.observing) this.sendEvent(INCOMING_SHARE_EVENT);
  };

  constructor(context: ExpoModuleContext) {
    super(context);

    // The subscriber owns the original Wants before the host rewrites their URI for Linking.
    const state = context.isHeadless ? undefined : states.get(context.uiAbilityContext);
    this.receivesModuleWants = !context.isHeadless && state === undefined;
    if (!context.isHeadless) this.incoming = state ?? incomingState(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name(MODULE_NAME)
      .events([INCOMING_SHARE_EVENT])
      .asyncFunction(
        'shareAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), SHARING_OPTIONS_TYPE, async (url: string, options: SharingOptions): Promise<void> => {
          if (url.length === 0) {
            throw new ExpoSharingError('ERR_SHARING_INVALID_ARGS', 'URL must be a non-empty string.');
          }

          await this.share(url, options);
        }),
      )
      .asyncFunction('isAvailableAsync', async (): Promise<boolean> => {
        return (
          !this.destroyed &&
          this.context.isValid &&
          !this.context.isHeadless &&
          canIUse(SHARE_CAPABILITY)
        );
      })
      .syncFunction('getSharedPayloads', (): SharePayload[] => this.incoming?.getPayloads() ?? [])
      .asyncFunction('getResolvedSharedPayloadsAsync', async (): Promise<ResolvedSharePayload[]> => {
        return (await this.incoming?.getResolvedPayloads()) ?? [];
      })
      .syncFunction('clearSharedPayloads', (): void => this.incoming?.clear())
      .onStartObserving(INCOMING_SHARE_EVENT, (): void => this.startObserving())
      .onStopObserving(INCOMING_SHARE_EVENT, (): void => this.stopObserving())
      .onNewWant((want: Want): void => {
        if (this.receivesModuleWants) this.incoming?.receive(want);
      })
      .onWindowStageWillDestroy((): void => {
        this.cancelShare(new ExpoSharingError('ERR_SHARING_UNAVAILABLE', 'The sharing window was closed.'));
      })
      .onDestroy((): void => this.destroy());
  }

  private startObserving(): void {
    if (this.destroyed || this.observing) return;

    this.observing = true;
    this.incoming?.addListener(this.onIncomingChange);
  }

  private stopObserving(): void {
    if (!this.observing) return;

    this.observing = false;
    this.incoming?.removeListener(this.onIncomingChange);
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.stopObserving();

    if (this.receivesModuleWants && this.context.session === undefined) {
      this.incoming?.destroy();
    }

    this.cancelShare(new ExpoSharingError('ERR_SHARING_RUNTIME_DESTROYED', 'The Expo Sharing runtime has already been destroyed.'));
  }

  private cancelShare(error: ExpoSharingError): void {
    const session = this.session;
    if (session === undefined || session.cancellation !== undefined) return;

    session.cancellation = error;
    session.cancelPanel?.(error);
  }

  private async share(url: string, options: SharingOptions): Promise<void> {
    if (this.session !== undefined) {
      throw new ExpoSharingError('ERR_SHARING_IN_PROGRESS', 'Another share request is being processed now.');
    }

    this.assertActive();

    const session: ShareSession = {};
    this.session = session;

    try {
      const mime = normalizedMimeType(options.mimeType);

      if (options.dialogTitle !== undefined) {
        this.context.logger.warn('HarmonyOS Share Kit does not support a custom sharing panel title; dialogTitle was ignored.');
      }

      const file = await prepareShareFile(url, this.context);
      const preview = resolvePreview(file.name, mime);

      const cancellation = session.cancellation;
      if (cancellation !== undefined) {
        throw new ExpoSharingError(cancellation.code, cancellation.message, cancellation.cause);
      }
      this.assertActive();

      try {
        const data = new systemShare.SharedData({
          utd: preview.utd,
          uri: file.uri,
          title: file.name,
        });
        const controller = new systemShare.ShareController(data);
        const config: systemShare.ShareControllerOptions = {
          selectionMode: systemShare.SelectionMode.SINGLE,
          previewMode: preview.mode,
          anchor: await readAnchor(options.anchor, this.context),
        };

        this.assertActive();
        await showShare(controller, this.context, config, session);
      } catch (error) {
        if (error instanceof ExpoSharingError) {
          throw new ExpoSharingError(error.code, error.message, error.cause);
        }

        throw new ExpoSharingError('ERR_SHARING_FAILED', `Failed to share the file: ${errorMessage(error as Object)}`, error as Object);
      }
    } finally {
      if (this.session === session) this.session = undefined;
    }
  }

  private assertActive(): void {
    if (this.destroyed || !this.context.isValid) {
      throw new ExpoSharingError('ERR_SHARING_RUNTIME_DESTROYED', 'The Expo Sharing runtime has already been destroyed.');
    }
    if (this.context.isHeadless || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoSharingError('ERR_SHARING_UNAVAILABLE', 'Sharing requires a foreground UIAbility window.');
    }
    if (!canIUse(SHARE_CAPABILITY)) {
      throw new ExpoSharingError('ERR_SHARING_UNAVAILABLE', 'The HarmonyOS system sharing capability is unavailable on this device.');
    }
  }
}

async function showShare(
  controller: systemShare.ShareController,
  context: ExpoModuleContext,
  config: systemShare.ShareControllerOptions,
  session: ShareSession,
): Promise<void> {
  const cancellation = session.cancellation;
  if (cancellation !== undefined) {
    throw new ExpoSharingError(cancellation.code, cancellation.message, cancellation.cause);
  }

  let dismiss: () => void = (): void => {};
  const done = new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
    dismiss = resolve;
    session.cancelPanel = reject;
  });

  try {
    controller.on('dismiss', dismiss);

    // show() can remain pending after dismissal or teardown.
    const shown = controller.show(context.uiAbilityContext, config).then((): Promise<void> => done);
    await Promise.race([done, shown]);
  } finally {
    session.cancelPanel = undefined;

    try {
      controller.off('dismiss', dismiss);
    } catch (error) {
      context.logger.warn(`Unable to remove the Expo Sharing dismissal listener: ${String(error)}`);
    }
  }
}

async function prepareShareFile(url: string, context: ExpoModuleContext): Promise<ShareFile> {
  let source: uri.URI;

  try {
    source = new uri.URI(url);
  } catch (_) {
    throw new ExpoSharingError('ERR_SHARING_INVALID_URL', 'The URL to share is not a valid URI.');
  }

  if (source.scheme !== 'file') {
    throw new ExpoSharingError(
      'ERR_SHARING_INVALID_URL',
      `Only local file URLs are supported (expected scheme to be 'file', got '${source.scheme}').`,
    );
  }

  let file: fileIo.File | undefined;

  try {
    const target = context.fileSourceForRead(url);
    file = await fileIo.open(target, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);

    if (!(await fileIo.stat(file.fd)).isFile()) {
      throw new ExpoSharingError('ERR_SHARING_INVALID_URL', 'The URL to share does not point to a file.');
    }

    if (!target.startsWith('/')) return { uri: target, name: nameFromURI(target) ?? 'shared-file' };

    try {
      const path = context.readPathForDescriptor(target, file);

      return { uri: fileUri.getUriFromPath(path), name: path.slice(path.lastIndexOf('/') + 1) };
    } catch (error) {
      throw new ExpoSharingError('ERR_SHARING_FAILED', `The local file URI cannot be created: ${errorMessage(error as Object)}`, error as Object);
    }
  } catch (error) {
    if (error instanceof ExpoSharingError) {
      throw new ExpoSharingError(error.code, error.message, error.cause);
    }

    throw new ExpoSharingError(
      'ERR_SHARING_INVALID_URL',
      `The application or user file URI cannot be read: ${errorMessage(error as Object)}`,
      error as Object,
    );
  } finally {
    if (file !== undefined) {
      try { await fileIo.close(file); } catch (_) {}
    }
  }
}

function resolvePreview(name: string, mime: string | undefined): SharePreview {
  let utd: string = uniformTypeDescriptor.UniformDataType.FILE;
  let type: uniformTypeDescriptor.TypeDescriptor | null = null;

  try {
    if (mime !== undefined) {
      if (mime !== '*/*') utd = uniformTypeDescriptor.getUniformDataTypeByMIMEType(mime);
    } else {
      const dot = name.lastIndexOf('.');

      if (dot >= 0 && dot + 1 < name.length) {
        utd = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(name.slice(dot));
      }
    }

    type = uniformTypeDescriptor.getTypeDescriptor(utd);
  } catch (_) {}

  if (type === null) {
    try {
      const dot = name.lastIndexOf('.');
      if (dot >= 0 && dot + 1 < name.length) {
        utd = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(name.slice(dot));
        type = uniformTypeDescriptor.getTypeDescriptor(utd);
      }
    } catch (_) {}
  }
  if (type === null) utd = uniformTypeDescriptor.UniformDataType.FILE;

  if (type !== null) {
    if (type.belongsTo(uniformTypeDescriptor.UniformDataType.IMAGE)
      || type.belongsTo(uniformTypeDescriptor.UniformDataType.VIDEO)) {
      return { utd, mode: systemShare.SharePreviewMode.DETAIL };
    }

    // Share Kit represents text and links as inline content. shareAsync always sends a file URI.
    if (type.belongsTo(uniformTypeDescriptor.UniformDataType.TEXT)
      || type.belongsTo(uniformTypeDescriptor.UniformDataType.HYPERLINK)) {
      utd = uniformTypeDescriptor.UniformDataType.FILE;
    }
  }

  return { utd, mode: systemShare.SharePreviewMode.DEFAULT };
}

function isShareWant(want: Want): boolean {
  return want.action === SEND_ACTION || want.action === SEND_MULTIPLE_ACTION;
}

async function readIncomingRecords(want: Want): Promise<IncomingRecord[]> {
  try {
    if (canIUse(SHARE_CAPABILITY)) {
      const data = await systemShare.getSharedData(want);
      const records: IncomingRecord[] = [];

      for (const source of data.getRecords()) {
        const record = recordFromShareKit(source);
        if (record !== undefined) records.push(record);
      }

      if (records.length > 0) return records;
    }
  } catch (error) {
    const records = recordsFromFileWant(want);
    if (records.length > 0) return records;

    throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', errorMessage(error as Object), error as Object);
  }

  return recordsFromFileWant(want);
}

// A plain Stage-model Want can carry a grant without a serialized Share Kit payload.
function recordsFromFileWant(want: Want): IncomingRecord[] {
  if (((want.flags ?? 0) & FILE_GRANT_FLAGS) === 0) return [];

  const mimeType = normalizedMimeType(want.type) ?? 'application/octet-stream';
  const contentType = contentTypeFromMime(mimeType);
  const shareType: ShareType =
    contentType === 'audio' || contentType === 'image' || contentType === 'video' ? contentType : 'file';

  const values = new Set<string>();
  const direct = want.uri;
  if (direct !== undefined && isSharedFileUri(direct)) values.add(direct);

  const stream: ESObject = want.parameters?.[wantConstant.Params.PARAMS_STREAM];
  if (Array.isArray(stream)) {
    const entries = stream as string[];
    for (const value of entries.slice(0, MAX_SHARED_RECORDS)) {
      const source = optionalString(value);
      if (source !== undefined && isSharedFileUri(source)) values.add(source);
    }
  }

  return Array.from(values).slice(0, MAX_SHARED_RECORDS).map((value: string): IncomingRecord => ({
    payload: { value, shareType, mimeType },
  }));
}

function recordFromShareKit(record: systemShare.SharedRecord): IncomingRecord | undefined {
  const source = optionalString(record.uri);
  const content = optionalString(record.content);
  const file = source !== undefined && isSharedFileUri(source);
  const value = source !== undefined && (file || isWebURL(source)) ? source : content;
  if (value === undefined) return undefined;

  const type = typeDescriptor(record.utd);
  const shareType: ShareType = file ? fileShareType(type) : isWebURL(value) ? 'url' : 'text';
  // Upstream handles inline links as text/plain.
  const mime = shareType === 'url' ? defaultMimeType(shareType) :
    normalizedMimeType(type?.mimeTypes[0]) ?? defaultMimeType(shareType);

  return {
    payload: { value, shareType, mimeType: mime },
    originalName: optionalString(record.title),
  };
}

async function resolvedPayloadFromRecord(
  record: IncomingRecord,
  cache: string,
  generation: IncomingGeneration,
): Promise<ResolvedRecord> {
  const payload = record.payload;

  if (payload.shareType === 'text') {
    return {
      payload: {
        value: payload.value,
        shareType: payload.shareType,
        mimeType: payload.mimeType,
        contentUri: null,
        contentType: null,
        contentMimeType: null,
        originalName: null,
        contentSize: null,
      },
    };
  }

  if (payload.shareType === 'url') return await resolveURLPayload(payload, generation);

  return await resolveFilePayload(payload, record.originalName, cache);
}

async function resolveURLPayload(payload: SharePayload, generation: IncomingGeneration): Promise<ResolvedRecord> {
  try {
    if (!isWebURL(payload.value)) throw new Error('Shared links must have an HTTP or HTTPS URL.');

    const response = await streamURLHeaders(payload.value, generation);
    const headers = response.headers;
    const url = response.url;

    const mime = normalizedMimeType(headerValue(headers, 'content-type')) ?? 'text/plain';
    const disposition = headerValue(headers, 'content-disposition');

    return {
      payload: {
        value: payload.value,
        shareType: payload.shareType,
        mimeType: payload.mimeType,
        contentUri: url,
        contentType: contentTypeFromMime(mime),
        contentMimeType: mime,
        originalName: nameFromDisposition(disposition) ?? nameFromURI(url),
        contentSize: contentLength(headerValue(headers, 'content-length')),
      },
    };
  } catch (error) {
    throw new ExpoSharingError(
      'ERR_FAILED_TO_RESOLVE_SHARED_DATA',
      `Failed to resolve shared URL data: ${errorMessage(error as Object)}`,
      error as Object,
    );
  }
}

interface URLResponse {
  url: string;
  headers: Object;
}

async function streamURLHeaders(url: string, generation: IncomingGeneration): Promise<URLResponse> {
  const request = http.createHttp();

  try {
    return await new Promise<URLResponse>((resolve: (response: URLResponse) => void, reject: (error: Error) => void): void => {
      let headers: Object = new Object();
      let current = url;
      generation.cancelRequest = (): void => reject(new Error('Incoming share resolution was superseded by a newer payload.'));

      request.on('headersReceive', (value: Object): void => {
        try {
          const location = headerValue(headers, 'location');
          // A following response confirms the previous Location was followed.
          if (location !== undefined) current = new urls.URL(location, current).href;
          headers = value;
        } catch (error) {
          reject(new Error(`Invalid sharing redirect: ${String(error)}`));
        }
      });

      // GET preserves server redirect semantics; stop after the first body chunk.
      request.on('dataReceive', (_value: ArrayBuffer): void => resolve({ url: current, headers }));

      request
        .requestInStream(url, {
          method: http.RequestMethod.GET,
          connectTimeout: URL_TIMEOUT_MS,
          readTimeout: URL_TIMEOUT_MS,
          usingCache: false,
        })
        .then(
          (): void => resolve({ url: current, headers }),
          (error: Error): void => reject(error),
        );
    });
  } finally {
    generation.cancelRequest = undefined;
    request.off('headersReceive');
    request.off('dataReceive');
    request.destroy();
  }
}

async function resolveFilePayload(
  payload: SharePayload,
  originalName: string | undefined,
  cache: string,
): Promise<ResolvedRecord> {
  const url = payload.value;
  const uriName = nameFromURI(url);
  const name = originalName ?? uriName ?? 'unknown';
  const dir = `${cache}/expo-sharing`;
  const file = `${dir}/${cacheFileName(uriName ?? name)}`;

  let source: fileIo.File | undefined;
  let copying = false;

  try {
    // Opening the native Want URI directly lets Core File Kit check the OS grant without granting JS access.
    source = await fileIo.open(url, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);
    const stat = await fileIo.stat(source.fd);
    if (!stat.isFile()) {
      throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', 'Shared file URI does not point to a regular file.');
    }

    if (!(await fileIo.access(dir))) {
      try {
        await fileIo.mkdir(dir, true);
      } catch (error) {
        if (!(await fileIo.stat(dir)).isDirectory()) {
          throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', errorMessage(error as Object), error as Object);
        }
      }
    }

    copying = true;
    await fileIo.copyFile(source.fd, file);

    const size = (await fileIo.stat(file)).size;
    if (!Number.isSafeInteger(size) || size < 0) {
      throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', 'Shared cache file has an invalid size.');
    }

    return {
      file,
      payload: {
        value: payload.value,
        shareType: payload.shareType,
        mimeType: payload.mimeType,
        contentUri: fileUriFromPath(file),
        contentType: contentTypeFromMime(payload.mimeType ?? '', payload.shareType),
        contentMimeType: payload.mimeType ?? null,
        originalName: name,
        contentSize: size,
      },
    };
  } catch (error) {
    if (copying) {
      try {
        await fileIo.unlink(file);
      } catch (_) {}
    }

    throw new ExpoSharingError(
      'ERR_FAILED_TO_RESOLVE_SHARED_DATA',
      `Failed to copy shared file data into the application cache: ${errorMessage(error as Object)}`,
      error as Object,
    );
  } finally {
    if (source !== undefined) {
      try {
        await fileIo.close(source);
      } catch (_) {}
    }
  }
}

function fileShareType(type: uniformTypeDescriptor.TypeDescriptor | null): ShareType {
  try {
    if (type !== null) {
      if (type.belongsTo(uniformTypeDescriptor.UniformDataType.AUDIO)) return 'audio';
      if (type.belongsTo(uniformTypeDescriptor.UniformDataType.IMAGE)) return 'image';
      if (type.belongsTo(uniformTypeDescriptor.UniformDataType.VIDEO)) return 'video';
    }
  } catch (_) {}

  return 'file';
}

function isSharedFileUri(value: string): boolean {
  // Both app files and user/provider files are transferred with an authority.
  return !value.includes('\0') && /^file:\/\/(?!localhost\/)[^/?#]+\/[^?#]+/i.test(value);
}

function isWebURL(value: string): boolean {
  try {
    const source = new uri.URI(value);
    return (source.scheme === 'http' || source.scheme === 'https') && (source.authority ?? '').length > 0;
  } catch (_) {}

  return false;
}

function defaultMimeType(type: ShareType): string {
  if (type === 'text' || type === 'url') return 'text/plain';

  if (type === 'audio') return 'audio/*';

  if (type === 'image') return 'image/*';

  if (type === 'video') return 'video/*';

  return 'application/octet-stream';
}

function contentTypeFromMime(mime: string, fallback: ShareType = 'file'): ContentType {
  const value = mime.toLowerCase();

  if (value === 'text/html' || value === 'application/xhtml+xml') return 'website';
  if (value.startsWith('audio/')) return 'audio';
  if (value.startsWith('image/')) return 'image';
  if (value.startsWith('video/')) return 'video';
  if (value.startsWith('text/')) return 'text';

  return fallback === 'url' ? 'website' : fallback;
}

function typeDescriptor(utd: string): uniformTypeDescriptor.TypeDescriptor | null {
  try {
    return uniformTypeDescriptor.getTypeDescriptor(utd);
  } catch (_) {
    return null;
  }
}

function nameFromURI(value: string): string | null {
  try {
    return optionalString(new uri.URI(value).getLastSegment()) ?? null;
  } catch (_) {
    return null;
  }
}

function safeFileName(value: string): string {
  const segments = value.replaceAll('\\', '/').split('/');
  const name = (segments[segments.length - 1] ?? '').replace(/[\u0000-\u001F:*?"<>|]/g, '_').trim();
  if (name.length === 0 || name === '.' || name === '..') return 'unknown';

  return name;
}

function cacheFileName(value: string): string {
  const prefix = `${util.generateRandomUUID()}-`;
  const bytes = new util.TextEncoder().encodeInto(safeFileName(value));
  let start = Math.max(0, bytes.length + prefix.length - MAX_FILE_NAME_BYTES);

  // Keep the extension and begin at a complete UTF-8 character.
  while ((bytes[start] & 0xc0) === 0x80) start += 1;

  return prefix + util.TextDecoder.create('utf-8').decodeToString(bytes.subarray(start));
}

function normalizedMimeType(value: string | undefined): string | undefined {
  if (value === undefined) return undefined;

  const mime = value.split(';')[0].trim().toLowerCase();

  return mime.length > 0 ? mime : undefined;
}

function headerValue(headers: Object, name: string): string | undefined {
  const record = headers as Record<string, HeaderValue>;
  const keys = Object.keys(record);

  for (const key of keys) {
    if (key.toLowerCase() !== name) continue;

    const raw: HeaderValue = record[key];
    if (typeof raw === 'string') return raw;

    if (typeof raw === 'number') return String(raw);

    if (Array.isArray(raw) && raw.length > 0 && typeof raw[0] === 'string') return raw[0];
  }

  return undefined;
}

function contentLength(value: string | undefined): number | null {
  if (value === undefined || !/^\d+$/.test(value.trim())) return null;

  const size = Number(value);

  return Number.isSafeInteger(size) && size >= 0 ? size : null;
}

function nameFromDisposition(value: string | undefined): string | null {
  if (value === undefined) return null;

  const encoded = /filename\*=UTF-8''([^;]+)/i.exec(value);
  if (encoded !== null) {
    try {
      return safeFileName(decodeURIComponent(encoded[1]));
    } catch (_) {}
  }

  const plain = /filename\s*=\s*(?:"([^"]+)"|([^;]+))/i.exec(value);
  if (plain === null) return null;

  return safeFileName((plain[1] ?? plain[2]).trim());
}

async function readAnchor(anchor: SharingAnchor | undefined, context: ExpoModuleContext): Promise<systemShare.ShareControllerAnchor> {
  const window = await context.getReactNativeWindow();

  if (anchor === undefined) {
    // Older Share Kit versions require an anchor on tablets and 2-in-1 devices.
    const rect = window.getWindowProperties().windowRect;

    return {
      windowOffset: { x: Math.round(rect.width / 2), y: Math.round(rect.height / 2) },
      size: { width: 0, height: 0 },
    };
  }

  const ui = window.getUIContext();

  return {
    windowOffset: {
      x: ui.vp2px(anchor.x),
      y: ui.vp2px(anchor.y),
    },
    size: {
      width: ui.vp2px(Math.max(0, anchor.width)),
      height: ui.vp2px(Math.max(0, anchor.height)),
    },
  };
}

function decodeSharingOptions(value: ESObject, path: string): SharingOptions {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoSharingError(
      'ERR_INVALID_ARGUMENT_TYPE',
      `${path} expected a SharingOptions object, received ${value === null ? 'null' : typeof value}.`,
    );
  }

  const record = value as Record<string, ESObject>;
  const options = new SharingOptions();

  options.mimeType = decodeOptionalString(record['mimeType'], `${path}.mimeType`);
  options.UTI = decodeOptionalString(record['UTI'], `${path}.UTI`);
  options.dialogTitle = decodeOptionalString(record['dialogTitle'], `${path}.dialogTitle`);
  options.anchor = decodeAnchor(record['anchor'], `${path}.anchor`);

  return options;
}

function decodeAnchor(value: ESObject, path: string): SharingAnchor | undefined {
  if (value === undefined) return undefined;

  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoSharingError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected an anchor object, received ${value === null ? 'null' : typeof value}.`);
  }

  const record = value as Record<string, ESObject>;
  const anchor = new SharingAnchor();

  anchor.x = decodeOptionalNumber(record['x'], `${path}.x`);
  anchor.y = decodeOptionalNumber(record['y'], `${path}.y`);
  anchor.width = decodeOptionalNumber(record['width'], `${path}.width`);
  anchor.height = decodeOptionalNumber(record['height'], `${path}.height`);

  return anchor;
}

function decodeOptionalString(value: ESObject, path: string): string | undefined {
  if (value === undefined) return undefined;

  if (typeof value !== 'string') {
    throw new ExpoSharingError(
      'ERR_INVALID_ARGUMENT_TYPE',
      `${path} expected a string or undefined, received ${value === null ? 'null' : typeof value}.`,
    );
  }

  return value.length > 0 ? value : undefined;
}

function decodeOptionalNumber(value: ESObject, path: string): number {
  if (value === undefined) return 0;

  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new ExpoSharingError(
      'ERR_INVALID_ARGUMENT_TYPE',
      `${path} expected a finite number or undefined, received ${value === null ? 'null' : typeof value}.`,
    );
  }

  return value;
}

function encodeSharingOptions(value: SharingOptions): ESObject {
  const result: Record<string, ESObject> = {};
  if (value.mimeType !== undefined) result['mimeType'] = value.mimeType;
  if (value.UTI !== undefined) result['UTI'] = value.UTI;
  if (value.dialogTitle !== undefined) result['dialogTitle'] = value.dialogTitle;
  if (value.anchor !== undefined) {
    result['anchor'] = {
      x: value.anchor.x,
      y: value.anchor.y,
      width: value.anchor.width,
      height: value.anchor.height,
    };
  }

  return result;
}

function optionalString(value: ESObject): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function errorMessage(error: Object): string {
  if (typeof error === 'object' && error !== null) {
    const message = (error as ErrorLike).message;
    if (typeof message === 'string' && message.length > 0) {
      return message.replace(/^(?:Error:\s*)+/, '');
    }
  }

  try {
    return String(error).replace(/^(?:Error:\s*)+/, '');
  } catch (_) {
    return 'The Harmony sharing service failed.';
  }
}

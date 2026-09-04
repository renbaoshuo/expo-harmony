import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueType,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';
import type { Want } from '@kit.AbilityKit';
import uri from '@ohos.uri';

const SHARE_CAPABILITY: string = 'SystemCapability.Collaboration.SystemShare';
const SEND_ACTION: string = 'ohos.want.action.sendData';
const SEND_MULTIPLE_ACTION: string = 'ohos.want.action.sendMultipleData';
const URL_TIMEOUT_MS: number = 5000;
const MAX_INCOMING_RECORDS: number = 50;
const MAX_INCOMING_FILE_BYTES: number = 100 * 1024 * 1024;
const MAX_INCOMING_TOTAL_BYTES: number = 250 * 1024 * 1024;
const MODULE_NAME: string = 'ExpoSharing';
const INCOMING_SHARE_EVENT: string = 'onSharedPayloadsChanged';

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
  cancelled: boolean;
  finish?: () => void;
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

class IncomingGeneration {
  readonly revision: number;
  records: systemShare.SharedRecord[] = [];
  resolved?: ResolvedSharePayload[] = undefined;
  failure?: string = undefined;
  loading: Promise<void> = Promise.resolve();
  resolving?: Promise<void> = undefined;
  ready: boolean = false;
  cancelled: boolean = false;
  readonly files: Set<string> = new Set<string>();

  constructor(revision: number) {
    this.revision = revision;
  }
}

const incomingStates: WeakMap<common.UIAbilityContext, IncomingShareState> = new WeakMap<common.UIAbilityContext, IncomingShareState>();

class IncomingShareState {
  private readonly context: common.UIAbilityContext;
  private revision: number = 0;
  private generation: IncomingGeneration = new IncomingGeneration(0);
  private readonly listeners: Set<() => void> = new Set<() => void>();
  private lastWant?: Want = undefined;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.generation.ready = true;
  }

  receive(want: Want): void {
    if (!isShareWant(want)) return;
    if (this.lastWant === want) return;

    this.lastWant = want;
    const generation = new IncomingGeneration(++this.revision);
    this.replaceGeneration(generation);
    generation.loading = this.load(want, generation);
  }

  getPayloads(): SharePayload[] {
    const generation = this.generation;
    if (generation.failure !== undefined) {
      throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', `Failed to read incoming share data: ${generation.failure}`);
    }
    if (!generation.ready) return [];

    const payloads: SharePayload[] = [];
    generation.records.forEach((record: systemShare.SharedRecord): void => {
      const payload = payloadFromRecord(record);
      if (payload !== undefined) payloads.push(payload);
    });

    return payloads;
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
        generation.resolving = this.resolve(generation);
      }
      await generation.resolving;

      if (generation !== this.generation || generation.cancelled) continue;
      if (generation.failure !== undefined) {
        throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', `Failed to resolve incoming share data: ${generation.failure}`);
      }
      if (generation.resolved !== undefined) return generation.resolved;
    }
  }

  clear(): void {
    this.lastWant = undefined;
    const generation = new IncomingGeneration(++this.revision);
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
    this.lastWant = undefined;
    this.listeners.clear();

    const generation = new IncomingGeneration(++this.revision);
    generation.ready = true;
    this.replaceGeneration(generation);
  }

  private async load(want: Want, generation: IncomingGeneration): Promise<void> {
    try {
      const data = await systemShare.getSharedData(want);
      const records = data.getRecords();

      if (records.length > MAX_INCOMING_RECORDS) {
        throw new ExpoSharingError(
          'ERR_FAILED_TO_RESOLVE_SHARED_DATA',
          `Incoming share contains ${records.length} records; the limit is ${MAX_INCOMING_RECORDS}.`,
        );
      }
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
    let total: number = 0;

    try {
      for (let index = 0; index < generation.records.length; index += 1) {
        this.assertCurrent(generation);

        const result = await resolvedPayloadFromRecord(
          generation.records[index],
          this.context.cacheDir,
          generation.revision,
          index,
          MAX_INCOMING_TOTAL_BYTES - total,
        );
        if (result === undefined) continue;
        if (result.file !== undefined) generation.files.add(result.file);
        this.assertCurrent(generation);

        total += result.payload.contentSize ?? 0;
        resolved.push(result.payload);
      }

      this.assertCurrent(generation);
      generation.resolved = resolved;
    } catch (error) {
      await this.cleanup(generation);

      if (this.isCurrent(generation)) {
        generation.failure = errorMessage(error as Object);
      }
    }
  }

  private replaceGeneration(generation: IncomingGeneration): void {
    const previous = this.generation;
    previous.cancelled = true;
    this.generation = generation;
    this.cleanup(previous).catch((): void => {});
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
    this.listeners.forEach((listener: () => void): void => listener());
  }
}

function incomingState(context: common.UIAbilityContext): IncomingShareState {
  let state = incomingStates.get(context);
  if (state === undefined) {
    state = new IncomingShareState(context);
    incomingStates.set(context, state);
  }

  return state;
}

export class ExpoSharingModule extends ExpoModule {
  private readonly incoming: IncomingShareState;
  private sharing: boolean = false;
  private observing: boolean = false;
  private destroyed: boolean = false;
  private session: ShareSession | undefined = undefined;
  private readonly onIncomingChange = (): void => {
    if (!this.destroyed && this.observing) this.sendEvent(INCOMING_SHARE_EVENT);
  };

  constructor(context: ExpoModuleContext) {
    super(context);
    this.incoming = incomingState(context.uiAbilityContext);
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
        return !this.destroyed && canIUse(SHARE_CAPABILITY);
      })
      .syncFunction('getSharedPayloads', (): SharePayload[] => this.incoming.getPayloads())
      .asyncFunction('getResolvedSharedPayloadsAsync', async (): Promise<ResolvedSharePayload[]> => {
        return await this.incoming.getResolvedPayloads();
      })
      .syncFunction('clearSharedPayloads', (): void => this.incoming.clear())
      .onCreate((): void => {
        const want: Want | undefined = this.context.initialWant;
        if (want !== undefined) this.incoming.receive(want);
      })
      .onStartObserving(INCOMING_SHARE_EVENT, (): void => this.startObserving())
      .onStopObserving(INCOMING_SHARE_EVENT, (): void => this.stopObserving())
      .onNewWant((want: Want): void => this.incoming.receive(want))
      .onAbilityDestroy((): void => this.destroyAbility())
      .onDestroy((): void => this.destroy());
  }

  private startObserving(): void {
    if (this.destroyed || this.observing) return;

    this.observing = true;
    this.incoming.addListener(this.onIncomingChange);
  }

  private stopObserving(): void {
    if (!this.observing) return;

    this.observing = false;
    this.incoming.removeListener(this.onIncomingChange);
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.stopObserving();

    if (this.session !== undefined) {
      this.session.cancelled = true;
      this.session.finish?.();
    }
  }

  private destroyAbility(): void {
    this.destroy();
    this.incoming.destroy();
    incomingStates.delete(this.context.uiAbilityContext);
  }

  private async share(url: string, options: SharingOptions): Promise<void> {
    this.assertActive();
    if (this.sharing) {
      throw new ExpoSharingError('ERR_SHARING_IN_PROGRESS', 'Another share request is being processed now.');
    }

    const session: ShareSession = { cancelled: false };
    this.sharing = true;
    this.session = session;

    try {
      const mime = normalizedMimeType(options.mimeType);
      const anchor = readAnchor(options.anchor);
      if (options.dialogTitle !== undefined) {
        this.context.logger.warn('HarmonyOS Share Kit does not support a custom sharing panel title; dialogTitle was ignored.');
      }

      const file = await prepareShareFile(url);

      const preview = resolvePreview(file.name, mime);
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
        };
        if (anchor !== undefined) config.anchor = anchor;

        await showShare(controller, this.context, config, session);
      } catch (error) {
        throw new ExpoSharingError('ERR_SHARING_FAILED', `Failed to share the file: ${errorMessage(error as Object)}`, error as Object);
      }
    } finally {
      if (this.session === session) this.session = undefined;
      this.sharing = false;
    }
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoSharingError('ERR_SHARING_RUNTIME_DESTROYED', 'The Expo Sharing runtime has already been destroyed.');
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
  let finish: () => void = (): void => {};
  let dismissed: boolean = false;
  const done = new Promise<void>((resolve: () => void): void => {
    finish = resolve;
  });

  const dismiss = (): void => {
    if (dismissed) return;

    dismissed = true;
    finish();
  };

  session.finish = dismiss;
  if (session.cancelled) {
    dismiss();
    return;
  }

  controller.on('dismiss', dismiss);

  try {
    if (session.cancelled) return;

    await controller.show(context.uiAbilityContext, config);
    await done;
  } finally {
    session.finish = undefined;
    controller.off('dismiss', dismiss);
  }
}

async function prepareShareFile(url: string): Promise<ShareFile> {
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

  const authority = source.authority ?? '';
  const name = source.getLastSegment();
  if (authority.length > 0 && authority !== 'localhost') {
    let file: fileIo.File | undefined;
    try {
      file = await fileIo.open(url, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);

      if (!stat.isFile()) {
        throw new ExpoSharingError('ERR_SHARING_INVALID_URL', 'The URL to share does not point to a file.');
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
        try {
          await fileIo.close(file);
        } catch (_) {}
      }
    }

    return { uri: url, name: name.length > 0 ? name : 'shared-file' };
  }

  const path = source.path ?? '';
  if (path.length === 0 || !path.startsWith('/')) {
    throw new ExpoSharingError('ERR_SHARING_INVALID_URL', 'The URL to share must contain an absolute file path.');
  }

  let file: fileIo.File | undefined;
  try {
    file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    const stat = await fileIo.stat(file.fd);

    if (!stat.isFile()) {
      throw new ExpoSharingError('ERR_SHARING_INVALID_URL', 'The URL to share does not point to a file.');
    }
  } catch (error) {
    if (error instanceof ExpoSharingError) {
      throw new ExpoSharingError(error.code, error.message, error.cause);
    }

    throw new ExpoSharingError('ERR_SHARING_INVALID_URL', `The local file cannot be read: ${errorMessage(error as Object)}`, error as Object);
  } finally {
    if (file !== undefined) {
      try {
        await fileIo.close(file);
      } catch (_) {}
    }
  }

  let result: string;
  try {
    result = fileUri.getUriFromPath(path);
  } catch (error) {
    throw new ExpoSharingError('ERR_SHARING_FAILED', `The local file URI cannot be created: ${errorMessage(error as Object)}`, error as Object);
  }

  return {
    uri: result,
    name: name.length > 0 ? name : 'shared-file',
  };
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
    if (type.belongsTo(uniformTypeDescriptor.UniformDataType.IMAGE)) {
      return { utd, mode: systemShare.SharePreviewMode.DETAIL };
    }
    if (type.belongsTo(uniformTypeDescriptor.UniformDataType.VIDEO)) {
      return { utd, mode: systemShare.SharePreviewMode.DETAIL };
    }
    if (type.belongsTo(uniformTypeDescriptor.UniformDataType.AUDIO)) {
      return { utd, mode: systemShare.SharePreviewMode.DEFAULT };
    }
  }

  return { utd, mode: systemShare.SharePreviewMode.DEFAULT };
}

function isShareWant(want: Want): boolean {
  return want.action === SEND_ACTION || want.action === SEND_MULTIPLE_ACTION;
}

function payloadFromRecord(record: systemShare.SharedRecord): SharePayload | undefined {
  const value = recordValue(record);
  if (value.trim().length === 0) return undefined;

  const type = shareTypeFromRecord(record, value);

  return {
    value,
    shareType: type,
    mimeType: mimeFromUTD(record.utd) ?? defaultMimeType(type),
  };
}

async function resolvedPayloadFromRecord(
  record: systemShare.SharedRecord,
  cache: string,
  revision: number,
  index: number,
  remaining: number,
): Promise<ResolvedRecord | undefined> {
  const payload = payloadFromRecord(record);
  if (payload === undefined) return undefined;

  if (payload.shareType === 'text' && optionalString(record.uri) === undefined) {
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

  if (payload.shareType === 'url') return await resolveURLPayload(payload);

  return await resolveFilePayload(record, payload, cache, revision, index, remaining);
}

async function resolveURLPayload(payload: SharePayload): Promise<ResolvedRecord> {
  try {
    const headers = await streamURLHeaders(payload.value);

    const url = payload.value;
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

async function streamURLHeaders(url: string): Promise<Object> {
  const request = http.createHttp();
  let headers: Object = new Object();
  const receive = (value: Object): void => {
    headers = value;
  };
  const discard = (_value: ArrayBuffer): void => {};

  request.on('headersReceive', receive);
  request.on('dataReceive', discard);
  try {
    await request.requestInStream(url, {
      method: http.RequestMethod.GET,
      connectTimeout: URL_TIMEOUT_MS,
      readTimeout: URL_TIMEOUT_MS,
      usingCache: false,
    });

    return headers;
  } finally {
    request.off('headersReceive', receive);
    request.off('dataReceive', discard);
    request.destroy();
  }
}

async function resolveFilePayload(
  record: systemShare.SharedRecord,
  payload: SharePayload,
  cache: string,
  revision: number,
  index: number,
  remaining: number,
): Promise<ResolvedRecord> {
  const url = optionalString(record.uri);
  if (url === undefined) {
    throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', `Shared ${payload.shareType} data does not contain a readable file URI.`);
  }

  const name = sharedFileName(record, url);
  const dir = `${cache}/expo-sharing`;
  const file = `${dir}/${Date.now()}-${revision}-${index}-${safeFileName(name)}`;
  let source: fileIo.File | undefined;

  try {
    if (!(await fileIo.access(dir))) await fileIo.mkdir(dir, true);

    source = await fileIo.open(url, fileIo.OpenMode.READ_ONLY);
    const bytes = (await fileIo.stat(source.fd)).size;

    if (!Number.isSafeInteger(bytes) || bytes < 0) {
      throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', 'Shared file has an invalid size.');
    }
    if (bytes > MAX_INCOMING_FILE_BYTES) {
      throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', `Shared file exceeds the ${MAX_INCOMING_FILE_BYTES}-byte per-file limit.`);
    }
    if (bytes > remaining) {
      throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', `Incoming share exceeds the ${MAX_INCOMING_TOTAL_BYTES}-byte total limit.`);
    }

    await fileIo.copyFile(source.fd, file);

    const size = (await fileIo.stat(file)).size;
    if (size !== bytes) {
      throw new ExpoSharingError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', 'Shared file copy was incomplete.');
    }

    return {
      file,
      payload: {
        value: payload.value,
        shareType: payload.shareType,
        mimeType: payload.mimeType,
        contentUri: fileUri.getUriFromPath(file),
        contentType: contentTypeFromMime(payload.mimeType ?? '', payload.shareType),
        contentMimeType: payload.mimeType ?? null,
        originalName: name,
        contentSize: size,
      },
    };
  } catch (error) {
    try {
      await fileIo.unlink(file);
    } catch (_) {}

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

function shareTypeFromRecord(record: systemShare.SharedRecord, value: string): ShareType {
  try {
    const type = uniformTypeDescriptor.getTypeDescriptor(record.utd);
    if (type !== null) {
      if (type.belongsTo(uniformTypeDescriptor.UniformDataType.AUDIO)) return 'audio';
      if (type.belongsTo(uniformTypeDescriptor.UniformDataType.IMAGE)) return 'image';
      if (type.belongsTo(uniformTypeDescriptor.UniformDataType.VIDEO)) return 'video';
      if (type.belongsTo(uniformTypeDescriptor.UniformDataType.HYPERLINK)) return 'url';
      if (type.belongsTo(uniformTypeDescriptor.UniformDataType.TEXT)) {
        return isWebURL(value) ? 'url' : 'text';
      }
      if (type.belongsTo(uniformTypeDescriptor.UniformDataType.FILE)) return 'file';
    }
  } catch (_) {}

  if (isWebURL(value)) return 'url';

  return optionalString(record.uri) === undefined ? 'text' : 'file';
}

function recordValue(record: systemShare.SharedRecord): string {
  return optionalString(record.uri) ?? optionalString(record.content) ?? '';
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
  if (value.startsWith('text/html') || value.startsWith('application/xhtml+xml')) return 'website';
  if (value.startsWith('audio/')) return 'audio';
  if (value.startsWith('image/')) return 'image';
  if (value.startsWith('video/')) return 'video';
  if (value.startsWith('text/')) return 'text';
  if (fallback === 'url') return 'website';
  return fallback;
}

function mimeFromUTD(utd: string): string | undefined {
  try {
    const type = uniformTypeDescriptor.getTypeDescriptor(utd);
    if (type !== null && type.mimeTypes.length > 0) return normalizedMimeType(type.mimeTypes[0]);
  } catch (_) {
    return undefined;
  }

  return undefined;
}

function nameFromURI(value: string): string | null {
  try {
    const name = new uri.URI(value).getLastSegment();
    return name.length > 0 ? name : null;
  } catch (_) {
    return null;
  }
}

function sharedFileName(record: systemShare.SharedRecord, value: string): string {
  return nameFromURI(value) ?? optionalString(record.title) ?? 'unknown';
}

function safeFileName(value: string): string {
  const segments = value.replaceAll('\\', '/').split('/');
  const name = (segments[segments.length - 1] ?? '').replace(/[\u0000-\u001F:*?"<>|]/g, '_').trim();
  if (name.length === 0 || name === '.' || name === '..') return 'unknown';

  return name.slice(0, 180);
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
  if (value === undefined) return null;

  const size = Number.parseInt(value, 10);
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

function readAnchor(anchor: SharingAnchor | undefined): systemShare.ShareControllerAnchor | undefined {
  if (anchor === undefined) return undefined;

  return {
    windowOffset: {
      x: anchor.x,
      y: anchor.y,
    },
    size: {
      width: Math.max(0, anchor.width),
      height: Math.max(0, anchor.height),
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

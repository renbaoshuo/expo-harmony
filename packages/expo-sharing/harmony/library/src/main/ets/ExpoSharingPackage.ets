import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { EXPO_MODULE_EVENT, ExpoPlatformServiceError, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';
import type { Want } from '@kit.AbilityKit';
import uri from '@ohos.uri';

// Keep this value in sync with kServiceName in ExpoSharingProvider.cpp.
const SERVICE_NAME: string = 'ExpoSharingService';
const SHARE_CAPABILITY: string = 'SystemCapability.Collaboration.SystemShare';
const SEND_ACTION: string = 'ohos.want.action.sendData';
const SEND_MULTIPLE_ACTION: string = 'ohos.want.action.sendMultipleData';
const URL_TIMEOUT_MS: number = 5000;
const SHARE_SESSION_TIMEOUT_MS: number = 5 * 60 * 1000;
const MODULE_NAME: string = 'ExpoSharing';
const INCOMING_SHARE_EVENT: string = 'onSharedPayloadsChanged';
let registered: boolean = false;

interface ShareFile {
  uri: string;
  name: string;
}

interface SharePreview {
  utd: string;
  label: string;
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

class IncomingShareEventMessage {
  moduleName: string = MODULE_NAME;
  eventName: string = INCOMING_SHARE_EVENT;
  arguments: ESObject[] = [];
}

interface ErrorLike {
  message?: string;
}

interface ResolvedRecord {
  payload: ResolvedSharePayload;
  file?: string;
}

class FinalResponseInterceptor implements http.HttpInterceptor {
  readonly interceptorType: http.InterceptorType = http.InterceptorType.FINAL_RESPONSE;
  url: string = '';

  async interceptorHandle(context: http.HttpRequestContext, _response: http.HttpResponse): Promise<boolean> {
    this.url = context.url;
    return false;
  }
}

const incomingStates: WeakMap<common.UIAbilityContext, IncomingShareState> = new WeakMap<common.UIAbilityContext, IncomingShareState>();

class IncomingShareState {
  private readonly context: common.UIAbilityContext;
  private records: systemShare.SharedRecord[] = [];
  private resolved: ResolvedSharePayload[] | undefined = undefined;
  private failure: string | undefined = undefined;
  private revision: number = 0;
  private loading: Promise<void> = Promise.resolve();
  private readonly files: Set<string> = new Set<string>();
  private readonly listeners: Set<() => void> = new Set<() => void>();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  receive(want: Want): void {
    if (!isShareWant(want)) return;

    const revision = ++this.revision;
    this.records = [];
    this.resolved = undefined;
    this.failure = undefined;
    this.notify();

    this.loading = this.load(want, revision);
  }

  getPayloads(): SharePayload[] {
    if (this.failure !== undefined) return [];

    const payloads: SharePayload[] = [];
    this.records.forEach((record: systemShare.SharedRecord): void => {
      const payload = payloadFromRecord(record);
      if (payload !== undefined) payloads.push(payload);
    });
    return payloads;
  }

  async getResolvedPayloads(): Promise<ResolvedSharePayload[]> {
    await this.loading;

    if (this.failure !== undefined) {
      throw new ExpoPlatformServiceError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', `Failed to read incoming share data: ${this.failure}`);
    }
    if (this.resolved !== undefined) return this.resolved;

    const revision = this.revision;
    const records = this.records;
    const resolved: ResolvedSharePayload[] = [];
    for (let index = 0; index < records.length; index += 1) {
      try {
        const result = await resolvedPayloadFromRecord(records[index], this.context.cacheDir, revision, index);
        if (result === undefined) continue;
        if (result.file !== undefined) this.files.add(result.file);
        resolved.push(result.payload);
      } catch (error) {
        console.warn(`Expo Sharing skipped an incoming record that could not be resolved: ${errorMessage(error as Object)}`);
      }
    }

    if (revision !== this.revision) return await this.getResolvedPayloads();

    this.resolved = resolved;
    return resolved;
  }

  clear(): void {
    this.revision += 1;
    this.records = [];
    this.resolved = undefined;
    this.failure = undefined;
    this.loading = Promise.resolve();
    this.notify();
  }

  addListener(listener: () => void): void {
    this.listeners.add(listener);
  }

  removeListener(listener: () => void): void {
    this.listeners.delete(listener);
  }

  destroy(): void {
    this.clear();

    for (const file of this.files) {
      try {
        fileIo.unlinkSync(file);
      } catch (_) {}
    }

    this.files.clear();
  }

  private async load(want: Want, revision: number): Promise<void> {
    try {
      const data = await systemShare.getSharedData(want);
      const records = data.getRecords();

      if (revision === this.revision) {
        this.records = records;
        this.resolved = undefined;
        this.notify();
      }
    } catch (error) {
      if (revision === this.revision) {
        this.failure = errorMessage(error as Object);
        this.notify();
      }
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

export class ExpoSharingLifecycle {
  static onCreate(context: common.UIAbilityContext, want: Want): void {
    incomingState(context).receive(want);
  }

  static onNewWant(context: common.UIAbilityContext, want: Want): boolean {
    incomingState(context).receive(want);

    return !isShareWant(want);
  }

  static onDestroy(context: common.UIAbilityContext): void {
    const state = incomingStates.get(context);
    state?.destroy();

    incomingStates.delete(context);
  }
}

class ExpoSharingService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;
  private readonly incoming: IncomingShareState;
  private sharing: boolean = false;
  private destroyed: boolean = false;
  private session: ShareSession | undefined = undefined;
  private readonly onIncomingChange = (): void => {
    if (!this.destroyed) this.context.rnInstance.postMessageToCpp(EXPO_MODULE_EVENT, new IncomingShareEventMessage());
  };

  constructor(context: UITurboModuleContext) {
    this.context = context;
    this.incoming = incomingState(context.uiAbilityContext);
    this.incoming.addListener(this.onIncomingChange);
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (method === 'shareAsync') {
      const url = requireString(args[0], 'URL');
      const options = asRecord(args.length > 1 ? args[1] : undefined);

      await this.share(url, options);
      return null;
    }

    if (method === 'getResolvedSharedPayloadsAsync') return await this.incoming.getResolvedPayloads();

    if (method === 'isAvailableAsync') return !this.destroyed && canIUse(SHARE_CAPABILITY);

    if (method === 'destroy') {
      this.destroy();
      return null;
    }

    throw new ExpoPlatformServiceError('ERR_SHARING_UNKNOWN_METHOD', `Unknown ExpoSharing Harmony method '${method}'.`);
  }

  invokeSync(method: string, _: ESObject[]): ESObject {
    if (method === 'getSharedPayloads') return this.incoming.getPayloads();

    if (method === 'clearSharedPayloads') {
      this.incoming.clear();
      return null;
    }

    if (method === 'destroy') {
      this.destroy();
      return null;
    }

    throw new ExpoPlatformServiceError('ERR_SHARING_ASYNC_METHOD', `ExpoSharing Harmony method '${method}' is asynchronous.`);
  }

  onDestroy(): void {
    this.destroy();
  }

  private destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.incoming.removeListener(this.onIncomingChange);
    if (this.session !== undefined) {
      this.session.cancelled = true;
      this.session.finish?.();
    }
  }

  private async share(url: string, options: Record<string, ESObject>): Promise<void> {
    this.assertActive();
    if (this.sharing) {
      throw new ExpoPlatformServiceError('ERR_SHARING_IN_PROGRESS', 'Another share request is being processed now.');
    }

    const session: ShareSession = { cancelled: false };
    this.sharing = true;
    this.session = session;

    try {
      const mime = optionalString(options['mimeType']);
      const anchor = readAnchor(options['anchor']);
      const dialogTitle = optionalString(options['dialogTitle']);

      if (dialogTitle !== undefined) {
        this.context.logger.warn('HarmonyOS Share Kit does not support a custom sharing panel title; dialogTitle was ignored.');
      }

      const file = prepareShareFile(url);

      const preview = resolvePreview(file.name, mime);
      this.assertActive();

      try {
        const data = new systemShare.SharedData({
          utd: preview.utd,
          uri: file.uri,
          title: file.name,
          label: preview.label,
        });
        const controller = new systemShare.ShareController(data);
        const config: systemShare.ShareControllerOptions = {
          selectionMode: systemShare.SelectionMode.SINGLE,
          previewMode: preview.mode,
        };
        if (anchor !== undefined) config.anchor = anchor;

        await showShare(controller, this.context, config, session);
      } catch (error) {
        throw new ExpoPlatformServiceError('ERR_SHARING_FAILED', `Failed to share the file: ${errorMessage(error as Object)}`);
      }
    } finally {
      if (this.session === session) this.session = undefined;
      this.sharing = false;
    }
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoPlatformServiceError('ERR_SHARING_RUNTIME_DESTROYED', 'The Expo Sharing runtime has already been destroyed.');
    }
    if (!canIUse(SHARE_CAPABILITY)) {
      throw new ExpoPlatformServiceError('ERR_SHARING_UNAVAILABLE', 'The HarmonyOS system sharing capability is unavailable on this device.');
    }
  }
}

async function showShare(
  controller: systemShare.ShareController,
  context: UITurboModuleContext,
  config: systemShare.ShareControllerOptions,
  session: ShareSession,
): Promise<void> {
  let finish: () => void = (): void => {};
  let dismissed: boolean = false;
  let timeout: number = -1;
  const done = new Promise<void>((resolve: () => void): void => {
    finish = resolve;
  });

  const dismiss = (): void => {
    if (dismissed) return;

    dismissed = true;
    finish();
  };
  const complete = (_result: systemShare.ShareOperationResult): void => dismiss();

  session.finish = dismiss;
  if (session.cancelled) {
    dismiss();
    return;
  }

  controller.on('dismiss', dismiss);
  controller.on('shareCompleted', complete);
  timeout = setTimeout(dismiss, SHARE_SESSION_TIMEOUT_MS);

  try {
    if (session.cancelled) return;

    await controller.show(context.uiAbilityContext, config);
    await done;
  } finally {
    session.finish = undefined;
    if (timeout >= 0) clearTimeout(timeout);
    controller.off('dismiss', dismiss);
    controller.off('shareCompleted', complete);
  }
}

function prepareShareFile(url: string): ShareFile {
  let source: uri.URI;
  try {
    source = new uri.URI(url);
  } catch (_) {
    throw new ExpoPlatformServiceError('ERR_SHARING_INVALID_ARGS', 'The URL to share is not a valid URI.');
  }

  if (source.scheme !== 'file') {
    throw new ExpoPlatformServiceError(
      'ERR_SHARING_INVALID_ARGS',
      `Only local file URLs are supported (expected scheme to be 'file', got '${source.scheme}').`,
    );
  }
  const authority = source.authority ?? '';
  if (authority.length > 0 && authority !== 'localhost') {
    throw new ExpoPlatformServiceError('ERR_SHARING_INVALID_ARGS', 'Only empty or localhost file URL authorities are supported.');
  }
  const path = source.path ?? '';
  if (path.length === 0 || !path.startsWith('/')) {
    throw new ExpoPlatformServiceError('ERR_SHARING_INVALID_ARGS', 'The URL to share must contain an absolute file path.');
  }

  let readable: boolean;
  try {
    readable = fileIo.accessSync(path, fileIo.AccessModeType.READ) && fileIo.statSync(path).isFile();
  } catch (error) {
    throw new ExpoPlatformServiceError('ERR_SHARING_FAILED', `The local file cannot be read: ${errorMessage(error as Object)}`);
  }

  if (!readable) {
    throw new ExpoPlatformServiceError('ERR_SHARING_FAILED', 'The URL to share does not point to a readable local file.');
  }

  const name = source.getLastSegment();
  let shareUri: string;
  try {
    shareUri = fileUri.getUriFromPath(path);
  } catch (error) {
    throw new ExpoPlatformServiceError('ERR_SHARING_FAILED', `The local file URI cannot be created: ${errorMessage(error as Object)}`);
  }

  return {
    uri: shareUri,
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
      return { utd, label: 'IMAGE', mode: systemShare.SharePreviewMode.DETAIL };
    }
    if (type.belongsTo(uniformTypeDescriptor.UniformDataType.VIDEO)) {
      return { utd, label: 'VIDEO', mode: systemShare.SharePreviewMode.DETAIL };
    }
    if (type.belongsTo(uniformTypeDescriptor.UniformDataType.AUDIO)) {
      return { utd, label: 'AUDIO', mode: systemShare.SharePreviewMode.DEFAULT };
    }
  }

  return { utd, label: 'FILE', mode: systemShare.SharePreviewMode.DEFAULT };
}

function isShareWant(want: Want): boolean {
  return want.action === SEND_ACTION || want.action === SEND_MULTIPLE_ACTION;
}

function payloadFromRecord(record: systemShare.SharedRecord): SharePayload | undefined {
  const value = recordValue(record);
  if (value.trim().length === 0) return undefined;
  const shareType = shareTypeFromRecord(record, value);

  return {
    value,
    shareType,
    mimeType: mimeFromUTD(record.utd) ?? defaultMimeType(shareType),
  };
}

async function resolvedPayloadFromRecord(
  record: systemShare.SharedRecord,
  cacheDir: string,
  revision: number,
  index: number,
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

  return resolveFilePayload(record, payload, cacheDir, revision, index);
}

async function resolveURLPayload(payload: SharePayload): Promise<ResolvedRecord> {
  const request = http.createHttp();
  const interceptor = new FinalResponseInterceptor();

  try {
    const chain = new http.HttpInterceptorChain();
    if (!chain.addChain([interceptor]) || !chain.apply(request)) {
      throw new ExpoPlatformServiceError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', 'HarmonyOS could not attach the URL response interceptor.');
    }

    const response = await request.request(payload.value, {
      method: http.RequestMethod.HEAD,
      connectTimeout: URL_TIMEOUT_MS,
      readTimeout: URL_TIMEOUT_MS,
      maxRedirects: 5,
      usingCache: false,
    });
    const contentUri = interceptor.url.length > 0 ? interceptor.url : payload.value;
    const mime = normalizedMimeType(headerValue(response.header, 'content-type')) ?? 'text/plain';
    const disposition = headerValue(response.header, 'content-disposition');

    return {
      payload: {
        value: payload.value,
        shareType: payload.shareType,
        mimeType: payload.mimeType,
        contentUri,
        contentType: contentTypeFromMime(mime),
        contentMimeType: mime,
        originalName: nameFromDisposition(disposition) ?? nameFromURI(contentUri),
        contentSize: contentLength(headerValue(response.header, 'content-length')),
      },
    };
  } catch (error) {
    throw new ExpoPlatformServiceError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', `Failed to resolve shared URL data: ${errorMessage(error as Object)}`);
  } finally {
    request.destroy();
  }
}

function resolveFilePayload(
  record: systemShare.SharedRecord,
  payload: SharePayload,
  cacheDir: string,
  revision: number,
  index: number,
): ResolvedRecord {
  const sourceUri = optionalString(record.uri);
  if (sourceUri === undefined) {
    throw new ExpoPlatformServiceError('ERR_FAILED_TO_RESOLVE_SHARED_DATA', `Shared ${payload.shareType} data does not contain a readable file URI.`);
  }

  const name = sharedFileName(record, sourceUri);
  const dir = `${cacheDir}/expo-sharing`;
  const file = `${dir}/${Date.now()}-${revision}-${index}-${safeFileName(name)}`;
  let source: fileIo.File | undefined;

  try {
    if (!fileIo.accessSync(dir)) fileIo.mkdirSync(dir, true);

    source = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);

    fileIo.copyFileSync(source.fd, file);

    const size = fileIo.statSync(file).size;
    const contentUri = fileUri.getUriFromPath(file);

    return {
      file,
      payload: {
        value: payload.value,
        shareType: payload.shareType,
        mimeType: payload.mimeType,
        contentUri,
        contentType: contentTypeFromMime(payload.mimeType ?? '', payload.shareType),
        contentMimeType: payload.mimeType ?? null,
        originalName: name,
        contentSize: size,
      },
    };
  } catch (error) {
    try {
      fileIo.unlinkSync(file);
    } catch (_) {}

    throw new ExpoPlatformServiceError(
      'ERR_FAILED_TO_RESOLVE_SHARED_DATA',
      `Failed to copy shared file data into the application cache: ${errorMessage(error as Object)}`,
    );
  } finally {
    if (source !== undefined) {
      try {
        fileIo.closeSync(source);
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

  switch (record.label) {
    case 'HYPERLINK':
      return 'url';
    case 'AUDIO':
      return 'audio';
    case 'IMAGE':
      return 'image';
    case 'VIDEO':
      return 'video';
    case 'FILE':
      return 'file';
    case 'HTML':
    case 'TEXT':
      return 'text';
  }

  return optionalString(record.uri) === undefined ? 'text' : 'file';
}

function recordValue(record: systemShare.SharedRecord): string {
  return optionalString(record.uri) ?? optionalString(record.content) ?? '';
}

function isWebURL(value: string): boolean {
  try {
    const source = new uri.URI(value);
    if ((source.scheme === 'http' || source.scheme === 'https' || source.scheme === 'rtsp') && (source.authority ?? '').length > 0) return true;
  } catch (_) {
    return /^(?:www\.)?[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}(?::\d+)?(?:[/?#].*)?$/i.test(value.trim());
  }

  return /^(?:www\.)?[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}(?::\d+)?(?:[/?#].*)?$/i.test(value.trim());
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
    if (type !== null && type.mimeTypes.length > 0) return type.mimeTypes[0];
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
  return optionalString(record.title) ?? nameFromURI(value) ?? 'unknown';
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

function readAnchor(value: ESObject): systemShare.ShareControllerAnchor | undefined {
  const anchor = asRecord(value);
  if (Object.keys(anchor).length === 0) return undefined;

  return {
    windowOffset: {
      x: finiteNumber(anchor['x'], 0),
      y: finiteNumber(anchor['y'], 0),
    },
    size: {
      width: Math.max(0, finiteNumber(anchor['width'], 0)),
      height: Math.max(0, finiteNumber(anchor['height'], 0)),
    },
  };
}

function asRecord(value: ESObject): Record<string, ESObject> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return {};
  return value as Record<string, ESObject>;
}

function requireString(value: ESObject, label: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new ExpoPlatformServiceError('ERR_SHARING_INVALID_ARGS', `${label} must be a non-empty string.`);
  }
  return value;
}

function optionalString(value: ESObject): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function finiteNumber(value: ESObject, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
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

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new ExpoSharingService(context),
  });
  registered = true;
}

export class ExpoSharingPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerService();
    super(context);
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-sharing';
  }
}

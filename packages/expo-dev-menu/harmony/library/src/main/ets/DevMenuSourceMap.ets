/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { http } from '@kit.NetworkKit';
import { util, url } from '@kit.ArkTS';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import type { resourceManager } from '@kit.LocalizationKit';
import { ExpoModuleError } from '@expo-harmony/expo-modules-core';

// NetStack's documented maximum; its 5 MiB default is too small for Metro maps.
const MAX_SOURCE_MAP_BYTES: number = 100 * 1024 * 1024;

export class DevMenuSourceFile {
  readonly index: number;
  readonly path: string;
  readonly content: string | null;
  constructor(index: number, path: string, content: string | null) {
    this.index = index;
    this.path = path;
    this.content = content;
  }
}

export class DevMenuSourceEntry {
  readonly path: string;
  readonly file?: DevMenuSourceFile;
  constructor(path: string, file?: DevMenuSourceFile) {
    this.path = path;
    this.file = file;
  }
}

export class DevMenuSourceMap {
  private readonly resources: resourceManager.ResourceManager;
  private request?: http.HttpRequest;
  private disposed: boolean = false;

  constructor(resources: resourceManager.ResourceManager) {
    this.resources = resources;
  }

  async load(bundle: string, local?: string): Promise<DevMenuSourceFile[]> {
    this.assertActive();

    let failure: Object | undefined;
    // A host-provided cached bundle is authoritative: do not first wait on its CDN URL.
    if (local !== undefined) {
      return await this.loadLocal(local);
    }
    if (/^https?:\/\//i.test(bundle)) {
      try {
        const address = new url.URL(bundle);
        address.pathname = address.pathname.endsWith('.bundle') ? address.pathname.slice(0, -7) + '.map' : address.pathname + '.map';

        const request = http.createHttp();
        this.request = request;
        try {
          const response = await request.request(address.toString(), {
            method: http.RequestMethod.GET,
            expectDataType: http.HttpDataType.STRING,
            connectTimeout: 15000,
            readTimeout: 60000,
            maxLimit: MAX_SOURCE_MAP_BYTES,
          });
          if (response.responseCode < 200 || response.responseCode >= 300)
            throw new Error(`Source map request returned HTTP ${response.responseCode}.`);
          return this.parse(String(response.result));
        } finally {
          if (this.request === request) {
            this.request = undefined;
            request.destroy();
          }
        }
      } catch (error) {
        failure = error as Object;
      }
    }
    this.assertActive();

    if (bundle.startsWith('file://') || bundle.startsWith('/')) return await this.loadLocal(bundle);
    // RNOH ResourceJSBundleProvider exposes its rawfile-relative path as the bundle URL.
    if (bundle.length > 0 && !bundle.includes('://')) {
      try {
        const bytes = await this.resources.getRawFileContent(bundle);
        return this.parseInline(util.TextDecoder.create('utf-8').decodeToString(bytes));
      } catch (error) {
        failure = error as Object;
      }
    }

    throw new ExpoModuleError(
      'ERR_DEV_MENU_SOURCE_MAP',
      'No source map found. Connect to Metro or include an inline source map in the local bundle.',
      failure,
    );
  }

  private async loadLocal(local: string): Promise<DevMenuSourceFile[]> {
    const path = local.startsWith('file://') ? new fileUri.FileUri(local).path : local;
    return this.parseInline(await fileIo.readText(path));
  }

  private parseInline(content: string): DevMenuSourceFile[] {
    this.assertActive();
    const match = /\/\/[@#]\s*sourceMappingURL=data:application\/json(?:;charset=utf-8)?;base64,([^\r\n]+)/.exec(content);
    if (match === null) throw new ExpoModuleError('ERR_DEV_MENU_SOURCE_MAP', 'The local bundle does not contain an inline source map.');

    const bytes = new util.Base64Helper().decodeSync(match[1].trim());
    return this.parse(util.TextDecoder.create('utf-8').decodeToString(bytes));
  }

  dispose(): void {
    this.disposed = true;
    const request = this.request;
    this.request = undefined;
    request?.destroy();
  }

  private assertActive(): void {
    if (this.disposed) throw new ExpoModuleError('ERR_DEV_MENU_SOURCE_MAP', 'Source map request was cancelled.');
  }

  private parse(text: string): DevMenuSourceFile[] {
    this.assertActive();

    const value: ESObject = JSON.parse(text);
    if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid source map.');

    const map = value as Record<string, ESObject>;
    if (map.version !== 3 || !Array.isArray(map.sources) || !map.sources.every((source: ESObject): boolean => typeof source === 'string')) {
      throw new Error('Expected a version 3 source map with a sources array.');
    }

    const contents: ESObject[] = Array.isArray(map.sourcesContent) ? map.sourcesContent : [];

    return (map.sources as string[]).map(
      (path: string, index: number): DevMenuSourceFile =>
        new DevMenuSourceFile(index, path, typeof contents[index] === 'string' ? (contents[index] as string) : null),
    );
  }
}

export class DevMenuSourceData implements IDataSource {
  private files: DevMenuSourceEntry[] = [];
  private readonly listeners: Set<DataChangeListener> = new Set<DataChangeListener>();
  totalCount(): number {
    return this.files.length;
  }
  getData(index: number): DevMenuSourceEntry {
    return this.files[index];
  }
  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.add(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners.delete(listener);
  }
  replace(files: DevMenuSourceEntry[]): void {
    this.files = files;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
}

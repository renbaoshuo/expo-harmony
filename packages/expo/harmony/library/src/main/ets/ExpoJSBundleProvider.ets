/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import {
  AssetRoot,
  FileJSBundleProvider,
  HotReloadConfig,
  JSBundleProvider,
  JsBundle,
  RawFileJSBundle,
  ResourceJSBundleProvider,
  RNOHCoreContext,
} from '@rnoh/react-native-openharmony';
import type { ExpoReactHostDelegate } from './ExpoReactHostDelegate';

export class ExpoResourceBundle extends ResourceJSBundleProvider {
  private readonly context: common.Context;
  private readonly asset: string;

  constructor(context: common.Context, path: string, appKeys: string[] = []) {
    super(context.resourceManager, path, appKeys);
    this.context = context;
    this.asset = path;
  }

  override async getBundle(): Promise<ArrayBuffer | RawFileJSBundle> {
    const rnohCoreContext: RNOHCoreContext | undefined = AppStorage.get<RNOHCoreContext>('RNOHCoreContext');
    if (rnohCoreContext !== undefined && rnohCoreContext.uiAbilityContext.resourceManager === this.context.resourceManager) {
      try {
        const fd = this.context.resourceManager.getRawFdSync(this.asset);
        if (fd) {
          this.context.resourceManager.closeRawFdSync(this.asset);
          // RNOH mmaps the raw offset; Hermes requires uint32 bytecode alignment.
          if (fd.offset % Uint32Array.BYTES_PER_ELEMENT === 0) return { rawFilePath: this.asset };
        }
      } catch (_error) {}
    }

    const bytes = await this.context.resourceManager.getRawFileContent(this.asset);

    return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  }
}

export class ExpoJSBundleProvider extends JSBundleProvider {
  private selected?: JSBundleProvider;

  private readonly context: common.Context;
  private readonly fallback: JSBundleProvider;
  private readonly delegate: ExpoReactHostDelegate;
  private readonly debug: boolean;

  constructor(context: common.Context, fallback: JSBundleProvider, delegate: ExpoReactHostDelegate, debug: boolean) {
    super();
    this.context = context;
    this.fallback = fallback;
    this.delegate = delegate;
    this.debug = debug;
  }

  getURL(): string {
    return (this.selected ?? this.fallback).getURL();
  }
  getAppKeys(): string[] {
    return (this.selected ?? this.fallback).getAppKeys();
  }
  getAssetRoot(): AssetRoot | undefined {
    return (this.selected ?? this.fallback).getAssetRoot();
  }
  getHotReloadConfig(): HotReloadConfig | null {
    return (this.selected ?? this.fallback).getHotReloadConfig();
  }
  getHumanFriendlyURL(): string {
    return (this.selected ?? this.fallback).getHumanFriendlyURL();
  }

  async getBundle(progress?: (value: number) => void, switched?: (provider: JSBundleProvider) => void): Promise<JsBundle> {
    const previous = this.selected ?? this.fallback;
    this.selected = await this.delegate.getJSBundleProvider(this.debug);
    if (this.selected === undefined) {
      const appKeys = this.fallback.getAppKeys();
      const path = await this.delegate.getJSBundleFile(this.debug);
      if (path !== undefined) {
        this.selected = path.startsWith('assets://')
          ? new ExpoResourceBundle(this.context, path.slice('assets://'.length), appKeys)
          : new FileJSBundleProvider(path, appKeys);
      } else {
        const asset = await this.delegate.getBundleAssetName(this.debug);
        this.selected = asset === undefined ? this.fallback : new ExpoResourceBundle(this.context, asset, appKeys);
      }
    }

    if (this.selected !== this.fallback || this.selected !== previous) switched?.(this.selected);

    return await this.selected.getBundle(progress, switched);
  }
}

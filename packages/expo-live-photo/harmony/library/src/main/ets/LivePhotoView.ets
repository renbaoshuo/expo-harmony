/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoView, ExpoViewContext } from '@expo-harmony/expo-modules-core';
import type { ExpoViewContentContext } from '@expo-harmony/expo-modules-core';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { MovingPhotoView, MovingPhotoViewAttribute, MovingPhotoViewController, photoAccessHelper } from '@kit.MediaLibraryKit';

export enum ContentFit {
  Contain = 'contain',
  Cover = 'cover',
}

export enum PlaybackStyle {
  Full = 'full',
  Hint = 'hint',
}

export class LivePhotoAsset {
  readonly photoUri?: string | null;
  readonly pairedVideoUri?: string | null;

  constructor(photoUri?: string | null, pairedVideoUri?: string | null) {
    this.photoUri = photoUri;
    this.pairedVideoUri = pairedVideoUri;
  }
}

class RenderedPhoto {
  readonly id: number;
  readonly photo: photoAccessHelper.MovingPhoto;
  readonly controller: MovingPhotoViewController = new MovingPhotoViewController();
  readonly fit: ImageFit;
  previewLoaded: boolean = false;
  prepared: boolean = false;
  playing: boolean = false;

  constructor(id: number, photo: photoAccessHelper.MovingPhoto, fit: ContentFit) {
    this.id = id;
    this.photo = photo;
    this.fit = fit === ContentFit.Cover ? ImageFit.Cover : ImageFit.Contain;
  }
}

@Observed
export class LivePhotoView extends ExpoView {
  items: RenderedPhoto[] = [];
  muted: boolean = true;
  gestureEnabled: boolean = true;
  private source: LivePhotoAsset | null = null;
  private fit: ContentFit = ContentFit.Contain;
  private sourceDirty: boolean = false;
  private loadId: number = 0;
  private destroyed: boolean = false;
  private loadFailed: boolean = false;
  private hintWarned: boolean = false;

  constructor(context: ExpoViewContext) {
    super(context);
  }

  setSource(source: LivePhotoAsset | null): void {
    const unchanged = source === this.source || (
      source !== null && this.source !== null &&
      source.photoUri === this.source.photoUri && source.pairedVideoUri === this.source.pairedVideoUri
    );
    if (unchanged && !this.loadFailed) return;

    this.source = source;
    this.sourceDirty = true;
  }

  setContentFit(fit: ContentFit): void {
    if (fit === this.fit) return;

    this.fit = fit;
    this.sourceDirty = true;
  }

  setMuted(muted: boolean): void {
    this.muted = muted;
  }

  setGesture(gesture: boolean): void {
    this.gestureEnabled = gesture;
  }

  commitProps(): void {
    if (this.destroyed || !this.sourceDirty) return;

    this.sourceDirty = false;
    void this.loadSource();
  }

  startPlayback(style: PlaybackStyle): void {
    const item = this.items[0];
    if (this.destroyed || item === undefined || !item.previewLoaded || !item.prepared) return;

    if (style === PlaybackStyle.Hint && !this.hintWarned) {
      console.warn('ExpoLivePhoto: HarmonyOS has no iOS hint playback style; playing the full moving photo.');
      this.hintWarned = true;
    }

    item.controller.startPlayback();
  }

  stopPlayback(): void {
    const item = this.items[0];
    if (!this.destroyed && item !== undefined && (item.prepared || item.playing)) item.controller.stopPlayback();
  }

  onPreview(item: RenderedPhoto): void {
    if (!this.isCurrent(item) || item.previewLoaded) return;

    item.previewLoaded = true;
    this.sendEvent('onPreviewPhotoLoad');
    this.completeLoad(item);
  }

  onPrepared(item: RenderedPhoto): void {
    if (!this.isCurrent(item) || item.prepared) return;

    item.prepared = true;
    this.completeLoad(item);
  }

  onStart(item: RenderedPhoto): void {
    if (!this.isCurrent(item) || item.playing) return;

    item.playing = true;
    this.sendEvent('onPlaybackStart');
  }

  onStop(item: RenderedPhoto): void {
    if (!this.isCurrent(item) || !item.playing) return;

    item.playing = false;
    this.sendEvent('onPlaybackStop');
  }

  onError(item: RenderedPhoto): void {
    if (!this.isCurrent(item)) return;

    if (!item.previewLoaded || !item.prepared) {
      this.failLoad(this.loadId, new Error('HarmonyOS MovingPhotoView failed to load the live photo.'));
      return;
    }

    // Expo has no playback-error event; keep the loaded preview available.
    if (item.playing) {
      this.onStop(item);
      this.stopRenderedPhoto(item);
    }
    console.warn('ExpoLivePhoto: HarmonyOS MovingPhotoView failed to play the loaded live photo.');
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.loadId += 1;
    this.source = null;

    this.clearRenderedPhoto();
  }

  private async loadSource(): Promise<void> {
    const id = ++this.loadId;
    this.clearRenderedPhoto();

    this.loadFailed = false;

    const source = this.source;
    if (source === null) return;

    this.sendEvent('onLoadStart');

    try {
      const context = this.context.rnComponentContext.uiAbilityContext;
      const uris = await Promise.all([
        this.localFileUri(source.photoUri, 'photoUri'),
        this.localFileUri(source.pairedVideoUri, 'pairedVideoUri'),
      ]);
      if (!this.isCurrentLoad(id)) return;

      const photo = await photoAccessHelper.MediaAssetManager.loadMovingPhoto(context, uris[0], uris[1]);

      if (this.isCurrentLoad(id)) this.items = [new RenderedPhoto(id, photo, this.fit)];
    } catch (error) {
      this.failLoad(id, error);
    }
  }

  private async localFileUri(value: string | null | undefined, field: string): Promise<string> {
    if (!value) throw new Error(`Provided source is not a valid LivePhotoAsset: the \`${field}\` has to be provided.`);

    let file: fileIo.File | undefined;
    try {
      const context = this.context.moduleContext;
      const uri = /^file:\/(?!\/)/i.test(value) ? `file://${value.slice('file:'.length)}` : value;
      const source = context.filePathForRead(uri);

      file = await fileIo.open(source, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);
      if (!(await fileIo.stat(file.fd)).isFile()) throw new Error('Expected a regular file.');

      return fileUri.getUriFromPath(context.readPathForDescriptor(source, file));
    } catch (error) {
      const message = (error as Error).message || String(error);
      throw new Error(`Unable to read \`${field}\`: ${message}`);
    } finally {
      if (file !== undefined) {
        try {
          await fileIo.close(file);
        } catch (error) {
          console.warn(`ExpoLivePhoto: failed to close the source file: ${error}`);
        }
      }
    }
  }

  private clearRenderedPhoto(): void {
    const item = this.items[0];

    // Invalidate before stopping: synchronous and late native callbacks are stale.
    this.items = [];
    if (item === undefined) return;

    this.stopRenderedPhoto(item);
    if (item.playing && !this.destroyed) this.sendEvent('onPlaybackStop');
  }

  private stopRenderedPhoto(item: RenderedPhoto): void {
    if (!item.prepared && !item.playing) return;

    try {
      item.controller.stopPlayback();
    } catch (error) {
      console.warn(`ExpoLivePhoto: failed to stop playback: ${error}`);
    }
  }

  private completeLoad(item: RenderedPhoto): void {
    if (item.previewLoaded && item.prepared) this.sendEvent('onLoadComplete');
  }

  private failLoad(id: number, error: Object): void {
    if (!this.isCurrentLoad(id)) return;

    this.loadFailed = true;
    this.clearRenderedPhoto();

    const message = (error as Error).message || String(error);
    const payload: Record<string, ESObject> = { 'message': message };
    this.sendEvent('onLoadError', payload);
  }

  private isCurrent(item: RenderedPhoto): boolean {
    return !this.destroyed && this.items[0] === item;
  }

  private isCurrentLoad(id: number): boolean {
    return !this.destroyed && id === this.loadId;
  }
}

@Component
struct LivePhotoViewContent {
  @ObjectLink view: LivePhotoView;

  @Builder
  private photo(item: RenderedPhoto): void {
    MovingPhotoView({ movingPhoto: item.photo, controller: item.controller })
      .width('100%')
      .height('100%')
      .muted(this.view.muted)
      .objectFit(item.fit)
      .enableAnalyzer(false)
      .hitTestBehavior(this.view.gestureEnabled ? HitTestMode.Default : HitTestMode.None)
      .onComplete((): void => this.view.onPreview(item))
      .onPrepared((): void => this.view.onPrepared(item))
      .onStart((): void => this.view.onStart(item))
      .onStop((): void => this.view.onStop(item))
      .onPause((): void => this.view.onStop(item))
      .onFinish((): void => this.view.onStop(item))
      .onError((): void => this.view.onError(item));
  }

  build(): void {
    Stack() {
      ForEach(
        this.view.items,
        (item: RenderedPhoto): void => this.photo(item),
        (item: RenderedPhoto): string => item.id.toString(),
      )
    }
    .width('100%')
    .height('100%');
  }
}
@Builder
export function buildLivePhotoView(context: ExpoViewContentContext): void {
  LivePhotoViewContent({ view: context.nativeView as LivePhotoView });
}

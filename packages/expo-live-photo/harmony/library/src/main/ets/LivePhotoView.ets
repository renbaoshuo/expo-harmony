/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoView, ExpoViewContext, filePathFromUri } from '@expo-harmony/expo-modules-core';
import type { ExpoViewContentContext } from '@expo-harmony/expo-modules-core';
import { fileUri } from '@kit.CoreFileKit';
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

// MovingPhotoView requires a new node and controller when its attributes change.
class RenderedPhoto {
  readonly id: number;
  readonly photo: photoAccessHelper.MovingPhoto;
  readonly controller: MovingPhotoViewController = new MovingPhotoViewController();
  readonly muted: boolean;
  readonly fit: ImageFit;
  readonly gesture: boolean;
  previewLoaded: boolean = false;
  prepared: boolean = false;
  playing: boolean = false;

  constructor(id: number, photo: photoAccessHelper.MovingPhoto, muted: boolean, fit: ContentFit, gesture: boolean) {
    this.id = id;
    this.photo = photo;
    this.muted = muted;
    this.fit = fit === ContentFit.Cover ? ImageFit.Cover : ImageFit.Contain;
    this.gesture = gesture;
  }
}

@Observed
export class LivePhotoView extends ExpoView {
  items: RenderedPhoto[] = [];
  private source: LivePhotoAsset | null = null;
  private muted: boolean = true;
  private fit: ContentFit = ContentFit.Contain;
  private gesture: boolean = true;
  private sourceDirty: boolean = false;
  private renderDirty: boolean = false;
  private loadId: number = 0;
  private renderId: number = 0;
  private destroyed: boolean = false;
  private loadFailed: boolean = false;
  private previewSent: boolean = false;
  private completeSent: boolean = false;
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
    if (muted === this.muted) return;

    this.muted = muted;
    this.renderDirty = true;
  }

  setGesture(gesture: boolean): void {
    if (gesture === this.gesture) return;

    this.gesture = gesture;
    this.renderDirty = true;
  }

  commitProps(): void {
    if (this.destroyed) return;

    const reload = this.sourceDirty;
    const rerender = this.renderDirty;

    this.sourceDirty = false;
    this.renderDirty = false;

    if (reload) {
      void this.loadSource();
    } else if (rerender && this.items.length > 0) {
      const photo = this.items[0].photo;

      this.clearRenderedPhoto();
      this.renderPhoto(photo);
    }
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
    if (!this.destroyed) this.items[0]?.controller.stopPlayback();
  }

  onPreview(item: RenderedPhoto): void {
    if (!this.isCurrent(item)) return;

    item.previewLoaded = true;

    if (!this.previewSent) {
      this.previewSent = true;
      this.sendEvent('onPreviewPhotoLoad');
    }

    this.completeLoad(item);
  }

  onPrepared(item: RenderedPhoto): void {
    if (!this.isCurrent(item)) return;

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

    // Expo exposes load errors only. Preserve the loaded preview on playback failure.
    this.onStop(item);
    try {
      item.controller.stopPlayback();
    } catch (error) {
      console.warn(`ExpoLivePhoto: failed to stop playback after an error: ${error}`);
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
    this.previewSent = false;
    this.completeSent = false;

    const source = this.source;
    if (source === null) return;

    this.sendEvent('onLoadStart');

    try {
      const context = this.context.rnComponentContext.uiAbilityContext;
      const bundleName = context.abilityInfo.bundleName;
      const image = localFileUri(source.photoUri, 'photoUri', bundleName);
      const video = localFileUri(source.pairedVideoUri, 'pairedVideoUri', bundleName);

      const photo = await photoAccessHelper.MediaAssetManager.loadMovingPhoto(context, image, video);

      if (!this.destroyed && id === this.loadId) this.renderPhoto(photo);
    } catch (error) {
      this.failLoad(id, error);
    }
  }

  private renderPhoto(photo: photoAccessHelper.MovingPhoto): void {
    this.items = [new RenderedPhoto(++this.renderId, photo, this.muted, this.fit, this.gesture)];
  }

  private clearRenderedPhoto(): void {
    const item = this.items[0];

    // Invalidate before stopping: synchronous and late native callbacks are stale.
    this.items = [];
    if (item === undefined) return;

    try {
      item.controller.stopPlayback();
    } catch (error) {
      console.warn(`ExpoLivePhoto: failed to stop the removed view: ${error}`);
    }

    if (item.playing && !this.destroyed) this.sendEvent('onPlaybackStop');
  }

  private completeLoad(item: RenderedPhoto): void {
    if (!item.previewLoaded || !item.prepared || this.completeSent) return;

    this.completeSent = true;
    this.sendEvent('onLoadComplete');
  }

  private failLoad(id: number, error: Object): void {
    if (this.destroyed || id !== this.loadId) return;

    this.loadFailed = true;
    this.clearRenderedPhoto();

    const message = (error as Error).message || String(error);
    const payload: Record<string, ESObject> = { 'message': message };
    this.sendEvent('onLoadError', payload);
  }

  private isCurrent(item: RenderedPhoto): boolean {
    return !this.destroyed && this.items[0] === item;
  }
}

function localFileUri(value: string | null | undefined, field: string, bundleName: string): string {
  if (!value) throw new Error(`Provided source is not a valid LivePhotoAsset: the \`${field}\` has to be provided.`);

  if (value.includes('\0')) {
    throw new Error(`Provided source is not a valid LivePhotoAsset: \`${field}\` must not contain a NUL character.`);
  }
  if (value.startsWith('/')) return fileUri.getUriFromPath(value);

  const match = /^file:(?:\/\/([^/?#]*)(\/[^?#]*)|(\/(?!\/)[^?#]*))$/i.exec(value);
  if (match === null) {
    throw new Error(`Provided source is not a valid LivePhotoAsset: \`${field}\` must be an application sandbox file URI.`);
  }

  const authority = (match[1] ?? '').toLowerCase();
  if (authority && authority !== 'localhost' && authority !== bundleName.toLowerCase()) {
    throw new Error(`Provided source is not a valid LivePhotoAsset: \`${field}\` must refer to the application sandbox.`);
  }

  // Expo uses authority-free URIs. Media Library Kit needs a system file URI.
  const path = filePathFromUri(`file://${match[2] ?? match[3]}`);
  return fileUri.getUriFromPath(path);
}

@Component
struct LivePhotoViewContent {
  @ObjectLink view: LivePhotoView;

  @Builder
  private photo(item: RenderedPhoto): void {
    MovingPhotoView({ movingPhoto: item.photo, controller: item.controller })
      .width('100%')
      .height('100%')
      .muted(item.muted)
      .objectFit(item.fit)
      .enableAnalyzer(false)
      .hitTestBehavior(item.gesture ? HitTestMode.Default : HitTestMode.None)
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

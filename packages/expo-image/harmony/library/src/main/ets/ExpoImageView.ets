/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoSharedRef, ExpoView, ExpoViewContext, ExpoViewContentContext } from '@expo-harmony/expo-modules-core';
import { image } from '@kit.ImageKit';
import {
  ExpoImageLease,
  ExpoImageLoadCancellation,
  ExpoImageRepository,
  ExpoImageResource,
  ImageLoadOptions,
  ImageSourceRecord,
} from './ExpoImageRepository';
import { ExpoImageError } from './ExpoImageError';

export interface ContentPosition {
  top?: number | string;
  bottom?: number | string;
  left?: number | string;
  right?: number | string;
}

export interface TransitionOptions {
  duration?: number;
  timing?: string;
  effect?: string | null;
}

export interface ImageViewProps {
  source?: ImageSourceRecord[] | ExpoSharedRef<image.PixelMap> | null;
  placeholder?: ImageSourceRecord[] | null;
  contentFit?: string | null;
  placeholderContentFit?: string | null;
  contentPosition?: ContentPosition | null;
  blurRadius?: number | null;
  transition?: TransitionOptions | null;
  tintColor?: number | string | null;
  accessible?: boolean;
  accessibilityLabel?: string;
  focusable?: boolean;
  priority?: string | null;
  cachePolicy?: string | null;
  recyclingKey?: string | null;
  allowDownscaling?: boolean;
  autoplay?: boolean;
  decodeFormat?: string | null;
}

export class ExpoImageLayer {
  readonly resource: ExpoImageResource;
  readonly lease: ExpoImageLease;
  readonly id: number;
  readonly fit: string;
  readonly position: ContentPosition;
  readonly placeholder: boolean;
  readonly blurRadius: number;

  constructor(lease: ExpoImageLease, fit: string, position: ContentPosition, placeholder: boolean, id: number, blurRadius: number) {
    this.resource = lease.resource;
    this.lease = lease;
    this.id = id;
    this.fit = fit;
    this.position = position;
    this.placeholder = placeholder;
    this.blurRadius = placeholder ? 0 : blurRadius;
  }
}

export class ExpoImageRenderState {
  readonly current: ExpoImageLayer | undefined;
  readonly previous: ExpoImageLayer | undefined;
  readonly transition: TransitionOptions | undefined;
  readonly accessible: boolean;
  readonly accessibilityLabel: string;
  readonly focusable: boolean;
  readonly playing: boolean;

  constructor(
    current: ExpoImageLayer | undefined,
    previous: ExpoImageLayer | undefined,
    transition: TransitionOptions | undefined,
    props: ImageViewProps,
    playing: boolean = true,
  ) {
    this.playing = playing;
    this.current = current;
    this.previous = previous;
    this.transition = transition;
    this.accessible = props.accessible === true;
    this.accessibilityLabel = props.accessibilityLabel ?? '';
    this.focusable = props.focusable === true;
  }

  static empty(props: ImageViewProps = {}): ExpoImageRenderState {
    return new ExpoImageRenderState(undefined, undefined, undefined, props);
  }
}

class ImageLoadSourcePayload {
  readonly url: string;
  readonly width: number;
  readonly height: number;
  readonly mediaType: string | null;
  readonly isAnimated: boolean;

  constructor(resource: ExpoImageResource, url: string) {
    this.url = url;
    this.width = resource.width;
    this.height = resource.height;
    this.mediaType = resource.mediaType;
    this.isAnimated = resource.isAnimated;
  }
}

class ImageLoadPayload {
  readonly cacheType: string;
  readonly source: ImageLoadSourcePayload;

  constructor(lease: ExpoImageLease, url: string) {
    this.cacheType = lease.cacheType;

    const resource = lease.resource;
    this.source = new ImageLoadSourcePayload(resource, url);
  }
}

const DEFAULT_FRAME_DURATION_MS: number = 100;

type RenderHandler = (state: ExpoImageRenderState) => void;

function normalizedFit(value: string | null | undefined, placeholder: boolean): string {
  if (value === 'cover' || value === 'contain' || value === 'fill' || value === 'none' || value === 'scale-down') return value;
  return placeholder ? 'scale-down' : 'cover';
}

function normalizedPosition(value?: ContentPosition | null): ContentPosition {
  if (value === undefined || value === null) return { top: '50%', left: '50%' };
  return value;
}

function transitionDuration(value?: TransitionOptions | null): number {
  if (value?.effect === 'none') return 0;
  const duration = Number(value?.duration ?? 0);
  return Number.isFinite(duration) ? Math.max(0, duration) : 0;
}

function isHashResource(resource: ExpoImageResource): boolean {
  return resource.uri.startsWith('blurhash:/') || resource.uri.startsWith('thumbhash:/');
}

function sourcePixelCount(source: ImageSourceRecord): number {
  const width = Number(source.width ?? 0);
  const height = Number(source.height ?? 0);
  const scale = Number(source.scale ?? 1);

  if (width <= 0 || height <= 0 || scale <= 0) return 0;

  return width * height * scale * scale;
}

function chooseSource(sources: ImageSourceRecord[], width: number, height: number): ImageSourceRecord | undefined {
  if (sources.length === 0) return undefined;
  if (sources.length === 1) return sources[0];

  const target = width * height;
  if (target <= 0) return undefined;

  let best: ImageSourceRecord | undefined;
  let fit = Number.POSITIVE_INFINITY;

  for (const source of sources) {
    const candidate = Math.abs(1 - sourcePixelCount(source) / target);
    if (candidate < fit) {
      fit = candidate;
      best = source;
    }
  }

  return best ?? sources[0];
}

function eventError(error: Object): string {
  if (error instanceof ExpoImageError) return `${error.code}: ${error.message}`;
  return String(error).replace(/^(?:Error:\s*)+/, '');
}

export class ExpoImageView extends ExpoView {
  private readonly repository: ExpoImageRepository;
  props: ImageViewProps = {};
  private render?: RenderHandler;
  private current?: ExpoImageLease;
  private currentLayer?: ExpoImageLayer;
  private previousLayer?: ExpoImageLayer;
  private currentPlaceholder: boolean = false;
  private previous?: ExpoImageLease;
  private pixelWidth: number = 0;
  private pixelHeight: number = 0;
  private generation: number = 0;
  private releaseTimer?: number;
  private locked: boolean = false;
  private destroyed: boolean = false;
  private backgrounded: boolean = false;
  private signature: string = '';
  private reloadPending: boolean = false;
  private recycling?: string | null;
  private playing: boolean = true;
  private autoplay: boolean = true;
  private displayId: number = 0;
  private readonly acquireRef: (ref: ExpoSharedRef<image.PixelMap>) => Promise<ExpoImageLease>;
  private readonly imageLoaded: (url: string, pixel: image.PixelMap) => void;
  private sourceRef?: ExpoSharedRef<image.PixelMap>;
  private displayedId?: number;
  private sourceCancel?: ExpoImageLoadCancellation;
  private placeholderCancel?: ExpoImageLoadCancellation;
  private displayedPlaceholder?: string;

  constructor(
    context: ExpoViewContext,
    repository: ExpoImageRepository,
    acquireRef: (ref: ExpoSharedRef<image.PixelMap>) => Promise<ExpoImageLease>,
    imageLoaded: (url: string, pixel: image.PixelMap) => void,
  ) {
    super(context);
    this.repository = repository;
    this.acquireRef = acquireRef;
    this.imageLoaded = imageLoaded;
  }

  setRenderHandler(handler?: RenderHandler): void {
    this.render = handler;

    if (handler !== undefined) handler(this.snapshot());
  }

  setPixelSize(width: number, height: number): void {
    const w = Math.max(0, width);
    const h = Math.max(0, height);

    if (!Number.isFinite(w) || !Number.isFinite(h)) return;
    if (Math.abs(w - this.pixelWidth) < 0.5 && Math.abs(h - this.pixelHeight) < 0.5) return;

    this.pixelWidth = w;
    this.pixelHeight = h;

    void this.reload(false);
  }

  commitProps(): void {
    if (this.autoplay !== (this.props.autoplay !== false)) {
      this.autoplay = this.props.autoplay !== false;
      this.playing = this.currentPlaceholder || this.autoplay;
    }

    const ref = this.props.source instanceof ExpoSharedRef ? this.props.source : undefined;
    const signature = JSON.stringify({
      source: ref === undefined ? this.props.source : null,
      placeholder: this.props.placeholder,
      contentFit: this.props.contentFit,
      cachePolicy: this.props.cachePolicy,
      allowDownscaling: this.props.allowDownscaling,
      decodeFormat: this.props.decodeFormat,
      recyclingKey: this.props.recyclingKey,
      priority: this.props.priority,
      tintColor: this.props.tintColor,
    });

    const changed = signature !== this.signature || ref !== this.sourceRef;
    if (!changed && this.current !== undefined) {
      this.currentLayer = this.makeLayer(this.current, this.currentPlaceholder, this.displayId);
    }

    this.render?.(this.snapshot());

    if (changed) {
      this.signature = signature;
      this.sourceRef = ref;
      this.reloadPending = true;
    }
    if (this.reloadPending) void this.reload(false);
  }

  async startAnimating(): Promise<void> {
    this.playing = true;
    this.render?.(this.snapshot());
  }

  async stopAnimating(): Promise<void> {
    this.playing = false;
    this.render?.(this.snapshot());
  }

  async lockResourceAsync(): Promise<void> {
    this.locked = true;
  }
  async unlockResourceAsync(): Promise<void> {
    this.locked = false;
  }
  async reloadAsync(): Promise<void> {
    await this.reload(true);
  }

  onBackground(): void {
    this.backgrounded = true;
    this.render?.(this.snapshot());
  }

  onForeground(): void {
    this.backgrounded = false;
    this.render?.(this.snapshot());
  }

  onDisplay(id: number): void {
    if (this.destroyed || this.current === undefined || this.currentPlaceholder || this.displayId !== id || this.displayedId === id) return;

    this.displayedId = id;
    this.emit('onDisplay');
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.sourceRef = undefined;
    this.props.source = null;
    this.cancelPendingLoads();
    this.generation += 1;

    if (this.releaseTimer !== undefined) clearTimeout(this.releaseTimer);
    this.releaseTimer = undefined;

    this.current?.release();
    this.previous?.release();

    this.current = undefined;
    this.currentLayer = undefined;
    this.previous = undefined;
    this.previousLayer = undefined;

    this.render = undefined;
  }

  private async reload(force: boolean): Promise<void> {
    if (this.destroyed) return;
    if (this.locked && !force) {
      this.reloadPending = true;
      return;
    }

    this.reloadPending = false;
    this.cancelPendingLoads();
    const generation = (this.generation += 1);

    if (this.recycling !== this.props.recyclingKey) {
      this.recycling = this.props.recyclingKey;
      this.clearDisplayed();
    }

    const width = this.pixelWidth;
    const height = this.pixelHeight;
    if (width <= 0 || height <= 0) {
      if (this.current !== undefined || this.previous !== undefined) this.clearDisplayed();
      return;
    }

    const source = Array.isArray(this.props.source) ? chooseSource(this.props.source, width, height) : undefined;
    const placeholder = Array.isArray(this.props.placeholder) ? chooseSource(this.props.placeholder, width, height) : undefined;
    const sharedSource = this.props.source instanceof ExpoSharedRef ? this.props.source : undefined;

    if (this.currentPlaceholder && placeholder === undefined) this.clearDisplayed();

    if (source === undefined && sharedSource === undefined) {
      if (placeholder !== undefined) {
        await this.loadPlaceholder(placeholder, generation, true);
      } else this.clearDisplayed();
      return;
    }

    if ((this.current === undefined || this.currentPlaceholder) && placeholder !== undefined) {
      void this.loadPlaceholder(placeholder, generation);
    }

    this.emit('onLoadStart');

    let cancellation: ExpoImageLoadCancellation | undefined;
    let lease: ExpoImageLease | undefined;
    const tintColor = this.props.tintColor;

    try {
      if (sharedSource !== undefined) {
        lease = await this.acquireRef(sharedSource);
        if (generation !== this.generation || this.destroyed) return;
        if (tintColor != null) lease = await this.repository.tintLease(lease, tintColor);
      } else {
        cancellation = new ExpoImageLoadCancellation();
        this.sourceCancel = cancellation;

        const options: ImageLoadOptions = {};
        options.tintColor = tintColor;
        options.priority = this.props.priority ?? undefined;
        options.decodeFormat = this.props.decodeFormat ?? undefined;
        options.contentFit = this.props.contentFit ?? undefined;
        if (this.props.allowDownscaling !== false && this.props.contentFit !== 'none' && this.props.contentFit !== 'fill') {
          if (width > 0) options.maxWidth = width;
          if (height > 0) options.maxHeight = height;
        }

        lease = await this.repository.load(
          source as ImageSourceRecord,
          this.props.cachePolicy ?? undefined,
          options,
          (progress): void => {
            if (generation === this.generation && !this.destroyed) this.emit('onProgress', progress);
          },
          cancellation,
        );
      }

      if (generation !== this.generation || this.destroyed) return;

      this.cancelPlaceholderLoad();
      this.emit('onLoad', new ImageLoadPayload(lease, source?.uri ?? lease.resource.uri));
      if (source !== undefined) this.imageLoaded(source.uri ?? '', lease.resource.frames[0]);
      this.displayedPlaceholder = undefined;

      const displayed = lease;
      lease = undefined;
      this.display(displayed, false);
    } catch (error) {
      if (generation !== this.generation || this.destroyed) return;
      this.emit('onError', { error: eventError(error as Object) });
    } finally {
      lease?.release();
      if (cancellation !== undefined && this.sourceCancel === cancellation) {
        this.sourceCancel = undefined;
      }
    }
  }

  private async loadPlaceholder(source: ImageSourceRecord, generation: number, replaceCurrent: boolean = false): Promise<void> {
    const signature = JSON.stringify(source);
    if (this.currentPlaceholder && this.displayedPlaceholder === signature) return;

    const cancellation = new ExpoImageLoadCancellation();
    this.placeholderCancel = cancellation;

    try {
      const lease = await this.repository.load(source, 'disk', {}, undefined, cancellation);

      if (
        cancellation.isCancelled() || generation !== this.generation || this.destroyed ||
        (this.current !== undefined && !this.currentPlaceholder && !replaceCurrent)
      ) {
        lease.release();
        return;
      }

      this.displayedPlaceholder = signature;
      this.display(lease, true);
    } catch (error) {
      if (generation === this.generation && !cancellation.isCancelled()) {
        console.warn(`Expo Image placeholder failed: ${eventError(error as Object)}`);
      }
    } finally {
      if (this.placeholderCancel === cancellation) {
        this.placeholderCancel = undefined;
      }
    }
  }

  private cancelPendingLoads(): void {
    this.sourceCancel?.cancel();
    this.sourceCancel = undefined;

    this.cancelPlaceholderLoad();
  }

  private cancelPlaceholderLoad(): void {
    this.placeholderCancel?.cancel();
    this.placeholderCancel = undefined;
  }

  private display(lease: ExpoImageLease, placeholder: boolean): void {
    const stale: ExpoImageLease[] = [];

    if (this.releaseTimer !== undefined) {
      clearTimeout(this.releaseTimer);
      this.releaseTimer = undefined;
      if (this.previous !== undefined) stale.push(this.previous);
      this.previous = undefined;
      this.previousLayer = undefined;
    }

    const duration = placeholder ? 0 : transitionDuration(this.props.transition);
    this.displayId += 1;

    const outgoing = this.current;
    const outgoingLayer = this.currentLayer;
    this.current = lease;
    this.currentLayer = this.makeLayer(lease, placeholder, this.displayId);
    this.currentPlaceholder = placeholder;
    this.playing = placeholder || this.props.autoplay !== false;
    this.displayedId = undefined;

    if (outgoing !== undefined && outgoing.resource !== lease.resource && duration > 0) {
      this.previous = outgoing;
      this.previousLayer = outgoingLayer;

      this.releaseTimer = setTimeout((): void => {
        const previous = this.previous;
        this.previous = undefined;
        this.previousLayer = undefined;

        this.releaseTimer = undefined;
        this.render?.(this.snapshot());
        previous?.release();
      }, duration);
    } else {
      if (outgoing !== undefined) stale.push(outgoing);
    }

    this.render?.(this.snapshot(duration > 0 ? (this.props.transition ?? undefined) : undefined));

    for (const lease of stale) lease.release();
  }

  private makeLayer(lease: ExpoImageLease, placeholder: boolean, id: number): ExpoImageLayer {
    const regularPlaceholder = placeholder && !isHashResource(lease.resource);
    return new ExpoImageLayer(
      lease,
      normalizedFit(regularPlaceholder ? this.props.placeholderContentFit : this.props.contentFit, regularPlaceholder),
      placeholder ? { top: '50%', left: '50%' } : normalizedPosition(this.props.contentPosition),
      placeholder,
      id,
      Math.max(0, this.props.blurRadius ?? 0),
    );
  }

  private snapshot(transition?: TransitionOptions): ExpoImageRenderState {
    return new ExpoImageRenderState(this.currentLayer, this.previousLayer, transition, this.props, this.playing && !this.backgrounded);
  }

  private clearDisplayed(): void {
    if (this.releaseTimer !== undefined) clearTimeout(this.releaseTimer);
    this.releaseTimer = undefined;

    const current = this.current;
    const previous = this.previous;

    this.current = undefined;
    this.currentLayer = undefined;
    this.previous = undefined;
    this.previousLayer = undefined;

    this.currentPlaceholder = false;
    this.displayedPlaceholder = undefined;
    this.displayedId = undefined;

    this.render?.(this.snapshot());

    current?.release();
    previous?.release();
  }

  private emit(name: string, payload: ESObject = {}): void {
    if (!this.destroyed) this.sendEvent(name, payload);
  }
}

function offsetValue(raw: number | string, reverse: boolean, available: number): number {
  let value: number;

  if (typeof raw === 'number') value = raw;
  else if (raw === 'center') value = available * 0.5;
  else if (raw.trim().endsWith('%')) value = (available * Number.parseFloat(raw)) / 100;
  else value = Number(raw);

  if (!Number.isFinite(value)) value = available * 0.5;

  return reverse ? available - value : value;
}

function horizontalOffset(position: ContentPosition, available: number): number {
  if (position.left !== undefined) return offsetValue(position.left, false, available);
  if (position.right !== undefined) return offsetValue(position.right, true, available);
  return available * 0.5;
}

function verticalOffset(position: ContentPosition, available: number): number {
  if (position.top !== undefined) return offsetValue(position.top, false, available);
  if (position.bottom !== undefined) return offsetValue(position.bottom, true, available);
  return available * 0.5;
}

class LayerLayout {
  width: number;
  height: number;
  x: number;
  y: number;

  constructor(width: number, height: number, x: number, y: number) {
    this.width = width;
    this.height = height;
    this.x = x;
    this.y = y;
  }
}

function layerLayout(layer: ExpoImageLayer, containerWidth: number, containerHeight: number): LayerLayout {
  const sourceWidth = Math.max(1, layer.resource.width);
  const sourceHeight = Math.max(1, layer.resource.height);
  let width = sourceWidth;
  let height = sourceHeight;

  if (layer.fit === 'fill') {
    width = containerWidth;
    height = containerHeight;
  } else if (layer.fit === 'cover' || layer.fit === 'contain' || layer.fit === 'scale-down') {
    const cover = Math.max(containerWidth / sourceWidth, containerHeight / sourceHeight);
    const contain = Math.min(containerWidth / sourceWidth, containerHeight / sourceHeight);
    const scale = layer.fit === 'cover' ? cover : layer.fit === 'contain' ? contain : Math.min(1, contain);
    width = sourceWidth * scale;
    height = sourceHeight * scale;
  }

  const x = horizontalOffset(layer.position, containerWidth - width);
  const y = verticalOffset(layer.position, containerHeight - height);

  return new LayerLayout(width, height, x, y);
}
@Builder
export function buildExpoImageView(context: ExpoViewContentContext): void {
  ExpoImageSurface({ view: context.nativeView as ExpoImageView });
}

@Component
struct ExpoImageSurface {
  @Require view!: ExpoImageView;
  @State private renderState: ExpoImageRenderState = ExpoImageRenderState.empty();
  @State private surfaceWidth: number = 0;
  @State private surfaceHeight: number = 0;
  @State private currentOpacity: number = 1;
  @State private previousOpacity: number = 0;

  aboutToAppear(): void {
    this.view.setRenderHandler((next: ExpoImageRenderState): void => {
      this.renderState = next;
      if (next.transition !== undefined) {
        this.currentOpacity = 0;
        this.previousOpacity = next.previous === undefined ? 0 : 1;
        this.getUIContext().animateTo({ duration: transitionDuration(next.transition), curve: this.transitionCurve(next.transition) }, (): void => {
          this.currentOpacity = 1;
          this.previousOpacity = 0;
        });
      } else if (next.previous === undefined) {
        this.currentOpacity = 1;
        this.previousOpacity = 0;
      }
    });
  }

  aboutToDisappear(): void {
    this.view.setRenderHandler(undefined);
  }

  private activeLayer(layer: ExpoImageLayer): ExpoImageLayer {
    const current = this.renderState.current;
    return current !== undefined && layer.id === current.id ? current : layer;
  }

  private layers(): ExpoImageLayer[] {
    const layers: ExpoImageLayer[] = [];
    if (this.renderState.previous !== undefined) layers.push(this.renderState.previous);
    if (this.renderState.current !== undefined) layers.push(this.renderState.current);
    return layers;
  }

  build(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(
        this.layers(),
        (layer: ExpoImageLayer): void => {
          ExpoImageLayerContent({
            layer,
            view: this.view,
            layout: layerLayout(this.activeLayer(layer), this.surfaceWidth, this.surfaceHeight),
            playing: this.renderState.playing && layer.id === this.renderState.current?.id,
            blurRadius: this.activeLayer(layer).blurRadius,
          }).opacity(layer.id === this.renderState.current?.id ? this.currentOpacity : this.previousOpacity);
        },
        (layer: ExpoImageLayer): string => String(layer.id),
      )
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .accessibilityGroup(this.renderState.accessible)
    .accessibilityLevel(this.renderState.accessible ? 'yes' : 'no-hide-descendants')
    .accessibilityText(this.renderState.accessibilityLabel)
    .focusable(this.renderState.focusable)
    .onAreaChange((_: Area, area: Area): void => {
      const width = Number(area.width);
      const height = Number(area.height);
      if (!Number.isFinite(width) || !Number.isFinite(height)) return;

      this.surfaceWidth = width;
      this.surfaceHeight = height;
      const context = this.getUIContext();
      this.view.setPixelSize(context.vp2px(width), context.vp2px(height));
    });
  }

  private transitionCurve(options: TransitionOptions): Curve {
    if (options.timing === 'linear') return Curve.Linear;
    if (options.timing === 'ease-in') return Curve.EaseIn;
    if (options.timing === 'ease-out') return Curve.EaseOut;
    return Curve.EaseInOut;
  }
}

@Component
struct ExpoImageLayerContent {
  @Require layer!: ExpoImageLayer;
  @Require view!: ExpoImageView;
  @Prop layout: LayerLayout = new LayerLayout(0, 0, 0, 0);
  @Prop playing: boolean = true;
  @Prop blurRadius: number = 0;
  private lease?: ExpoImageLease;
  private animationFrames: ImageFrameInfo[] = [];

  aboutToAppear(): void {
    // Keep PixelMaps alive until ArkUI detaches the nodes, including during transitions.
    this.lease = this.layer.lease.acquire();

    // Keep the frame list stable so an opacity/layout update cannot restart playback.
    this.animationFrames = this.layer.resource.frames.map(
      (pixel, index: number): ImageFrameInfo => ({
        src: pixel,
        duration: this.layer.resource.delays[index] > 0 ? this.layer.resource.delays[index] : DEFAULT_FRAME_DURATION_MS,
      }),
    );
  }

  aboutToDisappear(): void {
    this.lease?.release();
    this.lease = undefined;
  }

  build(): void {
    Stack() {
      Image(this.layer.resource.frames[0])
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Fill)
        .onComplete((event): void => {
          if (event?.loadingStatus === 1) this.view.onDisplay(this.layer.id);
        })
      if (this.layer.resource.isAnimated) {
        ImageAnimator()
          .images(this.animationFrames)
          .fixedSize(true)
          .iterations(this.layer.resource.iterations)
          .fillMode(FillMode.Forwards)
          .state(this.playing ? AnimationStatus.Running : AnimationStatus.Paused)
          .width('100%')
          .height('100%');
      }
    }
    .width(this.layout.width)
    .height(this.layout.height)
    .position({ x: this.layout.x, y: this.layout.y })
    .blur(this.blurRadius)
    .hitTestBehavior(HitTestMode.None);
  }
}

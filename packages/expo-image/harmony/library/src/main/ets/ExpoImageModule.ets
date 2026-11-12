/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoSharedObjectClassDefinition,
  ExpoSharedObjectTypes,
  ExpoSharedRef,
  ExpoValueType,
  ExpoValueTypes,
  ExpoViewContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import { image } from '@kit.ImageKit';
import { ExpoImageError } from './ExpoImageError';
import { encodeBlurhash, encodeThumbhash } from './ExpoImageHash';
import { ExpoImageLease, ExpoImageRepository, ImageCacheConfig, ImageLoadOptions, ImageSourceRecord } from './ExpoImageRepository';
import { buildExpoImageView, ContentPosition, ExpoImageView, TransitionOptions } from './ExpoImageView';
import { copyPixelMap } from './ExpoImageUtils';

function record(value: ESObject, path: string): Record<string, ESObject> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoImageError('ERR_IMAGE_INVALID_ARGUMENT', `${path} must be an object.`);
  }

  return value as Record<string, ESObject>;
}

function field<T>(values: Record<string, ESObject>, name: string, type: ExpoValueType<T>, path: string): T | undefined {
  return values[name] == null ? undefined : type.decode(values[name], `${path}.${name}`);
}

function recordType<T>(name: string, decode: (fields: Record<string, ESObject>, path: string) => T): ExpoValueType<T> {
  return new ExpoValueType<T>(
    name,
    (value: ESObject, path: string): T => decode(record(value, path), path),
    (value: T): ESObject => value,
  );
}

function choice(name: string, values: string[]): ExpoValueType<string> {
  return new ExpoValueType<string>(
    name,
    (value: ESObject, path: string): string => {
      if (typeof value !== 'string' || !values.includes(value)) {
        throw new ExpoImageError('ERR_IMAGE_INVALID_ARGUMENT', `${path} must be one of ${values.join(', ')}.`);
      }

      return value;
    },
    (value: string): ESObject => value,
  );
}

const NUMBER = new ExpoValueType<number>(
  'finite number',
  (value: ESObject, path: string): number => {
    const number = ExpoValueTypes.number().decode(value, path);
    if (!Number.isFinite(number)) throw new ExpoImageError('ERR_IMAGE_INVALID_ARGUMENT', `${path} must be finite.`);

    return number;
  },
  (value: number): ESObject => value,
);
const NONNEGATIVE = new ExpoValueType<number>(
  'non-negative number',
  (value: ESObject, path: string): number => {
    const number = NUMBER.decode(value, path);
    if (number < 0) throw new ExpoImageError('ERR_IMAGE_INVALID_ARGUMENT', `${path} must not be negative.`);

    return number;
  },
  (value: number): ESObject => value,
);
const STRING = ExpoValueTypes.string();
const BOOLEAN = ExpoValueTypes.boolean();
const FIT = choice('ContentFit', ['cover', 'contain', 'fill', 'none', 'scale-down']);
const POLICY = choice('CachePolicy', ['none', 'disk', 'memory', 'memory-disk']);
const PRIORITY = choice('Priority', ['low', 'normal', 'high']);
const FORMAT = choice('DecodeFormat', ['argb', 'rgb']);
const COLOR = new ExpoValueType<number | string>(
  'Color',
  (value: ESObject, path: string): number | string => {
    if (typeof value === 'string') return value;
    return NUMBER.decode(value, path);
  },
  (value: number | string): ESObject => value,
);
const HEADERS = recordType<Record<string, string>>('Headers', (values: Record<string, ESObject>, path: string): Record<string, string> => {
  const headers: Record<string, string> = {};
  Object.keys(values).forEach((name: string): void => {
    headers[name] = STRING.decode(values[name], `${path}.${name}`);
  });

  return headers;
});
const SOURCE = recordType<ImageSourceRecord>(
  'ImageSource',
  (values: Record<string, ESObject>, path: string): ImageSourceRecord => ({
    uri: field(values, 'uri', STRING, path),
    width: field(values, 'width', NUMBER, path),
    height: field(values, 'height', NUMBER, path),
    scale: field(values, 'scale', NUMBER, path),
    headers: field(values, 'headers', HEADERS, path),
    cacheKey: field(values, 'cacheKey', STRING, path),
    isAnimated: field(values, 'isAnimated', BOOLEAN, path),
  }),
);
const SOURCES = ExpoValueTypes.array(SOURCE);
const POSITION_VALUE = new ExpoValueType<number | string>(
  'Position',
  (value: ESObject, path: string): number | string => {
    if (typeof value === 'number') return NUMBER.decode(value, path);
    if (
      typeof value === 'string' &&
      (value === 'center' || (/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?%?$/.test(value) && Number.isFinite(Number.parseFloat(value))))
    )
      return value;
    throw new ExpoImageError('ERR_IMAGE_INVALID_ARGUMENT', `${path} must be a number or percentage.`);
  },
  (value: number | string): ESObject => value,
);
const POSITION = recordType<ContentPosition>(
  'ContentPosition',
  (values: Record<string, ESObject>, path: string): ContentPosition => ({
    top: field(values, 'top', POSITION_VALUE, path),
    bottom: field(values, 'bottom', POSITION_VALUE, path),
    left: field(values, 'left', POSITION_VALUE, path),
    right: field(values, 'right', POSITION_VALUE, path),
  }),
);
const TRANSITION = recordType<TransitionOptions>(
  'ImageTransition',
  (values: Record<string, ESObject>, path: string): TransitionOptions => ({
    duration: field(values, 'duration', NUMBER, path),
    timing: field(values, 'timing', choice('Timing', ['linear', 'ease-in', 'ease-out', 'ease-in-out']), path),
    effect: field(values, 'effect', STRING, path),
  }),
);
const LOAD_OPTIONS = recordType<ImageLoadOptions>(
  'ImageLoadOptions',
  (values: Record<string, ESObject>, path: string): ImageLoadOptions => ({
    maxWidth: field(values, 'maxWidth', NUMBER, path),
    maxHeight: field(values, 'maxHeight', NUMBER, path),
    tintColor: field(values, 'tintColor', COLOR, path),
  }),
);
const CACHE_CONFIG = recordType<ImageCacheConfig>(
  'ImageCacheConfig',
  (values: Record<string, ESObject>, path: string): ImageCacheConfig => ({
    maxDiskSize: field(values, 'maxDiskSize', NUMBER, path),
    maxMemoryCost: field(values, 'maxMemoryCost', NUMBER, path),
    maxMemoryCount: field(values, 'maxMemoryCount', NUMBER, path),
  }),
);
const IMAGE_REF = ExpoSharedObjectTypes.sharedRef<ExpoSharedRef<image.PixelMap>>('image');
const HASH_SOURCE = new ExpoValueType<string | ExpoSharedRef<image.PixelMap>>(
  'URL | ImageRef',
  (value: ESObject, path: string): string | ExpoSharedRef<image.PixelMap> => {
    return typeof value === 'string' ? value : IMAGE_REF.decode(value, path);
  },
  (value: string | ExpoSharedRef<image.PixelMap>): ESObject => value,
);
const COMPONENTS = new ExpoValueType<number[]>(
  'BlurhashComponents',
  (value: ESObject, path: string): number[] => {
    let components: number[];
    if (Array.isArray(value)) components = ExpoValueTypes.array(NUMBER).decode(value, path);
    else {
      const values = record(value, path);
      components = [NUMBER.decode(values.width, `${path}.width`), NUMBER.decode(values.height, `${path}.height`)];
    }

    if (components.length !== 2 || components.some((part: number): boolean => !Number.isInteger(part) || part < 1 || part > 9)) {
      throw new ExpoImageError('ERR_IMAGE_INVALID_HASH_COMPONENTS', 'Blurhash needs two component counts between 1 and 9.');
    }

    return components;
  },
  (value: number[]): ESObject => value,
);

class ExpoImageRef extends ExpoSharedRef<image.PixelMap> {
  readonly lease: ExpoImageLease;

  constructor(context: ExpoModuleContext, lease: ExpoImageLease) {
    super(context, 'image', lease.resource.frames[0]);
    this.lease = lease;
  }

  override getAdditionalMemoryPressure(): number {
    return this.lease.resource.memoryBytes;
  }

  override sharedObjectWillRelease(): void {
    this.lease.release();
  }
}

export class ExpoImageModule extends ExpoModule {
  private repository?: ExpoImageRepository;
  private readonly views: Set<ExpoImageView> = new Set();
  private hasImageLoadedListener: boolean = false;
  private backgrounded: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  private images(): ExpoImageRepository {
    if (this.repository === undefined) this.repository = new ExpoImageRepository(this.context);
    return this.repository;
  }

  override definition(): ExpoModuleDefinition {
    const reference = new ExpoSharedObjectClassDefinition<ExpoImageRef>('Image')
      .sharedRef('image')
      .property('width', NUMBER, (ref: ExpoImageRef): number => ref.value.getImageInfoSync().size.width / ref.lease.resource.scale)
      .property('height', NUMBER, (ref: ExpoImageRef): number => ref.value.getImageInfoSync().size.height / ref.lease.resource.scale)
      .property('scale', NUMBER, (ref: ExpoImageRef): number => ref.lease.resource.scale)
      .property('isAnimated', BOOLEAN, (ref: ExpoImageRef): boolean => ref.lease.resource.isAnimated)
      .property('mediaType', STRING.nullable(), (ref: ExpoImageRef): string | null => ref.lease.resource.mediaType);

    const view = new ExpoViewDefinition<ExpoImageView>(
      'ImageView',
      (context: ExpoViewContext): ExpoImageView => {
        const instance = new ExpoImageView(
          context,
          this.images(),
          (ref: ExpoSharedRef<image.PixelMap>): Promise<ExpoImageLease> => this.acquireRef(ref),
          (url: string, pixel: image.PixelMap): void => this.emitImageLoaded(url, pixel),
        );
        if (this.backgrounded) instance.onBackground();
        this.views.add(instance);

        return instance;
      },
      wrapBuilder(buildExpoImageView),
    )
      .prop(
        'source',
        SOURCES.or(IMAGE_REF).nullable(),
        (view: ExpoImageView, value: ImageSourceRecord[] | ExpoSharedRef<image.PixelMap> | null): void => {
          view.props.source = value;
        },
        null,
      )
      .prop(
        'placeholder',
        SOURCES.nullable(),
        (view: ExpoImageView, value: ImageSourceRecord[] | null): void => {
          view.props.placeholder = value;
        },
        null,
      )
      .prop(
        'contentFit',
        FIT,
        (view: ExpoImageView, value: string): void => {
          view.props.contentFit = value;
        },
        'cover',
      )
      .prop(
        'placeholderContentFit',
        FIT,
        (view: ExpoImageView, value: string): void => {
          view.props.placeholderContentFit = value;
        },
        'scale-down',
      )
      .prop(
        'contentPosition',
        POSITION.nullable(),
        (view: ExpoImageView, value: ContentPosition | null): void => {
          view.props.contentPosition = value;
        },
        null,
      )
      .prop(
        'blurRadius',
        NONNEGATIVE,
        (view: ExpoImageView, value: number): void => {
          view.props.blurRadius = value;
        },
        0,
      )
      .prop(
        'transition',
        TRANSITION.nullable(),
        (view: ExpoImageView, value: TransitionOptions | null): void => {
          view.props.transition = value;
        },
        null,
      )
      .prop(
        'tintColor',
        COLOR.nullable(),
        (view: ExpoImageView, value: number | string | null): void => {
          view.props.tintColor = value;
        },
        null,
      )
      .prop(
        'accessible',
        BOOLEAN,
        (view: ExpoImageView, value: boolean): void => {
          view.props.accessible = value;
        },
        false,
      )
      .prop(
        'accessibilityLabel',
        STRING,
        (view: ExpoImageView, value: string): void => {
          view.props.accessibilityLabel = value;
        },
        '',
      )
      .prop(
        'focusable',
        BOOLEAN,
        (view: ExpoImageView, value: boolean): void => {
          view.props.focusable = value;
        },
        false,
      )
      .prop(
        'priority',
        PRIORITY,
        (view: ExpoImageView, value: string): void => {
          view.props.priority = value;
        },
        'normal',
      )
      .prop(
        'cachePolicy',
        POLICY,
        (view: ExpoImageView, value: string): void => {
          view.props.cachePolicy = value;
        },
        'disk',
      )
      .prop(
        'recyclingKey',
        STRING.nullable(),
        (view: ExpoImageView, value: string | null): void => {
          view.props.recyclingKey = value;
        },
        null,
      )
      .prop(
        'allowDownscaling',
        BOOLEAN,
        (view: ExpoImageView, value: boolean): void => {
          view.props.allowDownscaling = value;
        },
        true,
      )
      .prop(
        'autoplay',
        BOOLEAN,
        (view: ExpoImageView, value: boolean): void => {
          view.props.autoplay = value;
        },
        true,
      )
      .prop(
        'decodeFormat',
        FORMAT,
        (view: ExpoImageView, value: string): void => {
          view.props.decodeFormat = value;
        },
        'argb',
      )
      .events(['onLoadStart', 'onProgress', 'onLoad', 'onError', 'onDisplay'])
      .asyncFunction('startAnimating', async (view: ExpoImageView): Promise<void> => view.startAnimating())
      .asyncFunction('stopAnimating', async (view: ExpoImageView): Promise<void> => view.stopAnimating())
      .asyncFunction('lockResourceAsync', async (view: ExpoImageView): Promise<void> => view.lockResourceAsync())
      .asyncFunction('unlockResourceAsync', async (view: ExpoImageView): Promise<void> => view.unlockResourceAsync())
      .asyncFunction('reloadAsync', async (view: ExpoImageView): Promise<void> => view.reloadAsync())
      .onDidUpdateProps((view: ExpoImageView): void => view.commitProps())
      .onDestroy((view: ExpoImageView): void => {
        view.destroy();
        this.views.delete(view);
      });

    return new ExpoModuleDefinition()
      .name('ExpoImage')
      .events(['imageLoaded'])
      .onStartObserving('imageLoaded', (): void => {
        this.hasImageLoadedListener = true;
      })
      .onStopObserving('imageLoaded', (): void => {
        this.hasImageLoadedListener = false;
      })
      .sharedObjectClass(reference)
      .view(view)
      .syncFunction(
        'configureCache',
        ExpoFunction.typed1(CACHE_CONFIG, (config: ImageCacheConfig): void => this.images().configure(config)),
      )
      .asyncFunction(
        'prefetch',
        ExpoFunction.typed3(
          ExpoValueTypes.array(STRING),
          POLICY,
          HEADERS.nullable().optional(),
          async (urls: string[], policy: string, headers?: Record<string, string> | null): Promise<boolean> =>
            this.images().prefetch(urls, policy, headers ?? undefined),
        ),
      )
      .asyncFunction(
        'loadAsync',
        ExpoFunction.typed2(
          SOURCE,
          LOAD_OPTIONS.nullable().optional(),
          async (source: ImageSourceRecord, options?: ImageLoadOptions | null): Promise<ExpoImageRef> => {
            const lease = await this.images().load(source, 'memory-disk', options ?? {});

            try {
              this.emitImageLoaded(source.uri ?? '', lease.resource.frames[0]);
              return reference.instance(new ExpoImageRef(this.context, lease));
            } catch (error) {
              lease.release();

              throw new ExpoImageError('ERR_IMAGE_INVALID_REF', String(error));
            }
          },
        ).returns(reference.valueType()),
      )
      .asyncFunction(
        'writeToCacheAsync',
        ExpoFunction.typed2(HASH_SOURCE, STRING, async (source: string | ExpoSharedRef<image.PixelMap>, cacheKey: string): Promise<void> => {
          if (typeof source === 'string') {
            await this.images().writeToCache(source, cacheKey);
            return;
          }

          const lease = await this.acquireRef(source);

          try {
            await this.images().writeToCache(lease.resource.frames[0], cacheKey);
          } finally {
            lease.release();
          }
        }),
      )
      .asyncFunction(
        'readFromCacheAsync',
        ExpoFunction.typed1(STRING, async (cacheKey: string): Promise<ExpoImageRef | null> => {
          const lease = await this.images().readFromCache(cacheKey);
          if (lease === null) return null;

          try {
            return reference.instance(new ExpoImageRef(this.context, lease));
          } catch (error) {
            lease.release();
            throw new ExpoImageError('ERR_IMAGE_INVALID_REF', String(error));
          }
        }).returns(reference.valueType().nullable()),
      )
      .asyncFunction('clearMemoryCache', async (): Promise<boolean> => this.images().clearMemory())
      .asyncFunction('clearDiskCache', async (): Promise<boolean> => this.images().clearDisk())
      .asyncFunction(
        'getCachePathAsync',
        ExpoFunction.typed1(STRING, async (key: string): Promise<string | null> => this.images().getCachePath(key)),
      )
      .asyncFunction(
        'generateBlurhashAsync',
        ExpoFunction.typed2(
          HASH_SOURCE,
          COMPONENTS.optional(),
          async (source: string | ExpoSharedRef<image.PixelMap>, components?: number[]): Promise<string> => {
            const pixel = await this.hashPixel(source);

            try {
              return await encodeBlurhash(pixel, components?.[0] ?? 4, components?.[1] ?? 3);
            } finally {
              await pixel.release();
            }
          },
        ),
      )
      .asyncFunction(
        'generateThumbhashAsync',
        ExpoFunction.typed1(HASH_SOURCE, async (source: string | ExpoSharedRef<image.PixelMap>): Promise<string> => {
          const pixel = await this.hashPixel(source, 100);

          try {
            return await encodeThumbhash(pixel);
          } finally {
            await pixel.release();
          }
        }),
      )
      .onBackground((): void => {
        this.backgrounded = true;
        this.views.forEach((view: ExpoImageView): void => view.onBackground());
      })
      .onForeground((): void => {
        this.backgrounded = false;
        this.views.forEach((view: ExpoImageView): void => view.onForeground());
      })
      .onMemoryLevel((): void => {
        this.repository?.clearMemory();
      })
      .onDestroy((): void => {
        this.hasImageLoadedListener = false;
        this.views.forEach((view: ExpoImageView): void => view.destroy());
        this.views.clear();
        this.repository?.destroy();
      });
  }

  private emitImageLoaded(url: string, pixel: image.PixelMap): void {
    if (!this.hasImageLoadedListener || url.length === 0) return;
    const size = pixel.getImageInfoSync().size;
    if (size.width <= 0 || size.height <= 0) return;

    this.sendEvent('imageLoaded', { url, width: size.width, height: size.height });
  }

  private async acquireRef(ref: ExpoSharedRef<image.PixelMap>): Promise<ExpoImageLease> {
    if (ref instanceof ExpoImageRef) return ref.lease.acquire();
    return this.images().adoptPixelMap(await copyPixelMap(ref.value));
  }

  private async hashPixel(source: string | ExpoSharedRef<image.PixelMap>, maxSize?: number): Promise<image.PixelMap> {
    const lease = typeof source === 'string' ? await this.images().load({ uri: source }, 'none') : await this.acquireRef(source);

    try {
      return await this.images().pixelForHash(lease.resource, maxSize);
    } finally {
      lease.release();
    }
  }
}

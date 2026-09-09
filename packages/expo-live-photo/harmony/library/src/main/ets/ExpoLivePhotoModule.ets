import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoRecordShape,
  ExpoValueTypes,
  ExpoViewContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import { buildLivePhotoView, ContentFit, LivePhotoAsset, LivePhotoView, PlaybackStyle } from './LivePhotoView';

const SOURCE_TYPE = ExpoValueTypes.shapedRecord<LivePhotoAsset>(
  'LivePhotoAsset',
  new ExpoRecordShape()
    .field('photoUri', ExpoValueTypes.string().nullable().optional())
    .field('pairedVideoUri', ExpoValueTypes.string().nullable().optional()),
  (fields: Record<string, ESObject>): LivePhotoAsset => new LivePhotoAsset(fields.photoUri, fields.pairedVideoUri),
  (asset: LivePhotoAsset): Record<string, ESObject> => {
    const fields: Record<string, ESObject> = {};
    fields['photoUri'] = asset.photoUri;
    fields['pairedVideoUri'] = asset.pairedVideoUri;

    return fields;
  },
);
const CONTENT_FIT_TYPE = ExpoValueTypes.enumerable<ContentFit>('ContentFit', { contain: ContentFit.Contain, cover: ContentFit.Cover });
const PLAYBACK_STYLE_TYPE = ExpoValueTypes.enumerable<PlaybackStyle>('PlaybackStyle', { full: PlaybackStyle.Full, hint: PlaybackStyle.Hint });

export class ExpoLivePhotoModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  override definition(): ExpoModuleDefinition {
    const view = new ExpoViewDefinition<LivePhotoView>(
      'LivePhotoView',
      (context: ExpoViewContext): LivePhotoView => new LivePhotoView(context),
      wrapBuilder(buildLivePhotoView),
    )
      .prop('source', SOURCE_TYPE.nullable(), (view: LivePhotoView, source: LivePhotoAsset | null): void => view.setSource(source), null)
      .prop('isMuted', ExpoValueTypes.boolean().nullable(), (view: LivePhotoView, value: boolean | null): void => view.setMuted(value ?? true), null)
      .prop(
        'contentFit',
        CONTENT_FIT_TYPE.nullable(),
        (view: LivePhotoView, value: ContentFit | null): void => view.setContentFit(value ?? ContentFit.Contain),
        null,
      )
      .prop(
        'useDefaultGestureRecognizer',
        ExpoValueTypes.boolean().nullable(),
        (view: LivePhotoView, value: boolean | null): void => view.setGesture(value ?? true),
        null,
      )
      .events(['onLoadStart', 'onPreviewPhotoLoad', 'onLoadComplete', 'onLoadError', 'onPlaybackStart', 'onPlaybackStop'])
      .asyncFunction(
        'startPlayback',
        ExpoFunction.ownedTyped1(PLAYBACK_STYLE_TYPE, async (view: LivePhotoView, style: PlaybackStyle): Promise<void> => {
          view.startPlayback(style);
        }),
      )
      .asyncFunction('stopPlayback', async (view: LivePhotoView): Promise<void> => view.stopPlayback())
      .onDidUpdateProps((view: LivePhotoView): void => view.commitProps())
      .onDestroy((view: LivePhotoView): void => view.destroy());

    return new ExpoModuleDefinition()
      .name('ExpoLivePhoto')
      .syncFunction('isAvailable', (): boolean => canIUse('SystemCapability.FileManagement.PhotoAccessHelper.Core'))
      .view(view);
  }
}

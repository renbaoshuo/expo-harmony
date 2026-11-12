/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoValueTypes,
  ExpoView,
  ExpoViewContentContext,
  ExpoViewContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import { image } from '@kit.ImageKit';
import { ContentType, GET_IMAGE_OPTIONS, GetImageOptions } from './ClipboardOptions';

const CONTENT_TYPES = ExpoValueTypes.enumerable<ContentType>('AcceptedContentType', {
  'plain-text': ContentType.PlainText,
  'html': ContentType.HTML,
  'image': ContentType.Image,
  'url': ContentType.URL,
});

const DEFAULT_CONTENT_TYPES = [ContentType.PlainText, ContentType.Image];

export interface PasteButtonResult {
  type: string;
  text?: string;
  data?: string;
  size?: image.Size;
}

type ReadPasteButton = (types: ContentType[], options: GetImageOptions) => Promise<PasteButtonResult | undefined>;

@Observed
class ClipboardPasteButtonView extends ExpoView {
  backgroundColor: string | null = null;
  foregroundColor: string | null = null;
  cornerStyle: string | null = null;
  displayMode: string | null = null;
  acceptedContentTypes: ContentType[] = DEFAULT_CONTENT_TYPES;
  imageOptions: GetImageOptions = new GetImageOptions();
  destroyed: boolean = false;
  private readonly read: ReadPasteButton;

  constructor(context: ExpoViewContext, read: ReadPasteButton) {
    super(context);
    this.read = read;
  }

  async paste(): Promise<void> {
    if (this.destroyed) return;

    try {
      const payload = await this.read(this.acceptedContentTypes, this.imageOptions);
      if (!this.destroyed && payload !== undefined) this.sendEvent('onPastePressed', payload);
    } catch (error) {
      if (!this.destroyed && this.context.moduleContext.isValid) {
        this.context.moduleContext.logger.warn(`Unable to paste from ClipboardPasteButton: ${String(error)}`);
      }
    }
  }

  options(): PasteButtonOptions {
    const options: PasteButtonOptions = {
      buttonType: this.cornerStyle === null || this.cornerStyle === 'capsule' || this.cornerStyle === 'dynamic'
        ? ButtonType.Capsule : ButtonType.Normal,
    };
    if (this.displayMode !== 'labelOnly') options.icon = PasteIconStyle.LINES;
    if (this.displayMode !== 'iconOnly') options.text = PasteDescription.PASTE;
    return options;
  }
}

@Component
struct ClipboardPasteButtonContent {
  @ObjectLink view: ClipboardPasteButtonView;

  build(): void {
    PasteButton(this.view.options())
      .width('100%')
      .height('100%')
      .backgroundColor(this.view.backgroundColor ?? $r('sys.color.ohos_id_color_emphasize'))
      .fontColor(this.view.foregroundColor ?? $r('sys.color.ohos_id_color_foreground_contrary'))
      .iconColor(this.view.foregroundColor ?? $r('sys.color.ohos_id_color_foreground_contrary'))
      .onClick((_event: ClickEvent, result: PasteButtonOnClickResult): void => {
        if (result === PasteButtonOnClickResult.SUCCESS) void this.view.paste();
      });
  }
}

@Builder
function buildClipboardPasteButton(context: ExpoViewContentContext): void {
  ClipboardPasteButtonContent({ view: context.nativeView as ClipboardPasteButtonView });
}

export function defineClipboardPasteButton(read: ReadPasteButton): ExpoViewDefinition<ClipboardPasteButtonView> {
  return new ExpoViewDefinition<ClipboardPasteButtonView>(
    'ClipboardPasteButton',
    (context: ExpoViewContext): ClipboardPasteButtonView => new ClipboardPasteButtonView(context, read),
    wrapBuilder(buildClipboardPasteButton),
  )
    .events(['onPastePressed'])
    .prop('backgroundColor', ExpoValueTypes.string().nullable(), (view, value) => { view.backgroundColor = value; }, null)
    .prop('foregroundColor', ExpoValueTypes.string().nullable(), (view, value) => { view.foregroundColor = value; }, null)
    .prop('cornerStyle', ExpoValueTypes.string().nullable(), (view, value) => { view.cornerStyle = value; }, null)
    .prop('displayMode', ExpoValueTypes.string().nullable(), (view, value) => { view.displayMode = value; }, null)
    .prop('acceptedContentTypes', ExpoValueTypes.array(CONTENT_TYPES), (view, value) => {
      view.acceptedContentTypes = value.length === 0 ? DEFAULT_CONTENT_TYPES : value;
    }, DEFAULT_CONTENT_TYPES)
    .prop('imageOptions', GET_IMAGE_OPTIONS.nullable(), (view, value) => {
      view.imageOptions = value ?? new GetImageOptions();
    }, null)
    .onDestroy((view) => { view.destroyed = true; });
}

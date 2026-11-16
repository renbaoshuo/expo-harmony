/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ImageCropper, ImageCropperConfig, ImageCropperController, ImageCropperLayerPainter, ImageCropperLayerPainterConfig } from '@candies/image_cropper';
import { common } from '@kit.AbilityKit';
import { ComponentContent } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { ExpoImagePickerError } from './ExpoImagePickerError';
import { ImagePickerOptions } from './ImagePickerOptions';

class OvalCropPainter extends ImageCropperLayerPainter {
  override paint(config: ImageCropperLayerPainterConfig): void {
    const canvas = config.canvas;
    const area = config.layoutRect;
    const crop = config.cropRect;
    if (crop.width <= 0 || crop.height <= 0) return;

    const centerX = crop.left + crop.width / 2;
    const centerY = crop.top + crop.height / 2;

    canvas.save();
    canvas.beginPath();
    canvas.rect(area.left, area.top, area.width, area.height);
    canvas.ellipse(centerX, centerY, crop.width / 2, crop.height / 2, 0, 0, 2 * Math.PI);
    canvas.fillStyle = config.maskColor;
    canvas.fill('evenodd');

    canvas.beginPath();
    canvas.ellipse(centerX, centerY, crop.width / 2, crop.height / 2, 0, 0, 2 * Math.PI);
    canvas.strokeStyle = config.lineColor;
    canvas.lineWidth = config.lineHeight;
    canvas.stroke();
    canvas.restore();

    this.paintCorners(config);
  }
}

interface CropDialogModel {
  source: image.ImageSource;
  config: ImageCropperConfig;
  save: () => boolean;
  cancel: () => void;
}

@Component
struct ImagePickerCropDialog {
  model?: CropDialogModel;
  @State source?: image.ImageSource = undefined;
  @State config?: ImageCropperConfig = undefined;
  @State private saving: boolean = false;

  aboutToDisappear(): void {
    this.model?.cancel();
  }

  build() {
    Column() {
      if (this.source !== undefined) {
        ImageCropper({ image: this.source, config: this.config })
          .width('100%')
          .layoutWeight(1)
      }
      Row({ space: 12 }) {
        Button($r('app.string.expo_image_picker_cancel'))
          .onClick((): void => this.model?.cancel())
        Button($r('app.string.expo_image_picker_crop'))
          .enabled(!this.saving)
          .onClick((): void => {
            this.saving = this.model?.save() ?? false;
          })
      }
      .padding(16)
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background'))
  }
}

@Builder
function buildCropDialog(model: CropDialogModel): void {
  ImagePickerCropDialog({ model, source: model.source, config: model.config })
}

export async function cropImage(
  ability: common.UIAbilityContext,
  uri: string,
  options: ImagePickerOptions,
  setCancel: (cancel: () => void) => void,
): Promise<image.PixelMap | null> {
  const ui = ability.windowStage.getMainWindowSync().getUIContext();
  const prompt = ui.getPromptAction();
  let file: fileIo.File | undefined;
  let source: image.ImageSource | undefined;
  let content: ComponentContent<CropDialogModel> | undefined;
  let opened = false;
  let canceled = false;
  let cancelResult: (() => void) | undefined;
  let saving: Promise<void> | undefined;

  const cancel = (): void => {
    canceled = true;
    cancelResult?.();
  };
  setCancel(cancel);

  try {
    file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    if (canceled) return null;

    const preview = image.createImageSource(file.fd);
    source = preview;

    const controller = new ImageCropperController();
    const config = new ImageCropperConfig({
      controller,
      cropAspectRatio: options.aspect === undefined ? null : options.aspect[0] / options.aspect[1],
      cropLayerPainter: options.shape === 'oval' ? new OvalCropPainter() : undefined,
    });

    const result = new Promise<image.PixelMap | null>((resolve, reject): void => {
      cancelResult = (): void => resolve(null);
      const model: CropDialogModel = {
        source: preview,
        config,
        cancel,
        save: (): boolean => {
          // The cropper decodes the preview and lays out its crop window asynchronously.
          if (canceled || controller.getActionDetails().cropRect === undefined) return false;

          saving ??= Promise.resolve().then(async (): Promise<void> => {
            const cropped = await controller.getCroppedImage();

            if (canceled) {
              await cropped?.release();
            } else if (cropped === null) {
              reject(new ExpoImagePickerError('ERR_IMAGE_PICKER_MEDIA_PROCESSING', 'Could not crop the selected image.'));
            } else {
              resolve(cropped);
            }
          }).catch((error: Error): void => reject(error));

          return true;
        },
      };
      content = new ComponentContent<CropDialogModel>(ui, wrapBuilder(buildCropDialog), model);
    });

    // If builder creation failed, observe the rejection before opening the dialog.
    if (content === undefined) return await result;

    await prompt.openCustomDialog(content, { autoCancel: false });
    opened = true;

    return await result;
  } finally {
    await saving;

    try {
      if (opened && content !== undefined) await prompt.closeCustomDialog(content);
    } catch (_) {}
    try {
      content?.dispose();
    } catch (_) {}
    try {
      await source?.release();
    } catch (_) {}
    try {
      if (file !== undefined) await fileIo.close(file);
    } catch (_) {}
  }
}

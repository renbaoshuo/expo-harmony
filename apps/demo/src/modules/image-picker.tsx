/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as ImagePicker from 'expo-image-picker';
import { useState } from 'react';
import { Image, Platform, StyleSheet } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const MEDIA_TYPES = [
  ['images', '图片'],
  ['videos', '视频'],
  ['livePhotos', '实况照片'],
] as const;

function useChoice<T>(options: readonly [T, ...T[]]) {
  const [index, setIndex] = useState(0);
  return {
    value: options[index] ?? options[0],
    next: () => setIndex(value => (value + 1) % options.length),
  };
}

function readNumber(text: string, label: string, min: number, max: number, integer = false) {
  const value = Number(text);
  if (!text.trim() || !Number.isFinite(value) || value < min || value > max || (integer && !Number.isInteger(value))) {
    throw new Error(`请输入有效的${label}。`);
  }
  return value;
}

function Toggle({ label, selected, onPress, testID }: {
  label: string;
  selected: boolean;
  onPress: () => void;
  testID?: string;
}) {
  return <ActionButton label={label} onPress={onPress} testID={testID} tone={selected ? 'primary' : 'secondary'} />;
}

function CameraPermissions() {
  const [get, setGet] = useState(false);
  const [request, setRequest] = useState(false);
  const [permission, requestPermission, getPermission] = ImagePicker.useCameraPermissions({ get, request });
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const run = (operation: () => Promise<ImagePicker.PermissionResponse>) =>
    void action.run(async () => json(await operation()));

  return (
    <Panel title="相机权限">
      <ActionRow>
        <ActionButton disabled={busy} label="查询权限" onPress={() => run(ImagePicker.getCameraPermissionsAsync)} testID="image-picker-permissions" />
        <ActionButton disabled={busy} label="申请权限" onPress={() => run(ImagePicker.requestCameraPermissionsAsync)} testID="image-picker-camera-permission" tone="secondary" />
      </ActionRow>
      <DataRow label="useCameraPermissions" value={permission?.status ?? '尚未查询'} />
      <ActionRow>
        <ActionButton disabled={busy} label="从 Hook 查询" onPress={() => run(getPermission)} tone="secondary" />
        <ActionButton disabled={busy} label="从 Hook 申请" onPress={() => run(requestPermission)} tone="secondary" />
        <Toggle label="自动查询" onPress={() => setGet(value => !value)} selected={get} />
        <Toggle label="自动申请" onPress={() => setRequest(value => !value)} selected={request} />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function LibraryPermissions({ writeOnly, onToggleWriteOnly }: {
  writeOnly: boolean;
  onToggleWriteOnly: () => void;
}) {
  const [get, setGet] = useState(false);
  const [request, setRequest] = useState(false);
  const [permission, requestPermission, getPermission] = ImagePicker.useMediaLibraryPermissions({
    get,
    request,
    writeOnly,
  });
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const run = (operation: () => Promise<ImagePicker.MediaLibraryPermissionResponse>) =>
    void action.run(async () => json(await operation()));

  return (
    <Panel title="图库权限">
      <ActionRow>
        <Toggle label="仅写入" onPress={onToggleWriteOnly} selected={writeOnly} />
        <ActionButton disabled={busy} label="查询权限" onPress={() => run(() => ImagePicker.getMediaLibraryPermissionsAsync(writeOnly))} />
        <ActionButton disabled={busy} label="申请权限" onPress={() => run(() => ImagePicker.requestMediaLibraryPermissionsAsync(writeOnly))} testID="image-picker-library-permission" tone="secondary" />
      </ActionRow>
      <DataRow label="useMediaLibraryPermissions" value={permission?.status ?? '尚未查询'} />
      <ActionRow>
        <ActionButton disabled={busy} label="从 Hook 查询" onPress={() => run(getPermission)} tone="secondary" />
        <ActionButton disabled={busy} label="从 Hook 申请" onPress={() => run(requestPermission)} tone="secondary" />
        <Toggle label="自动查询" onPress={() => setGet(value => !value)} selected={get} />
        <Toggle label="自动申请" onPress={() => setRequest(value => !value)} selected={request} />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function AssetPreview({ asset }: { asset: ImagePicker.ImagePickerAsset }) {
  const image = asset.type === 'image' || asset.type === 'livePhoto';
  const web = Platform.OS === 'web';
  const mimeType = web ? asset.mimeType : 'image/jpeg';
  const uri = asset.base64 && mimeType ? `data:${mimeType};base64,${asset.base64}` : asset.uri;
  const duration = asset.duration == null ? null : (web ? Math.round(asset.duration * 1000) : asset.duration);
  const rotation = 'rotation' in asset ? asset.rotation : undefined;

  return (
    <>
      {image ? <Image accessibilityLabel="所选图片" resizeMode="contain" source={{ uri }} style={styles.preview} /> : null}
      <DataRow label="URI" value={asset.uri} />
      <DataRow label="文件名" value={asset.fileName ?? '无'} />
      <DataRow label="媒体类型" value={asset.type ?? '未知'} />
      <DataRow label="MIME 类型" value={asset.mimeType ?? '未知'} />
      <DataRow label="尺寸" value={`${asset.width} × ${asset.height}`} />
      {asset.fileSize != null ? <DataRow label="文件大小" value={`${asset.fileSize} B`} /> : null}
      <DataRow label="资源 ID" value={asset.assetId ?? '无'} />
      {duration != null ? <DataRow label="视频时长" value={`${duration} ms`} /> : null}
      {typeof rotation === 'number' ? <DataRow label="旋转角度" value={`${rotation}°`} /> : null}
      {asset.base64 != null ? <DataRow label="Base64 字符数" value={asset.base64.length} /> : null}
      {asset.exif != null ? <DataRow label="EXIF" value={json(asset.exif)} /> : null}
      {asset.pairedVideoAsset ? <DataRow label="配对视频" value={json(asset.pairedVideoAsset)} /> : null}
      {asset.file ? <DataRow label="浏览器文件" value={asset.file.name} /> : null}
    </>
  );
}

export function ImagePickerDemo() {
  const [quality, setQuality] = useState('1');
  const [limit, setLimit] = useState('3');
  const [duration, setDuration] = useState('0');
  const [cropWidth, setCropWidth] = useState('');
  const [cropHeight, setCropHeight] = useState('');
  const [base64, setBase64] = useState(false);
  const [exif, setExif] = useState(false);
  const [multiple, setMultiple] = useState(false);
  const [editing, setEditing] = useState(false);
  const [legacy, setLegacy] = useState(false);
  const [ordered, setOrdered] = useState(false);
  const [download, setDownload] = useState(false);
  const [writeOnly, setWriteOnly] = useState(false);
  const [mediaTypes, setMediaTypes] = useState<ImagePicker.MediaType[]>(['images']);
  const [assets, setAssets] = useState<ImagePicker.ImagePickerAsset[]>([]);
  const camera = useChoice([ImagePicker.CameraType.back, ImagePicker.CameraType.front]);
  const tab = useChoice(['photos', 'albums'] as const);
  const shape = useChoice(['rectangle', 'oval'] as const);
  const presentation = useChoice([
    ImagePicker.UIImagePickerPresentationStyle.AUTOMATIC,
    ImagePicker.UIImagePickerPresentationStyle.FULL_SCREEN,
    ImagePicker.UIImagePickerPresentationStyle.PAGE_SHEET,
    ImagePicker.UIImagePickerPresentationStyle.FORM_SHEET,
    ImagePicker.UIImagePickerPresentationStyle.CURRENT_CONTEXT,
    ImagePicker.UIImagePickerPresentationStyle.OVER_FULL_SCREEN,
    ImagePicker.UIImagePickerPresentationStyle.OVER_CURRENT_CONTEXT,
    ImagePicker.UIImagePickerPresentationStyle.POPOVER,
  ]);
  const representation = useChoice([
    ImagePicker.UIImagePickerPreferredAssetRepresentationMode.Automatic,
    ImagePicker.UIImagePickerPreferredAssetRepresentationMode.Compatible,
    ImagePicker.UIImagePickerPreferredAssetRepresentationMode.Current,
  ]);
  const exportPreset = useChoice([
    ImagePicker.VideoExportPreset.Passthrough,
    ImagePicker.VideoExportPreset.LowQuality,
    ImagePicker.VideoExportPreset.MediumQuality,
    ImagePicker.VideoExportPreset.HighestQuality,
    ImagePicker.VideoExportPreset.H264_640x480,
    ImagePicker.VideoExportPreset.H264_960x540,
    ImagePicker.VideoExportPreset.H264_1280x720,
    ImagePicker.VideoExportPreset.H264_1920x1080,
    ImagePicker.VideoExportPreset.H264_3840x2160,
    ImagePicker.VideoExportPreset.HEVC_1920x1080,
    ImagePicker.VideoExportPreset.HEVC_3840x2160,
  ]);
  const videoQuality = useChoice([
    ImagePicker.UIImagePickerControllerQualityType.High,
    ImagePicker.UIImagePickerControllerQualityType.Medium,
    ImagePicker.UIImagePickerControllerQualityType.Low,
    ImagePicker.UIImagePickerControllerQualityType.VGA640x480,
    ImagePicker.UIImagePickerControllerQualityType.IFrame1280x720,
    ImagePicker.UIImagePickerControllerQualityType.IFrame960x540,
  ]);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const android = Platform.OS === 'android';
  const ios = Platform.OS === 'ios';
  const web = Platform.OS === 'web';
  const canEdit = !web && !multiple && mediaTypes.includes('images');
  const canPickLive = ios || String(Platform.OS) === 'harmony';

  function pictureOptions(): ImagePicker.ImagePickerOptions {
    return web ? { base64 } : { quality: readNumber(quality, '图片质量', 0, 1), base64, exif };
  }

  function toggleMediaType(type: ImagePicker.MediaType) {
    setMediaTypes(value => value.includes(type) ? value.filter(item => item !== type) : [...value, type]);
  }

  function show(result: ImagePicker.ImagePickerResult) {
    setAssets(result.assets ?? []);
    return result.canceled ? '已取消' : `返回 ${result.assets.length} 个文件`;
  }

  async function launchLibrary() {
    const allowsEditing = canEdit && editing;
    const options: ImagePicker.ImagePickerOptions = {
      ...pictureOptions(),
      mediaTypes,
      allowsEditing,
      allowsMultipleSelection: multiple,
      selectionLimit: multiple && !web ? readNumber(limit, '多选上限', 0, Number.MAX_SAFE_INTEGER, true) : undefined,
    };

    if (android) {
      options.defaultTab = tab.value;
      options.legacy = legacy;
      if (allowsEditing) {
        options.shape = shape.value;
        if (cropWidth.trim() || cropHeight.trim()) {
          options.aspect = [
            readNumber(cropWidth, '裁剪比例的宽', 1, Number.MAX_SAFE_INTEGER, true),
            readNumber(cropHeight, '裁剪比例的高', 1, Number.MAX_SAFE_INTEGER, true),
          ];
        }
      }
    }

    if (ios) {
      options.orderedSelection = multiple && ordered;
      options.presentationStyle = presentation.value;
      options.preferredAssetRepresentationMode = representation.value;
      options.videoExportPreset = exportPreset.value;
      options.shouldDownloadFromNetwork = download;
    }

    return show(await ImagePicker.launchImageLibraryAsync(options));
  }

  async function launchCamera(type: 'images' | 'videos') {
    const options: ImagePicker.ImagePickerOptions = { mediaTypes: [type], cameraType: camera.value };
    if (type === 'images') Object.assign(options, pictureOptions());
    if (type === 'videos' && !web) options.videoMaxDuration = readNumber(duration, '录像时长', 0, 2147483647);
    if (ios) {
      options.presentationStyle = presentation.value;
      if (type === 'videos') options.videoQuality = videoQuality.value;
    }

    return show(await ImagePicker.launchCameraAsync(options));
  }

  return (
    <>
      <Panel title="图片输出">
        {!web ? <Field keyboardType="decimal-pad" label="图片质量（0 到 1）" onChangeText={setQuality} testID="image-picker-quality" value={quality} /> : null}
        <ActionRow>
          <Toggle label="返回 Base64" onPress={() => setBase64(value => !value)} selected={base64} testID="image-picker-base64" />
          {!web ? <Toggle label="返回 EXIF" onPress={() => setExif(value => !value)} selected={exif} testID="image-picker-exif" /> : null}
          {ios
            ? (
                <ActionButton label={`选择器样式 ${presentation.value}`} onPress={presentation.next} tone="secondary" />
              )
            : null}
        </ActionRow>
      </Panel>

      <Panel title="图库选择">
        <ActionRow>
          {MEDIA_TYPES.filter(([type]) => type !== 'livePhotos' || canPickLive).map(([type, label]) => (
            <Toggle
              key={type}
              label={label}
              onPress={() => toggleMediaType(type)}
              selected={mediaTypes.includes(type)}
            />
          ))}
          <Toggle label="允许多选" onPress={() => setMultiple(value => !value)} selected={multiple} />
          {canEdit ? <Toggle label="允许编辑" onPress={() => setEditing(value => !value)} selected={editing} /> : null}
        </ActionRow>
        {multiple && !web
          ? (
              <Field keyboardType="number-pad" label="多选上限（0 使用系统上限）" onChangeText={setLimit} testID="image-picker-limit" value={limit} />
            )
          : null}
        {android && canEdit && editing
          ? (
              <>
                <Field keyboardType="number-pad" label="裁剪比例的宽" onChangeText={setCropWidth} value={cropWidth} />
                <Field keyboardType="number-pad" label="裁剪比例的高" onChangeText={setCropHeight} value={cropHeight} />
                <ActionButton label={shape.value === 'rectangle' ? '矩形裁剪' : '椭圆裁剪'} onPress={shape.next} tone="secondary" />
              </>
            )
          : null}
        {android
          ? (
              <ActionRow>
                <ActionButton label={tab.value === 'photos' ? '默认打开照片' : '默认打开相册'} onPress={tab.next} tone="secondary" />
                <Toggle label="旧版选择器" onPress={() => setLegacy(value => !value)} selected={legacy} />
              </ActionRow>
            )
          : null}
        {ios
          ? (
              <ActionRow>
                {multiple ? <Toggle label="按选择顺序返回" onPress={() => setOrdered(value => !value)} selected={ordered} /> : null}
                <Toggle label="允许从 iCloud 下载" onPress={() => setDownload(value => !value)} selected={download} />
                <ActionButton label={`资源格式 ${representation.value}`} onPress={representation.next} tone="secondary" />
                <ActionButton label={`视频导出预设 ${ImagePicker.VideoExportPreset[exportPreset.value]}`} onPress={exportPreset.next} tone="secondary" />
              </ActionRow>
            )
          : null}
        <ActionButton disabled={busy || mediaTypes.length === 0} label="打开图库" onPress={() => void action.run(launchLibrary)} testID="image-picker-image" />
      </Panel>

      <Panel title="系统相机">
        <ActionButton label={camera.value === 'back' ? '后置相机' : '前置相机'} onPress={camera.next} tone="secondary" />
        {!web ? <Field keyboardType="decimal-pad" label="录像时限（秒，0 表示不限）" onChangeText={setDuration} value={duration} /> : null}
        {ios
          ? (
              <ActionButton label={`录像质量 ${ImagePicker.UIImagePickerControllerQualityType[videoQuality.value]}`} onPress={videoQuality.next} tone="secondary" />
            )
          : null}
        <ActionRow>
          <ActionButton disabled={busy} label="拍照" onPress={() => void action.run(() => launchCamera('images'))} testID="image-picker-camera" />
          <ActionButton disabled={busy} label="录像" onPress={() => void action.run(() => launchCamera('videos'))} testID="image-picker-record" tone="secondary" />
        </ActionRow>
      </Panel>

      <Panel title="选择结果">
        <ActionButton
          disabled={busy}
          label="读取待恢复结果"
          onPress={() => void action.run(async () => {
            const pending = await ImagePicker.getPendingResultAsync();
            if (pending && 'canceled' in pending) return show(pending);
            return pending ? json(pending) : '没有待恢复结果';
          })}
          tone="secondary"
        />
        <ResultPanel state={action.state} />
      </Panel>
      {assets.map((asset, index) => (
        <Panel key={`${asset.uri}-${index}`} title={asset.fileName ?? `文件 ${index + 1}`}>
          <AssetPreview asset={asset} />
        </Panel>
      ))}

      <CameraPermissions />
      <LibraryPermissions
        key={String(writeOnly)}
        onToggleWriteOnly={() => setWriteOnly(value => !value)}
        writeOnly={writeOnly}
      />
    </>
  );
}

const styles = StyleSheet.create({
  preview: { width: '100%', height: 200, borderRadius: 10 },
});

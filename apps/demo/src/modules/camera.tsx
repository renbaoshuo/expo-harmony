/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Asset } from 'expo-asset';
import { Camera, CameraView, useCameraPermissions, useMicrophonePermissions } from 'expo-camera';
import type {
  BarcodeType,
  CameraCapturedPicture,
  CameraPictureOptions,
  CameraRecordingOptions,
  CameraViewProps,
  PermissionResponse,
  PhotoResult,
  PictureRef,
  SavePictureOptions,
  ScanningOptions,
  ScanningResult,
} from 'expo-camera';
import { useEffect, useRef, useState } from 'react';
import { Image, Platform, StyleSheet, View } from 'react-native';

import barcodeSample from '../../assets/image/barcode.png';
import { json } from '../format';
import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

type ViewSettings = Pick<CameraViewProps,
  'flash' | 'enableTorch' | 'zoom' | 'mute' | 'autofocus' | 'pictureSize' | 'ratio'
  | 'videoQuality' | 'videoBitrate' | 'videoStabilizationMode' | 'mirror'
  | 'animateShutter' | 'responsiveOrientationWhenOrientationLocked' | 'selectedLens' | 'poster'>;

const isHarmony = String(Platform.OS) === 'harmony';
const supportedBarcodeTypes: BarcodeType[] = [
  'qr', 'aztec', 'codabar', 'code39', 'code93', 'code128', 'datamatrix', 'ean8', 'ean13',
  'itf14', 'pdf417', 'upc_a', 'upc_e',
];
const viewSettings: ViewSettings = {
  flash: 'off',
  enableTorch: false,
  zoom: 0,
  mute: true,
  autofocus: 'off',
  pictureSize: '',
  ratio: '4:3',
  videoQuality: '1080p',
  videoBitrate: 8_000_000,
  videoStabilizationMode: 'auto',
  mirror: false,
  animateShutter: true,
  responsiveOrientationWhenOrientationLocked: false,
  selectedLens: '',
};

const pictureOptions: CameraPictureOptions = {
  quality: 0.9,
  base64: false,
  exif: false,
  additionalExif: {},
  skipProcessing: false,
  imageType: 'jpg',
  mirror: false,
  maxDownsampling: 1,
  shutterSound: true,
  ...(Platform.OS === 'web' ? { scale: 1, isImageMirror: false } : {}),
};

function photoResult(photo: CameraCapturedPicture | PhotoResult) {
  const { base64, ...fields } = photo;
  return json({ ...fields, base64Length: base64?.length });
}

function parseOptions<T>(text: string): T {
  const parsed: unknown = JSON.parse(text);
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('参数需要使用 JSON 对象。');
  }
  return parsed as T;
}

export function CameraDemo() {
  const camera = useRef<CameraView>(null);
  const pictureRef = useRef<PictureRef | null>(null);
  const saving = useRef(false);
  const mounted = useRef(false);
  const [cameraAllowed, setCameraAllowed] = useState(false);
  const [facing, setFacing] = useState<'back' | 'front'>('back');
  const [mode, setMode] = useState<'picture' | 'video'>('picture');
  const [active, setActive] = useState(true);
  const [ready, setReady] = useState(false);
  const [paused, setPaused] = useState(false);
  const [lenses, setLenses] = useState<string[]>([]);
  const [orientation, setOrientation] = useState('');
  const [config, setConfig] = useState(viewSettings);
  const [viewText, setViewText] = useState(() => json({
    ...viewSettings,
    ...(Platform.OS === 'web' ? { poster: '' } : {}),
  }));
  const [pictureText, setPictureText] = useState(() => json(pictureOptions));
  const [saveText, setSaveText] = useState(() => json({ quality: 0.9, base64: false, metadata: {} }));
  const [recordText, setRecordText] = useState(() => json({
    maxDuration: 10,
    maxFileSize: 10_000_000,
    mirror: false,
    ...(isHarmony || Platform.OS === 'ios' ? { codec: 'avc1' } : {}),
  }));
  const [photoUri, setPhotoUri] = useState('');
  const [hasPictureRef, setHasPictureRef] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [barcodeTypes, setBarcodeTypes] = useState<BarcodeType[]>(['qr']);
  const [liveScan, setLiveScan] = useState<ScanningResult | null>(null);
  const controls = useAsyncResult();
  const photo = useAsyncResult();
  const recording = useAsyncResult();
  const recordingControls = useAsyncResult();
  const capabilities = useAsyncResult();
  const isRecording = recording.state.phase === 'running';
  const busy = isRecording || photo.state.phase === 'running' || controls.state.phase === 'running';

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      if (!saving.current) pictureRef.current?.release();
      pictureRef.current = null;
    };
  }, []);

  function getCamera() {
    if (!camera.current) throw new Error('相机尚未打开。');
    return camera.current;
  }

  function updatePreview() {
    setReady(false);
    setPaused(false);
    setLenses([]);
    setOrientation('');
  }

  function capture(kind: 'file' | 'callback' | 'reference') {
    return photo.run(async () => {
      const settings = parseOptions<CameraPictureOptions>(pictureText);
      const device = getCamera();

      if (kind === 'reference') {
        const image = await device.takePictureAsync({
          ...settings, pictureRef: true, fastMode: false, onPictureSaved: undefined,
        });
        if (!image) throw new Error('相机未返回图片引用。');
        const result = json({ width: image.width, height: image.height, nativeRefType: image.nativeRefType });
        if (!mounted.current) {
          image.release();
          return result;
        }
        pictureRef.current?.release();
        pictureRef.current = image;
        setHasPictureRef(true);
        return result;
      }

      const image = await device.takePictureAsync({
        ...settings,
        pictureRef: false,
        fastMode: kind === 'callback',
        onPictureSaved: kind === 'callback'
          ? (image) => {
              if (!mounted.current) return;
              setPhotoUri(image.uri);
              void photo.run(() => photoResult(image));
            }
          : undefined,
      });
      if (image) {
        setPhotoUri(image.uri);
        return photoResult(image);
      }
      return '等待 onPictureSaved';
    });
  }

  function savePicture() {
    return photo.run(async () => {
      const image = pictureRef.current;
      if (!image) throw new Error('请先拍摄图片引用。');
      saving.current = true;
      try {
        const saved = await image.savePictureAsync(parseOptions<SavePictureOptions>(saveText));
        if (mounted.current) setPhotoUri(saved.uri);
        return photoResult(saved);
      } finally {
        saving.current = false;
        if (!mounted.current) image.release();
      }
    });
  }

  return (
    <>
      <CameraPermissions onCameraAccess={setCameraAllowed} />

      {cameraAllowed
        ? (
            <>
              <Panel title="相机预览">
                <View style={styles.preview}>
                  {active || isHarmony || Platform.OS === 'ios'
                    ? (
                        <CameraView
                          {...config}
                          active={active}
                          barcodeScannerSettings={{ barcodeTypes }}
                          facing={facing}
                          mode={mode}
                          onAvailableLensesChanged={({ lenses }) => setLenses(lenses)}
                          onBarcodeScanned={scanning ? setLiveScan : undefined}
                          onCameraReady={() => setReady(true)}
                          onMountError={({ message }) => {
                            setReady(false);
                            void controls.run(() => {
                              throw new Error(message);
                            });
                          }}
                          onResponsiveOrientationChanged={({ orientation }) => setOrientation(orientation)}
                          pictureSize={config.pictureSize || undefined}
                          ref={camera}
                          selectedLens={config.selectedLens || undefined}
                          style={StyleSheet.absoluteFill}
                        />
                      )
                    : null}
                </View>
                <DataRow label="onCameraReady" value={active ? (ready ? '就绪' : '等待预览') : '已停用'} />
                {orientation ? <DataRow label="onResponsiveOrientationChanged" value={orientation} /> : null}
                {lenses.length ? <DataRow label="onAvailableLensesChanged" value={lenses.join(', ')} /> : null}
                <ActionRow>
                  <ActionButton
                    disabled={busy}
                    label={facing === 'back' ? '切换前摄' : '切换后摄'}
                    onPress={() => {
                      updatePreview();
                      setFacing(value => value === 'back' ? 'front' : 'back');
                    }}
                    tone="secondary"
                  />
                  <ActionButton
                    disabled={busy}
                    label={mode === 'picture' ? '切换录像模式' : '切换拍照模式'}
                    onPress={() => {
                      updatePreview();
                      setMode(value => value === 'picture' ? 'video' : 'picture');
                    }}
                    tone="secondary"
                  />
                  <ActionButton
                    disabled={busy}
                    label={active ? '停用相机' : '启用相机'}
                    onPress={() => {
                      updatePreview();
                      setActive(value => !value);
                    }}
                    tone="secondary"
                  />
                  <ActionButton
                    disabled={busy || !ready || !active || paused}
                    label="暂停预览"
                    onPress={() => void controls.run(async () => {
                      await getCamera().pausePreview();
                      setPaused(true);
                      return '预览已暂停';
                    })}
                    tone="secondary"
                  />
                  <ActionButton
                    disabled={busy || !active || !paused}
                    label="恢复预览"
                    onPress={() => void controls.run(async () => {
                      await getCamera().resumePreview();
                      setPaused(false);
                      return '预览已恢复';
                    })}
                    tone="secondary"
                  />
                </ActionRow>
                <Field label="CameraView 属性（JSON）" multiline value={viewText} onChangeText={setViewText} />
                <ActionButton
                  disabled={busy}
                  label="应用预览设置"
                  onPress={() => void controls.run(() => {
                    setConfig(parseOptions<ViewSettings>(viewText));
                    return '已更新预览设置';
                  })}
                />
                <ResultPanel state={controls.state} />
              </Panel>

              <Panel title="预览扫码">
                <ActionRow>
                  {supportedBarcodeTypes.map(type => (
                    <ActionButton key={type} label={type} tone={barcodeTypes.includes(type) ? 'primary' : 'secondary'} onPress={() => setBarcodeTypes(types => types.includes(type) ? types.filter(value => value !== type) : [...types, type])} />
                  ))}
                  <ActionButton label={scanning ? '停止识别' : '开始识别'} onPress={() => setScanning(value => !value)} testID="camera-toggle-barcode" />
                </ActionRow>
                {liveScan ? <DataRow label="onBarcodeScanned" value={json(liveScan)} /> : null}
              </Panel>

              <Panel title="拍照">
                <Field label="takePictureAsync 参数（JSON）" multiline value={pictureText} onChangeText={setPictureText} />
                <ActionRow>
                  <ActionButton disabled={!ready || !active || paused || busy || mode !== 'picture'} label="拍照" onPress={() => void capture('file')} testID="camera-take-photo" />
                  {Platform.OS !== 'web' ? <ActionButton disabled={!ready || !active || paused || busy || mode !== 'picture'} label="通过 onPictureSaved 接收照片" onPress={() => void capture('callback')} tone="secondary" /> : null}
                  {isHarmony || Platform.OS === 'ios' ? <ActionButton disabled={!ready || !active || paused || busy || mode !== 'picture'} label="拍摄图片引用" onPress={() => void capture('reference')} testID="camera-take-ref" tone="secondary" /> : null}
                </ActionRow>
                {isHarmony || Platform.OS === 'ios'
                  ? (
                      <>
                        <Field label="savePictureAsync 参数（JSON）" multiline value={saveText} onChangeText={setSaveText} />
                        <ActionButton disabled={busy || !hasPictureRef} label="保存图片引用" onPress={() => void savePicture()} tone="secondary" />
                      </>
                    )
                  : null}
                {photoUri ? <Image accessibilityLabel="拍摄结果" source={{ uri: photoUri }} resizeMode="contain" style={styles.preview} /> : null}
                <ResultPanel state={photo.state} />
              </Panel>

              {Platform.OS !== 'web'
                ? (
                    <Panel title="录像">
                      <Field label="recordAsync 参数（JSON）" multiline value={recordText} onChangeText={setRecordText} />
                      <ActionRow>
                        <ActionButton disabled={!ready || !active || paused || busy || mode !== 'video'} label="开始录像" onPress={() => void recording.run(async () => json(await getCamera().recordAsync(parseOptions<CameraRecordingOptions>(recordText))))} />
                        <ActionButton
                          disabled={
                            !isRecording || !camera.current?.getSupportedFeatures().toggleRecordingAsyncAvailable
                          }
                          label="暂停或继续录像"
                          onPress={() => void recordingControls.run(async () => {
                            await getCamera().toggleRecordingAsync();
                            return '已切换录制状态';
                          })}
                          tone="secondary"
                        />
                        <ActionButton disabled={!isRecording} label="结束录像" onPress={() => camera.current?.stopRecording()} tone="secondary" />
                      </ActionRow>
                      <ResultPanel state={recording.state} />
                      <ResultPanel state={recordingControls.state} />
                    </Panel>
                  )
                : null}
            </>
          )
        : null}

      <Panel title="相机设备">
        <ActionRow>
          {isHarmony || Platform.OS === 'web' ? <ActionButton label="查询摄像头可用性" onPress={() => void capabilities.run(async () => json(await CameraView.isAvailableAsync()))} tone="secondary" /> : null}
          {isHarmony || Platform.OS === 'ios' ? <ActionButton label="查询录像编码" onPress={() => void capabilities.run(async () => json(await CameraView.getAvailableVideoCodecsAsync()))} tone="secondary" /> : null}
          <ActionButton disabled={!ready} label="查询拍照分辨率" onPress={() => void capabilities.run(async () => json(await getCamera().getAvailablePictureSizesAsync()))} tone="secondary" />
          {isHarmony || Platform.OS === 'ios' ? <ActionButton disabled={!ready} label="查询镜头" onPress={() => void capabilities.run(async () => json(await getCamera().getAvailableLensesAsync()))} tone="secondary" /> : null}
          <ActionButton disabled={!ready} label="查询扫码和录像能力" onPress={() => void capabilities.run(() => json(getCamera().getSupportedFeatures()))} tone="secondary" />
        </ActionRow>
        <ResultPanel state={capabilities.state} />
      </Panel>

      <BarcodeScanner />
    </>
  );
}

function CameraPermissions({ onCameraAccess }: { onCameraAccess: (allowed: boolean) => void }) {
  const [target, setTarget] = useState<'camera' | 'microphone'>('camera');
  const [behavior, setBehavior] = useState<'get' | 'request' | 'manual'>('get');
  const isCamera = target === 'camera';
  const [camera, requestCamera, getCamera] = useCameraPermissions({
    get: isCamera && behavior === 'get',
    request: isCamera && behavior === 'request',
  });
  const [microphone, requestMicrophone, getMicrophone] = useMicrophonePermissions({
    get: !isCamera && behavior === 'get',
    request: !isCamera && behavior === 'request',
  });
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const run = (operation: () => Promise<PermissionResponse>) => void action.run(async () => json(await operation()));

  useEffect(() => {
    onCameraAccess(camera?.granted === true);
  }, [camera?.granted, onCameraAccess]);

  function select(value: typeof target) {
    if (value === target) return;
    setBehavior('get');
    action.clear();
    setTarget(value);
  }

  return (
    <Panel title="权限">
      <ActionRow>
        <ActionButton disabled={busy} label="相机" onPress={() => select('camera')} tone={isCamera ? 'primary' : 'secondary'} />
        <ActionButton disabled={busy} label="麦克风" onPress={() => select('microphone')} tone={isCamera ? 'secondary' : 'primary'} />
      </ActionRow>
      <DataRow label={isCamera ? 'useCameraPermissions' : 'useMicrophonePermissions'} value={(isCamera ? camera : microphone)?.status ?? '尚未查询'} />
      <ActionRow>
        <ActionButton disabled={busy} label="手动" onPress={() => setBehavior('manual')} tone={behavior === 'manual' ? 'primary' : 'secondary'} />
        <ActionButton disabled={busy} label="自动查询" onPress={() => setBehavior('get')} tone={behavior === 'get' ? 'primary' : 'secondary'} />
        <ActionButton disabled={busy} label="自动申请" onPress={() => setBehavior('request')} tone={behavior === 'request' ? 'primary' : 'secondary'} />
      </ActionRow>
      <ActionRow>
        <ActionButton disabled={busy} label="从 Hook 查询" onPress={() => run(isCamera ? getCamera : getMicrophone)} tone="secondary" />
        <ActionButton disabled={busy} label="从 Hook 申请" onPress={() => run(isCamera ? requestCamera : requestMicrophone)} testID={isCamera ? 'camera-request-permission' : undefined} tone="secondary" />
        <ActionButton disabled={busy} label="直接查询" onPress={() => run(isCamera ? Camera.getCameraPermissionsAsync : Camera.getMicrophonePermissionsAsync)} tone="secondary" />
        <ActionButton
          disabled={busy}
          label="直接申请"
          onPress={() => run(async () => {
            const result = isCamera
              ? await Camera.requestCameraPermissionsAsync()
              : await Camera.requestMicrophonePermissionsAsync();
            if (isCamera) onCameraAccess(result.granted);
            return result;
          })}
          tone="secondary"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function BarcodeScanner() {
  const [source, setSource] = useState('');
  const [scan, setScan] = useState<ScanningResult | null>(null);
  const [options, setOptions] = useState(() => json({
    barcodeTypes: ['qr'],
    ...(Platform.OS === 'ios'
      ? {
          isPinchToZoomEnabled: true,
          isGuidanceEnabled: true,
          isHighlightingEnabled: false,
        }
      : {}),
  }));
  const system = useAsyncResult();
  const image = useAsyncResult();
  const available = Boolean(CameraView.isModernBarcodeScannerAvailable);
  const busy = system.state.phase === 'running';

  useEffect(() => {
    if (!available) return;
    const subscription = CameraView.onModernBarcodeScanned(setScan);
    return () => subscription.remove();
  }, [available]);

  return (
    <Panel title="系统扫码与图片识码">
      <DataRow label="系统扫码可用" value={String(available)} />
      <Field label="扫码参数（JSON）" multiline value={options} onChangeText={setOptions} />
      <ActionRow>
        <ActionButton
          disabled={!available || busy}
          label="打开系统扫码"
          onPress={() => void system.run(async () => {
            await CameraView.launchScanner(parseOptions<ScanningOptions>(options));
            return '扫码结束';
          })}
        />
        {Platform.OS === 'ios' ? <ActionButton disabled={!available || !busy} label="关闭系统扫码" onPress={() => void CameraView.dismissScanner()} tone="secondary" /> : null}
      </ActionRow>
      {scan ? <DataRow label="onModernBarcodeScanned" value={json(scan)} /> : null}
      <ResultPanel state={system.state} />
      <Field label="图片 URI" value={source} onChangeText={setSource} placeholder="file:///… 或 https://…" />
      <ActionRow>
        <ActionButton
          disabled={image.state.phase === 'running'}
          label="识别内置二维码"
          onPress={() => void image.run(async () => {
            const asset = await Asset.fromModule(barcodeSample).downloadAsync();
            const { barcodeTypes } = parseOptions<ScanningOptions>(options);
            return json(await Camera.scanFromURLAsync(asset.localUri ?? asset.uri, barcodeTypes));
          })}
        />
        <ActionButton disabled={!source.trim() || image.state.phase === 'running'} label="识别指定图片" onPress={() => void image.run(async () => json(await Camera.scanFromURLAsync(source.trim(), parseOptions<ScanningOptions>(options).barcodeTypes)))} tone="secondary" />
      </ActionRow>
      <ResultPanel state={image.state} />
    </Panel>
  );
}

const styles = StyleSheet.create({
  preview: { backgroundColor: palette.canvas, borderRadius: 12, height: 280, overflow: 'hidden' },
});

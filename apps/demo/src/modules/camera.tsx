import { CameraView, useCameraPermissions } from 'expo-camera';
import type { CameraCapturedPicture, CameraType } from 'expo-camera';
import { useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Note, Panel, ResultPanel, Tag, useAsyncResult } from '../ui';
import { json } from '../format';

function photoSummary(photo: CameraCapturedPicture): string {
  return json({
    exifKeys: photo.exif ? Object.keys(photo.exif).sort() : [],
    format: photo.format,
    height: photo.height,
    uri: photo.uri,
    width: photo.width,
  });
}

export function CameraDemo() {
  const camera = useRef<CameraView>(null);
  const [permission, requestPermission] = useCameraPermissions();
  const [facing, setFacing] = useState<CameraType>('back');
  const [ready, setReady] = useState(false);
  const [active, setActive] = useState(true);
  const action = useAsyncResult();

  if (!permission) {
    return (
      <Panel eyebrow="相机权限" title="读取原生权限状态">
        <Tag>加载中</Tag>
      </Panel>
    );
  }

  if (!permission.granted) {
    return (
      <Panel eyebrow="相机权限" title="允许使用虚拟相机">
        <DataRow label="状态" value={permission.status} />
        <DataRow label="可再次询问" value={String(permission.canAskAgain)} />
        <ActionButton
          disabled={!permission.canAskAgain}
          label="申请相机权限"
          onPress={() => void requestPermission()}
          testID="camera-request-permission"
        />
      </Panel>
    );
  }

  const takePhoto = () => action.run(async () => {
    const photo = await camera.current?.takePictureAsync({ exif: true, quality: 0.82 });
    if (!photo) throw new Error('相机未返回拍摄结果。');

    return photoSummary(photo);
  });

  const takeRef = () => action.run(async () => {
    const picture = await camera.current?.takePictureAsync({ pictureRef: true });
    if (!picture) throw new Error('相机未返回图片引用。');

    const saved = await picture.savePictureAsync({ quality: 0.73 });

    return json({
      height: picture.height,
      saved,
      width: picture.width,
    });
  });

  const inspect = () => action.run(async () => {
    const [available, codecs, lenses, sizes] = await Promise.all([
      CameraView.isAvailableAsync(),
      CameraView.getAvailableVideoCodecsAsync(),
      camera.current?.getAvailableLensesAsync() ?? Promise.resolve([]),
      camera.current?.getAvailablePictureSizesAsync() ?? Promise.resolve([]),
    ]);

    return json({ available, codecs, lenses, sizes: sizes.slice(0, 12) });
  });

  return (
    <>
      <Panel eyebrow="CAMERAKIT 画面" title="Harmony 实时预览">
        <View style={styles.cameraFrame}>
          {active
            ? (
                <CameraView
                  active
                  animateShutter
                  facing={facing}
                  onCameraReady={() => setReady(true)}
                  onMountError={(error) => {
                    setReady(false);
                    void action.run(() => {
                      throw new Error(error.message);
                    });
                  }}
                  ref={camera}
                  responsiveOrientationWhenOrientationLocked
                  style={styles.cameraPreview}
                />
              )
            : <Text style={styles.cameraInactive}>相机已停用</Text>}
        </View>
        <DataRow label="会话状态" value={<Tag tone={ready ? 'success' : 'signal'}>{ready ? '就绪' : '启动中'}</Tag>} />
        <DataRow label="朝向" value={facing} />
        <ActionRow>
          <ActionButton
            label={facing === 'back' ? '切换前摄像头' : '切换后摄像头'}
            onPress={() => {
              setReady(false);
              setFacing(value => value === 'back' ? 'front' : 'back');
            }}
            tone="secondary"
          />
          <ActionButton
            label={active ? '停用相机' : '启用相机'}
            onPress={() => {
              setReady(false);
              setActive(value => !value);
            }}
            tone="secondary"
          />
        </ActionRow>
      </Panel>

      <Panel eyebrow="拍摄管线" title="照片处理与 SharedRef">
        <ActionRow>
          <ActionButton disabled={!ready || action.state.phase === 'running'} label="拍摄照片" onPress={() => void takePhoto()} testID="camera-take-photo" />
          <ActionButton disabled={!ready || action.state.phase === 'running'} label="拍摄图片引用" onPress={() => void takeRef()} testID="camera-take-ref" tone="secondary" />
        </ActionRow>
        <Note>
          照片拍摄会验证实际尺寸、EXIF 元数据、质量编码以及 PictureRef 保存行为。
        </Note>
      </Panel>

      <Panel eyebrow="设备能力" title="查询当前虚拟设备">
        <ActionButton disabled={!ready || action.state.phase === 'running'} label="读取相机能力" onPress={() => void inspect()} testID="camera-read-capabilities" />
      </Panel>

      <ResultPanel state={action.state} />
    </>
  );
}

const styles = StyleSheet.create({
  cameraFrame: { alignItems: 'center', backgroundColor: palette.canvas, borderColor: palette.lineStrong, borderRadius: 6, borderWidth: 1, height: 320, justifyContent: 'center', overflow: 'hidden' },
  cameraInactive: { color: palette.faint, fontFamily: 'monospace', fontSize: 11, fontWeight: '800', letterSpacing: 1.2 },
  cameraPreview: { height: '100%', width: '100%' },
});

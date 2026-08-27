import AntDesign from '@expo/vector-icons/AntDesign';
import * as Application from 'expo-application';
import { Asset } from 'expo-asset';
import * as BackgroundFetch from 'expo-background-fetch';
import * as BackgroundTask from 'expo-background-task';
import * as Battery from 'expo-battery';
import Constants from 'expo-constants';
import { CameraView, useCameraPermissions } from 'expo-camera';
import type { CameraCapturedPicture, CameraType } from 'expo-camera';
import { Directory, File, Paths } from 'expo-file-system';
import * as Font from 'expo-font';
import {
  activateKeepAwakeAsync,
  deactivateKeepAwake,
  isAvailableAsync,
  useKeepAwake,
} from 'expo-keep-awake';
import * as Linking from 'expo-linking';
import { LinearGradient } from 'expo-linear-gradient';
import * as NavigationBar from 'expo-navigation-bar';
import * as Network from 'expo-network';
import * as Sharing from 'expo-sharing';
import * as SplashScreen from 'expo-splash-screen';
import * as SystemUI from 'expo-system-ui';
import * as TaskManager from 'expo-task-manager';
import { fetch as expoFetch } from 'expo/fetch';
import { useEffect, useMemo, useRef, useState } from 'react';
import { StyleSheet, Switch, Text, View } from 'react-native';

import { antDesignFontAsset, DYNAMIC_FONT_FAMILY } from './fixtures';
import { AppMetricsDemo } from './appMetrics';
import { AudioDemo } from './audio';
import {
  BACKGROUND_FETCH_OPTIONS,
  BACKGROUND_FETCH_TASK,
  getBackgroundFetchExecution,
  subscribeToBackgroundFetchExecution,
} from './backgroundFetch';
import {
  BACKGROUND_TASK,
  BACKGROUND_TASK_OPTIONS,
  getBackgroundTaskExecution,
  subscribeToBackgroundTaskExecution,
} from './backgroundTask';
import type { ModuleId } from './catalog';
import { HapticsDemo } from './haptics';
import { AdditionalModuleDemo } from './packageScreens';
import { palette } from './theme';
import {
  ActionButton,
  ActionRow,
  DataRow,
  Field,
  Note,
  Panel,
  ResultPanel,
  Tag,
  useAsyncResult,
} from './ui';

function json(value: unknown): string {
  return JSON.stringify(value, null, 2);
}

const BATTERY_STATE_LABELS: Record<Battery.BatteryState, string> = {
  [Battery.BatteryState.UNKNOWN]: '未知',
  [Battery.BatteryState.UNPLUGGED]: '未充电',
  [Battery.BatteryState.CHARGING]: '充电中',
  [Battery.BatteryState.FULL]: '已充满',
};

function batteryLevelLabel(level: number): string {
  return level < 0 ? '未知' : `${Math.round(level * 100)}%`;
}

function isBatteryLevel(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= -1 && value <= 1;
}

function isBatteryState(value: unknown): value is Battery.BatteryState {
  return typeof value === 'number' && Object.prototype.hasOwnProperty.call(BATTERY_STATE_LABELS, value);
}

function photoSummary(photo: CameraCapturedPicture): string {
  return json({
    exifKeys: photo.exif ? Object.keys(photo.exif).sort() : [],
    format: photo.format,
    height: photo.height,
    uri: photo.uri,
    width: photo.width,
  });
}

function CameraDemo() {
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

function AssetDemo() {
  const bundled = useAsyncResult();
  const remote = useAsyncResult();
  const [url, setUrl] = useState('https://example.com');

  return (
    <>
      <Panel eyebrow="内置资源" title="解析内置的 AntDesign 字体">
        <Note>这里使用与 Font 载体在运行时注册时相同的静态 Metro 资源。</Note>
        <ActionButton
          disabled={bundled.state.phase === 'running'}
          label="解析内置资源"
          onPress={() => void bundled.run(async () => {
            const asset = Asset.fromModule(antDesignFontAsset());
            await asset.downloadAsync();
            return json({
              downloaded: asset.downloaded,
              hash: asset.hash,
              localUri: asset.localUri,
              type: asset.type,
              uri: asset.uri,
            });
          })}
        />
        <ResultPanel state={bundled.state} />
      </Panel>

      <Panel eyebrow="远程缓存" title="下载任意 URL">
        <Field label="资源 URL" onChangeText={setUrl} value={url} />
        <ActionButton
          disabled={!url.trim() || remote.state.phase === 'running'}
          label="下载到资源缓存"
          onPress={() => void remote.run(async () => {
            const asset = Asset.fromURI(url.trim());
            await asset.downloadAsync();
            return json({ downloaded: asset.downloaded, localUri: asset.localUri, type: asset.type, uri: asset.uri });
          })}
        />
        <ResultPanel state={remote.state} />
      </Panel>
    </>
  );
}

type HarmonyPlatformConstants = {
  apiVersion?: number;
  bundleName?: string;
  deviceType?: string;
  osFullName?: string;
  versionCode?: number;
  versionName?: string;
};

function ConstantsDemo() {
  const userAgent = useAsyncResult();
  const harmony = (Constants.platform as { harmony?: HarmonyPlatformConstants } | undefined)?.harmony;
  const harmonyConfig = (Constants.expoConfig as typeof Constants.expoConfig & {
    harmony?: { bundleName?: string; targetApiVersion?: number };
  } | null)?.harmony;

  return (
    <>
      <Panel eyebrow="运行时" title="Expo 常量">
        <DataRow label="executionEnvironment" value={Constants.executionEnvironment} />
        <DataRow label="sessionId" value={Constants.sessionId} />
        <DataRow label="deviceName" value={Constants.deviceName || '不可用'} />
        <DataRow label="systemVersion" value={String(Constants.systemVersion ?? '不可用')} />
        <DataRow label="statusBarHeight" value={`${Constants.statusBarHeight}px`} />
        <DataRow label="debugMode" value={String(Constants.debugMode)} />
      </Panel>

      <Panel eyebrow="HARMONY 清单" title="原生与内嵌信息">
        <DataRow label="bundleName" value={harmony?.bundleName || harmonyConfig?.bundleName || '缺失'} />
        <DataRow label="version" value={harmony ? `${harmony.versionName ?? '?'} (${harmony.versionCode ?? '?'})` : '缺失'} />
        <DataRow label="设备 / API" value={harmony ? `${harmony.deviceType ?? '?'} · API ${harmony.apiVersion ?? '?'}` : '缺失'} />
        <DataRow label="系统全名" value={harmony?.osFullName || '不可用'} />
        <DataRow label="系统字体数量" value={String(Constants.systemFonts.length)} />
        <Text selectable style={styles.compactCode}>{Constants.systemFonts.slice(0, 12).join('\n') || '未上报系统字体。'}</Text>
      </Panel>

      <Panel eyebrow="平台服务" title="WebView 用户代理">
        <ActionButton
          disabled={userAgent.state.phase === 'running'}
          label="读取 User Agent"
          onPress={() => void userAgent.run(async () => (await Constants.getWebViewUserAgentAsync()) || '平台返回了 null。')}
        />
        <ResultPanel state={userAgent.state} />
      </Panel>
    </>
  );
}

function FileSystemDemo() {
  const operation = useAsyncResult();

  const runSandbox = () => operation.run(async () => {
    const directory = new Directory(Paths.cache, 'expo-harmony-demo-manual');
    try {
      directory.create({ idempotent: true, intermediates: true });
      const source = new File(directory, 'source.txt');
      source.create({ overwrite: true });
      source.write('Harmony file system\n', { append: false });
      source.write(new TextEncoder().encode('shared object API'), { append: true });

      const copied = new File(directory, 'copy.txt');
      source.copy(copied);
      const moved = new File(directory, 'moved.txt');
      copied.move(moved);
      copied.rename('renamed.txt');

      const handle = source.open();
      let prefix: Uint8Array;
      try {
        handle.offset = 0;
        prefix = handle.readBytes(7);
      } finally {
        handle.close();
      }

      return json({
        contentUri: source.contentUri,
        entries: directory.list().map(entry => entry.uri),
        md5: source.info({ md5: true }).md5,
        prefix: new TextDecoder().decode(prefix),
        size: source.size,
        text: await source.text(),
      });
    } finally {
      if (directory.exists) directory.delete();
    }
  });

  const pickFile = () => operation.run(async () => {
    const selection = await File.pickFileAsync(undefined, '*/*');
    const file = Array.isArray(selection) ? selection[0] : selection;
    if (!file) throw new Error('选择器未返回文件。');
    const handle = file.open();
    let sample: Uint8Array;
    try {
      sample = handle.readBytes(Math.min(file.size, 64));
    } finally {
      handle.close();
    }
    return json({
      contentUri: file.contentUri,
      exists: file.exists,
      mimeType: file.type,
      sampleBytes: Array.from(sample),
      size: file.size,
      uri: file.uri,
    });
  });

  const pickDirectory = () => operation.run(async () => {
    const directory = await Directory.pickDirectoryAsync();
    return json({
      entries: directory.list().slice(0, 12).map(entry => entry.uri),
      exists: directory.exists,
      size: directory.size,
      uri: directory.uri,
    });
  });

  return (
    <>
      <Panel eyebrow="沙箱" title="演练现代文件对象">
        <Note>测试只会在应用缓存目录下写入，并在输出结果后删除该目录。</Note>
        <ActionButton
          disabled={operation.state.phase === 'running'}
          label="执行 创建 · 复制 · 移动 · 句柄"
          onPress={() => void runSandbox()}
        />
      </Panel>

      <Panel eyebrow="系统选择器" title="检查持久化授权">
        <ActionRow>
          <ActionButton disabled={operation.state.phase === 'running'} label="选择文件" onPress={() => void pickFile()} />
          <ActionButton disabled={operation.state.phase === 'running'} label="选择目录" onPress={() => void pickDirectory()} tone="secondary" />
        </ActionRow>
        <Note>
          选中的内容仅作抽样读取，演示不会编辑或删除用户选择的文件和目录。
        </Note>
      </Panel>
      <ResultPanel state={operation.state} />
    </>
  );
}

function FontDemo() {
  const action = useAsyncResult();
  const [revision, setRevision] = useState(0);
  const loaded = Font.getLoadedFonts();
  const glyphValue = AntDesign.glyphMap.experiment;
  const glyph = typeof glyphValue === 'number' ? String.fromCodePoint(glyphValue) : glyphValue;

  const refresh = async (operation: () => Promise<void>, message: string) => {
    await operation();
    setRevision(value => value + 1);
    return `${message}\n\n已加载的字体系列：\n${Font.getLoadedFonts().join('\n')}`;
  };

  return (
    <>
      <Panel eyebrow="CNG 资源" title="应用启动时的内置字体">
        <View style={styles.fontSpecimen}>
          <AntDesign color={palette.signal} name="experiment" size={42} />
          <View style={styles.specimenCopy}>
            <Text style={styles.specimenTitle}>AntDesign</Text>
            <Text style={styles.specimenCaption}>已在 JavaScript 运行前完成注册</Text>
          </View>
          <Tag tone={Font.isLoaded('AntDesign') ? 'success' : 'danger'}>
            {Font.isLoaded('AntDesign') ? '已加载' : '未加载'}
          </Tag>
        </View>
      </Panel>

      <Panel eyebrow="运行时注册" title="加载与卸载字体系列别名">
        <View key={revision} style={styles.dynamicSpecimen}>
          <Text style={[styles.dynamicGlyph, { fontFamily: DYNAMIC_FONT_FAMILY }]}>{glyph}</Text>
          <Text style={styles.specimenCaption}>{DYNAMIC_FONT_FAMILY}</Text>
        </View>
        <ActionRow>
          <ActionButton
            disabled={action.state.phase === 'running'}
            label="加载别名"
            onPress={() => void action.run(() => refresh(
              () => Font.loadAsync(DYNAMIC_FONT_FAMILY, antDesignFontAsset()),
              '动态字体系列已注册。'
            ))}
          />
          <ActionButton
            disabled={action.state.phase === 'running' || !Font.isLoaded(DYNAMIC_FONT_FAMILY)}
            label="卸载别名"
            onPress={() => void action.run(() => refresh(
              () => Font.unloadAsync(DYNAMIC_FONT_FAMILY),
              '动态字体系列已注销。'
            ))}
            tone="secondary"
          />
        </ActionRow>
        <DataRow label="已加载字体系列数" value={String(loaded.length)} />
        <ResultPanel state={action.state} />
      </Panel>
    </>
  );
}

const MANUAL_KEEP_AWAKE_TAG = 'expo-harmony-demo-manual';

function HookKeepAwakeProbe() {
  useKeepAwake('expo-harmony-demo-hook');
  return <Tag tone="success">Hook 已挂载</Tag>;
}

function KeepAwakeDemo() {
  const action = useAsyncResult();
  const [manualActive, setManualActive] = useState(false);
  const [hookActive, setHookActive] = useState(false);

  useEffect(() => () => {
    void deactivateKeepAwake(MANUAL_KEEP_AWAKE_TAG);
  }, []);

  const toggleManual = () => action.run(async () => {
    if (manualActive) {
      await deactivateKeepAwake(MANUAL_KEEP_AWAKE_TAG);
      setManualActive(false);
      return '手动标签已释放，屏幕可以正常休眠。';
    }
    await activateKeepAwakeAsync(MANUAL_KEEP_AWAKE_TAG);
    setManualActive(true);
    return '手动标签已生效。请将应用切到后台再切回，验证常亮状态是否恢复。';
  });

  return (
    <>
      <Panel eyebrow="标签常亮锁" title="手动生命周期">
        <DataRow label="本地 UI 状态" value={<Tag tone={manualActive ? 'success' : 'neutral'}>{manualActive ? '生效中' : '已释放'}</Tag>} />
        <ActionButton
          disabled={action.state.phase === 'running'}
          label={manualActive ? '释放标签' : '激活标签'}
          onPress={() => void toggleManual()}
          tone={manualActive ? 'secondary' : 'primary'}
        />
        <ResultPanel state={action.state} />
      </Panel>

      <Panel eyebrow="React Hook" title="随挂载生效的常亮锁">
        <View style={styles.switchRow}>
          <View style={styles.switchCopy}>
            <Text style={styles.switchTitle}>useKeepAwake</Text>
            <Text style={styles.switchCaption}>卸载探针时会自动释放其独立标签。</Text>
          </View>
          <Switch
            onValueChange={setHookActive}
            thumbColor={hookActive ? palette.signal : palette.muted}
            trackColor={{ false: palette.lineStrong, true: palette.signalSoft }}
            value={hookActive}
          />
        </View>
        {hookActive ? <HookKeepAwakeProbe /> : <Tag>Hook 已卸载</Tag>}
      </Panel>

      <Panel eyebrow="能力探测" title="官方可用性 API">
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="检查可用性"
          onPress={() => void action.run(async () => `isAvailableAsync() → ${await isAvailableAsync()}`)}
        />
      </Panel>
    </>
  );
}

function appendPreview(
  current: Uint8Array<ArrayBufferLike>,
  chunk: Uint8Array<ArrayBufferLike>,
  limit = 2048
): Uint8Array<ArrayBufferLike> {
  if (current.length >= limit) return current;
  const addition = chunk.subarray(0, limit - current.length);
  const result = new Uint8Array(current.length + addition.length);
  result.set(current);
  result.set(addition, current.length);
  return result;
}

function FetchDemo() {
  const action = useAsyncResult();
  const [method, setMethod] = useState<'GET' | 'POST'>('GET');
  const [url, setUrl] = useState('https://example.com');
  const controller = useRef<AbortController | null>(null);
  const isRunning = action.state.phase === 'running';

  useEffect(() => () => controller.current?.abort(), []);

  const request = () => action.run(async () => {
    const requestController = new AbortController();
    controller.current = requestController;
    try {
      const response = await expoFetch(url.trim(), {
        body: method === 'POST' ? JSON.stringify({ source: 'expo-harmony-demo' }) : undefined,
        credentials: 'include',
        headers: method === 'POST' ? { 'content-type': 'application/json' } : undefined,
        method,
        redirect: 'follow',
        signal: requestController.signal,
      });
      let bytes = 0;
      let chunks = 0;
      let preview: Uint8Array<ArrayBufferLike> = new Uint8Array();
      if (response.body) {
        const reader = response.body.getReader();
        while (true) {
          const item = await reader.read();
          if (item.done) break;
          chunks += 1;
          bytes += item.value.length;
          preview = appendPreview(preview, item.value);
        }
      }
      return json({
        bodyPreview: new TextDecoder().decode(preview),
        bytes,
        chunks,
        headers: Object.fromEntries([...response.headers.entries()].slice(0, 16)),
        redirected: response.redirected,
        status: response.status,
        url: response.url,
      });
    } finally {
      if (controller.current === requestController) controller.current = null;
    }
  });

  const requestHint = useMemo(
    () => method === 'GET'
      ? '可使用任意 HTTP(S) 地址。重定向、Set-Cookie 与分块响应体都会体现在结果中。'
      : 'POST 会发送一个较小的 JSON 请求体，并保持重定向与凭据处理开启。',
    [method]
  );

  return (
    <Panel eyebrow="网络试验场" title="流式读取 HTTP 响应">
      <Field label="请求 URL" onChangeText={setUrl} value={url} />
      <View style={styles.methodRow}>
        {(['GET', 'POST'] as const).map(value => (
          <ActionButton
            key={value}
            disabled={isRunning}
            label={value}
            onPress={() => setMethod(value)}
            tone={method === value ? 'primary' : 'secondary'}
          />
        ))}
      </View>
      <Note>{requestHint}</Note>
      <ActionRow>
        <ActionButton disabled={isRunning || !url.trim()} label="发送请求" onPress={() => void request()} />
        <ActionButton
          disabled={!isRunning}
          label="中止"
          onPress={() => controller.current?.abort()}
          tone="danger"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function LinkingDemo() {
  const action = useAsyncResult();
  const linkingURL = Linking.useLinkingURL();
  const [url, setUrl] = useState(linkingURL || 'expoharmonydemo://module/linking');

  return (
    <>
      <Panel eyebrow="原生生命周期" title="当前链接 URL">
        <DataRow label="getLinkingURL()" value={Linking.getLinkingURL() || 'null'} />
        <DataRow label="useLinkingURL()" value={linkingURL || 'null'} />
        <ActionButton
          label="清除缓存的初始 URL"
          onPress={() => void action.run(async () => {
            const initialURL = await Linking.getInitialURL();
            Linking.clearInitialURL();
            const next = Linking.getLinkingURL();
            if (next !== null) throw new Error(`清除后应为 null，实际为 ${next}。`);
            const retainedInitialURL = await Linking.getInitialURL();
            if (retainedInitialURL !== initialURL) {
              throw new Error(
                `React Native 初始 URL 由 ${String(initialURL)} 变为 ${String(retainedInitialURL)}。`
              );
            }
            return 'Expo 缓存已清除，React Native 冷启动 URL 保持不变。';
          })}
          testID="linking-clear-initial-url"
          tone="secondary"
        />
        <ResultPanel state={action.state} />
      </Panel>

      <Panel eyebrow="纯 URL API" title="解析任意深链接">
        <Field label="URL" onChangeText={setUrl} value={url} />
        <ActionRow>
          <ActionButton
            disabled={!url.trim()}
            label="解析 URL"
            onPress={() => void action.run(() => json(Linking.parse(url.trim())))}
          />
          <ActionButton
            disabled={!url.trim() || action.state.phase === 'running'}
            label="检测能否打开"
            onPress={() => void action.run(async () => `canOpenURL() → ${await Linking.canOpenURL(url.trim())}`)}
            tone="secondary"
          />
          <ActionButton
            disabled={!url.trim() || action.state.phase === 'running'}
            label="打开 URL"
            onPress={() => void action.run(async () => `openURL() → ${await Linking.openURL(url.trim())}`)}
            tone="secondary"
          />
        </ActionRow>
      </Panel>
    </>
  );
}

function NetworkDemo() {
  const action = useAsyncResult();
  const state = Network.useNetworkState();
  const [events, setEvents] = useState(0);
  const [lastEvent, setLastEvent] = useState<Network.NetworkState>();

  useEffect(() => {
    const subscription = Network.addNetworkStateListener((event) => {
      setEvents(value => value + 1);
      setLastEvent(event);
    });

    return () => subscription.remove();
  }, []);

  const inspect = () => action.run(async () => {
    const [current, ipAddress, airplaneMode] = await Promise.all([
      Network.getNetworkStateAsync(),
      Network.getIpAddressAsync(),
      Network.isAirplaneModeEnabledAsync(),
    ]);

    return json({ airplaneMode, ipAddress, state: current });
  });

  return (
    <>
      <Panel eyebrow="实时状态" title="观察 Harmony 网络连接">
        <DataRow label="连接类型" value={state.type ?? '加载中'} />
        <DataRow label="已连接" value={String(state.isConnected ?? '未知')} />
        <DataRow label="互联网可达" value={String(state.isInternetReachable ?? '未知')} />
        <DataRow label="状态事件数" value={String(events)} />
        {lastEvent ? <Text selectable style={styles.compactCode}>{json(lastEvent)}</Text> : null}
      </Panel>

      <Panel eyebrow="原生方法" title="读取当前网络快照">
        <Note>返回当前承载网络、本地 IPv4 地址与系统飞行模式设置。</Note>
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="读取网络状态"
          onPress={() => void inspect()}
          testID="network-read-state"
        />
        <ResultPanel state={action.state} />
      </Panel>
    </>
  );
}

function SharingDemo() {
  const action = useAsyncResult();
  const incoming = Sharing.useIncomingShare();

  const shareFile = () => action.run(async () => {
    if (!await Sharing.isAvailableAsync()) throw new Error('Harmony 系统分享不可用。');

    const directory = new Directory(Paths.cache, 'expo-harmony-demo-sharing');
    try {
      directory.create({ idempotent: true, intermediates: true });
      const file = new File(directory, 'expo-sharing-check.txt');
      file.create({ overwrite: true });
      file.write('Expo Sharing on HarmonyOS\n本地文件 · text/plain · 系统分享面板\n');

      await Sharing.shareAsync(file.uri, {
        dialogTitle: 'Expo Harmony 分享检测',
        mimeType: 'text/plain',
      });

      return `系统分享面板已打开并关闭。\n${file.uri}`;
    } finally {
      if (directory.exists) directory.delete();
    }
  });

  const validateURL = () => action.run(async () => {
    try {
      await Sharing.shareAsync('https://example.com/not-a-local-file.txt', { mimeType: 'text/plain' });
    } catch (error) {
      const code = typeof error === 'object' && error !== null && 'code' in error
        ? String((error as { code: unknown }).code)
        : undefined;
      if (code !== 'ERR_SHARING_INVALID_URL') {
        throw new Error(`预期错误码 ERR_SHARING_INVALID_URL，实际为 ${code || '无错误码'}。`);
      }

      return code;
    }

    throw new Error('远程 HTTPS URL 不应进入系统分享面板。');
  });

  return (
    <>
      <Panel eyebrow="接收分享" title="检查发送到本应用的数据">
        <DataRow label="负载数量" value={String(incoming.sharedPayloads.length)} />
        <DataRow label="已解析数量" value={String(incoming.resolvedSharedPayloads.length)} />
        <DataRow label="是否解析中" value={String(incoming.isResolving)} />
        {incoming.error ? <Text selectable style={styles.compactCode}>{incoming.error.message}</Text> : null}
        {incoming.sharedPayloads.length > 0
          ? <Text selectable style={styles.compactCode}>{json(incoming.sharedPayloads)}</Text>
          : <Note>向本应用分享文本、网页链接或文件，即可验证接收链路。</Note>}
        {incoming.resolvedSharedPayloads.length > 0
          ? <Text selectable style={styles.compactCode}>{json(incoming.resolvedSharedPayloads)}</Text>
          : null}
        <ActionRow>
          <ActionButton
            label="刷新分享负载"
            onPress={() => void incoming.refreshSharePayloads()}
            testID="sharing-refresh-payloads"
          />
          <ActionButton
            label="清空分享负载"
            onPress={() => {
              incoming.clearSharedPayloads();
              void incoming.refreshSharePayloads();
            }}
            testID="sharing-clear-payloads"
            tone="secondary"
          />
        </ActionRow>
      </Panel>

      <Panel eyebrow="能力探测" title="Harmony 系统分享">
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="检查可用性"
          onPress={() => void action.run(async () => `isAvailableAsync() → ${await Sharing.isAvailableAsync()}`)}
          testID="sharing-check-availability"
        />
      </Panel>

      <Panel eyebrow="本地文件" title="打开系统分享面板">
        <Note>
          会在应用缓存中创建一个临时的 UTF-8 文本文件，以 text/plain 分享，面板关闭后随即删除。
        </Note>
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="分享测试文件"
          onPress={() => void shareFile()}
          testID="sharing-open-panel"
        />
      </Panel>

      <Panel eyebrow="错误契约" title="拒绝非本地 URL">
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="验证 URL 校验"
          onPress={() => void validateURL()}
          testID="sharing-invalid-url"
          tone="secondary"
        />
        <ResultPanel state={action.state} />
      </Panel>
    </>
  );
}

function ApplicationDemo() {
  const action = useAsyncResult();

  return (
    <>
      <Panel eyebrow="已安装应用" title="原生应用包标识">
        <DataRow label="applicationId" value={Application.applicationId || 'null'} />
        <DataRow label="applicationName" value={Application.applicationName || 'null'} />
        <DataRow label="nativeApplicationVersion" value={Application.nativeApplicationVersion || 'null'} />
        <DataRow label="nativeBuildVersion" value={Application.nativeBuildVersion || 'null'} />
      </Panel>
      <Panel eyebrow="安装记录" title="系统报告的时间戳">
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="读取安装时间"
          onPress={() => void action.run(async () => {
            const installedAt = await Application.getInstallationTimeAsync();
            if (Number.isNaN(installedAt.getTime())) throw new Error('原生安装时间无效。');
            return installedAt.toISOString();
          })}
        />
        <ResultPanel state={action.state} />
      </Panel>
    </>
  );
}

function SystemUIDemo() {
  const action = useAsyncResult();

  return (
    <Panel eyebrow="窗口根视图" title="运行时背景色">
      <ActionRow>
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="设为实验室背景"
          onPress={() => void action.run(async () => {
            await SystemUI.setBackgroundColorAsync(palette.canvas);
            return `getBackgroundColorAsync() → ${String(await SystemUI.getBackgroundColorAsync())}`;
          })}
          testID="system-ui-set-background"
        />
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="清除覆盖"
          onPress={() => void action.run(async () => {
            await SystemUI.setBackgroundColorAsync(null);
            return `getBackgroundColorAsync() → ${String(await SystemUI.getBackgroundColorAsync())}`;
          })}
          testID="system-ui-reset-background"
          tone="secondary"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function SplashScreenDemo() {
  const action = useAsyncResult();

  return (
    <>
      <Panel eyebrow="启动交接" title="原生启动屏状态机">
        <Note>
          根布局在模块作用域调用 preventAutoHideAsync，加载内置字体后，恰好在 React 内容就绪时隐藏启动屏。
        </Note>
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="验证幂等交接"
          onPress={() => void action.run(async () => {
            SplashScreen.setOptions({ duration: 0, fade: false });
            const prevented = await SplashScreen.preventAutoHideAsync();
            SplashScreen.hide();
            await SplashScreen.hideAsync();
            return `就绪后 prevent → ${String(prevented)}；重复 hide 已完成`;
          })}
        />
        <ResultPanel state={action.state} />
      </Panel>
      <Panel eyebrow="CNG 资源" title="冷启动视觉契约">
        <DataRow label="背景色" value={palette.canvas} />
        <DataRow label="缩放模式" value="contain" />
        <DataRow label="图片" value="assets/app-icon.svg" />
      </Panel>
    </>
  );
}

function LinearGradientDemo() {
  const [direction, setDirection] = useState<'horizontal' | 'vertical'>('horizontal');
  const start = { x: 0, y: 0 } as const;
  const end = direction === 'horizontal' ? { x: 1, y: 0 } as const : { x: 0, y: 1 } as const;

  return (
    <>
      <Panel eyebrow="多色渐变" title="精确的对角端点">
        <LinearGradient
          colors={['#FFB000', '#72D8FF', '#7B61FF']}
          end={{ x: 1, y: 1 }}
          locations={[0, 0.45, 1]}
          start={{ x: 0, y: 0 }}
          style={styles.gradientHero}
          testID="linear-gradient-multi-stop"
        >
          <Text style={styles.gradientEyebrow}>原生画布</Text>
          <Text style={styles.gradientTitle}>三种颜色，一个原生视图。</Text>
          <Text style={styles.gradientCopy}>
            子内容浮于渐变之上，原生图层始终跟随视图边界。
          </Text>
        </LinearGradient>
      </Panel>

      <Panel eyebrow="动态属性" title="切换渐变方向">
        <LinearGradient
          colors={['#FF7064', '#FFB000', '#51D88A']}
          end={end}
          locations={[0, 0.52, 1]}
          start={start}
          style={styles.gradientDirection}
          testID="linear-gradient-direction"
        >
          <Text style={styles.gradientDirectionText}>{direction === 'horizontal' ? '水平' : '垂直'}</Text>
        </LinearGradient>
        <DataRow label="起点 → 终点" value={direction === 'horizontal' ? '(0, 0) → (1, 0)' : '(0, 0) → (0, 1)'} />
        <ActionRow>
          <ActionButton label="水平" onPress={() => setDirection('horizontal')} tone="secondary" />
          <ActionButton label="垂直" onPress={() => setDirection('vertical')} tone="secondary" />
        </ActionRow>
      </Panel>

      <Panel eyebrow="断点与裁剪" title="硬过渡与单独圆角">
        <LinearGradient
          colors={['#111920', '#111920', '#72D8FF', '#7B61FF']}
          end={{ x: 1, y: 0 }}
          locations={[0, 0.5, 0.5, 1]}
          start={{ x: 0, y: 0 }}
          style={styles.gradientHardStop}
          testID="linear-gradient-hard-stop"
        >
          <Text style={styles.gradientHardStopText}>50% 硬过渡</Text>
        </LinearGradient>
      </Panel>

      <Panel eyebrow="边界情况" title="部分断点与退化坐标轴">
        <LinearGradient
          colors={['#FF7064', '#FFB000', '#72D8FF']}
          end={{ x: 1, y: 0 }}
          locations={[0.2, 0.65]}
          start={{ x: 0, y: 0 }}
          style={styles.gradientPartial}
          testID="linear-gradient-partial-locations"
        >
          <Text style={styles.gradientEdgeText}>部分断点仅保留 20% + 65%</Text>
        </LinearGradient>
        <LinearGradient
          colors={['#FF7064', '#51D88A']}
          end={{ x: 0.5, y: 0.5 }}
          start={{ x: 0.5, y: 0.5 }}
          style={styles.gradientDegenerate}
          testID="linear-gradient-degenerate"
        >
          <Text style={styles.gradientEdgeText}>退化坐标轴 = 末尾颜色</Text>
        </LinearGradient>
      </Panel>
    </>
  );
}

function NavigationBarDemo() {
  const action = useAsyncResult();
  const observedVisibility = NavigationBar.useVisibility();

  useEffect(() => () => {
    void Promise.all([
      NavigationBar.setBackgroundColorAsync(palette.canvas),
      NavigationBar.setButtonStyleAsync('light'),
      NavigationBar.setPositionAsync('relative'),
      NavigationBar.setVisibilityAsync('visible'),
    ]).catch(() => undefined);
  }, []);

  const inspect = () => action.run(async () => json({
    backgroundColor: await NavigationBar.getBackgroundColorAsync(),
    buttonStyle: await NavigationBar.getButtonStyleAsync(),
    position: await NavigationBar.unstable_getPositionAsync(),
    visibility: await NavigationBar.getVisibilityAsync(),
  }));

  return (
    <>
      <Panel eyebrow="实时状态" title="读取 Harmony 导航栏">
        <DataRow
          label="可见性事件 Hook"
          value={<Tag tone={observedVisibility === 'hidden' ? 'danger' : 'success'}>{observedVisibility ?? '加载中'}</Tag>}
        />
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="读取原生状态"
          onPress={() => void inspect()}
          testID="navigation-bar-read"
        />
        <ResultPanel state={action.state} />
      </Panel>

      <Panel eyebrow="颜色与按键" title="修改原生系统栏属性">
        <ActionRow>
          <ActionButton
            label="设置主题色"
            onPress={() => void NavigationBar.setBackgroundColorAsync(palette.signal)}
            testID="navigation-bar-signal-color"
          />
          <ActionButton
            label="恢复默认背景"
            onPress={() => void NavigationBar.setBackgroundColorAsync(palette.canvas)}
            tone="secondary"
          />
        </ActionRow>
        <ActionRow>
          <ActionButton label="浅色按键" onPress={() => void NavigationBar.setButtonStyleAsync('light')} />
          <ActionButton label="深色按键" onPress={() => void NavigationBar.setButtonStyleAsync('dark')} tone="secondary" />
        </ActionRow>
      </Panel>

      <Panel eyebrow="布局与可见性" title="演练系统栏生命周期">
        <ActionRow>
          <ActionButton label="显示导航栏" onPress={() => void NavigationBar.setVisibilityAsync('visible')} />
          <ActionButton
            label="隐藏导航栏"
            onPress={() => void NavigationBar.setVisibilityAsync('hidden')}
            testID="navigation-bar-hide"
            tone="secondary"
          />
        </ActionRow>
        <ActionRow>
          <ActionButton label="相对定位" onPress={() => void NavigationBar.setPositionAsync('relative')} />
          <ActionButton label="绝对定位" onPress={() => void NavigationBar.setPositionAsync('absolute')} tone="secondary" />
        </ActionRow>
        <Note>
          绝对定位模式下 React 内容会延伸到系统栏下方。离开本页面时会自动恢复实验室默认设置。
        </Note>
      </Panel>
    </>
  );
}

function BatteryDemo() {
  const powerState = Battery.usePowerState();
  const action = useAsyncResult();
  const [events, setEvents] = useState({ level: 0, mode: 0, state: 0 });
  const [payloads, setPayloads] = useState({ level: '暂无', mode: '暂无', state: '暂无' });
  const [invalidEvent, setInvalidEvent] = useState<string | null>(null);
  const [removal, setRemoval] = useState({ calls: 0, phase: 'idle' });
  const removalSubscription = useRef<Battery.Subscription | null>(null);

  useEffect(() => {
    const subscriptions = [
      Battery.addBatteryLevelListener((event) => {
        if (!isBatteryLevel(event?.batteryLevel)) {
          setInvalidEvent(`无效的电量事件：${json(event)}`);
        } else {
          setPayloads(value => ({ ...value, level: String(event.batteryLevel) }));
        }

        setEvents(value => ({ ...value, level: value.level + 1 }));
      }),
      Battery.addBatteryStateListener((event) => {
        if (!isBatteryState(event?.batteryState)) {
          setInvalidEvent(`无效的电池状态事件：${json(event)}`);
        } else {
          setPayloads(value => ({ ...value, state: String(event.batteryState) }));
        }

        setEvents(value => ({ ...value, state: value.state + 1 }));
      }),
      Battery.addLowPowerModeListener((event) => {
        if (typeof event?.lowPowerMode !== 'boolean') {
          setInvalidEvent(`无效的低电量模式事件：${json(event)}`);
        } else {
          setPayloads(value => ({ ...value, mode: String(event.lowPowerMode) }));
        }

        setEvents(value => ({ ...value, mode: value.mode + 1 }));
      }),
    ];

    return () => {
      subscriptions.forEach(subscription => subscription.remove());
      removalSubscription.current?.remove();
      removalSubscription.current = null;
    };
  }, []);

  const armRemovalProbe = () => {
    removalSubscription.current?.remove();
    removalSubscription.current = null;
    setRemoval({ calls: 0, phase: '等待首个电量事件' });

    let calls = 0;
    const subscription = Battery.addBatteryLevelListener((event) => {
      calls += 1;

      if (!isBatteryLevel(event?.batteryLevel)) {
        setInvalidEvent(`无效的移除探针事件：${json(event)}`);
      }

      setRemoval({
        calls,
        phase: calls === 1 ? '首个事件后已移除' : '失败：回调被重复触发',
      });

      if (calls === 1) {
        subscription.remove();
        if (removalSubscription.current === subscription) removalSubscription.current = null;
      }
    });

    removalSubscription.current = subscription;
  };

  const inspect = () => action.run(async () => {
    const [available, current, optimized] = await Promise.all([
      Battery.isAvailableAsync(),
      Battery.getPowerStateAsync(),
      Battery.isBatteryOptimizationEnabledAsync(),
    ]);

    return json({ available, batteryOptimization: optimized, ...current });
  });

  return (
    <>
      <Panel eyebrow="实时 Hook" title="观察 Harmony 电源状态">
        <DataRow label="电量" value={batteryLevelLabel(powerState.batteryLevel)} />
        <DataRow
          label="电池状态"
          value={`${BATTERY_STATE_LABELS[powerState.batteryState]} (${String(powerState.batteryState)})`}
        />
        <DataRow label="低电量模式" value={String(powerState.lowPowerMode)} />
      </Panel>

      <Panel eyebrow="原生事件" title="跟踪 Expo Battery 的全部公开事件">
        <DataRow label="电量事件数" value={String(events.level)} />
        <DataRow label="状态事件数" value={String(events.state)} />
        <DataRow label="低电量模式事件数" value={String(events.mode)} />
        <DataRow label="最近电量事件值" value={payloads.level} />
        <DataRow label="最近状态事件值" value={payloads.state} />
        <DataRow label="最近模式事件值" value={payloads.mode} />
        <DataRow
          label="事件数据契约"
          value={<Tag tone={invalidEvent === null ? 'success' : 'danger'}>{invalidEvent ?? '有效'}</Tag>}
        />
        <Note>
          请在本页面停留期间修改模拟器的电量或充电状态。Hook 数值与对应计数器应即时更新，无需重新进入页面。
        </Note>
        <Text selectable style={styles.compactCode}>
          {'Emulator -instance "<name>" -battery 37\nEmulator -instance "<name>" -batteryStatus 1'}
        </Text>
      </Panel>

      <Panel eyebrow="移除契约" title="在首个事件后移除监听器">
        <DataRow label="探针状态" value={removal.phase} />
        <DataRow label="回调次数" value={String(removal.calls)} />
        <ActionButton
          label="启动「首个事件后移除」探针"
          onPress={armRemovalProbe}
          testID="battery-arm-removal-probe"
          tone="secondary"
        />
        <Note>
          启动探针后，连续修改两次模拟器电量。回调次数应达到一次，且第二次修改后仍保持一次。
        </Note>
      </Panel>

      <Panel eyebrow="原生方法" title="读取一致的电源快照">
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="读取电池状态"
          onPress={() => void inspect()}
          testID="battery-read-state"
        />
        <ResultPanel state={action.state} />
      </Panel>
    </>
  );
}

function backgroundFetchStatusLabel(status: BackgroundFetch.BackgroundFetchStatus | null): string {
  if (status === null) return '不可用';

  return BackgroundFetch.BackgroundFetchStatus[status] ?? String(status);
}

function BackgroundFetchDemo() {
  const action = useAsyncResult();
  const [registered, setRegistered] = useState(false);
  const [execution, setExecution] = useState(getBackgroundFetchExecution);

  useEffect(() => subscribeToBackgroundFetchExecution(setExecution), []);

  const inspect = () => action.run(async () => {
    const [available, status, isRegistered] = await Promise.all([
      TaskManager.isAvailableAsync(),
      BackgroundFetch.getStatusAsync(),
      TaskManager.isTaskRegisteredAsync(BACKGROUND_FETCH_TASK),
    ]);
    const options = isRegistered
      ? await TaskManager.getTaskOptionsAsync<BackgroundFetch.BackgroundFetchOptions>(BACKGROUND_FETCH_TASK)
      : null;

    setRegistered(isRegistered);

    return json({ available, options, registered: isRegistered, status: backgroundFetchStatusLabel(status) });
  });

  const register = () => action.run(async () => {
    await BackgroundFetch.registerTaskAsync(BACKGROUND_FETCH_TASK, BACKGROUND_FETCH_OPTIONS);

    setRegistered(true);

    return `已注册 ${BACKGROUND_FETCH_TASK}，最小间隔为不精确的 20 分钟。`;
  });

  const unregister = () => action.run(async () => {
    await BackgroundFetch.unregisterTaskAsync(BACKGROUND_FETCH_TASK);

    setRegistered(false);

    return `已取消注册 ${BACKGROUND_FETCH_TASK}。`;
  });

  return (
    <>
      <Panel eyebrow="原生状态" title="检查 BackgroundFetch 与 TaskManager">
        <DataRow label="任务名" value={BACKGROUND_FETCH_TASK} />
        <DataRow label="已注册" value={<Tag tone={registered ? 'success' : 'signal'}>{registered ? '是' : '否'}</Tag>} />
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="读取原生状态"
          onPress={() => void inspect()}
          testID="background-fetch-inspect"
        />
      </Panel>

      <Panel eyebrow="WORKSCHEDULER" title="注册 Expo 后台拉取任务">
        <ActionRow>
          <ActionButton
            disabled={registered || action.state.phase === 'running'}
            label="注册任务"
            onPress={() => void register()}
            testID="background-fetch-register"
          />
          <ActionButton
            disabled={!registered || action.state.phase === 'running'}
            label="取消注册"
            onPress={() => void unregister()}
            testID="background-fetch-unregister"
            tone="secondary"
          />
        </ActionRow>
        <Note>
          HarmonyOS 对延迟任务的调度并不精确，且强制最小间隔 20 分钟。请保持应用进程存活，将其切到后台并等待系统回调；出于功耗策略，调度器可能会推迟执行。
        </Note>
      </Panel>

      <Panel eyebrow="任务执行" title="观察 JavaScript 回调">
        <DataRow label="回调次数" value={String(execution?.count ?? 0)} />
        <DataRow label="最近事件" value={execution?.eventId ?? '尚未观测到'} />
        <DataRow label="发生时间" value={execution?.occurredAt ?? '尚未观测到'} />
        <DataRow label="错误" value={execution?.error ?? '无'} />
        <Note>
          回调记录保存在当前 JavaScript 运行时中。进程重启后此处会清空，但原生注册仍会保留，可在上方查看。
        </Note>
      </Panel>

      <ResultPanel state={action.state} />
    </>
  );
}

function backgroundTaskStatusLabel(status: BackgroundTask.BackgroundTaskStatus): string {
  return BackgroundTask.BackgroundTaskStatus[status] ?? String(status);
}

function BackgroundTaskDemo() {
  const action = useAsyncResult();
  const [registered, setRegistered] = useState(false);
  const [execution, setExecution] = useState(getBackgroundTaskExecution);
  const [expirations, setExpirations] = useState(0);

  useEffect(() => {
    const unsubscribe = subscribeToBackgroundTaskExecution(setExecution);
    const expiration = BackgroundTask.addExpirationListener(() => {
      setExpirations(value => value + 1);
    });

    return () => {
      unsubscribe();
      expiration.remove();
    };
  }, []);

  const inspect = () => action.run(async () => {
    const [available, status, isRegistered, tasks] = await Promise.all([
      TaskManager.isAvailableAsync(),
      BackgroundTask.getStatusAsync(),
      TaskManager.isTaskRegisteredAsync(BACKGROUND_TASK),
      TaskManager.getRegisteredTasksAsync(),
    ]);

    const options = isRegistered
      ? await TaskManager.getTaskOptionsAsync<BackgroundTask.BackgroundTaskOptions>(BACKGROUND_TASK)
      : null;
    const task = tasks.find(value => value.taskName === BACKGROUND_TASK) ?? null;

    setRegistered(isRegistered);

    return json({
      available,
      options,
      registered: isRegistered,
      status: backgroundTaskStatusLabel(status),
      taskType: task?.taskType ?? null,
    });
  });

  const register = () => action.run(async () => {
    await BackgroundTask.registerTaskAsync(BACKGROUND_TASK, BACKGROUND_TASK_OPTIONS);

    setRegistered(true);

    return `已注册 ${BACKGROUND_TASK}，最小间隔为不精确的 20 分钟。`;
  });

  const unregister = () => action.run(async () => {
    await BackgroundTask.unregisterTaskAsync(BACKGROUND_TASK);

    setRegistered(false);

    return `已取消注册 ${BACKGROUND_TASK}。`;
  });

  const trigger = () => action.run(async () => {
    const triggered = await BackgroundTask.triggerTaskWorkerForTestingAsync();
    const current = getBackgroundTaskExecution();

    return json({
      callbackCount: current?.count ?? 0,
      eventId: current?.eventId ?? null,
      triggered,
    });
  });

  return (
    <>
      <Panel eyebrow="原生状态" title="检查 BackgroundTask 与 TaskManager">
        <DataRow label="任务名" value={BACKGROUND_TASK} />
        <DataRow label="已注册" value={<Tag tone={registered ? 'success' : 'signal'}>{registered ? '是' : '否'}</Tag>} />
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="读取原生状态"
          onPress={() => void inspect()}
          testID="background-task-inspect"
        />
      </Panel>

      <Panel eyebrow="WORKSCHEDULER" title="注册新一代 Expo 后台任务">
        <ActionRow>
          <ActionButton
            disabled={registered || action.state.phase === 'running'}
            label="注册任务"
            onPress={() => void register()}
            testID="background-task-register"
          />
          <ActionButton
            disabled={!registered || action.state.phase === 'running'}
            label="取消注册"
            onPress={() => void unregister()}
            testID="background-task-unregister"
            tone="secondary"
          />
        </ActionRow>
        <Note>
          HarmonyOS 强制最小间隔 20 分钟，并可能出于功耗策略推迟周期任务。即使 JavaScript 运行时重启，注册信息与任务元数据也会保留。
        </Note>
      </Panel>

      <Panel eyebrow="调试执行" title="立即运行原生 worker">
        <ActionButton
          disabled={!registered || action.state.phase === 'running'}
          label="触发调试 worker"
          onPress={() => void trigger()}
          testID="background-task-trigger"
        />
        <DataRow label="回调次数" value={String(execution?.count ?? 0)} />
        <DataRow label="最近事件" value={execution?.eventId ?? '尚未观测到'} />
        <DataRow label="发生时间" value={execution?.occurredAt ?? '尚未观测到'} />
        <DataRow label="错误" value={execution?.error ?? '无'} />
        <DataRow label="过期事件数" value={String(expirations)} />
        <Note>
          触发 API 仅在 debug 构建中可用；常规周期执行仍由系统调度。
        </Note>
      </Panel>

      <ResultPanel state={action.state} />
    </>
  );
}

export function ModuleDemo({ id }: { id: ModuleId }) {
  switch (id) {
    case 'asset': return <AssetDemo />;
    case 'constants': return <ConstantsDemo />;
    case 'file-system': return <FileSystemDemo />;
    case 'font': return <FontDemo />;
    case 'keep-awake': return <KeepAwakeDemo />;
    case 'fetch': return <FetchDemo />;
    case 'linking': return <LinkingDemo />;
    case 'application': return <ApplicationDemo />;
    case 'system-ui': return <SystemUIDemo />;
    case 'splash-screen': return <SplashScreenDemo />;
    case 'linear-gradient': return <LinearGradientDemo />;
    case 'navigation-bar': return <NavigationBarDemo />;
    case 'sharing': return <SharingDemo />;
    case 'network': return <NetworkDemo />;
    case 'camera': return <CameraDemo />;
    case 'battery': return <BatteryDemo />;
    case 'background-fetch': return <BackgroundFetchDemo />;
    case 'background-task': return <BackgroundTaskDemo />;
    case 'haptics': return <HapticsDemo />;
    case 'app-metrics': return <AppMetricsDemo />;
    case 'audio': return <AudioDemo />;
  }

  return <AdditionalModuleDemo id={id} />;
}

const styles = StyleSheet.create({
  compactCode: { backgroundColor: palette.canvas, borderRadius: 4, color: palette.muted, fontFamily: 'monospace', fontSize: 10, lineHeight: 16, padding: 12 },
  fontSpecimen: { alignItems: 'center', flexDirection: 'row', gap: 14 },
  specimenCopy: { flex: 1, gap: 3 },
  specimenTitle: { color: palette.text, fontSize: 18, fontWeight: '700' },
  specimenCaption: { color: palette.muted, fontSize: 12, lineHeight: 17 },
  dynamicSpecimen: { alignItems: 'center', backgroundColor: palette.canvas, borderColor: palette.line, borderRadius: 4, borderWidth: 1, gap: 8, minHeight: 118, justifyContent: 'center' },
  dynamicGlyph: { color: palette.cyan, fontSize: 44 },
  switchRow: { alignItems: 'center', flexDirection: 'row', gap: 16, justifyContent: 'space-between' },
  switchCopy: { flex: 1, gap: 4 },
  switchTitle: { color: palette.text, fontSize: 16, fontWeight: '700' },
  switchCaption: { color: palette.muted, fontSize: 12, lineHeight: 18 },
  methodRow: { flexDirection: 'row', gap: 10 },
  gradientHero: { borderRadius: 18, gap: 10, minHeight: 210, overflow: 'hidden', padding: 22, justifyContent: 'flex-end' },
  gradientEyebrow: { color: '#111920', fontFamily: 'monospace', fontSize: 10, fontWeight: '800', letterSpacing: 1.8 },
  gradientTitle: { color: '#111920', fontSize: 28, fontWeight: '800', letterSpacing: -0.8, lineHeight: 31, maxWidth: 280 },
  gradientCopy: { color: '#243039', fontSize: 12, fontWeight: '600', lineHeight: 18, maxWidth: 300 },
  gradientDirection: { alignItems: 'center', borderRadius: 12, height: 124, justifyContent: 'center', overflow: 'hidden' },
  gradientDirectionText: { color: '#111920', fontFamily: 'monospace', fontSize: 13, fontWeight: '800', letterSpacing: 2 },
  gradientHardStop: { borderBottomRightRadius: 24, borderTopLeftRadius: 24, height: 92, justifyContent: 'center', overflow: 'hidden', paddingHorizontal: 18 },
  gradientHardStopText: { color: palette.text, fontFamily: 'monospace', fontSize: 11, fontWeight: '800', letterSpacing: 1.4, textAlign: 'center' },
  gradientPartial: { borderRadius: 12, height: 88, justifyContent: 'center', overflow: 'hidden', paddingHorizontal: 18 },
  gradientDegenerate: { borderRadius: 12, height: 72, justifyContent: 'center', overflow: 'hidden', paddingHorizontal: 18 },
  gradientEdgeText: { color: '#111920', fontFamily: 'monospace', fontSize: 10, fontWeight: '800', letterSpacing: 1.2, textAlign: 'center' },
  cameraFrame: { alignItems: 'center', backgroundColor: palette.canvas, borderColor: palette.lineStrong, borderRadius: 6, borderWidth: 1, height: 320, justifyContent: 'center', overflow: 'hidden' },
  cameraInactive: { color: palette.faint, fontFamily: 'monospace', fontSize: 11, fontWeight: '800', letterSpacing: 1.2 },
  cameraPreview: { height: '100%', width: '100%' },
});

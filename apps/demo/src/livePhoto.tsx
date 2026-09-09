import { Asset } from 'expo-asset';
import { Directory, File, Paths } from 'expo-file-system';
import { LivePhotoView } from 'expo-live-photo';
import type { ContentFit, LivePhotoAsset, LivePhotoViewType } from 'expo-live-photo';
import { useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import photoAsset from '../assets/live-photo/photo.jpg';
import videoAsset from '../assets/live-photo/video.mp4';
import { palette } from './theme';
import { ActionButton, ActionRow, DataRow, Field, Note, Panel, ResultPanel, Tag, useAsyncResult } from './ui';

const INITIAL_COUNTS = {
  onLoadStart: 0,
  onPreviewPhotoLoad: 0,
  onLoadComplete: 0,
  onLoadError: 0,
  onPlaybackStart: 0,
  onPlaybackStop: 0,
};

export function LivePhotoDemo() {
  const view = useRef<LivePhotoViewType>(null);
  const [source, setSource] = useState<LivePhotoAsset | null>(null);
  const [photo, setPhoto] = useState('');
  const [video, setVideo] = useState('');
  const [mounted, setMounted] = useState(true);
  const [muted, setMuted] = useState(true);
  const [fit, setFit] = useState<ContentFit>('contain');
  const [gesture, setGesture] = useState(true);
  const [status, setStatus] = useState('未加载');
  const [error, setError] = useState('');
  const [counts, setCounts] = useState(INITIAL_COUNTS);
  const [events, setEvents] = useState<string[]>([]);
  const action = useAsyncResult();
  const available = LivePhotoView.isAvailable();
  const busy = action.state.phase === 'running';

  const record = (event: keyof typeof INITIAL_COUNTS, status: string) => {
    setCounts(counts => ({ ...counts, [event]: counts[event] + 1 }));
    setEvents(events => [...events.slice(-11), event]);
    setStatus(status);
  };

  const load = (source: LivePhotoAsset | null) => {
    setError('');
    setStatus(source ? '等待加载' : '已清空');
    setMounted(true);
    setSource(source);
  };

  const sample = (special = false) => action.run(async () => {
    const [photo, video] = await Asset.loadAsync([photoAsset, videoAsset]);
    if (!photo?.localUri || !video?.localUri) throw new Error('样例尚未下载到应用沙箱。');

    let source = { photoUri: photo.localUri, pairedVideoUri: video.localUri };
    if (special) {
      const directory = new Directory(Paths.cache, 'expo-live-photo-demo');
      directory.create({ idempotent: true });
      const image = new File(directory, '实况 照片 100% #.jpg');
      const movie = new File(directory, '实况 视频 100% #.mp4');
      if (image.exists) image.delete();
      if (movie.exists) movie.delete();

      new File(photo.localUri).copy(image);
      new File(video.localUri).copy(movie);
      source = { photoUri: image.uri, pairedVideoUri: movie.uri };
    }

    setPhoto(source.photoUri);
    setVideo(source.pairedVideoUri);
    load(source);

    return `${special ? '特殊文件名' : '内置'}样例已准备，原生加载结果见状态与事件。`;
  });

  return (
    <>
      <Panel eyebrow="LivePhotoView" title="预览与播放">
        <DataRow label="设备支持" value={<Tag tone={available ? 'success' : 'danger'}>{String(available)}</Tag>} />
        <View style={styles.preview}>
          {available && mounted
            ? (
                <LivePhotoView
                  ref={view}
                  contentFit={fit}
                  isMuted={muted}
                  onLoadComplete={() => record('onLoadComplete', '可播放')}
                  onLoadError={(error) => {
                    record('onLoadError', '加载失败');
                    setError(error.message);
                  }}
                  onLoadStart={() => record('onLoadStart', '加载中')}
                  onPlaybackStart={() => record('onPlaybackStart', '播放中')}
                  onPlaybackStop={() => record('onPlaybackStop', '已停止')}
                  onPreviewPhotoLoad={() => record('onPreviewPhotoLoad', '预览已加载')}
                  source={source}
                  style={StyleSheet.absoluteFill}
                  testID="live-photo-view"
                  useDefaultGestureRecognizer={gesture}
                />
              )
            : <Text style={styles.placeholder}>{mounted ? '设备不支持实况照片' : '组件已卸载'}</Text>}
        </View>
        <DataRow label="状态" value={status} />
        <ActionRow>
          <ActionButton disabled={!available || busy} label="加载样例" onPress={() => void sample()} testID="live-photo-load" />
          <ActionButton disabled={!available || busy} label="特殊文件名" onPress={() => void sample(true)} testID="live-photo-special" tone="secondary" />
          <ActionButton disabled={busy} label="清空" onPress={() => load(null)} testID="live-photo-clear" tone="secondary" />
        </ActionRow>
        <ActionRow>
          <ActionButton disabled={!available || !mounted} label="播放 full" onPress={() => view.current?.startPlayback()} testID="live-photo-play" />
          <ActionButton disabled={!available || !mounted} label="播放 hint" onPress={() => view.current?.startPlayback('hint')} testID="live-photo-hint" tone="secondary" />
          <ActionButton label="停止" onPress={() => view.current?.stopPlayback()} testID="live-photo-stop" tone="secondary" />
        </ActionRow>
        <Note>内置样例为 3 秒彩色测试图及低音量提示音，用于验证 HarmonyOS 播放；不包含 Apple Live Photo 配对元数据。长按画面可测试默认手势。</Note>
      </Panel>

      <ResultPanel state={action.state} />
      <ResultPanel state={error ? { phase: 'error', output: error } : { phase: 'idle' }} />

      <Panel eyebrow="Properties" title="显示属性与生命周期">
        <ActionRow>
          <ActionButton label={`静音：${muted ? '开' : '关'}`} onPress={() => setMuted(value => !value)} testID="live-photo-mute" tone="secondary" />
          <ActionButton label={`填充：${fit}`} onPress={() => setFit(value => value === 'contain' ? 'cover' : 'contain')} testID="live-photo-fit" tone="secondary" />
          <ActionButton label={`长按：${gesture ? '开' : '关'}`} onPress={() => setGesture(value => !value)} testID="live-photo-gesture" tone="secondary" />
          <ActionButton
            disabled={busy}
            label={mounted ? '卸载组件' : '挂载组件'}
            onPress={() => {
              setMounted(value => !value);
              setStatus(mounted ? '已卸载' : '等待加载');
            }}
            testID="live-photo-mount"
            tone="secondary"
          />
        </ActionRow>
        <Note>HarmonyOS 的 hint 使用完整播放。更改静音或长按开关会重建系统组件并停止当前播放；填充模式变化会重新加载资源。</Note>
      </Panel>

      <Panel eyebrow="Events" title="事件记录">
        {Object.entries(counts).map(([event, count]) => <DataRow key={event} label={event} value={String(count)} />)}
        <Text selectable style={styles.events} testID="live-photo-events">{events.join(' → ') || '尚未收到事件'}</Text>
        <ActionButton
          label="清除记录"
          onPress={() => {
            setCounts(INITIAL_COUNTS);
            setEvents([]);
          }}
          testID="live-photo-reset-events"
          tone="secondary"
        />
      </Panel>

      <Panel eyebrow="Source" title="自定义资源与错误恢复">
        <Field label="photoUri" onChangeText={setPhoto} placeholder="file:///…/photo.jpg" value={photo} testID="live-photo-photo-uri" />
        <Field label="pairedVideoUri" onChangeText={setVideo} placeholder="file:///…/video.mp4" value={video} testID="live-photo-video-uri" />
        <ActionRow>
          <ActionButton disabled={!available || busy} label="加载输入" onPress={() => load({ photoUri: photo, pairedVideoUri: video })} testID="live-photo-custom" />
          <ActionButton disabled={!available || busy} label="空图片 URI" onPress={() => load({ photoUri: '', pairedVideoUri: video })} testID="live-photo-empty" tone="secondary" />
          <ActionButton disabled={!available || busy} label="网络 URI" onPress={() => load({ photoUri: 'https://example.invalid/photo.jpg', pairedVideoUri: video })} testID="live-photo-network" tone="secondary" />
          <ActionButton disabled={!available || busy || !photo || !video} label="不存在的文件" onPress={() => load({ photoUri: `${photo}.missing`, pairedVideoUri: video })} testID="live-photo-missing" tone="secondary" />
        </ActionRow>
        <Note>非法资源应触发 onLoadError，且不触发 onLoadComplete；再次加载有效样例应恢复。特殊文件名覆盖空格、中文、百分号与井号。自定义资源须为应用可读的本地图片与视频文件。</Note>
      </Panel>
    </>
  );
}

const styles = StyleSheet.create({
  preview: { alignItems: 'center', backgroundColor: palette.canvas, height: 220, justifyContent: 'center', overflow: 'hidden' },
  placeholder: { color: palette.muted, fontSize: 13 },
  events: { color: palette.muted, fontFamily: 'monospace', fontSize: 11, lineHeight: 18 },
});

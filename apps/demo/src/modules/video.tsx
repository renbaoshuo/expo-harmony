/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { useEvent, useEventListener } from 'expo';
import { Asset } from 'expo-asset';
import { Image } from 'expo-image';
import {
  clearVideoCacheAsync,
  createVideoPlayer,
  getCurrentVideoCacheSize,
  isPictureInPictureSupported,
  setVideoCacheSizeAsync,
  useVideoPlayer,
  VideoAirPlayButton,
  VideoView,
} from 'expo-video';
import type {
  AudioMixingMode,
  BufferOptions,
  ButtonOptions,
  PlayerBuilderOptions,
  ScrubbingModeOptions,
  VideoContentFit,
  VideoPlayer,
  VideoPlayerEvents,
  VideoSource,
  VideoSourceObject,
  VideoThumbnail,
  VideoThumbnailOptions,
  VideoViewProps,
} from 'expo-video';
import { useEffect, useRef, useState } from 'react';
import { Platform, processColor, StyleSheet } from 'react-native';

import sample from '../../assets/live-photo/video.mp4';
import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const harmony = String(Platform.OS) === 'harmony';
const web = Platform.OS === 'web';
const ios = Platform.OS === 'ios';
const android = Platform.OS === 'android';
const playerEvents: (keyof VideoPlayerEvents)[] = [
  'statusChange', 'playingChange', 'playbackRateChange', 'volumeChange', 'mutedChange', 'playToEnd',
  'timeUpdate', 'sourceChange', 'sourceLoad', 'availableSubtitleTracksChange', 'subtitleTrackChange',
  'availableAudioTracksChange', 'audioTrackChange', 'videoTrackChange',
  ...(ios ? ['isExternalPlaybackActiveChange' as const] : []),
];
const viewButtons: readonly (readonly [keyof ButtonOptions, string, boolean])[] = [
  ['showPlayPause', '播放与暂停按钮', true],
  ['showSeekBackward', '后退按钮', true],
  ['showSeekForward', '前进按钮', true],
  ['showBottomBar', '底部控制栏', true],
  ...(android
    ? [
        ['showNext', '下一集按钮', false],
        ['showPrevious', '上一集按钮', false],
        ['showSubtitles', '字幕按钮', false],
        ['showSettings', '设置按钮', true],
      ] as const
    : []),
];

type FullscreenOptions = NonNullable<VideoViewProps['fullscreenOptions']>;
const orientations = [
  'default', 'portrait', 'portraitUp', 'portraitDown', 'landscape', 'landscapeLeft', 'landscapeRight',
] as const satisfies readonly NonNullable<FullscreenOptions['orientation']>[];
const afterPiP: readonly [NonNullable<FullscreenOptions['keepFullscreenOnPiPStop']>, string][] = [
  ['always', '总是返回全屏'],
  ['autoEnter', '自动画中画结束后返回全屏'],
  ['never', '结束画中画后退出全屏'],
];

function readNumber(value: string, label: string, min = -Infinity, max = Infinity) {
  const number = Number(value);
  if (!value.trim() || !Number.isFinite(number)) throw new Error(`${label}需要填写数字。`);
  if (number < min || number > max) throw new Error(`${label}超出取值范围。`);
  return number;
}

function toggleLabel(label: string, enabled: boolean) {
  return `${enabled ? '关闭' : '开启'}${label}`;
}

type BuilderProps = { source: VideoSource; options: PlayerBuilderOptions };

function HookPlayer({ source, options }: BuilderProps) {
  const player = useVideoPlayer(source, (instance) => {
    instance.muted = true;
    if (!web) instance.timeUpdateEventInterval = 0.25;
  }, options);

  useEffect(() => {
    if (!web) return;
    player.timeUpdateEventInterval = 0.25;
    return () => {
      player.timeUpdateEventInterval = 0;
    };
  }, [player]);

  return <PlayerDemo player={player} />;
}

function DirectPlayer({ source, options }: BuilderProps) {
  const [player, setPlayer] = useState<VideoPlayer | null>(null);
  const { run, state } = useAsyncResult();

  useEffect(() => {
    let instance: VideoPlayer | undefined;
    void run(() => {
      instance = createVideoPlayer(source, options);
      instance.muted = true;
      instance.timeUpdateEventInterval = 0.25;
      setPlayer(instance);
      return '';
    });

    return () => {
      if (!instance) return;
      if (web) instance.timeUpdateEventInterval = 0;
      instance.release();
    };
  }, [run, options, source]);

  return player ? <PlayerDemo player={player} /> : <ResultPanel state={state} />;
}

export function VideoDemo() {
  const [kind, setKind] = useState<'hook' | 'direct' | null>('hook');
  const [seekBackward, setSeekBackward] = useState('10');
  const [seekForward, setSeekForward] = useState('10');
  const [options, setOptions] = useState<PlayerBuilderOptions>({});
  const [source, setSource] = useState<VideoSource>(sample);
  const [initialSample, setInitialSample] = useState(true);
  const [cacheSize, setCacheSize] = useState('104857600');
  const action = useAsyncResult();
  const cache = useAsyncResult();
  const busy = action.state.phase === 'running';

  function create(nextKind: 'hook' | 'direct') {
    void action.run(() => {
      setOptions(harmony || android
        ? {
            seekBackwardIncrement: readNumber(seekBackward, '后退步长', 0.001, 999),
            seekForwardIncrement: readNumber(seekForward, '前进步长', 0.001, 999),
          }
        : {});
      setSource(initialSample ? sample : null);
      setKind(nextKind);
      return '';
    });
  }

  return (
    <>
      {kind === 'hook' ? <HookPlayer options={options} source={source} /> : null}
      {kind === 'direct' ? <DirectPlayer options={options} source={source} /> : null}
      <Panel title="创建与释放播放器">
        {kind
          ? (
              <ActionButton
                label={kind === 'direct' ? '释放播放器（release）' : '卸载播放器（useVideoPlayer）'}
                onPress={() => {
                  action.clear();
                  setKind(null);
                }}
                tone="secondary"
              />
            )
          : (
              <>
                {harmony || android
                  ? (
                      <>
                        <Field label="后退步长（秒）" value={seekBackward} onChangeText={setSeekBackward} keyboardType="decimal-pad" />
                        <Field label="前进步长（秒）" value={seekForward} onChangeText={setSeekForward} keyboardType="decimal-pad" />
                      </>
                    )
                  : null}
                <ActionRow>
                  <ActionButton
                    label={initialSample ? '初始视频使用样例' : '初始视频留空'}
                    onPress={() => setInitialSample(value => !value)}
                    tone="secondary"
                  />
                  <ActionButton label="useVideoPlayer" disabled={busy} onPress={() => create('hook')} />
                  <ActionButton label="createVideoPlayer" disabled={busy} onPress={() => create('direct')} />
                </ActionRow>
                {action.state.phase === 'error' ? <ResultPanel state={action.state} /> : null}
              </>
            )}
      </Panel>
      {!web
        ? (
            <Panel title="视频缓存">
              {!harmony
                ? (
                    <Field label="缓存容量（字节）" value={cacheSize} onChangeText={setCacheSize} keyboardType="number-pad" />
                  )
                : null}
              <ActionRow>
                <ActionButton
                  disabled={cache.state.phase === 'running'}
                  label="读取缓存大小"
                  onPress={() => void cache.run(() => `${getCurrentVideoCacheSize()} B`)}
                />
                <ActionButton
                  disabled={cache.state.phase === 'running' || kind !== null}
                  label="清空缓存"
                  onPress={() => void cache.run(async () => {
                    await clearVideoCacheAsync();
                    return '缓存已清空';
                  })}
                  tone="secondary"
                />
                {!harmony
                  ? (
                      <ActionButton
                        disabled={cache.state.phase === 'running' || kind !== null}
                        label="设置缓存容量"
                        onPress={() => void cache.run(async () => {
                          await setVideoCacheSizeAsync(readNumber(cacheSize, '缓存容量', 0));
                          return '缓存容量已更新';
                        })}
                        tone="secondary"
                      />
                    )
                  : null}
              </ActionRow>
              <ResultPanel state={cache.state} />
            </Panel>
          )
        : null}
    </>
  );
}

function PlaybackStatus({ player }: { player: VideoPlayer }) {
  const time = useEvent(player, 'timeUpdate', {
    currentTime: player.currentTime,
    currentLiveTimestamp: player.currentLiveTimestamp,
    currentOffsetFromLive: player.currentOffsetFromLive,
    bufferedPosition: player.bufferedPosition,
  });

  return (
    <>
      <DataRow label="播放位置" value={`${time.currentTime.toFixed(2)} 秒`} />
      <DataRow label="视频时长" value={`${player.duration.toFixed(2)} 秒`} />
      <DataRow label="缓冲位置" value={`${time.bufferedPosition.toFixed(2)} 秒`} />
      <DataRow label="直播" value={player.isLive ? '是' : '否'} />
      {player.isLive
        ? (
            <>
              <DataRow label="直播时间戳" value={String(time.currentLiveTimestamp)} />
              <DataRow label="直播延迟" value={String(time.currentOffsetFromLive)} />
            </>
          )
        : null}
    </>
  );
}

function PlayerDemo({ player }: { player: VideoPlayer }) {
  const { status, error } = useEvent(player, 'statusChange', { status: player.status });
  const { isPlaying } = useEvent(player, 'playingChange', { isPlaying: player.playing });
  const [fit, setFit] = useState<VideoContentFit>('contain');
  const [controls, setControls] = useState(true);
  const [timecodes, setTimecodes] = useState(true);
  const [linear, setLinear] = useState(false);
  const [fullscreenOptions, setFullscreenOptions] = useState<FullscreenOptions>({ enable: true });
  const [exitWhenFinished, setExitWhenFinished] = useState(false);
  const [surfaceType, setSurfaceType] = useState<VideoViewProps['surfaceType']>('surfaceView');
  const [useExoShutter, setUseExoShutter] = useState(false);
  const [allowsVideoFrameAnalysis, setAllowsVideoFrameAnalysis] = useState(true);
  const [playsInline, setPlaysInline] = useState(true);
  const [crossOrigin, setCrossOrigin] = useState<VideoViewProps['crossOrigin']>();
  const [useAudioNodePlayback, setUseAudioNodePlayback] = useState(false);
  const [buttons, setButtons] = useState<ButtonOptions>({});
  const [dx, setDx] = useState('0');
  const [dy, setDy] = useState('0');
  const [position, setPosition] = useState({ dx: 0, dy: 0 });
  const [fullscreen, setFullscreen] = useState(false);
  const [pictureInPicture, setPictureInPicture] = useState(false);
  const [allowPiP, setAllowPiP] = useState(isPictureInPictureSupported);
  const [automaticPiP, setAutomaticPiP] = useState(false);
  const [frames, setFrames] = useState(0);
  const view = useRef<VideoView>(null);
  const playback = useAsyncResult();
  const action = useAsyncResult();
  const positionAction = useAsyncResult();
  const supportsPiP = isPictureInPictureSupported();
  const ready = status === 'readyToPlay';

  function invoke(operation: () => void | Promise<void>, message: string) {
    void action.run(async () => {
      await operation();
      return message;
    });
  }

  useEventListener(player, 'playToEnd', () => {
    if (fullscreen && exitWhenFinished) invoke(() => view.current?.exitFullscreen(), '已退出全屏');
  });

  return (
    <>
      <Panel title="视频预览">
        <VideoView
          key={web ? String(useAudioNodePlayback) : surfaceType}
          ref={view}
          player={player}
          surfaceType={android ? surfaceType : undefined}
          useExoShutter={android ? useExoShutter : undefined}
          allowsVideoFrameAnalysis={ios ? allowsVideoFrameAnalysis : undefined}
          playsInline={web ? playsInline : undefined}
          crossOrigin={web ? crossOrigin : undefined}
          useAudioNodePlayback={web ? useAudioNodePlayback : undefined}
          style={styles.preview}
          nativeControls={controls}
          contentFit={fit}
          contentPosition={position}
          showsTimecodes={timecodes}
          requiresLinearPlayback={linear}
          fullscreenOptions={fullscreenOptions}
          buttonOptions={buttons}
          allowsPictureInPicture={allowPiP}
          startsPictureInPictureAutomatically={allowPiP && automaticPiP}
          onFirstFrameRender={() => setFrames(value => value + 1)}
          onFullscreenEnter={() => setFullscreen(true)}
          onFullscreenExit={() => setFullscreen(false)}
          onPictureInPictureStart={() => setPictureInPicture(true)}
          onPictureInPictureStop={() => setPictureInPicture(false)}
          testID="video-view"
        />
        <DataRow label="状态" value={status} />
        <DataRow label="onFirstFrameRender" value={frames} />
        {error ? <ResultPanel state={{ phase: 'error', output: error.message }} /> : null}
        <ActionRow>
          <ActionButton
            label={isPlaying ? '暂停' : '播放'}
            disabled={!ready && !isPlaying}
            onPress={() => void playback.run(() => {
              if (isPlaying) player.pause();
              else player.play();
              return '';
            })}
            testID="video-play"
          />
          <ActionButton
            label="从头播放"
            disabled={!ready}
            onPress={() => void playback.run(() => {
              player.replay();
              return '';
            })}
            testID="video-replay"
            tone="secondary"
          />
        </ActionRow>
        <PlaybackStatus player={player} />
        {playback.state.phase === 'error' ? <ResultPanel state={playback.state} /> : null}
      </Panel>

      <VideoSourcePanel player={player} idle={status === 'idle'} />
      <VideoPlaybackOptions player={player} ready={ready} />
      {ios || android ? <SeekingOptions player={player} /> : null}
      {!web ? <VideoTracks player={player} /> : null}

      <Panel title="画面与控制栏">
        <ActionRow>
          {(['contain', 'cover', 'fill'] as const).map(value => (
            <ActionButton key={value} label={value} tone={fit === value ? 'primary' : 'secondary'} onPress={() => setFit(value)} />
          ))}
        </ActionRow>
        {(harmony || Platform.OS === 'ios')
          ? (
              <>
                <Field label="水平偏移 dx" value={dx} onChangeText={setDx} keyboardType="numbers-and-punctuation" />
                <Field label="垂直偏移 dy" value={dy} onChangeText={setDy} keyboardType="numbers-and-punctuation" />
                <ActionButton
                  label="应用画面偏移"
                  tone="secondary"
                  onPress={() => void positionAction.run(() => {
                    const nextPosition = { dx: readNumber(dx, '水平偏移'), dy: readNumber(dy, '垂直偏移') };
                    setPosition(nextPosition);
                    return json(nextPosition);
                  })}
                />
              </>
            )
          : null}
        <ActionRow>
          <ActionButton label={controls ? '隐藏控制栏' : '显示控制栏'} onPress={() => setControls(value => !value)} tone="secondary" />
          {!web
            ? (
                <ActionButton label={toggleLabel('顺序播放', linear)} onPress={() => setLinear(value => !value)} tone="secondary" />
              )
            : null}
          {harmony || Platform.OS === 'ios'
            ? (
                <ActionButton label={timecodes ? '隐藏时间' : '显示时间'} onPress={() => setTimecodes(value => !value)} tone="secondary" />
              )
            : null}
          {harmony || android
            ? viewButtons.map(([key, label, defaultValue]) => {
                const visible = buttons[key] ?? defaultValue;
                return (
                  <ActionButton
                    key={key}
                    label={`${visible ? '隐藏' : '显示'}${label}`}
                    onPress={() => setButtons(value => ({ ...value, [key]: !visible }))}
                    tone="secondary"
                  />
                );
              })
            : null}
          {android
            ? (
                <>
                  <ActionButton
                    label={`渲染表面 ${surfaceType}`}
                    onPress={() => setSurfaceType(value => value === 'surfaceView' ? 'textureView' : 'surfaceView')}
                    tone="secondary"
                  />
                  <ActionButton
                    label={toggleLabel('ExoPlayer 快门遮罩', useExoShutter)}
                    onPress={() => setUseExoShutter(value => !value)}
                    tone="secondary"
                  />
                </>
              )
            : null}
          {ios
            ? (
                <ActionButton
                  label={toggleLabel('视频帧分析', allowsVideoFrameAnalysis)}
                  onPress={() => setAllowsVideoFrameAnalysis(value => !value)}
                  tone="secondary"
                />
              )
            : null}
          {web
            ? (
                <>
                  <ActionButton label={toggleLabel('行内播放', playsInline)} onPress={() => setPlaysInline(value => !value)} tone="secondary" />
                  <ActionButton
                    label={toggleLabel('Web Audio 播放', useAudioNodePlayback)}
                    onPress={() => setUseAudioNodePlayback(value => !value)}
                    tone="secondary"
                  />
                  {([undefined, 'anonymous', 'use-credentials'] as const).map(value => (
                    <ActionButton
                      key={value ?? 'default'}
                      label={value ?? '默认跨域设置'}
                      onPress={() => setCrossOrigin(value)}
                      tone={crossOrigin === value ? 'primary' : 'secondary'}
                    />
                  ))}
                </>
              )
            : null}
        </ActionRow>
        <ResultPanel state={positionAction.state} />
      </Panel>

      <Panel title="全屏与画中画">
        <DataRow label="全屏" value={fullscreen ? '开启' : '关闭'} />
        <DataRow label="画中画" value={supportsPiP ? (pictureInPicture ? '开启' : '关闭') : '不可用'} />
        <ActionRow>
          <ActionButton label={toggleLabel('全屏入口', fullscreenOptions.enable)} onPress={() => setFullscreenOptions(value => ({ ...value, enable: !value.enable }))} tone="secondary" />
          <ActionButton
            label={fullscreen ? '退出全屏' : '进入全屏'}
            disabled={action.state.phase === 'running' || (!fullscreen && !fullscreenOptions.enable)}
            onPress={() => invoke(
              () => fullscreen ? view.current?.exitFullscreen() : view.current?.enterFullscreen(),
              fullscreen ? '已退出全屏' : '已进入全屏'
            )}
            testID="video-fullscreen"
          />
          <ActionButton
            label={toggleLabel('播完退出全屏', exitWhenFinished)}
            onPress={() => setExitWhenFinished(value => !value)}
            tone="secondary"
          />
          {supportsPiP
            ? (
                <>
                  <ActionButton label={toggleLabel('画中画入口', allowPiP)} onPress={() => setAllowPiP(value => !value)} tone="secondary" />
                  {!web
                    ? (
                        <ActionButton
                          label={toggleLabel('自动画中画', automaticPiP)}
                          disabled={!allowPiP}
                          onPress={() => setAutomaticPiP(value => !value)}
                          tone="secondary"
                        />
                      )
                    : null}
                  <ActionButton
                    label={pictureInPicture ? '退出画中画' : '进入画中画'}
                    disabled={action.state.phase === 'running' || (!pictureInPicture && (!allowPiP || !ready || frames === 0))}
                    onPress={() => invoke(
                      () => pictureInPicture
                        ? view.current?.stopPictureInPicture()
                        : view.current?.startPictureInPicture(),
                      pictureInPicture ? '已退出画中画' : '已进入画中画'
                    )}
                    testID="video-picture-in-picture"
                  />
                </>
              )
            : null}
        </ActionRow>
        {android || ios
          ? (
              <ActionRow>
                {orientations.map(value => (
                  <ActionButton
                    key={value}
                    label={value}
                    onPress={() => setFullscreenOptions(options => ({ ...options, orientation: value }))}
                    tone={(fullscreenOptions.orientation ?? 'default') === value ? 'primary' : 'secondary'}
                  />
                ))}
                <ActionButton
                  label={toggleLabel('旋转时退出全屏', fullscreenOptions.autoExitOnRotate ?? false)}
                  onPress={() => setFullscreenOptions(options => ({
                    ...options,
                    autoExitOnRotate: !options.autoExitOnRotate,
                  }))}
                  tone="secondary"
                />
              </ActionRow>
            )
          : null}
        {ios && supportsPiP
          ? (
              <ActionRow>
                {afterPiP.map(([value, label]) => (
                  <ActionButton
                    key={value}
                    label={label}
                    onPress={() => setFullscreenOptions(options => ({ ...options, keepFullscreenOnPiPStop: value }))}
                    tone={(fullscreenOptions.keepFullscreenOnPiPStop ?? 'autoEnter') === value ? 'primary' : 'secondary'}
                  />
                ))}
              </ActionRow>
            )
          : null}
        <ResultPanel state={action.state} />
      </Panel>

      {!web ? <VideoThumbnails player={player} ready={ready} /> : null}
      {ios ? <AirPlayPanel player={player} /> : null}
      <VideoEvents player={player} />
    </>
  );
}

function VideoSourcePanel({ player, idle }: { player: VideoPlayer; idle: boolean }) {
  const [source, setSource] = useState('');
  const [headers, setHeaders] = useState('{}');
  const [title, setTitle] = useState('Expo Harmony 视频');
  const [artist, setArtist] = useState('Demo');
  const [artwork, setArtwork] = useState('');
  const [contentType, setContentType] = useState<VideoSourceObject['contentType']>('auto');
  const [buffer, setBuffer] = useState(() => json({
    preferredForwardBufferDuration: android ? 20 : 0,
    ...(android ? { minBufferForPlayback: 2, maxBufferBytes: 0, prioritizeTimeOverSizeThreshold: false } : {}),
    ...(ios ? { waitsToMinimizeStalling: true } : {}),
  } satisfies BufferOptions));
  const [suppressWarning, setSuppressWarning] = useState(true);
  const [useCaching, setUseCaching] = useState(false);
  const [drm, setDRM] = useState(() => json({
    type: ios ? 'fairplay' : 'widevine',
    licenseServer: '',
    headers: {},
    ...(android ? { multiKey: false } : {}),
    ...(ios ? { contentId: '', certificateUrl: '', base64CertificateData: '' } : {}),
  } satisfies NonNullable<VideoSourceObject['drm']>));
  const [enableDRM, setEnableDRM] = useState(false);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  function sourceOptions(): VideoSourceObject {
    return {
      headers: JSON.parse(headers),
      metadata: { title, artist, artwork: artwork || undefined },
      contentType,
      useCaching: ios || android ? useCaching : undefined,
    };
  }

  function customSource(): VideoSourceObject {
    return { ...sourceOptions(), uri: source, drm: enableDRM ? JSON.parse(drm) : undefined };
  }

  return (
    <Panel title="视频来源">
      <ActionRow>
        <ActionButton
          label="加载内置视频"
          disabled={busy}
          onPress={() => void action.run(async () => {
            await player.replaceAsync({ ...sourceOptions(), assetId: sample, contentType: 'auto' });
            return '已载入内置视频';
          })}
          testID="video-load"
        />
        <ActionButton
          label="加载本地样例"
          disabled={busy}
          onPress={() => void action.run(async () => {
            const asset = await Asset.fromModule(sample).downloadAsync();
            if (!asset.localUri) throw new Error('样例未下载到本地。');
            setSource(asset.localUri);
            await player.replaceAsync({ ...sourceOptions(), uri: asset.localUri, contentType: 'auto' });
            return asset.localUri;
          })}
          tone="secondary"
        />
        <ActionButton
          label="清空视频"
          disabled={busy || idle}
          onPress={() => void action.run(async () => {
            await player.replaceAsync(null);
            return '已清空视频';
          })}
          tone="secondary"
        />
      </ActionRow>
      <Field label="视频 URI" value={source} onChangeText={setSource} placeholder="https://… 或 file:///…" testID="video-source" />
      {!web ? <Field label="HTTP 请求头（JSON）" value={headers} onChangeText={setHeaders} testID="video-headers" /> : null}
      {!web
        ? (
            <>
              <Field label="媒体标题" value={title} onChangeText={setTitle} />
              <Field label="作者" value={artist} onChangeText={setArtist} />
              <Field label="封面 URI" value={artwork} onChangeText={setArtwork} />
            </>
          )
        : null}
      {!web
        ? (
            <ActionRow>
              {(['auto', 'hls', ...(ios || android ? ['progressive' as const] : []),
                ...(android ? ['dash' as const, 'smoothStreaming' as const] : [])] as const).map(value => (
                <ActionButton
                  key={value}
                  label={value === 'auto' ? '自动识别格式' : value}
                  onPress={() => setContentType(value)}
                  tone={contentType === value ? 'primary' : 'secondary'}
                />
              ))}
              {ios || android
                ? (
                    <ActionButton label={toggleLabel('缓存视频', useCaching)} onPress={() => setUseCaching(value => !value)} tone="secondary" />
                  )
                : null}
            </ActionRow>
          )
        : null}
      {ios || android
        ? (
            <>
              <ActionButton label={toggleLabel('DRM 配置', enableDRM)} onPress={() => setEnableDRM(value => !value)} tone="secondary" />
              {enableDRM ? <Field label="DRM 配置（JSON）" value={drm} onChangeText={setDRM} multiline /> : null}
            </>
          )
        : null}
      <ActionRow>
        <ActionButton
          label="异步换源（replaceAsync）"
          disabled={busy || !source}
          onPress={() => void action.run(async () => {
            await player.replaceAsync(customSource());
            return source;
          })}
          testID="video-custom"
        />
        <ActionButton
          label="换源（replace）"
          disabled={busy || !source}
          onPress={() => void action.run(() => {
            player.replace(customSource(), suppressWarning);
            return source;
          })}
          tone="secondary"
        />
        {!web
          ? (
              <ActionButton
                label={suppressWarning ? '显示换源警告' : '隐藏换源警告'}
                onPress={() => setSuppressWarning(value => !value)}
                tone="secondary"
              />
            )
          : null}
      </ActionRow>
      {!web
        ? (
            <>
              <Field label="bufferOptions（JSON）" value={buffer} onChangeText={setBuffer} multiline />
              <ActionButton
                label="设置缓冲参数"
                disabled={busy || (harmony && !idle)}
                onPress={() => void action.run(() => {
                  player.bufferOptions = JSON.parse(buffer);
                  return json(player.bufferOptions);
                })}
                tone="secondary"
              />
            </>
          )
        : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

const playerToggles = [
  ['muted', '静音'],
  ['loop', '循环'],
  ...(!harmony ? [['preservesPitch', '音高修正']] as const : []),
  ...(!web
    ? [
        ['keepScreenOnWhilePlaying', '屏幕常亮'],
        ['staysActiveInBackground', '后台播放'],
        ['showNowPlayingNotification', '系统媒体控制'],
      ] as const
    : []),
] as const;

function VideoPlaybackOptions({ player, ready }: { player: VideoPlayer; ready: boolean }) {
  const [seek, setSeek] = useState('1');
  const [volume, setVolume] = useState('0.5');
  const [rate, setRate] = useState('1.5');
  const [interval, setInterval] = useState('0.25');
  const action = useAsyncResult();

  function apply(operation: () => unknown) {
    void action.run(() => json(operation()));
  }

  return (
    <Panel title="播放参数">
      <Field label="跳转秒数" value={seek} onChangeText={setSeek} keyboardType="numbers-and-punctuation" />
      <ActionRow>
        <ActionButton
          label="跳转到指定位置"
          disabled={!ready || player.isLive}
          onPress={() => apply(() => {
            const currentTime = readNumber(seek, '跳转秒数', 0);
            player.currentTime = currentTime;
            return { currentTime };
          })}
        />
        <ActionButton
          label="相对当前位置跳转"
          disabled={!ready || player.isLive}
          onPress={() => apply(() => {
            const seconds = readNumber(seek, '跳转秒数');
            player.seekBy(seconds);
            return { seconds };
          })}
          tone="secondary"
        />
      </ActionRow>
      <Field label="音量（0 至 1）" value={volume} onChangeText={setVolume} keyboardType="decimal-pad" />
      <ActionButton label="设置音量" onPress={() => apply(() => ({ volume: player.volume = readNumber(volume, '音量', 0, 1) }))} tone="secondary" />
      <Field label="播放倍速" value={rate} onChangeText={setRate} keyboardType="decimal-pad" />
      <ActionButton
        label="设置倍速"
        disabled={player.isLive}
        onPress={() => apply(() => ({ playbackRate: player.playbackRate = readNumber(rate, '播放倍速', 0.125, harmony ? 4 : 16) }))}
        tone="secondary"
      />
      <Field label="进度事件间隔（秒）" value={interval} onChangeText={setInterval} keyboardType="decimal-pad" />
      <ActionButton
        label="设置事件间隔"
        onPress={() => apply(() => ({ timeUpdateEventInterval: player.timeUpdateEventInterval = readNumber(interval, '事件间隔', 0) }))}
        tone="secondary"
      />
      <ActionRow>
        {playerToggles.map(([key, label]) => (
          <ActionButton
            key={key}
            label={toggleLabel(label, player[key])}
            disabled={key === 'loop' && player.isLive}
            onPress={() => apply(() => {
              player[key] = !player[key];
              return { [key]: player[key] };
            })}
            tone="secondary"
          />
        ))}
      </ActionRow>
      {!web
        ? (
            <ActionRow>
              {([
                ['自动混音', 'auto'],
                ['与其他音频混音', 'mixWithOthers'],
                ['降低其他音频音量', 'duckOthers'],
                ['独占音频', 'doNotMix'],
              ] as const satisfies readonly [string, AudioMixingMode][]).map(([label, value]) => (
                <ActionButton key={value} label={label} onPress={() => apply(() => ({ audioMixingMode: player.audioMixingMode = value }))} tone={player.audioMixingMode === value ? 'primary' : 'secondary'} />
              ))}
            </ActionRow>
          )
        : null}
      {harmony ? <DataRow label="音高修正" value={player.preservesPitch ? '开启' : '关闭'} /> : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function SeekingOptions({ player }: { player: VideoPlayer }) {
  const [before, setBefore] = useState('0');
  const [after, setAfter] = useState('0');
  const [liveOffset, setLiveOffset] = useState('0');
  const [scrubbing, setScrubbing] = useState(() => json({
    scrubbingModeEnabled: false,
    ...(android
      ? {
          increaseCodecOperatingRate: true,
          enableDynamicScheduling: true,
          useDecodeOnlyFlag: true,
          allowSkippingMediaCodecFlush: true,
        }
      : {}),
  } satisfies ScrubbingModeOptions));
  const action = useAsyncResult();

  return (
    <Panel title="跳转精度与拖动进度">
      <Field label="允许提前（秒）" value={before} onChangeText={setBefore} keyboardType="decimal-pad" />
      <Field label="允许延后（秒）" value={after} onChangeText={setAfter} keyboardType="decimal-pad" />
      <ActionButton
        label="设置跳转容差"
        onPress={() => void action.run(() => {
          player.seekTolerance = {
            toleranceBefore: readNumber(before, '允许提前', 0),
            toleranceAfter: readNumber(after, '允许延后', 0),
          };
          return json(player.seekTolerance);
        })}
        tone="secondary"
      />
      <Field label="scrubbingModeOptions（JSON）" value={scrubbing} onChangeText={setScrubbing} multiline />
      <ActionButton
        label="应用拖动进度设置"
        onPress={() => void action.run(() => {
          player.scrubbingModeOptions = JSON.parse(scrubbing);
          return json(player.scrubbingModeOptions);
        })}
        tone="secondary"
      />
      {ios
        ? (
            <>
              <Field label="目标直播延迟（秒）" value={liveOffset} onChangeText={setLiveOffset} keyboardType="decimal-pad" />
              <ActionButton
                label="设置目标直播延迟"
                onPress={() => void action.run(() => {
                  player.targetOffsetFromLive = readNumber(liveOffset, '目标直播延迟', 0);
                  return json(player.targetOffsetFromLive);
                })}
                tone="secondary"
              />
            </>
          )
        : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function VideoTracks({ player }: { player: VideoPlayer }) {
  const { availableAudioTracks } = useEvent(player, 'availableAudioTracksChange', { availableAudioTracks: player.availableAudioTracks });
  const { availableSubtitleTracks } = useEvent(player, 'availableSubtitleTracksChange', { availableSubtitleTracks: player.availableSubtitleTracks });
  const { audioTrack } = useEvent(player, 'audioTrackChange', { audioTrack: player.audioTrack });
  const { subtitleTrack } = useEvent(player, 'subtitleTrackChange', { subtitleTrack: player.subtitleTrack });
  const { videoTrack } = useEvent(player, 'videoTrackChange', { videoTrack: player.videoTrack });
  const action = useAsyncResult();

  return (
    <Panel title="音轨、字幕与视频轨">
      <ActionRow>
        <ActionButton
          label="禁用音轨"
          onPress={() => void action.run(() => {
            player.audioTrack = null;
            return '已禁用音轨';
          })}
          tone="secondary"
        />
        {availableAudioTracks.map((track, index) => (
          <ActionButton
            key={track.id ?? index}
            label={`音轨 ${track.label || track.language || index + 1}`}
            onPress={() => void action.run(() => {
              player.audioTrack = track;
              return json(track);
            })}
            tone={audioTrack?.id === track.id ? 'primary' : 'secondary'}
          />
        ))}
      </ActionRow>
      <ActionRow>
        <ActionButton
          label="关闭字幕"
          onPress={() => void action.run(() => {
            player.subtitleTrack = null;
            return '已关闭字幕';
          })}
          tone="secondary"
        />
        {availableSubtitleTracks.map((track, index) => (
          <ActionButton
            key={track.id ?? index}
            label={`字幕 ${track.label || track.language || index + 1}`}
            onPress={() => void action.run(() => {
              player.subtitleTrack = track;
              return json(track);
            })}
            tone={subtitleTrack?.id === track.id ? 'primary' : 'secondary'}
          />
        ))}
      </ActionRow>
      <DataRow label="当前音轨" value={audioTrack?.label || audioTrack?.language || audioTrack?.id || '无'} />
      <DataRow label="当前字幕" value={subtitleTrack?.label || subtitleTrack?.language || subtitleTrack?.id || '无'} />
      <DataRow label="当前视频轨" value={videoTrack ? json(videoTrack) : '无'} />
      <ActionRow>
        <ActionButton label="读取音轨列表" onPress={() => void action.run(() => json(player.availableAudioTracks))} tone="secondary" />
        <ActionButton label="读取字幕列表" onPress={() => void action.run(() => json(player.availableSubtitleTracks))} tone="secondary" />
        <ActionButton label="读取视频轨列表" onPress={() => void action.run(() => json(player.availableVideoTracks))} tone="secondary" />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function VideoThumbnails({ player, ready }: { player: VideoPlayer; ready: boolean }) {
  const [times, setTimes] = useState('0, 1');
  const [width, setWidth] = useState('160');
  const [height, setHeight] = useState('120');
  const [images, setImages] = useState<VideoThumbnail[]>([]);
  const mounted = useRef(false);
  const action = useAsyncResult();

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);
  useEffect(() => () => images.forEach(image => image.release()), [images]);

  return (
    <Panel title="提取视频帧">
      <Field label="取帧时间（秒，逗号分隔）" value={times} onChangeText={setTimes} keyboardType="numbers-and-punctuation" />
      <Field label="最大宽度（像素）" value={width} onChangeText={setWidth} keyboardType="number-pad" />
      <Field label="最大高度（像素）" value={height} onChangeText={setHeight} keyboardType="number-pad" />
      <ActionButton
        label="生成缩略图"
        disabled={!ready || action.state.phase === 'running'}
        onPress={() => void action.run(async () => {
          const seconds = times.split(',').map(value => readNumber(value, '取帧时间', 0));
          const options: VideoThumbnailOptions = {
            maxWidth: width.trim() ? readNumber(width, '最大宽度', 1) : undefined,
            maxHeight: height.trim() ? readNumber(height, '最大高度', 1) : undefined,
          };
          const input = seconds.length === 1 ? seconds[0]! : seconds;
          const nextImages = await player.generateThumbnailsAsync(input, options);
          if (mounted.current) setImages(nextImages);
          else nextImages.forEach(image => image.release());
          return '';
        })}
        testID="video-capture"
      />
      {images.map((image, index) => (
        <Image
          key={index}
          accessibilityLabel={`${image.requestedTime} 秒的视频画面`}
          source={image}
          style={styles.thumbnail}
          contentFit="contain"
          testID="video-thumbnail"
        />
      ))}
      {images.length > 0
        ? (
            <DataRow
              label="缩略图"
              value={json(images.map(image => ({
                requestedTime: image.requestedTime,
                width: image.width,
                height: image.height,
                actualTime: Platform.OS === 'ios' ? image.actualTime : undefined,
              })))}
            />
          )
        : null}
      {action.state.phase !== 'success' ? <ResultPanel state={action.state} /> : null}
    </Panel>
  );
}

function AirPlayPanel({ player }: { player: VideoPlayer }) {
  const [tint, setTint] = useState('#007aff');
  const [activeTint, setActiveTint] = useState('#248a3d');
  const [prioritize, setPrioritize] = useState(true);
  const [routesVisible, setRoutesVisible] = useState(false);
  const action = useAsyncResult();
  const { isExternalPlaybackActive } = useEvent(player, 'isExternalPlaybackActiveChange', {
    isExternalPlaybackActive: player.isExternalPlaybackActive,
  });

  return (
    <Panel title="AirPlay">
      <Field label="图标颜色" value={tint} onChangeText={setTint} />
      <Field label="连接后的图标颜色" value={activeTint} onChangeText={setActiveTint} />
      <ActionRow>
        <ActionButton
          label={toggleLabel('优先显示视频设备', prioritize)}
          onPress={() => setPrioritize(value => !value)}
          tone="secondary"
        />
        <ActionButton
          label={toggleLabel('外部播放', player.allowsExternalPlayback)}
          onPress={() => void action.run(() => {
            player.allowsExternalPlayback = !player.allowsExternalPlayback;
            return player.allowsExternalPlayback ? '外部播放已启用' : '外部播放已关闭';
          })}
          tone="secondary"
        />
      </ActionRow>
      <VideoAirPlayButton
        style={styles.airPlay}
        tint={processColor(tint) != null ? tint : undefined}
        activeTint={processColor(activeTint) != null ? activeTint : undefined}
        prioritizeVideoDevices={prioritize}
        onBeginPresentingRoutes={() => setRoutesVisible(true)}
        onEndPresentingRoutes={() => setRoutesVisible(false)}
      />
      <DataRow label="设备列表" value={routesVisible ? '已打开' : '已关闭'} />
      <DataRow label="外部播放" value={isExternalPlaybackActive ? '播放中' : '未连接'} />
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function VideoEvents({ player }: { player: VideoPlayer }) {
  const [event, setEvent] = useState<keyof VideoPlayerEvents>('statusChange');
  const [payload, setPayload] = useState<{ event: keyof VideoPlayerEvents; value: string } | null>(null);

  useEffect(() => {
    const subscription = player.addListener(event, (value?: unknown) => {
      setPayload({ event, value: value === undefined ? '已触发' : json(value) });
    });

    return () => subscription.remove();
  }, [event, player]);

  return (
    <Panel title="播放器事件">
      <ActionRow>
        {playerEvents.map(name => (
          <ActionButton
            key={name}
            label={name}
            onPress={() => {
              setPayload(null);
              setEvent(name);
            }}
            tone={event === name ? 'primary' : 'secondary'}
          />
        ))}
      </ActionRow>
      <DataRow label={event} value={payload?.event === event ? payload.value : '等待事件'} />
    </Panel>
  );
}

const styles = StyleSheet.create({
  airPlay: { width: 44, height: 44 },
  preview: { height: 220, overflow: 'hidden', borderRadius: 12, backgroundColor: '#000000' },
  thumbnail: { width: '100%', height: 160, backgroundColor: '#000000', borderRadius: 12 },
});

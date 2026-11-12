/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { useEvent } from 'expo';
import {
  clearAllPreloadedSources,
  clearPreloadedSource,
  createAudioPlayer,
  createAudioPlaylist,
  getPreloadedSources,
  getRecordingPermissionsAsync,
  preload,
  RecordingPresets,
  requestNotificationPermissionsAsync,
  requestRecordingPermissionsAsync,
  setAudioModeAsync,
  setIsAudioActiveAsync,
  useAudioPlayer,
  useAudioPlayerStatus,
  useAudioPlaylist,
  useAudioPlaylistStatus,
  useAudioRecorder,
  useAudioRecorderState,
  useAudioSampleListener,
  useAudioStream,
} from 'expo-audio';
import type {
  AudioLockScreenOptions,
  AudioMetadata,
  AudioMode,
  AudioPlayer,
  AudioPlayerOptions,
  AudioPlaylist,
  AudioPlaylistOptions,
  AudioRecorder,
  AudioSource,
  AudioStreamEncoding,
  PitchCorrectionQuality,
  RecorderState,
  RecordingOptions,
  RecordingStatus,
} from 'expo-audio';
import { useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import sample from '../../assets/audio/sample.wav';
import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const isHarmony = String(Platform.OS) === 'harmony';
const isWeb = Platform.OS === 'web';
const isIOS = Platform.OS === 'ios';
const playerOptions: AudioPlayerOptions = {
  updateInterval: 250,
  downloadFirst: false,
  ...(isWeb ? { crossOrigin: 'anonymous' } : { keepAudioSessionActive: false, preferredForwardBufferDuration: 0 }),
};

const TONE_DATA_URI
  = 'data:audio/wav;base64,UklGRkQDAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YSADAAAAAJ4GcwzQEC8TShMeEesMMQedAPf5B/SC7/Dsn+yZ7qHyPvjG/nMFewsnEOsSchOsEdANUQjXASX7BvUz8D/tguwT7sPxIveN/UMEdwpvD5MShhMpEqcOaQkOA1f8D/bz8KDteOyg7fPwD/ZX/A4DaQmnDikShhOTEm8PdwpDBI39IvfD8RPuguw/7TPwBvUl+9cBUQjQDawRchPrEicQewtzBcb+Pvih8pnun+zw7ILvB/T3+Z0AMQfrDB4RShMvE9AQcwyeBgAAYvmN8zDv0ey27OLuFfPP+GP/CQb5C34QEBNhE2cRXw3CBzoBjfqF9NnvFe2O7FTuMPKv9yn+2wT6Cs0PwRJ+E+0RPQ7eCHMCvfuJ9ZHwbe167NftWfGX9vL8qQPxCQ0PYBKIE2ASDQ/xCakD8vyX9lnx1+167G3tkfCJ9b37cwLeCD0O7RF+E8ESzQ/6CtsEKf6v9zDyVO6O7BXt2e+F9I36OgHCB18NZxFhExATfhD5CwkGY//P+BXz4u627NHsMO+N82L5AACeBnMM0BAvE0oTHhHrDDEHnQD3+Qf0gu/w7J/sme6h8j74xv5zBXsLJxDrEnITrBHQDVEI1wEl+wb1M/A/7YLsE+7D8SL3jf1DBHcKbw+TEoYTKRKnDmkJDgNX/A/28/Cg7XjsoO3z8A/2V/wOA2kJpw4pEoYTkxJvD3cKQwSN/SL3w/ET7oLsP+0z8Ab1JfvXAVEI0A2sEXIT6xInEHsLcwXG/j74ofKZ7p/s8OyC7wf09/mdADEH6wweEUoTLxPQEHMMngYAAGL5jfMw79Hstuzi7hXzz/hj/wkG+Qt+EBATYRNnEV8Nwgc6AY36hfTZ7xXtjuxU7jDyr/cp/tsE+grND8ESfhPtET0O3ghzAr37ifWR8G3teuzX7Vnxl/by/KkD8QkND2ASiBNgEg0P8QmpA/L8l/ZZ8dfteuxt7ZHwifW9+3MC3gg9Du0RfhPBEs0P+grbBCn+r/cw8lTujuwV7dnvhfSN+joBwgdfDWcRYRMQE34Q+QsJBmP/z/gV8+LutuzR7DDvjfNi+Q==';
const PACKAGED_SOURCES = ['RAWFILE://audio/probe.wav', 'asset://audio/probe.wav', 'resource://RAWFILE/audio/probe.wav'] as const;

const demoTracks = [
  { name: '三段音阶', assetId: sample },
  { name: '短音', uri: TONE_DATA_URI },
];

const audioModeDefaults: Partial<AudioMode> = {
  playsInSilentMode: true,
  interruptionMode: 'mixWithOthers',
  shouldPlayInBackground: false,
  shouldRouteThroughEarpiece: false,
  allowsBackgroundRecording: false,
  ...(isIOS ? { allowsRecording: false } : {}),
};

function useAudioAction() {
  const { state, run } = useAsyncResult();

  return {
    state,
    run: (operation: () => unknown) => void run(async () => {
      const result = await operation();
      return result === undefined ? '已完成' : json(result);
    }),
  };
}

function readNumber(text: string) {
  const value = Number(text);
  if (!text.trim() || !Number.isFinite(value)) throw new Error('请输入有效数字。');
  return value;
}

function readOptions<T>(text: string): T {
  const parsed: unknown = JSON.parse(text);
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('参数需要使用 JSON 对象。');
  return parsed as T;
}

export function AudioDemo() {
  return (
    <>
      <AudioPermissions />
      <AudioPlayers />
      <AudioPlaylists />
      {Platform.isTV ? null : <AudioRecording />}
      {isWeb ? null : <AudioStreaming />}
      <AudioSettings />
    </>
  );
}

function AudioPermissions() {
  const action = useAudioAction();

  return (
    <Panel title="音频权限">
      <ActionRow>
        <ActionButton label="读取麦克风权限" onPress={() => action.run(getRecordingPermissionsAsync)} tone="secondary" />
        <ActionButton label="申请麦克风权限" onPress={() => action.run(requestRecordingPermissionsAsync)} />
        {isHarmony || Platform.OS === 'android'
          ? <ActionButton label="申请通知权限" onPress={() => action.run(requestNotificationPermissionsAsync)} tone="secondary" />
          : null}
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function AudioPlayers() {
  const hookPlayer = useAudioPlayer(sample, playerOptions);
  const [manual, setManual] = useState<AudioPlayer | null>(null);
  const [sourceUri, setSourceUri] = useState('');
  const [sourceFields, setSourceFields] = useState(() => json({ name: '音频样例', assetId: sample, headers: {} }));
  const [settings, setSettings] = useState(() => json(playerOptions));
  const [bufferDuration, setBufferDuration] = useState('10');
  const sourceAction = useAudioAction();
  const cache = useAudioAction();
  const player = manual ?? hookPlayer;

  useEffect(() => {
    return () => manual?.remove();
  }, [manual]);

  function source() {
    const fields = readOptions<Exclude<AudioSource, string | number | null>>(sourceFields);
    return sourceUri.trim() ? { ...fields, uri: sourceUri.trim() } : fields;
  }

  return (
    <>
      <Panel title="音频源">
        <Field label="音频 URI" placeholder="留空使用内置音频" value={sourceUri} onChangeText={setSourceUri} />
        <Field label="音频源参数（JSON）" multiline value={sourceFields} onChangeText={setSourceFields} />
        <ActionRow>
          <ActionButton label="加载音频源" onPress={() => sourceAction.run(() => player.replace(source()))} />
          <ActionButton label="清空音频源" onPress={() => sourceAction.run(() => player.replace(null))} tone="secondary" />
          <ActionButton
            label="播放短音资源"
            onPress={() => sourceAction.run(() => {
              player.replace(TONE_DATA_URI);
              player.play();
            })}
            tone="secondary"
          />
        </ActionRow>
        {isHarmony
          ? (
              <ActionRow>
                {PACKAGED_SOURCES.map(uri => (
                  <ActionButton key={uri} label={uri.split(':')[0]!} onPress={() => sourceAction.run(() => player.replace(uri))} tone="secondary" />
                ))}
              </ActionRow>
            )
          : null}
        <Field label="创建播放器参数（JSON）" multiline value={settings} onChangeText={setSettings} />
        <DataRow label="创建方式" value={manual ? 'createAudioPlayer' : 'useAudioPlayer'} />
        <ActionRow>
          <ActionButton
            label="创建播放器"
            onPress={() => sourceAction.run(() => {
              const next = createAudioPlayer(source(), readOptions<AudioPlayerOptions>(settings));
              player.pause();
              setManual(next);
              return { id: next.id };
            })}
          />
          <ActionButton disabled={!manual} label="释放播放器" onPress={() => setManual(null)} tone="secondary" />
        </ActionRow>
        <ResultPanel state={sourceAction.state} />
      </Panel>

      <PlayerControls key={player.id} player={player} />

      <Panel title="音频预加载">
        <Field label="预缓冲时间（秒）" keyboardType="decimal-pad" value={bufferDuration} onChangeText={setBufferDuration} />
        <ActionRow>
          <ActionButton label="预加载音频源" onPress={() => cache.run(() => preload(source(), { preferredForwardBufferDuration: readNumber(bufferDuration) }))} />
          <ActionButton label="读取预加载列表" onPress={() => cache.run(getPreloadedSources)} tone="secondary" />
          <ActionButton label="清除当前预加载" onPress={() => cache.run(() => clearPreloadedSource(source()))} tone="secondary" />
          <ActionButton label="清除全部预加载" onPress={() => cache.run(clearAllPreloadedSources)} tone="secondary" />
        </ActionRow>
        <ResultPanel state={cache.state} />
      </Panel>
    </>
  );
}

function PlayerControls({ player }: { player: AudioPlayer }) {
  const status = useAudioPlayerStatus(player);
  const [seek, setSeek] = useState('1');
  const [toleranceBefore, setToleranceBefore] = useState('0');
  const [toleranceAfter, setToleranceAfter] = useState('0');
  const [rate, setRate] = useState('1.25');
  const [volume, setVolume] = useState('0.5');
  const [pitchQuality, setPitchQuality] = useState<PitchCorrectionQuality>('medium');
  const [sampling, setSampling] = useState(false);
  const [metadata, setMetadata] = useState(() => json({ title: '三段音阶', artist: 'Expo Harmony', albumTitle: 'Demo', artworkUrl: '' }));
  const [lockOptions, setLockOptions] = useState(() => json({
    showSeekForward: true,
    showSeekBackward: true,
    isLiveStream: false,
  }));
  const action = useAudioAction();
  const media = useAudioAction();

  return (
    <>
      <Panel title="音频播放">
        <DataRow label="播放进度" value={`${status.currentTime.toFixed(2)} / ${status.duration.toFixed(2)} 秒`} />
        <DataRow label="播放状态" value={status.error || status.playbackState} />
        <ActionRow>
          <ActionButton label="播放" onPress={() => action.run(() => player.play())} />
          <ActionButton label="暂停" onPress={() => action.run(() => player.pause())} tone="secondary" />
          <ActionButton
            label={status.mute ? '取消静音' : '静音'}
            onPress={() => action.run(() => {
              player.muted = !player.muted;
            })}
            tone="secondary"
          />
          <ActionButton
            label={status.loop ? '关闭循环' : '开启循环'}
            onPress={() => action.run(() => {
              player.loop = !player.loop;
            })}
            tone="secondary"
          />
          <ActionButton label="读取播放状态" onPress={() => action.run(() => ({ ...player.currentStatus, paused: player.paused, volume: player.volume, isAudioSamplingSupported: player.isAudioSamplingSupported }))} tone="secondary" />
        </ActionRow>
        <Field label="跳转位置（秒）" keyboardType="decimal-pad" value={seek} onChangeText={setSeek} />
        {isIOS
          ? (
              <>
                <Field label="向前容差（毫秒）" keyboardType="decimal-pad" value={toleranceBefore} onChangeText={setToleranceBefore} />
                <Field label="向后容差（毫秒）" keyboardType="decimal-pad" value={toleranceAfter} onChangeText={setToleranceAfter} />
              </>
            )
          : null}
        <ActionButton disabled={!status.isLoaded} label="跳转" onPress={() => action.run(() => player.seekTo(readNumber(seek), isIOS ? readNumber(toleranceBefore) : undefined, isIOS ? readNumber(toleranceAfter) : undefined))} />
        <Field label="音量（0 到 1）" keyboardType="decimal-pad" value={volume} onChangeText={setVolume} />
        <ActionButton
          label="设置音量"
          onPress={() => action.run(() => {
            player.volume = readNumber(volume);
            return player.volume;
          })}
          tone="secondary"
        />
        <Field label="播放倍速" keyboardType="decimal-pad" value={rate} onChangeText={setRate} />
        {isIOS || isWeb
          ? (
              <ActionRow>
                {(['low', 'medium', 'high'] as const).map(value => (
                  <ActionButton key={value} label={value} onPress={() => setPitchQuality(value)} tone={pitchQuality === value ? 'primary' : 'secondary'} />
                ))}
              </ActionRow>
            )
          : null}
        <ActionRow>
          <ActionButton
            label="设置倍速"
            onPress={() => action.run(() => {
              player.setPlaybackRate(readNumber(rate), isIOS || isWeb ? pitchQuality : undefined);
              return player.playbackRate;
            })}
          />
          {!isHarmony && !isWeb
            ? <ActionButton
                label={status.shouldCorrectPitch ? '关闭音高修正' : '开启音高修正'}
                onPress={() => action.run(() => {
                  player.shouldCorrectPitch = !player.shouldCorrectPitch;
                })}
                tone="secondary"
              />
            : null}
          {player.isAudioSamplingSupported
            ? <ActionButton
                label={sampling ? '停止采样' : '监听音频采样'}
                disabled={action.state.phase === 'running'}
                onPress={() => action.run(async () => {
                  if (sampling) player.setAudioSamplingEnabled(false);
                  else if (Platform.OS === 'android' && !(await getRecordingPermissionsAsync()).granted) {
                    throw new Error('请先申请麦克风权限。');
                  }
                  setSampling(!sampling);
                })}
                tone="secondary"
              />
            : null}
        </ActionRow>
        {sampling ? <AudioSampleData player={player} /> : null}
        <ResultPanel state={action.state} />
      </Panel>

      <Panel title="锁屏播放控制">
        <Field label="媒体元数据（JSON）" multiline value={metadata} onChangeText={setMetadata} />
        <Field label="锁屏控制选项（JSON）" multiline value={lockOptions} onChangeText={setLockOptions} />
        <ActionRow>
          <ActionButton label="启用锁屏控制" onPress={() => media.run(() => player.setActiveForLockScreen(true, readOptions<AudioMetadata>(metadata), readOptions<AudioLockScreenOptions>(lockOptions)))} />
          <ActionButton label="停用锁屏控制" onPress={() => media.run(() => player.setActiveForLockScreen(false))} tone="secondary" />
          <ActionButton label="更新媒体信息" onPress={() => media.run(() => player.updateLockScreenMetadata(readOptions<AudioMetadata>(metadata)))} tone="secondary" />
          <ActionButton label="清除锁屏控制" onPress={() => media.run(() => player.clearLockScreenControls())} tone="secondary" />
        </ActionRow>
        <ResultPanel state={media.state} />
      </Panel>
    </>
  );
}

function AudioSampleData({ player }: { player: AudioPlayer }) {
  const [sampleData, setSampleData] = useState('');
  const nextUpdate = useRef(0);

  useAudioSampleListener(player, ({ channels, timestamp }) => {
    if (Date.now() < nextUpdate.current) return;
    nextUpdate.current = Date.now() + 250;
    setSampleData(json({ framesPerChannel: channels.map(channel => channel.frames.length), timestamp }));
  });

  return <DataRow label="audioSampleUpdate" value={sampleData || '等待采样'} />;
}

function AudioPlaylists() {
  const hookPlaylist = useAudioPlaylist({ sources: demoTracks });
  const [manual, setManual] = useState<AudioPlaylist | null>(null);
  const [options, setOptions] = useState(() => json({
    sources: [demoTracks[0], sample],
    updateInterval: 250,
    loop: 'none',
    ...(isWeb ? { crossOrigin: 'anonymous' } : {}),
  }));
  const action = useAudioAction();
  const playlist = manual ?? hookPlaylist;

  useEffect(() => {
    return () => manual?.destroy();
  }, [manual]);

  return (
    <Panel title="播放列表">
      <Field label="播放列表参数（JSON）" multiline value={options} onChangeText={setOptions} />
      <DataRow label="创建方式" value={manual ? 'createAudioPlaylist' : 'useAudioPlaylist'} />
      <ActionRow>
        <ActionButton
          label="创建播放列表"
          onPress={() => action.run(() => {
            const next = createAudioPlaylist(readOptions<AudioPlaylistOptions>(options));
            playlist.pause();
            setManual(next);
            return { id: next.id };
          })}
        />
        <ActionButton disabled={!manual} label="销毁播放列表" onPress={() => setManual(null)} tone="secondary" />
      </ActionRow>
      <ResultPanel state={action.state} />
      <PlaylistControls key={playlist.id} playlist={playlist} />
    </Panel>
  );
}

function PlaylistControls({ playlist }: { playlist: AudioPlaylist }) {
  const status = useAudioPlaylistStatus(playlist);
  const track = useEvent(playlist, 'trackChanged');
  const [index, setIndex] = useState('0');
  const [seek, setSeek] = useState('1');
  const [rate, setRate] = useState('1.25');
  const [volume, setVolume] = useState('0.5');
  const [uri, setUri] = useState('');
  const action = useAudioAction();
  const trackSource = uri.trim() || sample;

  return (
    <>
      <DataRow label="曲目索引" value={status.trackCount ? String(status.currentIndex) : '无曲目'} />
      <DataRow label="播放进度" value={`${status.currentTime.toFixed(2)} / ${status.duration.toFixed(2)} 秒`} />
      {track ? <DataRow label="trackChanged" value={json(track)} /> : null}
      <ActionRow>
        <ActionButton label="播放列表" onPress={() => action.run(() => playlist.play())} />
        <ActionButton label="暂停" onPress={() => action.run(() => playlist.pause())} tone="secondary" />
        <ActionButton label="上一首" onPress={() => action.run(() => playlist.previous())} tone="secondary" />
        <ActionButton label="下一首" onPress={() => action.run(() => playlist.next())} tone="secondary" />
        <ActionButton
          label={status.muted ? '取消静音' : '静音'}
          onPress={() => action.run(() => {
            playlist.muted = !playlist.muted;
          })}
          tone="secondary"
        />
        <ActionButton label="读取播放列表状态" onPress={() => action.run(() => ({ ...playlist.currentStatus, sources: playlist.sources.map(({ uri, name }) => ({ uri: uri?.startsWith('data:') ? 'data:audio/wav' : uri, name })) }))} tone="secondary" />
      </ActionRow>
      <Field label="曲目 URI" placeholder="留空使用内置音频" value={uri} onChangeText={setUri} />
      <Field label="曲目索引（从 0 开始）" keyboardType="number-pad" value={index} onChangeText={setIndex} />
      <ActionRow>
        <ActionButton label="追加曲目" onPress={() => action.run(() => playlist.add(trackSource))} />
        <ActionButton label="插入曲目" onPress={() => action.run(() => playlist.insert(trackSource, readNumber(index)))} tone="secondary" />
        <ActionButton label="移除曲目" onPress={() => action.run(() => playlist.remove(readNumber(index)))} tone="secondary" />
        <ActionButton label="跳到曲目" onPress={() => action.run(() => playlist.skipTo(readNumber(index)))} tone="secondary" />
        <ActionButton label="清空曲目" onPress={() => action.run(() => playlist.clear())} tone="secondary" />
      </ActionRow>
      <Field label="跳转位置（秒）" keyboardType="decimal-pad" value={seek} onChangeText={setSeek} />
      <ActionButton disabled={!status.isLoaded} label="跳转" onPress={() => action.run(() => playlist.seekTo(readNumber(seek)))} />
      <Field label="音量（0 到 1）" keyboardType="decimal-pad" value={volume} onChangeText={setVolume} />
      <ActionButton
        label="设置音量"
        onPress={() => action.run(() => {
          playlist.volume = readNumber(volume);
          return playlist.volume;
        })}
        tone="secondary"
      />
      <Field label="播放倍速" keyboardType="decimal-pad" value={rate} onChangeText={setRate} />
      <ActionButton
        label="设置倍速"
        onPress={() => action.run(() => {
          playlist.playbackRate = readNumber(rate);
          return playlist.playbackRate;
        })}
        tone="secondary"
      />
      <ActionRow>
        {(['none', 'single', 'all'] as const).map((loop, index) => (
          <ActionButton
            key={loop}
            label={['不循环', '单曲循环', '列表循环'][index]!}
            onPress={() => action.run(() => {
              playlist.loop = loop;
            })}
            tone={status.loop === loop ? 'primary' : 'secondary'}
          />
        ))}
      </ActionRow>
      <ResultPanel state={action.state} />
    </>
  );
}

function AudioRecording() {
  const [preset, setPreset] = useState<keyof typeof RecordingPresets>('HIGH_QUALITY');
  const [event, setEvent] = useState<RecordingStatus | null>(null);
  const [interval, setInterval] = useState(500);
  const [options, setOptions] = useState(() => json(recordingSettings(RecordingPresets.HIGH_QUALITY)));
  const [start, setStart] = useState('0');
  const [duration, setDuration] = useState('3');
  const [input, setInput] = useState('');
  const player = useAudioPlayer(null);
  const recordingMode = useRef(false);
  const recorder = useAudioRecorder(RecordingPresets[preset], (status) => {
    setEvent(status);
    if (status.isFinished) void resetRecordingMode(recordingMode).catch(() => undefined);
  });
  const [state, setState] = useState(() => recorder.getStatus());
  const action = useAudioAction();
  const prepared = state.canRecord;
  const busy = action.state.phase === 'running';
  const uri = event?.url ?? state.url ?? recorder.uri;

  useEffect(() => () => {
    void resetRecordingMode(recordingMode).catch(() => undefined);
  }, []);

  function changePreset(value: keyof typeof RecordingPresets) {
    setEvent(null);
    setPreset(value);
    setOptions(json(recordingSettings(RecordingPresets[value])));
  }

  return (
    <Panel title="录音">
      <RecorderStateMonitor key={`${recorder.id}:${interval}`} recorder={recorder} interval={interval} onChange={setState} />
      <ActionRow>
        <ActionButton disabled={prepared || busy} label="高音质预设" onPress={() => changePreset('HIGH_QUALITY')} tone={preset === 'HIGH_QUALITY' ? 'primary' : 'secondary'} />
        <ActionButton disabled={prepared || busy} label="低音质预设" onPress={() => changePreset('LOW_QUALITY')} tone={preset === 'LOW_QUALITY' ? 'primary' : 'secondary'} />
      </ActionRow>
      <Field label="录音参数（JSON）" multiline value={options} onChangeText={setOptions} />
      <ActionButton
        disabled={prepared || busy}
        label="准备录音"
        onPress={() => action.run(async () => {
          const settings = readOptions<Partial<RecordingOptions>>(options);
          if (!(await getRecordingPermissionsAsync()).granted) throw new Error('请先申请麦克风权限。');
          if (isIOS) {
            await setAudioModeAsync({ allowsRecording: true });
            recordingMode.current = true;
          }
          try {
            await recorder.prepareToRecordAsync(settings);
          } catch (error) {
            await resetRecordingMode(recordingMode);
            throw error;
          }
          setEvent(null);
          const state = recorder.getStatus();
          setState(state);
          return state;
        })}
      />
      <Field label="开始时间（秒）" keyboardType="decimal-pad" value={start} onChangeText={setStart} />
      <Field label="定时停止（秒）" keyboardType="decimal-pad" value={duration} onChangeText={setDuration} />
      <ActionRow>
        <ActionButton disabled={!prepared || state.isRecording || busy} label="开始或继续录音" onPress={() => action.run(() => recorder.record())} />
        <ActionButton
          disabled={!prepared || state.isRecording || busy}
          label="按时间录音"
          onPress={() => action.run(() => recorder.record({
            atTime: readNumber(start),
            forDuration: readNumber(duration),
          }))}
          tone="secondary"
        />
        <ActionButton disabled={!state.isRecording || busy} label="暂停录音" onPress={() => action.run(() => recorder.pause())} tone="secondary" />
        <ActionButton
          disabled={!prepared || busy}
          label="结束录音"
          onPress={() => action.run(async () => {
            try {
              await recorder.stop();
            } finally {
              await resetRecordingMode(recordingMode);
            }
          })}
          tone="secondary"
        />
      </ActionRow>
      {!isWeb
        ? (
            <ActionRow>
              <ActionButton disabled={!prepared || state.isRecording || busy} label="recordForDuration" onPress={() => action.run(() => recorder.recordForDuration(readNumber(duration)))} tone="secondary" />
              <ActionButton disabled={!prepared || state.isRecording || busy} label="startRecordingAtTime" onPress={() => action.run(() => recorder.startRecordingAtTime(readNumber(start)))} tone="secondary" />
            </ActionRow>
          )
        : null}
      <DataRow label="录音进度" value={`${state.durationMillis} 毫秒`} />
      {state.metering !== undefined ? <DataRow label="录音电平" value={state.metering.toFixed(1)} /> : null}
      <DataRow label="状态刷新间隔" value={`${interval} 毫秒`} />
      <ActionRow>
        {[250, 500, 1000].map(value => <ActionButton key={value} label={`${value} ms`} onPress={() => setInterval(value)} tone={interval === value ? 'primary' : 'secondary'} />)}
        <ActionButton label="读取录音状态" onPress={() => action.run(() => ({ ...recorder.getStatus(), id: recorder.id, currentTime: recorder.currentTime, isRecording: recorder.isRecording, uri: recorder.uri }))} tone="secondary" />
      </ActionRow>
      {event ? <DataRow label="recordingStatusUpdate" value={json(event)} /> : null}
      {uri && !prepared
        ? (
            <ActionRow>
              <ActionButton
                label="播放录音"
                onPress={() => action.run(() => {
                  player.replace(uri);
                  player.play();
                })}
              />
              <ActionButton label="暂停播放" onPress={() => action.run(() => player.pause())} tone="secondary" />
            </ActionRow>
          )
        : null}
      {!isWeb
        ? (
            <>
              <Field label="录音输入 UID" value={input} onChangeText={setInput} />
              <ActionRow>
                <ActionButton disabled={!prepared || busy} label="列出录音输入" onPress={() => action.run(() => recorder.getAvailableInputs())} tone="secondary" />
                <ActionButton disabled={!prepared || busy} label="读取当前输入" onPress={() => action.run(() => recorder.getCurrentInput())} tone="secondary" />
                <ActionButton disabled={!prepared || busy || !input.trim()} label="切换录音输入" onPress={() => action.run(() => recorder.setInput(input.trim()))} tone="secondary" />
              </ActionRow>
            </>
          )
        : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function RecorderStateMonitor({ recorder, interval, onChange }: {
  recorder: AudioRecorder;
  interval: number;
  onChange: (state: RecorderState) => void;
}) {
  const state = useAudioRecorderState(recorder, interval);
  useEffect(() => onChange(state), [onChange, state]);
  return null;
}

async function resetRecordingMode(mode: { current: boolean }) {
  if (!mode.current) return;
  mode.current = false;
  await setAudioModeAsync({ allowsRecording: false });
}

function recordingSettings(preset: RecordingOptions) {
  const { ios, android, web, ...common } = preset;
  return {
    ...common,
    isMeteringEnabled: true,
    ...(!isWeb ? { directory: 'cache' } : {}),
    ...(isIOS ? { ios } : {}),
    ...(Platform.OS === 'android' ? { android } : {}),
    ...(isWeb || isHarmony ? { web } : {}),
  };
}

function AudioStreaming() {
  const [rate, setRate] = useState('48000');
  const [format, setFormat] = useState<{ sampleRate: number; channels: number; encoding: AudioStreamEncoding }>({
    sampleRate: 48000,
    channels: 1,
    encoding: 'float32',
  });
  const [buffer, setBuffer] = useState('');
  const nextUpdate = useRef(0);
  const { stream, isStreaming } = useAudioStream({
    ...format,
    onBuffer: ({ data, timestamp, sampleRate, channels }) => {
      if (Date.now() < nextUpdate.current) return;
      nextUpdate.current = Date.now() + 250;
      setBuffer(json({ bytes: data.byteLength, timestamp, sampleRate, channels }));
    },
  });
  const action = useAudioAction();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="麦克风 PCM 流">
      <Field label="采样率（Hz）" keyboardType="number-pad" value={rate} onChangeText={setRate} />
      <ActionRow>
        {[1, 2].map(channels => (
          <ActionButton key={channels} disabled={isStreaming || busy} label={channels === 1 ? '单声道' : '双声道'} onPress={() => setFormat(value => ({ ...value, channels }))} tone={format.channels === channels ? 'primary' : 'secondary'} />
        ))}
        {(['float32', 'int16'] as const).map(encoding => (
          <ActionButton key={encoding} disabled={isStreaming || busy} label={encoding} onPress={() => setFormat(value => ({ ...value, encoding }))} tone={format.encoding === encoding ? 'primary' : 'secondary'} />
        ))}
        <ActionButton
          disabled={isStreaming || busy}
          label="应用采样率"
          onPress={() => action.run(() => {
            const sampleRate = readNumber(rate);
            if (!Number.isSafeInteger(sampleRate) || sampleRate <= 0) throw new Error('采样率需要为正整数。');
            setFormat(value => ({ ...value, sampleRate }));
          })}
          tone="secondary"
        />
      </ActionRow>
      <ActionRow>
        <ActionButton
          disabled={!stream || isStreaming || busy}
          label="开始采集"
          onPress={() => action.run(async () => {
            if (!(await getRecordingPermissionsAsync()).granted) throw new Error('请先申请麦克风权限。');
            setBuffer('');
            await stream.start();
            return { id: stream.id, sampleRate: stream.sampleRate, channels: stream.channels };
          })}
        />
        <ActionButton disabled={!stream || !isStreaming} label="停止采集" onPress={() => action.run(() => stream.stop())} tone="secondary" />
      </ActionRow>
      <DataRow label="audioStreamStatus" value={isStreaming ? '采集中' : '已停止'} />
      {buffer ? <DataRow label="audioStreamBuffer" value={buffer} /> : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function AudioSettings() {
  const [mode, setMode] = useState(() => json(audioModeDefaults));
  const changedMode = useRef(false);
  const changedActive = useRef(false);
  const action = useAudioAction();

  useEffect(() => {
    return () => {
      if (changedMode.current) void setAudioModeAsync(audioModeDefaults).catch(() => undefined);
      if (changedActive.current) void setIsAudioActiveAsync(true).catch(() => undefined);
    };
  }, []);

  return (
    <Panel title="音频会话">
      <Field label="音频会话设置（JSON）" multiline value={mode} onChangeText={setMode} />
      <ActionRow>
        <ActionButton
          label="应用音频设置"
          onPress={() => action.run(async () => {
            const settings = readOptions<Partial<AudioMode>>(mode);
            changedMode.current = true;
            await setAudioModeAsync(settings);
          })}
        />
        <ActionButton
          label="启用音频"
          onPress={() => action.run(() => {
            changedActive.current = true;
            return setIsAudioActiveAsync(true);
          })}
          tone="secondary"
        />
        <ActionButton
          label="停用音频"
          onPress={() => action.run(() => {
            changedActive.current = true;
            return setIsAudioActiveAsync(false);
          })}
          tone="secondary"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

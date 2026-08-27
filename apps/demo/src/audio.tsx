import {
  clearAllPreloadedSources,
  createAudioPlayer,
  createAudioPlaylist,
  getPreloadedSources,
  preload,
  setAudioModeAsync,
  useAudioPlayer,
  useAudioPlayerStatus,
} from 'expo-audio';

import { ActionButton, ActionRow, DataRow, Note, Panel, ResultPanel, Tag, useAsyncResult } from './ui';

const TONE_DATA_URI
  = 'data:audio/wav;base64,UklGRkQDAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YSADAAAAAJ4GcwzQEC8TShMeEesMMQedAPf5B/SC7/Dsn+yZ7qHyPvjG/nMFewsnEOsSchOsEdANUQjXASX7BvUz8D/tguwT7sPxIveN/UMEdwpvD5MShhMpEqcOaQkOA1f8D/bz8KDteOyg7fPwD/ZX/A4DaQmnDikShhOTEm8PdwpDBI39IvfD8RPuguw/7TPwBvUl+9cBUQjQDawRchPrEicQewtzBcb+Pvih8pnun+zw7ILvB/T3+Z0AMQfrDB4RShMvE9AQcwyeBgAAYvmN8zDv0ey27OLuFfPP+GP/CQb5C34QEBNhE2cRXw3CBzoBjfqF9NnvFe2O7FTuMPKv9yn+2wT6Cs0PwRJ+E+0RPQ7eCHMCvfuJ9ZHwbe167NftWfGX9vL8qQPxCQ0PYBKIE2ASDQ/xCakD8vyX9lnx1+167G3tkfCJ9b37cwLeCD0O7RF+E8ESzQ/6CtsEKf6v9zDyVO6O7BXt2e+F9I36OgHCB18NZxFhExATfhD5CwkGY//P+BXz4u627NHsMO+N82L5AACeBnMM0BAvE0oTHhHrDDEHnQD3+Qf0gu/w7J/sme6h8j74xv5zBXsLJxDrEnITrBHQDVEI1wEl+wb1M/A/7YLsE+7D8SL3jf1DBHcKbw+TEoYTKRKnDmkJDgNX/A/28/Cg7XjsoO3z8A/2V/wOA2kJpw4pEoYTkxJvD3cKQwSN/SL3w/ET7oLsP+0z8Ab1JfvXAVEI0A2sEXIT6xInEHsLcwXG/j74ofKZ7p/s8OyC7wf09/mdADEH6wweEUoTLxPQEHMMngYAAGL5jfMw79Hstuzi7hXzz/hj/wkG+Qt+EBATYRNnEV8Nwgc6AY36hfTZ7xXtjuxU7jDyr/cp/tsE+grND8ESfhPtET0O3ghzAr37ifWR8G3teuzX7Vnxl/by/KkD8QkND2ASiBNgEg0P8QmpA/L8l/ZZ8dfteuxt7ZHwifW9+3MC3gg9Du0RfhPBEs0P+grbBCn+r/cw8lTujuwV7dnvhfSN+joBwgdfDWcRYRMQE34Q+QsJBmP/z/gV8+LutuzR7DDvjfNi+Q==';
const PACKAGED_SOURCES = ['RAWFILE://audio/probe.wav', 'asset://audio/probe.wav'] as const;

function wait(milliseconds: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

function statusSummary(status: ReturnType<typeof useAudioPlayerStatus>) {
  return {
    didJustFinish: status.didJustFinish,
    duration: status.duration,
    isBuffering: status.isBuffering,
    isLoaded: status.isLoaded,
    playbackState: status.playbackState,
    playing: status.playing,
    timeControlStatus: status.timeControlStatus,
  };
}

async function probePackagedSource(uri: string) {
  const player = createAudioPlayer(uri, { preferredForwardBufferDuration: 1, updateInterval: 25 });
  let finishes = 0;
  const subscription = player.addListener('playbackStatusUpdate', (status) => {
    if (status.didJustFinish) finishes += 1;
  });

  try {
    player.play();

    for (let attempt = 0; attempt < 100 && finishes === 0; attempt += 1) await wait(50);

    if (!player.isLoaded) throw new Error(`内置资源 '${uri}' 未能进入已加载状态。`);
    if (finishes !== 1) throw new Error(`'${uri}' 预期恰好一次完成事件，实际收到 ${finishes} 次。`);

    return statusSummary(player.currentStatus);
  } finally {
    subscription.remove();
    player.remove();
  }
}

export function AudioDemo() {
  const player = useAudioPlayer(TONE_DATA_URI, { updateInterval: 25 });
  const status = useAudioPlayerStatus(player);
  const probe = useAsyncResult();

  const runDataUriProbe = () => probe.run(async () => {
    let finishes = 0;
    const subscription = player.addListener('playbackStatusUpdate', (next) => {
      if (next.didJustFinish) finishes += 1;
    });

    try {
      await player.seekTo(0);
      player.play();
      await wait(500);

      if (!player.isLoaded) throw new Error('data URI 播放器未能进入已加载状态。');
      if (finishes !== 1) throw new Error(`预期恰好一次完成事件，实际收到 ${finishes} 次。`);

      return JSON.stringify({ completionEvents: finishes, status: statusSummary(player.currentStatus) }, null, 2);
    } finally {
      subscription.remove();
      player.pause();
    }
  });

  const runPreloadProbe = () => probe.run(async () => {
    await clearAllPreloadedSources();
    await preload(TONE_DATA_URI);

    const sources = await getPreloadedSources();
    if (!sources.includes(TONE_DATA_URI)) throw new Error('原生预加载缓存未保留该 data URI。');

    const consumer = createAudioPlayer(TONE_DATA_URI);
    try {
      for (let attempt = 0; attempt < 100 && !consumer.isLoaded; attempt += 1) await wait(25);

      if (!consumer.isLoaded) throw new Error('播放器未能使用已预备的资源。');
      if (!(await getPreloadedSources()).includes(TONE_DATA_URI)) {
        throw new Error('预加载缓存的条目在首次使用后即消失。');
      }
    } finally {
      consumer.remove();
    }

    await clearAllPreloadedSources();

    return JSON.stringify({
      cachedSources: sources.length,
      retainedAfterUse: true,
      cleared: (await getPreloadedSources()).length === 0,
    }, null, 2);
  });

  const runPackagedProbe = () => probe.run(async () => {
    const results: Record<string, unknown> = {};

    for (const uri of PACKAGED_SOURCES) results[uri] = await probePackagedSource(uri);

    return JSON.stringify(results, null, 2);
  });

  const runStateProbe = () => probe.run(async () => {
    const playlist = createAudioPlaylist({ sources: [TONE_DATA_URI, TONE_DATA_URI, TONE_DATA_URI] });
    const replacement = createAudioPlayer(TONE_DATA_URI);

    try {
      playlist.playbackRate = 1.5;
      playlist.next();
      playlist.next();

      for (
        let attempt = 0;
        attempt < 100 && (!playlist.isLoaded || playlist.currentIndex !== 2);
        attempt += 1
      ) await wait(25);

      if (playlist.currentIndex !== 2) throw new Error(`连续调用 next() 后停在索引 ${playlist.currentIndex}。`);
      if (playlist.playbackRate !== 1.5) throw new Error(`播放列表倍速为 ${playlist.playbackRate}。`);

      replacement.play();
      replacement.replace(PACKAGED_SOURCES[0]);
      replacement.pause();
      await wait(500);

      if (replacement.playing) throw new Error('replace() 在 pause() 之后恢复了过期的播放请求。');

      return JSON.stringify({
        currentIndex: playlist.currentIndex,
        playbackRate: playlist.playbackRate,
        replacementPlaying: replacement.playing,
      }, null, 2);
    } finally {
      playlist.destroy();
      replacement.remove();
    }
  });

  const configureBackground = () => probe.run(async () => {
    await setAudioModeAsync({
      allowsBackgroundRecording: true,
      interruptionMode: 'duckOthers',
      shouldPlayInBackground: true,
    });

    player.loop = true;
    player.play();

    return '后台播放已配置并开始运行。请将应用切到后台，验证 AVSession 控制后再回到此处暂停。';
  });

  const verifyPitchBoundary = () => probe.run(async () => {
    try {
      player.shouldCorrectPitch = false;
    } catch (error) {
      return error instanceof Error ? error.message : String(error);
    }

    throw new Error('关闭音高修正不应成功。');
  });

  const busy = probe.state.phase === 'running';

  return (
    <>
      <Panel eyebrow="官方 Expo JS" title="通过 Harmony 原生模块播放 data URI">
        <DataRow label="原生状态" value={<Tag tone={status.isLoaded ? 'success' : 'signal'}>{status.playbackState}</Tag>} />
        <DataRow label="时间控制" value={status.timeControlStatus} />
        <DataRow label="播放进度" value={`${status.currentTime.toFixed(3)}s / ${status.duration.toFixed(3)}s`} />
        <DataRow label="音频采样" value={player.isAudioSamplingSupported ? '支持' : '不支持'} />
        <ActionRow>
          <ActionButton disabled={busy} label="运行 data URI 检测" onPress={() => void runDataUriProbe()} testID="audio-data-uri-probe" />
          <ActionButton disabled={busy} label="运行预加载检测" onPress={() => void runPreloadProbe()} tone="secondary" />
          <ActionButton disabled={busy} label="运行内置资源检测" onPress={() => void runPackagedProbe()} tone="secondary" />
          <ActionButton disabled={busy} label="运行状态检测" onPress={() => void runStateProbe()} tone="secondary" />
        </ActionRow>
        <Note>检测覆盖 JavaScript data URI 以及真实的 rawfile:// 与 asset:// WAV 资源。每个资源都必须成功加载，且恰好触发一次完成事件。</Note>
      </Panel>

      <Panel eyebrow="平台边界" title="后台媒体与不支持的 PCM 控制">
        <ActionRow>
          <ActionButton disabled={busy} label="开始后台循环播放" onPress={() => void configureBackground()} />
          <ActionButton
            label="暂停"
            onPress={() => {
              player.loop = false;
              player.pause();
            }}
            tone="secondary"
          />
          <ActionButton
            disabled={busy}
            label="验证音高报错"
            onPress={() => void verifyPitchBoundary()}
            tone="secondary"
          />
        </ActionRow>
        <Note>
          HarmonyOS AVPlayer 不提供解码后的 PCM 采样，也没有音高修正开关。模块会如实上报这些边界，而不是把空操作伪装成成功。
        </Note>
      </Panel>

      <ResultPanel state={probe.state} />
    </>
  );
}

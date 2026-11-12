/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Speech from 'expo-speech';
import { useEffect, useRef, useState } from 'react';
import { Platform, Switch } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function SpeechDemo() {
  const [voices, setVoices] = useState<Speech.Voice[]>([]);
  const [voice, setVoice] = useState('');
  const [text, setText] = useState('你好，今天适合出门走走。');
  const [language, setLanguage] = useState('zh-CN');
  const [rate, setRate] = useState('1');
  const [pitch, setPitch] = useState('1');
  const [volume, setVolume] = useState('1');
  const [useApplicationAudioSession, setUseApplicationAudioSession] = useState(true);
  const [events, setEvents] = useState<string[]>([]);
  const active = useRef(false);
  const sequence = useRef(0);
  const status = useAsyncResult();
  const playback = useAsyncResult();
  const busy = playback.state.phase === 'running';
  const canPause = Platform.OS === 'ios' || Platform.OS === 'web';
  const harmony = String(Platform.OS) === 'harmony';

  useEffect(() => {
    active.current = true;

    return () => {
      active.current = false;
      if (sequence.current > 0) void Speech.stop().catch(() => {});
    };
  }, []);

  const speak = () => playback.run(() => {
    const id = ++sequence.current;
    const record = (event: string) => {
      if (active.current) setEvents(rows => [...rows.slice(-19), `#${id} ${event}`]);
    };

    Speech.speak(text, {
      language: language || undefined,
      voice: voice || undefined,
      rate: rate.trim() ? Number(rate) : undefined,
      pitch: pitch.trim() ? Number(pitch) : undefined,
      volume: volume.trim() ? Number(volume) : undefined,
      ...(Platform.OS === 'ios' ? { useApplicationAudioSession } : {}),
      onStart: () => record('onStart'),
      onDone: () => record('onDone'),
      onStopped: () => record('onStopped'),
      onError: error => record(`onError ${error.message}`),
      ...(!harmony
        ? {
            onBoundary: ({ charIndex, charLength }: { charIndex: number; charLength: number }) => record(`onBoundary ${charIndex} + ${charLength}`),
          }
        : {}),
      ...(Platform.OS === 'web'
        ? {
          onMark: event => record(`onMark ${event.name}`),
          onResume: () => record('onResume'),
        } satisfies Partial<Speech.SpeechOptions>
        : {}),
    });

    return `已加入播报队列 #${id}`;
  });

  const changePlayback = (method: 'stop' | 'pause' | 'resume', label: string) => void playback.run(async () => {
    await Speech[method]();
    return label;
  });

  return (
    <>
      <Panel title="系统音色">
        <DataRow label="最大文本长度" value={Speech.maxSpeechInputLength} />
        <ActionRow>
          <ActionButton
            disabled={status.state.phase === 'running'}
            label="查询可用音色"
            onPress={() => void status.run(async () => {
              const available = await Speech.getAvailableVoicesAsync();
              setVoices(available);
              return json(available);
            })}
            testID="speech-inspect"
          />
          <ActionButton disabled={status.state.phase === 'running'} label="查询是否正在播报" onPress={() => void status.run(async () => String(await Speech.isSpeakingAsync()))} tone="secondary" />
        </ActionRow>
        <ResultPanel state={status.state} />
      </Panel>

      <Panel title="语音播报">
        <Field label="播报文本" multiline onChangeText={setText} testID="speech-text" value={text} />
        <Field label="语言标签" onChangeText={setLanguage} value={language} />
        <Field label="音色 ID" onChangeText={setVoice} value={voice} />
        {voices.length > 0
          ? (
              <ActionRow>
                {voices.map(item => (
                  <ActionButton key={item.identifier} label={`${item.name} · ${item.language}`} onPress={() => setVoice(item.identifier)} tone={voice === item.identifier ? 'primary' : 'secondary'} />
                ))}
              </ActionRow>
            )
          : null}
        <Field keyboardType="decimal-pad" label="语速" onChangeText={setRate} value={rate} />
        <Field keyboardType="decimal-pad" label="音调" onChangeText={setPitch} value={pitch} />
        <Field keyboardType="decimal-pad" label="音量" onChangeText={setVolume} value={volume} />
        {Platform.OS === 'ios'
          ? <DataRow
              label="使用应用音频会话"
              value={
                <Switch accessibilityLabel="使用应用音频会话" value={useApplicationAudioSession} onValueChange={setUseApplicationAudioSession} />
              }
            />
          : null}
        <ActionRow>
          <ActionButton disabled={busy} label="播报文本" onPress={() => void speak()} testID="speech-speak" />
          <ActionButton disabled={busy} label="停止播报" onPress={() => changePlayback('stop', '已停止')} testID="speech-stop" tone="secondary" />
          {canPause
            ? (
                <>
                  <ActionButton disabled={busy} label="暂停播报" onPress={() => changePlayback('pause', '已暂停')} tone="secondary" />
                  <ActionButton disabled={busy} label="继续播报" onPress={() => changePlayback('resume', '已继续')} tone="secondary" />
                </>
              )
            : null}
        </ActionRow>
        <ResultPanel state={playback.state} />
        {events.length > 0 ? <DataRow label="最近播报事件" value={events.join('\n')} /> : null}
      </Panel>
    </>
  );
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Asset } from 'expo-asset';
import { launchImageLibraryAsync } from 'expo-image-picker';
import { LivePhotoView } from 'expo-live-photo';
import type { ContentFit, LivePhotoAsset, LivePhotoViewType } from 'expo-live-photo';
import { useRef, useState } from 'react';
import { Platform, StyleSheet, View } from 'react-native';

import photoAsset from '../../assets/live-photo/photo.jpg';
import videoAsset from '../../assets/live-photo/video.mp4';
import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function LivePhotoDemo() {
  const view = useRef<LivePhotoViewType>(null);
  const [source, setSource] = useState<LivePhotoAsset | null>(null);
  const [photo, setPhoto] = useState('');
  const [video, setVideo] = useState('');
  const [muted, setMuted] = useState(true);
  const [fit, setFit] = useState<ContentFit>('contain');
  const [gesture, setGesture] = useState(true);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState('');
  const [events, setEvents] = useState<string[]>([]);
  const action = useAsyncResult();
  const available = LivePhotoView.isAvailable();
  const busy = action.state.phase === 'running';

  function record(event: string) {
    setEvents(previous => [...previous.slice(-7), event]);
  }

  function load(nextSource: LivePhotoAsset | null) {
    if (nextSource?.photoUri !== source?.photoUri || nextSource?.pairedVideoUri !== source?.pairedVideoUri) {
      setError('');
      setReady(false);
    }
    setSource(nextSource);
  }

  function fillSource(pair: LivePhotoAsset) {
    setPhoto(pair.photoUri);
    setVideo(pair.pairedVideoUri);
    load(pair);
  }

  async function loadSample() {
    const [photo, video] = await Asset.loadAsync([photoAsset, videoAsset]);
    if (!photo?.localUri || !video?.localUri) throw new Error('找不到内置实况照片。');

    fillSource({ photoUri: photo.localUri, pairedVideoUri: video.localUri });
    return '已载入样例';
  }

  async function pick() {
    const result = await launchImageLibraryAsync({ mediaTypes: ['livePhotos'] });
    if (result.canceled) return '已取消选择';

    const asset = result.assets[0];
    if (asset?.type !== 'livePhoto' || !asset.pairedVideoAsset?.uri) {
      throw new Error('所选实况照片缺少配对视频。');
    }

    fillSource({ photoUri: asset.uri, pairedVideoUri: asset.pairedVideoAsset.uri });
    return '已选择实况照片';
  }

  return (
    <>
      <Panel title="LivePhotoView">
        <DataRow label="isAvailable()" value={String(available)} />
        {available
          ? (
              <>
                <View style={styles.preview}>
                  <LivePhotoView
                    contentFit={fit}
                    isMuted={muted}
                    onLoadComplete={() => {
                      setReady(true);
                      record('onLoadComplete');
                    }}
                    onLoadError={({ message }) => {
                      setReady(false);
                      setError(message);
                      record('onLoadError');
                    }}
                    onLoadStart={() => {
                      setReady(false);
                      setError('');
                      record('onLoadStart');
                    }}
                    onPlaybackStart={() => record('onPlaybackStart')}
                    onPlaybackStop={() => record('onPlaybackStop')}
                    onPreviewPhotoLoad={() => record('onPreviewPhotoLoad')}
                    ref={view}
                    source={source}
                    style={StyleSheet.absoluteFill}
                    testID="live-photo-view"
                    useDefaultGestureRecognizer={gesture}
                  />
                </View>
                <ActionRow>
                  <ActionButton disabled={!ready} label="完整播放" onPress={() => view.current?.startPlayback('full')} testID="live-photo-play" />
                  <ActionButton disabled={!ready} label="播放 hint" onPress={() => view.current?.startPlayback('hint')} testID="live-photo-hint" tone="secondary" />
                  <ActionButton disabled={!ready} label="停止播放" onPress={() => view.current?.stopPlayback()} testID="live-photo-stop" tone="secondary" />
                </ActionRow>
                <ActionRow>
                  <ActionButton label={muted ? '取消静音' : '静音'} onPress={() => setMuted(value => !value)} testID="live-photo-mute" tone="secondary" />
                  <ActionButton label={fit === 'contain' ? '裁切填满' : '完整显示'} onPress={() => setFit(value => value === 'contain' ? 'cover' : 'contain')} testID="live-photo-fit" tone="secondary" />
                  <ActionButton label={gesture ? '关闭长按播放' : '开启长按播放'} onPress={() => setGesture(value => !value)} testID="live-photo-gesture" tone="secondary" />
                </ActionRow>
              </>
            )
          : null}
      </Panel>

      {available
        ? (
            <>
              <Panel title="实况照片来源">
                <Field label="图片 URI" onChangeText={setPhoto} placeholder="file:///…/photo.jpg" value={photo} testID="live-photo-photo-uri" />
                <Field label="配对视频 URI" onChangeText={setVideo} placeholder="file:///…/video.mp4" value={video} testID="live-photo-video-uri" />
                <ActionRow>
                  <ActionButton disabled={busy} label="加载实况照片" onPress={() => load({ photoUri: photo.trim(), pairedVideoUri: video.trim() })} testID="live-photo-custom" />
                  <ActionButton disabled={!source || busy} label="清空画面" onPress={() => load(null)} testID="live-photo-clear" tone="secondary" />
                  {String(Platform.OS) === 'harmony'
                    ? (
                        <ActionButton disabled={busy} label="加载样例" onPress={() => void action.run(loadSample)} testID="live-photo-load" tone="secondary" />
                      )
                    : null}
                  <ActionButton disabled={busy} label="从图库选择" onPress={() => void action.run(pick)} testID="live-photo-pick" tone="secondary" />
                </ActionRow>
                <ResultPanel state={action.state} />
                <ResultPanel state={error ? { phase: 'error', output: error } : { phase: 'idle' }} />
              </Panel>

              <Panel title="视图事件">
                <DataRow label="最近事件" value={events.join('\n') || '等待事件'} />
                <ActionButton disabled={events.length === 0} label="清空记录" onPress={() => setEvents([])} testID="live-photo-reset-events" tone="secondary" />
              </Panel>
            </>
          )
        : null}
    </>
  );
}

const styles = StyleSheet.create({
  preview: { backgroundColor: palette.canvas, borderRadius: 12, height: 220, overflow: 'hidden' },
});

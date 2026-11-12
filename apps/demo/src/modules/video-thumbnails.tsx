/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Asset } from 'expo-asset';
import { getDocumentAsync } from 'expo-document-picker';
import { File } from 'expo-file-system';
import { Image } from 'expo-image';
import { getThumbnailAsync } from 'expo-video-thumbnails';
import type { VideoThumbnailsResult } from 'expo-video-thumbnails';
import { useEffect, useRef, useState } from 'react';
import { Platform, StyleSheet } from 'react-native';

import sample from '../../assets/live-photo/video.mp4';
import { json } from '../format';
import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

function parseHeaders(text: string): Record<string, string> | undefined {
  if (!text.trim()) return undefined;

  const headers: unknown = JSON.parse(text);
  if (!headers || typeof headers !== 'object' || Array.isArray(headers)
    || Object.values(headers).some(value => typeof value !== 'string')) {
    throw new Error('请求头需要使用 JSON 对象，每个值都要写成字符串。');
  }
  return Object.fromEntries(Object.entries(headers));
}

function deleteFile(file: File | null) {
  if (file?.exists) file.delete();
}

export function VideoThumbnailsDemo() {
  const action = useAsyncResult();
  const thumbnailFile = useRef<File | null>(null);
  const pickedFile = useRef<File | null>(null);
  const mounted = useRef(true);
  const [preview, setPreview] = useState<VideoThumbnailsResult | null>(null);
  const [source, setSource] = useState('');
  const [time, setTime] = useState('1000');
  const [quality, setQuality] = useState('0.8');
  const [headers, setHeaders] = useState('');
  const busy = action.state.phase === 'running';

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      deleteFile(thumbnailFile.current);
      deleteFile(pickedFile.current);
    };
  }, []);

  async function loadSample() {
    const asset = await Asset.fromModule(sample).downloadAsync();
    if (!asset.localUri) throw new Error('找不到内置视频。');
    if (mounted.current) setSource(asset.localUri);
    return asset.localUri;
  }

  async function pickVideo() {
    const result = await getDocumentAsync({ type: 'video/*', copyToCacheDirectory: true });
    if (result.canceled) return '已取消选择';

    const asset = result.assets[0];
    if (!asset) throw new Error('选择器没有返回视频。');

    const file = new File(asset.uri);
    if (!mounted.current) {
      deleteFile(file);
      return '';
    }

    deleteFile(pickedFile.current);
    pickedFile.current = file;
    setSource(asset.uri);
    return asset.name;
  }

  async function capture(useDefaults: boolean) {
    const uri = source.trim() || await loadSample();
    const result = await getThumbnailAsync(uri, useDefaults
      ? undefined
      : {
          time: time.trim() ? Number(time) : undefined,
          quality: quality.trim() ? Number(quality) : undefined,
          headers: parseHeaders(headers),
        });
    const file = new File(result.uri);
    if (!mounted.current) {
      deleteFile(file);
      return '';
    }

    deleteFile(thumbnailFile.current);
    thumbnailFile.current = file;
    setPreview(result);
    return json({ ...result, bytes: file.size });
  }

  if (Platform.OS === 'web') {
    return <Panel title="视频提帧"><DataRow label="提帧" value="当前设备不可用" /></Panel>;
  }

  return (
    <Panel title="getThumbnailAsync">
      <Field
        label="视频 URI"
        onChangeText={setSource}
        placeholder="内置视频"
        testID="video-thumbnails-source"
        value={source}
      />
      <ActionRow>
        <ActionButton disabled={busy} label="载入样例地址" onPress={() => void action.run(loadSample)} tone="secondary" />
        <ActionButton disabled={busy} label="选择视频" onPress={() => void action.run(pickVideo)} testID="video-thumbnails-pick" tone="secondary" />
      </ActionRow>
      <Field keyboardType="numbers-and-punctuation" label="提帧时间（毫秒）" onChangeText={setTime} testID="video-thumbnails-time" value={time} />
      <Field keyboardType="decimal-pad" label="JPEG 质量（0 到 1）" onChangeText={setQuality} testID="video-thumbnails-quality" value={quality} />
      <Field label="HTTP 请求头（JSON）" onChangeText={setHeaders} placeholder='{"Accept":"video/mp4"}' testID="video-thumbnails-headers" value={headers} />
      <ActionRow>
        <ActionButton disabled={busy} label="提取缩略图" onPress={() => void action.run(() => capture(false))} testID="video-thumbnails-custom" />
        <ActionButton disabled={busy} label="按默认设置提取" onPress={() => void action.run(() => capture(true))} testID="video-thumbnails-default" tone="secondary" />
      </ActionRow>
      {preview
        ? (
            <Image
              accessibilityLabel="视频缩略图"
              contentFit="contain"
              source={preview.uri}
              style={styles.preview}
              testID="video-thumbnails-preview"
            />
          )
        : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

const styles = StyleSheet.create({
  preview: { height: 210, borderRadius: 12, backgroundColor: palette.surfaceRaised },
});

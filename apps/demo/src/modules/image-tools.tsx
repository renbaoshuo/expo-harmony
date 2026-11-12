/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Asset } from 'expo-asset';
import { Image, useImage } from 'expo-image';
import type { ImageCacheConfig, ImageLoadOptions, ImagePrefetchOptions, ImageRef } from 'expo-image';
import { useEffect, useRef, useState } from 'react';
import { Platform, StyleSheet } from 'react-native';

import animation from '../../assets/image/animation.gif';
import sample from '../../assets/image/sample.png';
import { json } from '../format';
import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { Cycle, optionalNumber, Toggle } from './visual-controls';

const prefetchPolicies: NonNullable<ImagePrefetchOptions['cachePolicy']>[] = ['memory-disk', 'disk', 'memory'];
const defaultCacheConfig: ImageCacheConfig = { maxDiskSize: 0, maxMemoryCost: 0, maxMemoryCount: 0 };
const harmony = String(Platform.OS) === 'harmony';

export function parseHeaders(text: string): Record<string, string> | undefined {
  if (!text.trim()) return undefined;

  const headers: unknown = JSON.parse(text);
  if (typeof headers !== 'object' || headers === null || Array.isArray(headers) || Object.values(headers).some(value => typeof value !== 'string')) {
    throw new Error('请求头需要是 JSON 对象，值需要是字符串。');
  }
  return headers as Record<string, string>;
}

export function ImageTools({ defaultUrl }: { defaultUrl: string }) {
  return (
    <>
      <ReferenceDemo />
      <PrefetchDemo defaultUrl={defaultUrl} />
      {Platform.OS !== 'web'
        ? (
            <>
              <HashDemo />
              <CacheDemo defaultUrl={defaultUrl} />
            </>
          )
        : null}
    </>
  );
}

function ReferenceDemo() {
  const action = useAsyncResult();
  const [source, setSource] = useState(Asset.fromModule(sample).uri);
  const [maxWidth, setMaxWidth] = useState('80');
  const [maxHeight, setMaxHeight] = useState('80');
  const [tint, setTint] = useState('');
  const [image, setImage] = useState<ImageRef | null>(null);
  const [hook, setHook] = useState<{ source: string; options: ImageLoadOptions; revision: number }>();
  const mounted = useRef(true);
  const busy = action.state.phase === 'running';

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);
  useEffect(() => () => image?.release(), [image]);

  function loadOptions() {
    return {
      maxWidth: optionalNumber(maxWidth, '最大宽度'),
      maxHeight: optionalNumber(maxHeight, '最大高度'),
      tintColor: tint.trim() || undefined,
    };
  }

  return (
    <Panel title="图片引用">
      <Field label="图片 URI" value={source} onChangeText={setSource} />
      <ActionRow>
        <ActionButton label="本地样图" onPress={() => setSource(Asset.fromModule(sample).uri)} tone="secondary" />
        <ActionButton label="GIF" onPress={() => setSource(Asset.fromModule(animation).uri)} tone="secondary" />
        <ActionButton label="无效图片" onPress={() => setSource('data:image/png;base64,AAAA')} tone="secondary" />
      </ActionRow>
      <Field label="最大宽度" value={maxWidth} onChangeText={setMaxWidth} keyboardType="number-pad" />
      <Field label="最大高度" value={maxHeight} onChangeText={setMaxHeight} keyboardType="number-pad" />
      <Field label="着色" value={tint} onChangeText={setTint} placeholder="无着色" />
      <ActionRow>
        <ActionButton
          disabled={busy || !source.trim()}
          label="加载（loadAsync）"
          onPress={() => void action.run(async () => {
            const value = await Image.loadAsync(source.trim(), loadOptions());
            const metadata = imageMetadata(value);
            if (mounted.current) setImage(value);
            else value.release();
            return json(metadata);
          })}
        />
        <ActionButton
          disabled={busy || !source.trim()}
          label="加载（useImage）"
          onPress={() => void action.run(() => {
            const options = loadOptions();
            setHook(previous => ({ source: source.trim(), options, revision: (previous?.revision ?? 0) + 1 }));
            return '已提交加载请求';
          })}
          tone="secondary"
        />
        <ActionButton
          disabled={!image || busy}
          label="释放图片引用"
          onPress={() => {
            setImage(null);
            action.clear();
          }}
          tone="secondary"
        />
      </ActionRow>
      {image ? <Image source={image} style={styles.preview} contentFit="contain" /> : null}
      {hook ? <HookPreview {...hook} /> : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function HookPreview({ source, options, revision }: { source: string; options: ImageLoadOptions; revision: number }) {
  const [failure, setFailure] = useState<{ message: string; retry: () => void; revision: number }>();
  const image = useImage(source, {
    ...options,
    onError: (error, retry) => setFailure({ message: error.message, retry, revision }),
  }, [revision]);

  if (failure?.revision === revision) {
    return (
      <>
        <DataRow label="useImage" value={failure.message} />
        <ActionButton
          label="重试加载"
          onPress={() => {
            setFailure(undefined);
            failure.retry();
          }}
          tone="secondary"
        />
      </>
    );
  }

  return image
    ? (
        <>
          <Image source={image} style={styles.preview} contentFit="contain" />
          <DataRow label="useImage" value={json(imageMetadata(image))} />
        </>
      )
    : null;
}

function PrefetchDemo({ defaultUrl }: { defaultUrl: string }) {
  const action = useAsyncResult();
  const [input, setInput] = useState(defaultUrl);
  const [headers, setHeaders] = useState('{}');
  const [policy, setPolicy] = useState<NonNullable<ImagePrefetchOptions['cachePolicy']>>('memory-disk');
  const busy = action.state.phase === 'running';

  const run = (asOptions: boolean) => void action.run(async () => {
    const urls = input.split(/\s+/).filter(Boolean);
    if (!urls.length) throw new Error('请输入图片地址。');
    const source = urls.length === 1 ? urls[0]! : urls;
    const success = asOptions
      ? await Image.prefetch(source, { cachePolicy: policy, headers: parseHeaders(headers) })
      : await Image.prefetch(source, policy);
    return json(success);
  });

  return (
    <Panel title="预取图片">
      <Field label="图片 URL（每行一个）" multiline value={input} onChangeText={setInput} />
      <Field label="请求头（JSON）" value={headers} onChangeText={setHeaders} />
      <Cycle label="缓存策略" value={policy} choices={prefetchPolicies} onChange={setPolicy} />
      <ActionRow>
        <ActionButton disabled={busy} label="按缓存策略预取" onPress={() => run(false)} />
        <ActionButton disabled={busy} label="按选项预取" onPress={() => run(true)} tone="secondary" />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function HashDemo() {
  const action = useAsyncResult();
  const [uri, setUri] = useState(Asset.fromModule(sample).uri);
  const [width, setWidth] = useState(4);
  const [height, setHeight] = useState(3);
  const [components, setComponents] = useState<'数组' | '对象'>('数组');
  const [useRefSource, setUseRefSource] = useState(false);
  const [hash, setHash] = useState<{ blurhash: string } | { thumbhash: string }>();
  const busy = action.state.phase === 'running';

  const generate = (kind: 'blurhash' | 'thumbhash') => void action.run(async () => {
    const image = useRefSource ? await Image.loadAsync(uri.trim(), { maxWidth: 100, maxHeight: 100 }) : null;
    const source = image ?? uri.trim();
    try {
      const value = kind === 'blurhash'
        ? await Image.generateBlurhashAsync(source, components === '数组' ? [width, height] : { width, height })
        : await Image.generateThumbhashAsync(source);
      setHash(value ? kind === 'blurhash' ? { blurhash: value } : { thumbhash: value } : undefined);
      return json(value);
    } finally {
      image?.release();
    }
  });

  return (
    <Panel title="图片哈希">
      <Field label="图片 URI" value={uri} onChangeText={setUri} />
      <ActionRow>
        <Toggle label="传入 ImageRef" value={useRefSource} onChange={setUseRefSource} />
        <Cycle label="BlurHash 分量写法" value={components} choices={['数组', '对象']} onChange={setComponents} />
        <Cycle label="横向分量" value={width} choices={[1, 2, 3, 4, 5, 6, 7, 8, 9]} onChange={setWidth} />
        <Cycle label="纵向分量" value={height} choices={[1, 2, 3, 4, 5, 6, 7, 8, 9]} onChange={setHeight} />
      </ActionRow>
      <ActionRow>
        <ActionButton disabled={busy || !uri.trim()} label="生成 BlurHash" onPress={() => generate('blurhash')} />
        <ActionButton disabled={busy || !uri.trim()} label="生成 ThumbHash" onPress={() => generate('thumbhash')} tone="secondary" />
      </ActionRow>
      {hash ? <Image source={hash} contentFit="fill" style={styles.preview} /> : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function CacheDemo({ defaultUrl }: { defaultUrl: string }) {
  const action = useAsyncResult();
  const [cacheKey, setCacheKey] = useState(defaultUrl);
  const [uri, setUri] = useState('');
  const [cached, setCached] = useState<ImageRef | null>(null);
  const [diskSize, setDiskSize] = useState('');
  const [memoryCost, setMemoryCost] = useState('');
  const [memoryCount, setMemoryCount] = useState('');
  const mounted = useRef(true);
  const configured = useRef(false);
  const busy = action.state.phase === 'running';
  const canConfigure = harmony || Platform.OS === 'ios';

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      if (configured.current) Image.configureCache(defaultCacheConfig);
    };
  }, []);
  useEffect(() => () => cached?.release(), [cached]);

  const write = (reference: boolean) => void action.run(async () => {
    const image = reference ? await Image.loadAsync(uri.trim(), { maxWidth: 320, maxHeight: 320 }) : null;
    try {
      await Image.writeToCacheAsync(image ?? uri.trim(), cacheKey.trim());
      return cacheKey.trim();
    } finally {
      image?.release();
    }
  });

  return (
    <Panel title="图片缓存">
      <Field label="缓存键" value={cacheKey} onChangeText={setCacheKey} />
      <Field label="本地文件 URI" value={uri} onChangeText={setUri} />
      <ActionButton
        disabled={busy}
        label="下载样图到本地"
        onPress={() => void action.run(async () => {
          const asset = await Asset.fromModule(sample).downloadAsync();
          if (!asset.localUri) throw new Error('未取得样图的本地地址。');
          setUri(asset.localUri);
          return asset.localUri;
        })}
        tone="secondary"
      />
      <ActionRow>
        <ActionButton disabled={busy || !uri.trim() || !cacheKey.trim()} label="写入文件" onPress={() => write(false)} />
        <ActionButton disabled={busy || !uri.trim() || !cacheKey.trim()} label="写入 ImageRef" onPress={() => write(true)} />
        <ActionButton disabled={busy || !cacheKey.trim()} label="读取缓存路径" onPress={() => void action.run(async () => json(await Image.getCachePathAsync(cacheKey.trim())))} tone="secondary" />
        <ActionButton
          disabled={busy || !cacheKey.trim()}
          label="读取缓存图片"
          onPress={() => void action.run(async () => {
            const value = await Image.readFromCacheAsync(cacheKey.trim());
            const metadata = value ? imageMetadata(value) : null;
            if (mounted.current) setCached(value);
            else value?.release();
            return json(metadata);
          })}
          tone="secondary"
        />
        <ActionButton disabled={busy} label="清理内存缓存" onPress={() => void action.run(async () => json(await Image.clearMemoryCache()))} tone="secondary" />
        <ActionButton disabled={busy} label="清理磁盘缓存" onPress={() => void action.run(async () => json(await Image.clearDiskCache()))} tone="secondary" />
      </ActionRow>
      {cached ? <Image source={cached} style={styles.preview} contentFit="contain" /> : null}
      {canConfigure
        ? (
            <>
              <Field label="磁盘缓存上限（字节）" value={diskSize} onChangeText={setDiskSize} keyboardType="number-pad" />
              <Field label="内存缓存上限（字节）" value={memoryCost} onChangeText={setMemoryCost} keyboardType="number-pad" />
              <Field label="内存缓存条目数上限" value={memoryCount} onChangeText={setMemoryCount} keyboardType="number-pad" />
              <ActionRow>
                <ActionButton
                  disabled={busy}
                  label="应用缓存上限"
                  onPress={() => void action.run(() => {
                    const config = {
                      maxDiskSize: optionalNumber(diskSize, '磁盘缓存上限'),
                      maxMemoryCost: optionalNumber(memoryCost, '内存缓存上限'),
                      maxMemoryCount: optionalNumber(memoryCount, '缓存条目数上限'),
                    };
                    Image.configureCache(config);
                    configured.current = true;
                    return json(config);
                  })}
                />
                <ActionButton
                  disabled={busy}
                  label="取消缓存上限"
                  onPress={() => void action.run(() => {
                    Image.configureCache(defaultCacheConfig);
                    configured.current = false;
                    return json(defaultCacheConfig);
                  })}
                  tone="secondary"
                />
              </ActionRow>
            </>
          )
        : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function imageMetadata(image: ImageRef) {
  const { width, height, scale, mediaType, nativeRefType, isAnimated } = image;
  return { width, height, scale, mediaType, nativeRefType, isAnimated };
}

const styles = StyleSheet.create({
  preview: { backgroundColor: palette.surfaceRaised, borderRadius: 12, height: 120, width: '100%' },
});

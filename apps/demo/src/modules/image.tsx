/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Asset } from 'expo-asset';
import { File } from 'expo-file-system';
import { Image, ImageBackground } from 'expo-image';
import type { ImageContentFit, ImageDecodeFormat, ImageProps, ImageSource, ImageTransition } from 'expo-image';
import { requireOptionalNativeModule } from 'expo-modules-core';
import type { ImageModuleEvents, ImageNativeModule } from 'expo-image';
import { useEffect, useRef, useState } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';

import animation from '../../assets/image/animation.gif';
import sample from '../../assets/image/sample.png';
import { json } from '../format';
import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { ImageTools, parseHeaders } from './image-tools';
import { Cycle, optionalNumber, Toggle } from './visual-controls';

const fits: ImageContentFit[] = ['contain', 'cover', 'fill', 'none', 'scale-down'];
const policies: NonNullable<ImageProps['cachePolicy']>[] = ['disk', 'memory', 'memory-disk', 'none'];
const timings: NonNullable<ImageTransition['timing']>[] = ['ease-in-out', 'ease-in', 'ease-out', 'linear'];
const positions = {
  '居中': 'center',
  '左上': 'top left',
  '右下': 'bottom right',
  '偏移 12 像素': { left: 12, top: 12 },
  '偏移 25%': { right: '25%', bottom: '25%' },
} satisfies Record<string, NonNullable<ImageProps['contentPosition']>>;
const placeholder = { blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj' };
const sampleSource = { uri: Asset.fromModule(sample).uri, width: 160, height: 96 };
const gifSource = { uri: Asset.fromModule(animation).uri, width: 64, height: 40 };
const defaultUrl = 'https://reactnative.dev/img/tiny_logo.png';

type ImageEvent = Parameters<ImageModuleEvents['imageLoaded']>[0];
type ImageSection = '来源' | '显示' | '加载' | '无障碍' | '操作';

export function ImageDemo() {
  const view = useRef<Image>(null);
  const sourceAction = useAsyncResult();
  const action = useAsyncResult();
  const [source, setSource] = useState<ImageProps['source']>(sample);
  const [uri, setUri] = useState(defaultUrl);
  const [headers, setHeaders] = useState('{}');
  const [cacheKey, setCacheKey] = useState('');
  const [width, setWidth] = useState('');
  const [height, setHeight] = useState('');
  const [isAnimated, setIsAnimated] = useState(false);
  const [fit, setFit] = useState<ImageContentFit>('contain');
  const [placeholderFit, setPlaceholderFit] = useState<ImageContentFit>('scale-down');
  const [placeholderSource, setPlaceholderSource] = useState<'无' | '样图' | 'BlurHash'>('BlurHash');
  const [placeholderProp, setPlaceholderProp] = useState<'placeholder' | 'defaultSource' | 'loadingIndicatorSource'>('placeholder');
  const [position, setPosition] = useState<keyof typeof positions>('居中');
  const [tint, setTint] = useState('');
  const [blur, setBlur] = useState(0);
  const [transitionDuration, setTransitionDuration] = useState(300);
  const [transitionTiming, setTransitionTiming] = useState<NonNullable<ImageTransition['timing']>>('ease-in-out');
  const [transitionProp, setTransitionProp] = useState<'对象' | '数字' | 'fadeDuration'>('对象');
  const [transitionEffect, setTransitionEffect] = useState<'cross-dissolve' | '关闭'>('cross-dissolve');
  const [resizeMode, setResizeMode] = useState<NonNullable<ImageProps['resizeMode']>>('contain');
  const [legacyFit, setLegacyFit] = useState(false);
  const [round, setRound] = useState(true);
  const [cachePolicy, setCachePolicy] = useState<NonNullable<ImageProps['cachePolicy']>>('disk');
  const [priority, setPriority] = useState<NonNullable<ImageProps['priority']>>('normal');
  const [allowDownscaling, setAllowDownscaling] = useState(true);
  const [autoplay, setAutoplay] = useState(true);
  const [decodeFormat, setDecodeFormat] = useState<ImageDecodeFormat>('argb');
  const [recyclingKey, setRecyclingKey] = useState('');
  const [accessible, setAccessible] = useState(true);
  const [focusable, setFocusable] = useState(false);
  const [accessibilityLabel, setAccessibilityLabel] = useState('');
  const [alt, setAlt] = useState('图片样例');
  const [section, setSection] = useState<ImageSection>('显示');
  const [events, setEvents] = useState<string[]>([]);
  const [listen, setListen] = useState(false);
  const [nativeEvent, setNativeEvent] = useState<ImageEvent>();
  const busy = action.state.phase === 'running';
  const native = Platform.OS !== 'web';
  const placeholderValue = placeholderSource === '样图' ? sampleSource : placeholderSource === 'BlurHash' ? placeholder : undefined;

  useEffect(() => {
    if (!listen) return;
    const image = requireOptionalNativeModule<ImageNativeModule>('ExpoImage');
    const subscription = image?.addListener('imageLoaded', setNativeEvent);

    return () => subscription?.remove();
  }, [listen]);

  function record(name: string, detail?: unknown) {
    setEvents(events => [...events.slice(-5), detail === undefined ? name : `${name} ${JSON.stringify(detail)}`]);
  }

  function applySource() {
    void sourceAction.run(() => {
      const url = uri.trim();
      if (!url) throw new Error('请输入图片地址。');
      const next: ImageSource = {
        uri: url,
        headers: parseHeaders(headers),
        cacheKey: cacheKey.trim() || undefined,
        width: optionalNumber(width, '来源宽度'),
        height: optionalNumber(height, '来源高度'),
        isAnimated: isAnimated || undefined,
      };
      setSource(next);
      return json(next);
    });
  }

  function invoke(method: 'startAnimating' | 'stopAnimating' | 'lockResourceAsync' | 'unlockResourceAsync' | 'reloadAsync') {
    void action.run(async () => {
      if (!view.current) throw new Error('图片视图尚未就绪。');
      await view.current[method]();
      return `${method}()`;
    });
  }

  return (
    <>
      <Panel title="Image">
        <Image
          ref={view}
          source={source}
          placeholder={placeholderProp === 'placeholder' ? placeholderValue : undefined}
          defaultSource={placeholderProp === 'defaultSource' ? placeholderValue : undefined}
          loadingIndicatorSource={placeholderProp === 'loadingIndicatorSource' ? placeholderValue : undefined}
          contentFit={legacyFit ? undefined : fit}
          resizeMode={legacyFit ? resizeMode : undefined}
          placeholderContentFit={placeholderFit}
          contentPosition={positions[position]}
          cachePolicy={cachePolicy}
          priority={priority}
          blurRadius={blur}
          tintColor={tint.trim() || undefined}
          transition={transitionEffect === '关闭' || transitionProp === 'fadeDuration'
            ? undefined
            : transitionProp === '数字'
              ? transitionDuration
              : { duration: transitionDuration, timing: transitionTiming, effect: transitionEffect }}
          fadeDuration={transitionEffect !== '关闭' && transitionProp === 'fadeDuration' ? transitionDuration : undefined}
          allowDownscaling={allowDownscaling}
          autoplay={autoplay}
          decodeFormat={decodeFormat}
          recyclingKey={recyclingKey || undefined}
          accessible={accessible}
          focusable={focusable}
          accessibilityLabel={accessibilityLabel || undefined}
          alt={alt}
          style={[styles.preview, round ? styles.rounded : null]}
          onLoadStart={() => record('onLoadStart')}
          onLoad={event => record('onLoad', event)}
          onDisplay={() => record('onDisplay')}
          onLoadEnd={() => record('onLoadEnd')}
          onProgress={event => record('onProgress', event)}
          onError={event => record('onError', event)}
          testID="image-preview"
        />
        <ActionRow>
          {(['来源', '显示', '加载', '无障碍', '操作'] as const).map(value => (
            <ActionButton key={value} label={value} onPress={() => setSection(value)} tone={section === value ? 'primary' : 'secondary'} />
          ))}
        </ActionRow>
        {section === '来源'
          ? (
              <>
                <ActionRow>
                  <ActionButton label="本地样图" onPress={() => setSource(sample)} testID="image-local" tone="secondary" />
                  <ActionButton label="GIF" onPress={() => setSource(animation)} testID="image-animation" tone="secondary" />
                  <ActionButton label="多个图片来源" onPress={() => setSource([sampleSource, gifSource])} tone="secondary" />
                  <ActionButton label="仅显示占位图" onPress={() => setSource(null)} tone="secondary" />
                  <ActionButton label="加载无效图片" onPress={() => setSource('data:image/png;base64,AAAA')} tone="secondary" />
                  {native
                    ? (
                        <ActionButton
                          disabled={sourceAction.state.phase === 'running'}
                          label="data URI"
                          onPress={() => void sourceAction.run(async () => {
                            const asset = await Asset.fromModule(sample).downloadAsync();
                            if (!asset.localUri) throw new Error('未取得样图的本地地址。');
                            setSource(`data:image/png;base64,${await new File(asset.localUri).base64()}`);
                            return '已载入样图';
                          })}
                          tone="secondary"
                        />
                      )
                    : null}
                </ActionRow>
                <Field label="图片 URI" onChangeText={setUri} value={uri} />
                <Field label="请求头（JSON）" onChangeText={setHeaders} value={headers} />
                <Field label="缓存键" onChangeText={setCacheKey} value={cacheKey} placeholder="默认使用图片地址" />
                <Field label="来源宽度" onChangeText={setWidth} value={width} keyboardType="number-pad" />
                <Field label="来源高度" onChangeText={setHeight} value={height} keyboardType="number-pad" />
                <ActionRow>
                  <Toggle label="标记为动画" value={isAnimated} onChange={setIsAnimated} />
                  <ActionButton disabled={sourceAction.state.phase === 'running'} label="加载 URI" onPress={applySource} />
                </ActionRow>
                <ResultPanel state={sourceAction.state} />
              </>
            )
          : null}
        {section === '显示'
          ? (
              <>
                <Field label="着色" value={tint} onChangeText={setTint} placeholder="无着色" />
                <ActionRow>
                  {legacyFit
                    ? (
                        <Cycle label="resizeMode" value={resizeMode} choices={['cover', 'contain', 'stretch', 'repeat', 'center']} onChange={setResizeMode} />
                      )
                    : <Cycle label="内容适配" value={fit} choices={fits} onChange={setFit} />}
                  <Toggle label="使用 resizeMode" value={legacyFit} onChange={setLegacyFit} />
                  <Cycle label="内容位置" value={position} choices={['居中', '左上', '右下', '偏移 12 像素', '偏移 25%']} onChange={setPosition} />
                  <Cycle label="模糊半径" value={blur} choices={[0, 4, 8, 16]} onChange={setBlur} />
                  <Toggle label="圆角" value={round} onChange={setRound} />
                  <Cycle label="占位图" value={placeholderSource} choices={['无', '样图', 'BlurHash']} onChange={setPlaceholderSource} />
                  <Cycle label="占位图属性" value={placeholderProp} choices={['placeholder', 'defaultSource', 'loadingIndicatorSource']} onChange={setPlaceholderProp} />
                  <Cycle label="占位图适配" value={placeholderFit} choices={fits} onChange={setPlaceholderFit} />
                </ActionRow>
              </>
            )
          : null}
        {section === '加载'
          ? (
              <>
                <Field label="复用键（recyclingKey）" value={recyclingKey} onChangeText={setRecyclingKey} />
                <ActionRow>
                  <Cycle label="缓存策略" value={cachePolicy} choices={policies} onChange={setCachePolicy} />
                  <Cycle label="下载优先级" value={priority} choices={['low', 'normal', 'high']} onChange={setPriority} />
                  <Toggle label="自动播放" value={autoplay} onChange={setAutoplay} />
                  <Toggle label="按视图尺寸下采样" value={allowDownscaling} onChange={setAllowDownscaling} />
                  <Cycle label="解码格式" value={decodeFormat} choices={['argb', 'rgb']} onChange={setDecodeFormat} />
                  <Cycle label="过渡时长（毫秒）" value={transitionDuration} choices={[0, 300, 750, 1500]} onChange={setTransitionDuration} />
                  <Cycle label="过渡写法" value={transitionProp} choices={['对象', '数字', 'fadeDuration']} onChange={setTransitionProp} />
                  <Cycle label="过渡曲线" value={transitionTiming} choices={timings} onChange={setTransitionTiming} disabled={transitionProp !== '对象'} />
                  <Cycle label="过渡效果" value={transitionEffect} choices={['cross-dissolve', '关闭']} onChange={setTransitionEffect} />
                </ActionRow>
              </>
            )
          : null}
        {section === '无障碍'
          ? (
              <>
                <Field label="accessibilityLabel" value={accessibilityLabel} onChangeText={setAccessibilityLabel} />
                <Field label="alt" value={alt} onChangeText={setAlt} />
                <ActionRow>
                  <Toggle label="无障碍元素" value={accessible} onChange={setAccessible} />
                  <Toggle label="允许键盘聚焦" value={focusable} onChange={setFocusable} />
                </ActionRow>
              </>
            )
          : null}
        {section === '操作'
          ? (
              <>
                <ActionRow>
                  {native
                    ? (
                        <>
                          <ActionButton disabled={busy} label="播放动画" onPress={() => invoke('startAnimating')} tone="secondary" />
                          <ActionButton disabled={busy} label="暂停动画" onPress={() => invoke('stopAnimating')} tone="secondary" />
                          <ActionButton disabled={busy} label="锁定图片资源" onPress={() => invoke('lockResourceAsync')} tone="secondary" />
                          <ActionButton disabled={busy} label="解除资源锁定" onPress={() => invoke('unlockResourceAsync')} tone="secondary" />
                          <ActionButton disabled={busy} label="重新加载图片" onPress={() => invoke('reloadAsync')} tone="secondary" />
                        </>
                      )
                    : null}
                  <ActionButton disabled={busy} label="获取动画引用" onPress={() => void action.run(() => json({ hasRef: view.current?.getAnimatableRef() != null }))} tone="secondary" />
                </ActionRow>
                <ResultPanel state={action.state} />
              </>
            )
          : null}
      </Panel>
      <Panel title="图片事件">
        {events.length ? <Text selectable style={styles.events}>{events.join('\n')}</Text> : null}
        <ActionRow>
          <ActionButton label="清空事件" disabled={!events.length} onPress={() => setEvents([])} tone="secondary" />
          {native ? <Toggle label="监听 imageLoaded" value={listen} onChange={setListen} /> : null}
        </ActionRow>
        {nativeEvent ? <DataRow label="imageLoaded" value={json(nativeEvent)} /> : null}
      </Panel>
      <ImageBackgroundDemo />
      <ImageTools defaultUrl={defaultUrl} />
    </>
  );
}

function ImageBackgroundDemo() {
  const [round, setRound] = useState(true);
  const [fit, setFit] = useState<ImageContentFit>('cover');
  const [tall, setTall] = useState(false);

  return (
    <Panel title="ImageBackground">
      <ImageBackground
        contentFit={fit}
        source={sample}
        style={[styles.background, { height: tall ? 180 : 100 }]}
        imageStyle={round ? styles.rounded : undefined}
      >
        <View style={styles.caption}><Text style={styles.captionText}>图片背景</Text></View>
      </ImageBackground>
      <ActionRow>
        <Cycle label="背景适配" value={fit} choices={fits} onChange={setFit} />
        <Toggle label="图片圆角" value={round} onChange={setRound} />
        <Toggle label="加高容器" value={tall} onChange={setTall} />
      </ActionRow>
    </Panel>
  );
}

const styles = StyleSheet.create({
  preview: { height: 190, backgroundColor: palette.surfaceRaised, width: '100%' },
  rounded: { borderRadius: 12, overflow: 'hidden' },
  events: { color: palette.muted, fontSize: 11, lineHeight: 16, fontFamily: 'monospace' },
  background: { alignItems: 'flex-start', justifyContent: 'flex-end', padding: 12 },
  caption: { backgroundColor: palette.surface, borderRadius: 8, padding: 8 },
  captionText: { color: palette.text, fontSize: 14, fontWeight: '700' },
});

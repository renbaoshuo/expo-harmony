/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import AntDesign from '@expo/vector-icons/AntDesign';
import { Asset } from 'expo-asset';
import * as Font from 'expo-font';
import { useState } from 'react';
import { Image, Platform, Text } from 'react-native';

import { antDesignFontAsset, DYNAMIC_FONT_FAMILY } from '../fixtures';
import { json } from '../format';
import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const glyphValue = AntDesign.glyphMap.experiment;
const glyph = typeof glyphValue === 'number' ? String.fromCodePoint(glyphValue) : glyphValue;
const sourceTypes = ['内置字体', '字体 URI', 'Asset', 'FontResource'] as const;
const web = Platform.OS === 'web';

function HookFont({ family, source }: { family: string; source?: Font.FontSource }) {
  const [loaded, error] = Font.useFonts(source ? { [family]: source } : family);
  return (
    <>
      <DataRow label="useFonts()" value={error?.message ?? (loaded ? '已加载' : '加载中')} />
      {loaded ? <Text style={{ fontFamily: family, fontSize: 48, color: palette.signal }}>{glyph}</Text> : null}
    </>
  );
}

export function FontDemo() {
  const [family, setFamily] = useState(DYNAMIC_FONT_FAMILY);
  const [uri, setUri] = useState('');
  const [sourceType, setSourceType] = useState<typeof sourceTypes[number]>('内置字体');
  const [display, setDisplay] = useState(Font.FontDisplay.AUTO);
  const [fallbackUri, setFallbackUri] = useState('');
  const [testString, setTestString] = useState('');
  const [hook, setHook] = useState<{ family: string; source?: Font.FontSource; revision: number }>();
  const [image, setImage] = useState<Font.RenderToImageResult>();
  const [imageText, setImageText] = useState('你好，Expo');
  const [imageFamily, setImageFamily] = useState('');
  const [size, setSize] = useState('36');
  const [color, setColor] = useState('#2466df');
  const [lineHeight, setLineHeight] = useState('48');
  const action = useAsyncResult();
  const status = useAsyncResult();
  const render = useAsyncResult();
  const busy = action.state.phase === 'running';

  const fontSource = (): Font.FontSource => {
    const bundled = antDesignFontAsset();
    if (sourceType === '字体 URI') {
      const asset = Asset.fromModule(bundled);
      return uri || asset.localUri || asset.uri;
    }
    if (sourceType === 'Asset') return uri ? Asset.fromURI(uri) : Asset.fromModule(bundled);
    if (sourceType === 'FontResource') {
      return {
        uri: uri || (web && fallbackUri ? undefined : bundled),
        ...(web ? { display, default: fallbackUri || undefined, testString: testString || undefined } : {}),
      };
    }
    return bundled;
  };

  return (
    <>
      <Panel title="加载字体">
        <Field label="字体系列" onChangeText={setFamily} value={family} />
        <ActionRow>
          {sourceTypes.map(value => (
            <ActionButton key={value} label={value} onPress={() => setSourceType(value)} tone={sourceType === value ? 'primary' : 'secondary'} />
          ))}
        </ActionRow>
        {sourceType !== '内置字体' ? <Field label="字体 URI" onChangeText={setUri} value={uri} /> : null}
        {web && sourceType === 'FontResource'
          ? (
              <>
                <Field label="备用 URI default" onChangeText={setFallbackUri} value={fallbackUri} />
                <Field label="字体加载探测文本 testString" onChangeText={setTestString} value={testString} />
                <ActionRow>
                  {Object.values(Font.FontDisplay).map(value => (
                    <ActionButton key={value} label={`display ${value}`} onPress={() => setDisplay(value)} tone={display === value ? 'primary' : 'secondary'} />
                  ))}
                </ActionRow>
              </>
            )
          : null}
        <ActionRow>
          <ActionButton
            disabled={busy || !family.trim()}
            label="loadAsync() 单个字体"
            onPress={() => void action.run(async () => {
              await Font.loadAsync(family, fontSource());
              return '已加载';
            })}
          />
          <ActionButton
            disabled={busy || !family.trim()}
            label="loadAsync() 字体映射"
            onPress={() => void action.run(async () => {
              await Font.loadAsync({ [family]: fontSource(), [`${family}-alt`]: antDesignFontAsset() });
              return '已加载';
            })}
          />
          <ActionButton
            disabled={busy || !family.trim()}
            label="useFonts() 字体映射"
            onPress={() => void action.run(() => {
              const source = fontSource();
              setHook(previous => ({ family, source, revision: (previous?.revision ?? 0) + 1 }));
              return '已挂载';
            })}
          />
          <ActionButton
            disabled={busy || !Font.isLoaded(family)}
            label="useFonts() 已加载的系列"
            onPress={() => setHook(previous => ({ family, revision: (previous?.revision ?? 0) + 1 }))}
            tone="secondary"
          />
          {web
            ? (
                <ActionButton
                  disabled={busy || !family.startsWith(DYNAMIC_FONT_FAMILY)}
                  label="unloadAsync()"
                  onPress={() => void action.run(async () => {
                    await Font.unloadAsync(family, { display });
                    return '已卸载';
                  })}
                  tone="secondary"
                />
              )
            : null}
        </ActionRow>
        {hook ? <HookFont key={hook.revision} family={hook.family} source={hook.source} /> : null}
        {Font.isLoaded(family)
          ? <Text style={{ fontFamily: family, fontSize: 48, color: palette.signal }}>{glyph}</Text>
          : null}
        <ResultPanel state={action.state} />
      </Panel>

      <Panel title="字体状态">
        <ActionRow>
          <ActionButton label="getLoadedFonts()" onPress={() => void status.run(() => json(Font.getLoadedFonts()))} />
          <ActionButton label="isLoaded()" onPress={() => void status.run(() => json(Font.isLoaded(family)))} />
          <ActionButton label="isLoading()" onPress={() => void status.run(() => json(Font.isLoading(family)))} />
        </ActionRow>
        <ResultPanel state={status.state} />
      </Panel>

      {web
        ? null
        : (
            <Panel title="将文字渲染为图片">
              <Field label="文字" multiline onChangeText={setImageText} value={imageText} />
              <Field label="字体系列" onChangeText={setImageFamily} value={imageFamily} />
              <Field label="字号" keyboardType="number-pad" onChangeText={setSize} value={size} />
              <Field label="颜色" onChangeText={setColor} value={color} />
              <Field label="行高" keyboardType="number-pad" onChangeText={setLineHeight} value={lineHeight} />
              <ActionButton
                disabled={render.state.phase === 'running'}
                label="renderToImageAsync()"
                onPress={() => void render.run(async () => {
                  const value = await Font.renderToImageAsync(imageText, {
                    fontFamily: imageFamily || undefined,
                    size: size ? Number(size) : undefined,
                    color: color || undefined,
                    lineHeight: lineHeight ? Number(lineHeight) : undefined,
                  });
                  setImage(value);
                  return json(value);
                })}
              />
              {image ? <Image source={{ uri: image.uri }} style={{ width: '100%', height: 150 }} resizeMode="contain" /> : null}
              <ResultPanel state={render.state} />
            </Panel>
          )}
    </>
  );
}

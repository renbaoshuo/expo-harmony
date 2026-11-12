/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Clipboard from 'expo-clipboard';
import { useEffect, useRef, useState } from 'react';
import { Image, Platform, StyleSheet, Switch } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const SAMPLE_PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGP4z8DAAMIM/4EAAB/uBfsL2WiLAAAAAElFTkSuQmCC';
const DISPLAY_MODES = {
  iconAndLabel: '图标和文字',
  iconOnly: '仅图标',
  labelOnly: '仅文字',
} satisfies Record<Clipboard.DisplayModeType, string>;
const CONTENT_TYPES = {
  'plain-text': '纯文本',
  'html': 'HTML',
  'url': 'URL',
  'image': '图片',
} satisfies Record<Clipboard.AcceptedContentType, string>;
const CORNER_STYLES = ['capsule', 'fixed', 'dynamic', 'large', 'medium', 'small'] as const;

function describeImage(image: Clipboard.ClipboardImage): string {
  return json({ size: image.size, dataLength: image.data.length });
}

export function ClipboardDemo() {
  const [text, setText] = useState('你好，Expo！');
  const [html, setHtml] = useState('<p>你好，<strong>Expo</strong>！</p>');
  const [url, setUrl] = useState('https://expo.dev/');
  const [base64, setBase64] = useState(SAMPLE_PNG);
  const [format, setFormat] = useState<Clipboard.GetImageOptions['format']>('png');
  const [jpegQuality, setJpegQuality] = useState('0.8');
  const [preview, setPreview] = useState<Clipboard.ClipboardImage | null>(null);
  const [pastedImage, setPastedImage] = useState<Clipboard.ClipboardImage | null>(null);
  const [listening, setListening] = useState(false);
  const [events, setEvents] = useState(0);
  const [types, setTypes] = useState<Clipboard.ContentType[]>([]);
  const subscription = useRef<Clipboard.Subscription | null>(null);
  const textResult = useAsyncResult();
  const imageResult = useAsyncResult();
  const pasteResult = useAsyncResult();
  const supportsUrl = String(Platform.OS) === 'harmony' || Platform.OS === 'ios';
  const web = Platform.OS === 'web';
  const busy = textResult.state.phase === 'running' || imageResult.state.phase === 'running';
  const imageOptions: Clipboard.GetImageOptions = {
    format,
    jpegQuality: format === 'jpeg' && jpegQuality.trim() ? Number(jpegQuality) : undefined,
  };

  useEffect(() => () => {
    if (subscription.current) Clipboard.removeClipboardListener(subscription.current);
  }, []);

  const showImage = (image: Clipboard.ClipboardImage | null) => {
    setPreview(image);
    return image ? describeImage(image) : '剪贴板中没有图片';
  };

  const toggleListener = () => {
    if (subscription.current) {
      Clipboard.removeClipboardListener(subscription.current);
      subscription.current = null;
      setListening(false);
      return;
    }

    subscription.current = Clipboard.addClipboardListener((event) => {
      setEvents(count => count + 1);
      setTypes(event.contentTypes);
    });
    setListening(true);
  };

  return (
    <>
      <Panel title="文本">
        <Field label="纯文本" multiline onChangeText={setText} testID="clipboard-text" value={text} />
        <ActionRow>
          <ActionButton disabled={busy} label="复制纯文本" onPress={() => void textResult.run(async () => String(await Clipboard.setStringAsync(text, { inputFormat: Clipboard.StringFormat.PLAIN_TEXT })))} testID="clipboard-copy-text" />
          <ActionButton disabled={busy} label="读取纯文本" onPress={() => void textResult.run(async () => json(await Clipboard.getStringAsync({ preferredFormat: Clipboard.StringFormat.PLAIN_TEXT })))} testID="clipboard-read-text" tone="secondary" />
        </ActionRow>
        <Field label="HTML" multiline onChangeText={setHtml} testID="clipboard-html" value={html} />
        <ActionRow>
          <ActionButton disabled={busy} label="复制 HTML" onPress={() => void textResult.run(async () => String(await Clipboard.setStringAsync(html, { inputFormat: Clipboard.StringFormat.HTML })))} testID="clipboard-copy-html" />
          <ActionButton disabled={busy} label="读取 HTML" onPress={() => void textResult.run(async () => json(await Clipboard.getStringAsync({ preferredFormat: Clipboard.StringFormat.HTML })))} testID="clipboard-read-html" tone="secondary" />
          <ActionButton disabled={busy} label="查询是否有文本" onPress={() => void textResult.run(async () => String(await Clipboard.hasStringAsync()))} tone="secondary" />
        </ActionRow>
        {supportsUrl
          ? (
              <>
                <Field label="URL" onChangeText={setUrl} testID="clipboard-url" value={url} />
                <ActionRow>
                  <ActionButton
                    disabled={busy}
                    label="复制 URL"
                    onPress={() => void textResult.run(async () => {
                      await Clipboard.setUrlAsync(url);
                      return '已复制 URL';
                    })}
                    testID="clipboard-copy-url"
                  />
                  <ActionButton disabled={busy} label="读取 URL" onPress={() => void textResult.run(async () => json(await Clipboard.getUrlAsync()))} testID="clipboard-read-url" tone="secondary" />
                  <ActionButton disabled={busy} label="查询是否有 URL" onPress={() => void textResult.run(async () => String(await Clipboard.hasUrlAsync()))} tone="secondary" />
                </ActionRow>
              </>
            )
          : null}
        <ResultPanel state={textResult.state} />
      </Panel>

      <Panel title="图片">
        <Field label="图片 Base64" multiline onChangeText={setBase64} value={base64} />
        <ActionButton
          disabled={busy || !base64.trim()}
          label="复制图片"
          onPress={() => void imageResult.run(async () => {
            await Clipboard.setImageAsync(base64.trim());
            return '已复制图片';
          })}
          testID="clipboard-copy-image"
        />
        {!web
          ? (
              <>
                <ActionRow>
                  <ActionButton label="PNG" onPress={() => setFormat('png')} tone={format === 'png' ? 'primary' : 'secondary'} />
                  <ActionButton label="JPEG" onPress={() => setFormat('jpeg')} tone={format === 'jpeg' ? 'primary' : 'secondary'} />
                </ActionRow>
                {format === 'jpeg' ? <Field label="JPEG 质量（0 到 1）" keyboardType="decimal-pad" onChangeText={setJpegQuality} value={jpegQuality} /> : null}
              </>
            )
          : null}
        <ActionRow>
          <ActionButton disabled={busy} label="读取图片" onPress={() => void imageResult.run(async () => showImage(await Clipboard.getImageAsync(imageOptions)))} />
          <ActionButton disabled={busy} label="查询是否有图片" onPress={() => void imageResult.run(async () => String(await Clipboard.hasImageAsync()))} tone="secondary" />
        </ActionRow>
        {preview ? <Image accessibilityLabel="剪贴板图片" source={{ uri: preview.data }} style={styles.preview} resizeMode="contain" /> : null}
        <ResultPanel state={imageResult.state} />
      </Panel>

      <Panel title="系统粘贴按钮">
        <DataRow label="按钮可用" value={String(Clipboard.isPasteButtonAvailable)} />
        {Clipboard.isPasteButtonAvailable
          ? <PasteButtonDemo
              imageOptions={imageOptions}
              onPaste={value => void pasteResult.run(() => {
                setPastedImage(value.type === 'image' ? value : null);
                return value.type === 'text' ? json(value.text) : describeImage(value);
              })}
            />
          : null}
        {pastedImage ? <Image accessibilityLabel="粘贴的图片" source={{ uri: pastedImage.data }} style={styles.preview} resizeMode="contain" /> : null}
        <ResultPanel state={pasteResult.state} />
      </Panel>

      {!web
        ? (
            <Panel title="剪贴板变化">
              <DataRow label="事件次数" value={events} />
              {events > 0 ? <DataRow label="最近内容类型" value={json(types)} /> : null}
              <ActionButton label={listening ? '移除变化监听' : '监听剪贴板变化'} onPress={toggleListener} testID="clipboard-listen" />
            </Panel>
          )
        : null}
    </>
  );
}

function PasteButtonDemo({ imageOptions, onPaste }: {
  imageOptions: Clipboard.GetImageOptions;
  onPaste: Clipboard.ClipboardPasteButtonProps['onPress'];
}) {
  const [accepted, setAccepted] = useState<Clipboard.AcceptedContentType>('plain-text');
  const [display, setDisplay] = useState<Clipboard.DisplayModeType>('iconAndLabel');
  const [corner, setCorner] = useState<Clipboard.CornerStyleType>('capsule');
  const [foreground, setForeground] = useState('');
  const [background, setBackground] = useState('');
  const [wide, setWide] = useState(false);
  const contentTypes = Object.keys(CONTENT_TYPES) as Clipboard.AcceptedContentType[];
  const displayModes = Object.keys(DISPLAY_MODES) as Clipboard.DisplayModeType[];

  return (
    <>
      <ActionRow>
        {contentTypes.map(type => (
          <ActionButton key={type} label={CONTENT_TYPES[type]} onPress={() => setAccepted(type)} tone={accepted === type ? 'primary' : 'secondary'} />
        ))}
      </ActionRow>
      <ActionRow>
        {displayModes.map(mode => (
          <ActionButton key={mode} label={DISPLAY_MODES[mode]} onPress={() => setDisplay(mode)} tone={display === mode ? 'primary' : 'secondary'} />
        ))}
      </ActionRow>
      <ActionRow>
        {(Platform.OS === 'ios' ? CORNER_STYLES : (['capsule', 'fixed'] as const)).map(shape => (
          <ActionButton key={shape} label={shape} onPress={() => setCorner(shape)} tone={corner === shape ? 'primary' : 'secondary'} />
        ))}
      </ActionRow>
      <Field label="前景色" placeholder="#FFFFFF" onChangeText={setForeground} value={foreground} />
      <Field label="背景色" placeholder="#007AFF" onChangeText={setBackground} value={background} />
      <DataRow label="加宽按钮" value={<Switch accessibilityLabel="加宽按钮" value={wide} onValueChange={setWide} />} />
      <Clipboard.ClipboardPasteButton
        acceptedContentTypes={[accepted]}
        backgroundColor={background || undefined}
        cornerStyle={corner}
        displayMode={display}
        foregroundColor={foreground || undefined}
        imageOptions={imageOptions}
        onPress={onPaste}
        style={wide ? styles.widePasteButton : styles.pasteButton}
        testID="clipboard-system-paste"
      />
    </>
  );
}

const styles = StyleSheet.create({
  pasteButton: { width: 160, height: 48 },
  preview: { width: 120, height: 120, alignSelf: 'center' },
  widePasteButton: { width: 220, height: 48 },
});

import * as Clipboard from 'expo-clipboard';
import { useEffect, useState } from 'react';
import { Image, Platform, StyleSheet } from 'react-native';

import { ActionButton, ActionRow, DataRow, Field, Note, Panel, ResultPanel, useAsyncResult } from './ui';

const SAMPLE_PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGP4z8DAAMIM/4EAAB/uBfsL2WiLAAAAAElFTkSuQmCC';

export function ClipboardDemo() {
  const [text, setText] = useState('Hello HarmonyOS · 剪贴板 📋');
  const [html, setHtml] = useState('<p>Hello <strong>HarmonyOS</strong> &amp; Expo</p>');
  const [url, setUrl] = useState('https://expo.dev/');
  const [preview, setPreview] = useState<Clipboard.ClipboardImage | null>(null);
  const [listening, setListening] = useState(false);
  const [events, setEvents] = useState(0);
  const [types, setTypes] = useState<Clipboard.ContentType[]>([]);
  const action = useAsyncResult();
  const images = useAsyncResult();
  const checks = useAsyncResult();
  const busy = [action, images, checks].some(result => result.state.phase === 'running');
  const supportsUrl = Platform.OS !== 'android' && Platform.OS !== 'web';

  useEffect(() => {
    if (!listening) return;

    const subscription = Clipboard.addClipboardListener((event) => {
      setEvents(count => count + 1);
      setTypes(event.contentTypes);
    });

    return () => subscription.remove();
  }, [listening]);

  const inspect = () => action.run(async () => JSON.stringify({
    text: await Clipboard.hasStringAsync(),
    image: await Clipboard.hasImageAsync(),
    url: supportsUrl ? await Clipboard.hasUrlAsync() : '当前平台不支持',
    pasteButton: Clipboard.isPasteButtonAvailable,
  }, null, 2));

  const readImage = (format: 'png' | 'jpeg') => images.run(async () => {
    const result = await Clipboard.getImageAsync({ format, jpegQuality: 0.8 });
    setPreview(result);

    return result === null ? '剪贴板中没有图片。' : JSON.stringify({ format, size: result.size, length: result.data.length }, null, 2);
  });

  const verify = () => checks.run(async () => {
    const rows: string[] = [];
    for (const value of ['', 'Hello HarmonyOS', '中文 📋\n第二行\t<&>']) {
      const copied = await Clipboard.setStringAsync(value);
      const actual = await Clipboard.getStringAsync();
      if (!copied || actual !== value || !(await Clipboard.hasStringAsync())) {
        throw new Error(`文本往返失败：${JSON.stringify({ expected: value, actual, copied })}`);
      }
    }
    rows.push('空字符串、普通文本、Unicode 与换行：通过');

    const markup = '<p>Hello <strong>HarmonyOS</strong> &amp; Expo</p>';
    await Clipboard.setStringAsync(markup, { inputFormat: Clipboard.StringFormat.HTML });
    const actual = await Clipboard.getStringAsync({ preferredFormat: Clipboard.StringFormat.HTML });
    const plain = await Clipboard.getStringAsync();
    if (actual !== markup || !(await Clipboard.hasStringAsync())) {
      throw new Error(`HTML 往返失败：${JSON.stringify({ expected: markup, actual })}`);
    }
    if (plain.replace(/\n$/, '') !== 'Hello HarmonyOS & Expo') {
      throw new Error(`HTML 纯文本转换失败：${JSON.stringify(plain)}`);
    }
    rows.push('HTML 原文、标签解析与实体解码：通过');

    const escaped = '<Expo> & HarmonyOS\n第二行';
    await Clipboard.setStringAsync(escaped);
    const converted = await Clipboard.getStringAsync({ preferredFormat: Clipboard.StringFormat.HTML });
    await Clipboard.setStringAsync(converted, { inputFormat: Clipboard.StringFormat.HTML });
    if ((await Clipboard.getStringAsync()).replace(/\n$/, '') !== escaped) {
      throw new Error(`纯文本与 HTML 转换失败：${converted}`);
    }
    rows.push('纯文本与 HTML 转换、转义及换行：通过');

    if (supportsUrl) {
      await Clipboard.setUrlAsync(url);
      if (!(await Clipboard.hasUrlAsync()) || await Clipboard.getUrlAsync() !== url
        || await Clipboard.getStringAsync() !== url) {
        throw new Error('URL 类型或往返内容不符。');
      }
      rows.push('URL 类型、读写及字符串读取：通过');
    }

    const queued = await Promise.all([
      Clipboard.setStringAsync('first'),
      Clipboard.getStringAsync(),
      Clipboard.setStringAsync('second'),
      Clipboard.getStringAsync(),
    ]);
    if (queued[1] !== 'first' || queued[3] !== 'second') {
      throw new Error(`并发调用顺序不符：${JSON.stringify(queued)}`);
    }
    rows.push('并发读写顺序：通过');

    if (await Clipboard.hasImageAsync() || await Clipboard.getImageAsync({ format: 'png' }) !== null
      || (supportsUrl && (await Clipboard.hasUrlAsync() || await Clipboard.getUrlAsync() !== null))) {
      throw new Error('纯文本写入后，图片或 URL 类型没有被替换。');
    }
    rows.push('类型替换与缺失内容返回值：通过');

    return rows.join('\n');
  });

  const verifyImages = () => checks.run(async () => {
    await Clipboard.setImageAsync(SAMPLE_PNG);
    if (!(await Clipboard.hasImageAsync()) || await Clipboard.hasStringAsync() || await Clipboard.getStringAsync() !== '') {
      throw new Error('图片写入后的内容类型或缺失文本返回值不符。');
    }

    const rows: string[] = [];
    for (const format of ['png', 'jpeg'] as const) {
      for (const quality of [0, 0.8, 1]) {
        const result = await Clipboard.getImageAsync({ format, jpegQuality: quality });
        if (result === null || result.size.width !== 2 || result.size.height !== 2
          || !result.data.startsWith(`data:image/${format};base64,`)) {
          throw new Error(`${format} 质量 ${quality}：图片格式或尺寸不符。`);
        }
        await Clipboard.setImageAsync(result.data.slice(result.data.indexOf(',') + 1));
        setPreview(result);
        rows.push(`${format} / ${quality}：2 × 2，重新解码通过`);
      }
    }

    for (const value of ['', 'not base64!', 'SGVsbG8=']) {
      let rejected = false;
      try {
        await Clipboard.setImageAsync(value);
      } catch (error) {
        if (!(error instanceof Error) || !('code' in error) || error.code !== 'ERR_INVALID_IMAGE') {
          throw new Error(`非法图片错误码不符：${String(error)}`);
        }
        rejected = true;
      }
      if (!rejected) throw new Error('非法图片未被拒绝。');
    }
    rows.push('空图片、非法 Base64、非图片内容：正确拒绝');

    await Clipboard.setImageAsync(SAMPLE_PNG);
    const recovered = await Clipboard.getImageAsync({ format: 'png' });
    if (recovered === null || recovered.size.width !== 2 || recovered.size.height !== 2) {
      throw new Error('非法图片后无法继续读写。');
    }
    setPreview(recovered);
    rows.push('错误后继续读写：通过');

    return rows.join('\n');
  });

  return (
    <>
      <Panel eyebrow="内容" title="文本、HTML 与 URL">
        <Field label="纯文本" multiline onChangeText={setText} testID="clipboard-text" value={text} />
        <ActionRow>
          <ActionButton disabled={busy} label="复制文本" onPress={() => void action.run(async () => String(await Clipboard.setStringAsync(text)))} testID="clipboard-copy-text" />
          <ActionButton disabled={busy} label="读取文本" onPress={() => void action.run(() => Clipboard.getStringAsync())} testID="clipboard-read-text" tone="secondary" />
        </ActionRow>
        <Field label="HTML" multiline onChangeText={setHtml} testID="clipboard-html" value={html} />
        <ActionRow>
          <ActionButton disabled={busy} label="复制 HTML" onPress={() => void action.run(async () => String(await Clipboard.setStringAsync(html, { inputFormat: Clipboard.StringFormat.HTML })))} testID="clipboard-copy-html" />
          <ActionButton disabled={busy} label="读取 HTML" onPress={() => void action.run(() => Clipboard.getStringAsync({ preferredFormat: Clipboard.StringFormat.HTML }))} testID="clipboard-read-html" tone="secondary" />
        </ActionRow>
        <Field label="URL" onChangeText={setUrl} testID="clipboard-url" value={url} />
        <ActionRow>
          <ActionButton
            disabled={busy || !supportsUrl}
            label="复制 URL"
            onPress={() => void action.run(async () => {
              await Clipboard.setUrlAsync(url);

              return 'URL 已复制。';
            })}
            testID="clipboard-copy-url"
          />
          <ActionButton disabled={busy || !supportsUrl} label="读取 URL" onPress={() => void action.run(async () => JSON.stringify(await Clipboard.getUrlAsync()))} testID="clipboard-read-url" tone="secondary" />
          <ActionButton disabled={busy} label="查询内容类型" onPress={() => void inspect()} testID="clipboard-inspect" tone="secondary" />
        </ActionRow>
        <Note>复制操作会覆盖系统剪贴板。HarmonyOS 读取外部内容可能请求权限；HTML 转换结果遵循系统版本，URL 接口供 HarmonyOS 和 iOS 使用。</Note>
        <ResultPanel state={action.state} />
      </Panel>

      <Panel eyebrow="图片" title="Base64 与 PNG / JPEG">
        <ActionRow>
          <ActionButton
            disabled={busy}
            label="复制示例图片"
            onPress={() => void images.run(async () => {
              await Clipboard.setImageAsync(SAMPLE_PNG);

              return '已复制 2 × 2 彩色 PNG。';
            })}
            testID="clipboard-copy-image"
          />
          <ActionButton disabled={busy} label="读取 PNG" onPress={() => void readImage('png')} testID="clipboard-read-png" tone="secondary" />
          <ActionButton disabled={busy} label="读取 JPEG" onPress={() => void readImage('jpeg')} testID="clipboard-read-jpeg" tone="secondary" />
        </ActionRow>
        {preview !== null ? <Image accessibilityLabel="剪贴板图片预览" source={{ uri: preview.data }} style={styles.preview} resizeMode="contain" /> : null}
        <Note>示例为红、绿、蓝、白四个像素。读取显示放大预览，输出尺寸仍为 2 × 2；也可以读取其他应用复制的系统图片。</Note>
        <ResultPanel state={images.state} />
      </Panel>

      <Panel eyebrow="接口验证" title="往返、边界与错误恢复">
        <ActionRow>
          <ActionButton disabled={busy} label="验证文本与类型" onPress={() => void verify()} testID="clipboard-verify" />
          <ActionButton disabled={busy} label="验证图片与错误" onPress={() => void verifyImages()} testID="clipboard-verify-images" tone="secondary" />
        </ActionRow>
        <Note>验证会覆盖剪贴板。文本验证使用固定 HTML 示例和上方 URL，仅允许系统段落末尾附加一个换行；图片验证包含 PNG / JPEG 质量边界、尺寸、重新解码、非法输入及失败后继续调用。</Note>
        <ResultPanel state={checks.state} />
      </Panel>

      <Panel eyebrow="事件" title="订阅与移除剪贴板监听">
        <DataRow label="正在监听" value={listening ? '是' : '否'} />
        <DataRow label="事件次数" value={String(events)} />
        <DataRow label="最近内容类型" value={types.length > 0 ? types.join(', ') : '无'} />
        <ActionRow>
          <ActionButton disabled={busy} label={listening ? '移除监听' : '开始监听'} onPress={() => setListening(value => !value)} testID="clipboard-listen" tone="secondary" />
          <ActionButton disabled={busy} label="复制文本触发事件" onPress={() => void action.run(async () => String(await Clipboard.setStringAsync(text)))} testID="clipboard-trigger" />
        </ActionRow>
        <Note>开启监听后复制文本或图片，观察事件次数和类型；移除监听后应不再更新。HarmonyOS 仅在前台发送事件，离开页面会自动移除监听。</Note>
      </Panel>
    </>
  );
}

const styles = StyleSheet.create({
  preview: { width: 120, height: 120, alignSelf: 'center' },
});

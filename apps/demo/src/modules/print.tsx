/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Print from 'expo-print';
import { useState } from 'react';
import { Platform, Switch } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const HTML = '<!doctype html><html><body><h1>周末活动</h1><p>周六上午九点在公园门口集合。</p></body></html>';
const MARGINS = { top: '24', right: '24', bottom: '24', left: '24' };
const MARGIN_LABELS = { top: '上边距', right: '右边距', bottom: '下边距', left: '左边距' };
const MARGIN_SIDES = ['top', 'right', 'bottom', 'left'] as const;

export function PrintDemo() {
  const [html, setHtml] = useState(HTML);
  const [uri, setUri] = useState('');
  const [width, setWidth] = useState('612');
  const [height, setHeight] = useState('792');
  const [textZoom, setTextZoom] = useState('100');
  const [margins, setMargins] = useState(MARGINS);
  const [base64, setBase64] = useState(false);
  const [landscape, setLandscape] = useState(false);
  const [useMarkupFormatter, setUseMarkupFormatter] = useState(false);
  const [markupFormatterIOS, setMarkupFormatterIOS] = useState('');
  const [printerUrl, setPrinterUrl] = useState('');
  const output = useAsyncResult();
  const printing = useAsyncResult();
  const busy = output.state.phase === 'running' || printing.state.phase === 'running';
  const ios = Platform.OS === 'ios';
  const web = Platform.OS === 'web';
  const harmony = String(Platform.OS) === 'harmony';

  const commonOptions = {
    html,
    width: width.trim() ? Number(width) : undefined,
    height: height.trim() ? Number(height) : undefined,
    margins: ios || harmony
      ? {
          top: Number(margins.top),
          right: Number(margins.right),
          bottom: Number(margins.bottom),
          left: Number(margins.left),
        }
      : undefined,
    useMarkupFormatter: ios ? useMarkupFormatter : undefined,
  };
  const zoomOption = textZoom.trim() ? Number(textZoom) : undefined;

  const create = () => output.run(async () => {
    const result = await Print.printToFileAsync({
      ...commonOptions,
      base64,
      textZoom: harmony || Platform.OS === 'android' ? zoomOption : undefined,
    });
    setUri(result.uri);

    return json({ uri: result.uri, numberOfPages: result.numberOfPages, base64Length: result.base64?.length });
  });

  const print = (options: Print.PrintOptions) => printing.run(async () => {
    await Print.printAsync(options);
    return '已提交打印请求';
  });

  if (web) {
    return (
      <Panel title="打印网页">
        <ActionRow>
          <ActionButton disabled={busy} label="打印当前页" onPress={() => void print({})} />
          <ActionButton
            disabled={busy}
            label="打开 PDF 导出界面"
            onPress={() => void printing.run(async () => {
              await Print.printToFileAsync();
              return '已调用 PDF 导出';
            })}
            tone="secondary"
          />
        </ActionRow>
        <ResultPanel state={printing.state} />
      </Panel>
    );
  }

  return (
    <>
      <Panel title="HTML 与纸张">
        <Field label="HTML" multiline onChangeText={setHtml} testID="print-html" value={html} />
        <Field label="页面宽度" keyboardType="decimal-pad" onChangeText={setWidth} value={width} />
        <Field label="页面高度" keyboardType="decimal-pad" onChangeText={setHeight} value={height} />
        {ios || harmony
          ? MARGIN_SIDES.map(side => (
              <Field key={side} label={MARGIN_LABELS[side]} keyboardType="decimal-pad" value={margins[side]} onChangeText={value => setMargins(current => ({ ...current, [side]: value }))} />
            ))
          : null}
        {harmony || Platform.OS === 'android' ? <Field label="文字缩放（%）" keyboardType="number-pad" onChangeText={setTextZoom} value={textZoom} /> : null}
        {ios ? <DataRow label="使用 HTML 格式化器" value={<Switch accessibilityLabel="使用 HTML 格式化器" onValueChange={setUseMarkupFormatter} value={useMarkupFormatter} />} /> : null}
      </Panel>

      <Panel title="导出 PDF">
        <DataRow label="附带 Base64" value={<Switch accessibilityLabel="附带 Base64" onValueChange={setBase64} value={base64} />} />
        <ActionButton disabled={busy} label="导出 PDF" onPress={() => void create()} testID="print-create" />
        <ResultPanel state={output.state} />
      </Panel>

      <Panel title="系统打印">
        <Field label="PDF URI" onChangeText={setUri} testID="print-uri" value={uri} />
        {ios || harmony ? <DataRow label="横向打印 HTML" value={<Switch accessibilityLabel="横向打印 HTML" onValueChange={setLandscape} value={landscape} />} /> : null}
        {ios
          ? (
              <>
                <Field label="打印机 URL" onChangeText={setPrinterUrl} value={printerUrl} />
                <ActionButton
                  disabled={busy}
                  label="选择打印机"
                  onPress={() => void printing.run(async () => {
                    const printer = await Print.selectPrinterAsync();
                    setPrinterUrl(printer.url);
                    return json(printer);
                  })}
                  tone="secondary"
                />
                <Field label="格式化器 HTML（旧版参数）" multiline onChangeText={setMarkupFormatterIOS} value={markupFormatterIOS} />
              </>
            )
          : null}
        <ActionRow>
          <ActionButton
            disabled={busy}
            label="打印 HTML"
            onPress={() => {
              const options: Print.PrintOptions & { textZoom?: number } = {
                ...commonOptions,
                orientation: ios || harmony ? Print.Orientation[landscape ? 'landscape' : 'portrait'] : undefined,
                printerUrl: ios ? printerUrl || undefined : undefined,
                markupFormatterIOS: ios ? markupFormatterIOS || undefined : undefined,
                textZoom: harmony ? zoomOption : undefined,
              };
              void print(options);
            }}
            testID="print-html-dialog"
          />
          <ActionButton
            disabled={busy || !uri.trim()}
            label="打印 PDF"
            onPress={() => void print({
              uri: uri.trim(),
              printerUrl: ios ? printerUrl || undefined : undefined,
            })}
            testID="print-pdf-dialog"
            tone="secondary"
          />
        </ActionRow>
        <ResultPanel state={printing.state} />
      </Panel>
    </>
  );
}

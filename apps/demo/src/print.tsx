import { File } from 'expo-file-system';
import * as Print from 'expo-print';
import { useState } from 'react';
import { Platform } from 'react-native';

import { ActionButton, ActionRow, DataRow, Field, Note, Panel, ResultPanel, useAsyncResult } from './ui';

const HTML = `<!doctype html>
<html><head><meta charset="utf-8"><style>
body { font-family: sans-serif; padding: 24px; color: #1c1c1e; }
h1 { color: #007aff; } section + section { break-before: page; page-break-before: always; }
</style></head><body>
<section><h1>Expo Print · 第一页</h1><p>HarmonyOS PDF · 中文 · 100% · #1 · &amp;</p></section>
<section><h1>第二页</h1><p>检查分页、文字和纸张方向。</p></section>
</body></html>`;

export function PrintDemo() {
  const [html, setHtml] = useState(HTML);
  const [uri, setUri] = useState('');
  const [result, setResult] = useState<Print.FilePrintResult | null>(null);
  const output = useAsyncResult();
  const printing = useAsyncResult();
  const checks = useAsyncResult();
  const busy = [output, printing, checks].some(item => item.state.phase === 'running');

  const create = () => output.run(async () => {
    const generated = await Print.printToFileAsync({ html, base64: true });
    setResult(generated);
    setUri(generated.uri);

    return JSON.stringify({
      uri: generated.uri,
      pages: generated.numberOfPages,
      base64Length: generated.base64?.length,
    }, null, 2);
  });

  const verify = () => checks.run(async () => {
    const rows: string[] = [];
    const cases: { label: string; options: Print.FilePrintOptions; pages: number }[] = [
      { label: '空白文档', options: {}, pages: 1 },
      { label: '两页 HTML 与 Base64', options: { html: HTML, base64: true }, pages: 2 },
      { label: '页面尺寸、边距与缩放', options: { html: HTML, width: 792, height: 612, margins: { top: 24, bottom: 24, left: 24, right: 24 }, textZoom: 120 }, pages: 2 },
    ];

    for (const item of cases) {
      const generated = await Print.printToFileAsync(item.options);
      const file = new File(generated.uri);
      try {
        if (!file.exists || file.size <= 0 || generated.numberOfPages !== item.pages) {
          throw new Error(`${item.label}：文件或页数不符，URI=${generated.uri}，pages=${generated.numberOfPages}`);
        }

        const bytes = await file.bytes();
        if (String.fromCharCode(...bytes.slice(0, 5)) !== '%PDF-') {
          throw new Error(`${item.label}：输出没有 PDF 文件头。`);
        }
        if (item.options.base64 && generated.base64 !== await file.base64()) {
          throw new Error(`${item.label}：返回的 Base64 与文件字节不一致。`);
        }
        if (!item.options.base64 && generated.base64 !== undefined) {
          throw new Error(`${item.label}：未请求 Base64 时仍然返回了该字段。`);
        }

        rows.push(`${item.label}：${generated.numberOfPages} 页，${bytes.length} 字节，通过`);
      } finally {
        if (file.exists) file.delete();
      }
    }

    return rows.join('\n');
  });

  const verifyErrors = () => checks.run(async () => {
    if (String(Platform.OS) !== 'harmony') return '这些参数边界按 HarmonyOS 的 ArkWeb 限制验证。';

    const cases: { label: string; options: Print.FilePrintOptions }[] = [
      { label: '宽度为零', options: { width: 0 } },
      { label: '高度为 NaN', options: { height: NaN } },
      { label: '无穷宽度', options: { width: Infinity } },
      { label: '负边距', options: { margins: { top: -1, bottom: 0, left: 0, right: 0 } } },
      { label: '边距占半页', options: { width: 612, margins: { top: 0, bottom: 0, left: 306, right: 0 } } },
      { label: '缩放非整数', options: { textZoom: 1.5 } },
    ];
    const rows: string[] = [];
    for (const item of cases) {
      let code: unknown;
      try {
        const generated = await Print.printToFileAsync(item.options);
        new File(generated.uri).delete();
      } catch (error) {
        code = error instanceof Error && 'code' in error ? error.code : undefined;
      }
      if (code !== 'ERR_PRINT_INVALID_OPTIONS') {
        throw new Error(`${item.label}：预期 ERR_PRINT_INVALID_OPTIONS，实际 ${String(code)}。`);
      }
      rows.push(`${item.label}：正确拒绝`);
    }

    const recovered = await Print.printToFileAsync({ html: '<!doctype html><html><body>Recovered</body></html>' });
    try {
      if (recovered.numberOfPages !== 1) throw new Error('错误后再次导出的页数不符。');
    } finally {
      new File(recovered.uri).delete();
    }
    rows.push('错误后继续导出：通过');

    return rows.join('\n');
  });

  return (
    <>
      <Panel eyebrow="PDF 导出" title="将 HTML 保存为 PDF">
        <Field label="HTML" multiline onChangeText={setHtml} testID="print-html" value={html} />
        <ActionRow>
          <ActionButton disabled={busy} label="导出 PDF" onPress={() => void create()} testID="print-create" />
          <ActionButton
            disabled={busy || result === null}
            label="删除导出文件"
            onPress={() => void output.run(() => {
              if (result === null) throw new Error('请先导出 PDF。');
              const file = new File(result.uri);
              if (file.exists) file.delete();
              if (uri === result.uri) setUri('');
              setResult(null);

              return '已删除导出文件。';
            })}
            testID="print-delete"
            tone="secondary"
          />
        </ActionRow>
        <DataRow label="最近导出页数" value={result?.numberOfPages ?? '尚未导出'} />
        <Note>默认示例为两页，含中文、百分号和 HTML 实体。导出的文件保留在缓存中，可用于下方的系统打印。</Note>
        <ResultPanel state={output.state} />
      </Panel>

      <Panel eyebrow="系统打印" title="打开打印预览与打印机选择">
        <Field label="PDF URI" onChangeText={setUri} placeholder="file://、https:// 或 data:application/pdf;base64,…" testID="print-uri" value={uri} />
        <ActionRow>
          <ActionButton
            disabled={busy}
            label="打印 HTML"
            onPress={() => void printing.run(async () => {
              await Print.printAsync({ html });

              return '系统打印接口已返回；请在系统界面检查预览并选择打印机。';
            })}
            testID="print-html-dialog"
          />
          <ActionButton
            disabled={busy || uri.length === 0}
            label="打印 PDF"
            onPress={() => void printing.run(async () => {
              await Print.printAsync({ uri });

              return 'PDF 已提交系统打印。返回不代表纸张已打印完成。';
            })}
            testID="print-pdf-dialog"
            tone="secondary"
          />
        </ActionRow>
        <Note>可以取消系统面板后再次打印。HarmonyOS 和 Android 打开面板即返回；实际打印需要可用打印服务和打印机。</Note>
        <ResultPanel state={printing.state} />
      </Panel>

      <Panel eyebrow="接口验证" title="文件、分页、参数边界与恢复">
        <ActionRow>
          <ActionButton disabled={busy} label="验证 PDF 输出" onPress={() => void verify()} testID="print-verify" />
          <ActionButton disabled={busy} label="验证参数与恢复" onPress={() => void verifyErrors()} testID="print-verify-errors" tone="secondary" />
        </ActionRow>
        <Note>使用固定示例校验空白文档、两页分页、Base64 与文件字节一致性，再检查非法尺寸、边距、缩放及错误恢复。验证文件结束后自动删除；纸张尺寸和文字外观需在系统预览中检查。</Note>
        <ResultPanel state={checks.state} />
      </Panel>
    </>
  );
}

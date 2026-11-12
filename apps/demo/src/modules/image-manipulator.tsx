/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Asset } from 'expo-asset';
import { Image, type ImageRef as SourceRef } from 'expo-image';
import { File } from 'expo-file-system';
import { FlipType, ImageManipulator, manipulateAsync, SaveFormat, useImageManipulator } from 'expo-image-manipulator';
import type { Action, ImageManipulatorContext, ImageRef, ImageResult, SaveOptions } from 'expo-image-manipulator';
import { useEffect, useRef, useState } from 'react';
import { Platform, StyleSheet } from 'react-native';

import sample from '../../assets/image/sample.png';
import { json } from '../format';
import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { Cycle, optionalNumber, Toggle } from './visual-controls';

const sampleUri = Asset.fromModule(sample).uri;
const formats = [SaveFormat.PNG, SaveFormat.JPEG, SaveFormat.WEBP];
const transforms = Platform.OS === 'web' ? ['缩放', '旋转', '翻转', '裁剪', '扩展画布'] : ['缩放', '旋转', '翻转', '裁剪'];

type ActiveContext = { id: number; context: ImageManipulatorContext; source: string | SourceRef };

export function ImageManipulatorDemo() {
  const [input, setInput] = useState(sampleUri);
  const [hookUri, setHookUri] = useState(sampleUri);
  const [mode, setMode] = useState<'Hook' | 'Context' | 'manipulateAsync'>('Hook');
  const [active, setActive] = useState<ActiveContext>();
  const activeRef = useRef<ActiveContext | undefined>(undefined);
  const mounted = useRef(true);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      releaseContext(activeRef.current);
    };
  }, []);

  function openContext(source: string | SourceRef) {
    const next = { id: (activeRef.current?.id ?? 0) + 1, context: ImageManipulator.manipulate(source), source };
    releaseContext(activeRef.current);
    activeRef.current = next;
    setActive(next);
    return '已创建处理上下文';
  }

  return (
    <>
      <Panel title="图片来源">
        <Field editable={!busy} label="图片 URI" value={input} onChangeText={setInput} />
        <ActionRow>
          <ActionButton disabled={busy} label="使用本地样图" onPress={() => setInput(sampleUri)} tone="secondary" />
          <Cycle disabled={busy} label="调用方式" value={mode} choices={['Hook', 'Context', 'manipulateAsync']} onChange={setMode} />
        </ActionRow>
        {mode === 'Hook' ? <ActionButton disabled={!input.trim()} label="载入图片（useImageManipulator）" onPress={() => setHookUri(input.trim())} /> : null}
        {mode === 'Context'
          ? (
              <ActionRow>
                <ActionButton disabled={busy || !input.trim()} label="从 URI 创建 Context" onPress={() => void action.run(() => openContext(input.trim()))} />
                <ActionButton
                  disabled={busy || !input.trim()}
                  label="从 ImageRef 创建 Context"
                  onPress={() => void action.run(async () => {
                    const source = await Image.loadAsync(input.trim(), { maxWidth: 640, maxHeight: 640 });
                    if (!mounted.current) {
                      source.release();
                      return '';
                    }
                    try {
                      return openContext(source);
                    } catch (error) {
                      source.release();
                      throw error;
                    }
                  })}
                  tone="secondary"
                />
              </ActionRow>
            )
          : null}
        <ResultPanel state={action.state} />
      </Panel>
      {mode === 'Hook' ? <HookEditor key={hookUri} uri={hookUri} /> : null}
      {mode === 'Context' && active ? <Editor key={active.id} source={active.source} context={active.context} /> : null}
      {mode === 'manipulateAsync' ? <Editor key="legacy" source={input.trim()} /> : null}
    </>
  );
}

function releaseContext(active?: ActiveContext) {
  active?.context.release();
  if (active && typeof active.source !== 'string') active.source.release();
}

function HookEditor({ uri }: { uri: string }) {
  const context = useImageManipulator(uri);
  return <Editor source={uri} context={context} />;
}

function Editor({ source, context }: { source: string | SourceRef; context?: ImageManipulatorContext }) {
  const [kind, setKind] = useState('缩放');
  const [width, setWidth] = useState('80');
  const [height, setHeight] = useState('');
  const [angle, setAngle] = useState('90');
  const [flip, setFlip] = useState(FlipType.Horizontal);
  const [x, setX] = useState('0');
  const [y, setY] = useState('0');
  const [background, setBackground] = useState('#FFFFFF');
  const [format, setFormat] = useState(SaveFormat.PNG);
  const [compress, setCompress] = useState('0.8');
  const [base64, setBase64] = useState(false);
  const [image, setImage] = useState<ImageRef>();
  const [saved, setSaved] = useState<ImageResult>();
  const mounted = useRef(true);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const rect = kind === '裁剪' || kind === '扩展画布';

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  useEffect(() => () => {
    if (image) releaseRenderedImage(image);
  }, [image]);
  useEffect(() => {
    if (!saved) return;
    return () => deleteOutput(saved.uri);
  }, [saved]);

  function transform(): Action {
    if (kind === '旋转') return { rotate: optionalNumber(angle, '角度') ?? 0 };
    if (kind === '翻转') return { flip };
    const size = { width: optionalNumber(width, '宽度'), height: optionalNumber(height, '高度') };
    if (kind === '缩放') return { resize: size };

    if (size.width === undefined || size.height === undefined) throw new Error('请输入宽度和高度。');
    const rectangle = {
      width: size.width, height: size.height,
      originX: optionalNumber(x, '横坐标') ?? 0,
      originY: optionalNumber(y, '纵坐标') ?? 0,
    };
    if (kind === '裁剪') return { crop: rectangle };
    return { extent: { ...rectangle, backgroundColor: background.trim() || undefined } };
  }

  function queue() {
    if (!context) return;

    const operation = transform();
    if ('resize' in operation) context.resize(operation.resize);
    else if ('rotate' in operation) context.rotate(operation.rotate);
    else if ('flip' in operation) context.flip(operation.flip);
    else if ('crop' in operation) context.crop(operation.crop);
    else context.extent(operation.extent);
    return json(operation);
  }

  function saveOptions(): SaveOptions {
    return { format, compress: optionalNumber(compress, '压缩质量'), base64 };
  }

  function acceptResult(result: ImageResult) {
    if (mounted.current) setSaved(result);
    else deleteOutput(result.uri);
    return json({ ...result, base64: result.base64 ? `${result.base64.length} 个字符` : undefined });
  }

  return (
    <>
      <Panel title="变换">
        <Image source={image ?? (typeof source === 'string' ? { uri: source } : source)} style={styles.preview} contentFit="contain" />
        {image ? <DataRow label="渲染尺寸" value={`${image.width} × ${image.height}`} /> : null}
        <Cycle disabled={busy} label="操作" value={kind} choices={transforms} onChange={setKind} />
        {kind === '缩放' || rect
          ? (
              <>
                <Field label="宽度" keyboardType="number-pad" value={width} onChangeText={setWidth} placeholder="按比例计算" />
                <Field label="高度" keyboardType="number-pad" value={height} onChangeText={setHeight} placeholder="按比例计算" />
              </>
            )
          : null}
        {kind === '旋转' ? <Field label="角度" value={angle} onChangeText={setAngle} /> : null}
        {kind === '翻转' ? <Cycle label="翻转方向" value={flip} choices={[FlipType.Horizontal, FlipType.Vertical]} onChange={setFlip} /> : null}
        {rect
          ? (
              <>
                <Field label="起点 X" value={x} onChangeText={setX} />
                <Field label="起点 Y" value={y} onChangeText={setY} />
              </>
            )
          : null}
        {kind === '扩展画布' ? <Field label="背景色" value={background} onChangeText={setBackground} /> : null}
        {context
          ? (
              <ActionRow>
                <ActionButton disabled={busy} label="添加变换" onPress={() => void action.run(() => queue() ?? '')} />
                <ActionButton
                  disabled={busy}
                  label="渲染（renderAsync）"
                  onPress={() => void action.run(async () => {
                    const output = await context.renderAsync();
                    const dimensions = { width: output.width, height: output.height };
                    if (mounted.current) setImage(output);
                    else releaseRenderedImage(output);
                    return json(dimensions);
                  })}
                />
                <ActionButton
                  disabled={busy}
                  label="重置变换"
                  onPress={() => void action.run(() => {
                    context.reset();
                    setImage(undefined);
                    return '已恢复原图';
                  })}
                  tone="secondary"
                />
              </ActionRow>
            )
          : null}
      </Panel>
      <Panel title="保存图片">
        <ActionRow>
          <Cycle label="格式" value={format} choices={formats} onChange={setFormat} />
          <Toggle label="返回 Base64" value={base64} onChange={setBase64} />
        </ActionRow>
        <Field label="压缩质量（0 到 1）" keyboardType="decimal-pad" value={compress} onChangeText={setCompress} />
        {context
          ? (
              <ActionButton
                disabled={!image || busy}
                label="保存渲染结果（saveAsync）"
                onPress={() => {
                  if (image) void action.run(async () => acceptResult(await image.saveAsync(saveOptions())));
                }}
              />
            )
          : (
              <ActionButton
                disabled={busy || typeof source !== 'string' || !source}
                label="应用变换并保存（manipulateAsync）"
                onPress={() => {
                  if (typeof source === 'string') void action.run(async () => acceptResult(await manipulateAsync(source, [transform()], saveOptions())));
                }}
              />
            )}
        {saved ? <Image source={{ uri: saved.uri }} style={styles.preview} contentFit="contain" /> : null}
        <ResultPanel state={action.state} />
      </Panel>
    </>
  );
}

function releaseRenderedImage(image: ImageRef) {
  if (Platform.OS === 'web' && 'uri' in image && typeof image.uri === 'string') URL.revokeObjectURL(image.uri);
  image.release();
}

function deleteOutput(uri: string) {
  if (Platform.OS === 'web') {
    URL.revokeObjectURL(uri);
    return;
  }
  const file = new File(uri);
  if (file.exists) file.delete();
}

const styles = StyleSheet.create({
  preview: { backgroundColor: palette.surfaceRaised, borderRadius: 12, height: 180, width: '100%' },
});

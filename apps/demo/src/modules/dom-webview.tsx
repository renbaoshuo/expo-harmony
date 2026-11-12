/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { WebView, type DomWebViewProps, type DomWebViewRef } from '@expo/dom-webview';
import { Asset } from 'expo-asset';
import { Directory, File, Paths } from 'expo-file-system';
import { useEffect, useRef, useState } from 'react';
import { Platform, StyleSheet } from 'react-native';

import videoSample from '../../assets/live-photo/video.mp4';
import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import DomCounter from './dom-webview-counter';

const PAGE_START = `<!doctype html>
<html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body { margin: 0; padding: 16px; background: #eaf3ff; color: #111827; font: 15px system-ui, sans-serif; }
button, input { font: inherit; padding: 8px; margin: 2px; }
fieldset { border: 0; margin: 0; padding: 0; }
output { display: block; white-space: pre-wrap; overflow-wrap: anywhere; padding-block: 8px; }
</style>`;

const SAMPLE_HTML = `${PAGE_START}
<title>WebView 样例</title></head><body>
<p id="before"></p>
<p id="after"></p>
<button id="message">发送网页消息</button>
<button id="object">读取注入对象</button>
<output id="output" aria-live="polite"></output>
<video src="./sample.mp4" width="180" controls autoplay playsinline></video>
<div style="min-width: 900px; margin-top: 900px; padding: 16px; background: #d5ecd9">页面底部</div>
<script>
function send(text) {
  document.querySelector('output').textContent = text;
  window.ReactNativeWebView.postMessage(text);
}
document.querySelector('#before').textContent = window.startMessage || '';
document.querySelector('#message').onclick = () => send('来自网页的消息');
document.querySelector('#object').onclick = () => send(window.ReactNativeWebView.injectedObjectJson());
document.querySelector('video').onplay = () => send('视频开始播放');
</script></body></html>`;

const BRIDGE_HTML = `${PAGE_START}
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'">
<title>Expo 原生模块</title></head><body>
<fieldset>
  <input id="text" value="你好，Expo" aria-label="消息">
  <div>
    <button id="echo">echo</button><button id="echoAsync">echoAsync</button><button id="failAsync">failAsync</button>
  </div>
  <div>
    <button id="listen">订阅事件</button><button id="emit">emitEvent</button><button id="remove">取消订阅</button>
  </div>
  <label>初始值 <input id="initial" type="number" value="2"></label>
  <label>增量 <input id="delta" type="number" value="3"></label>
  <div>
    <button id="create">创建计数器</button><button id="increment">increment</button>
    <button id="incrementAsync">incrementAsync</button><button id="release">release</button>
  </div>
</fieldset>
<output aria-live="polite"></output>
<script>
const get = id => document.getElementById(id);
const show = value => document.querySelector('output').textContent =
  typeof value === 'string' ? value : JSON.stringify(value);
let subscription;
let counter;
let busy = false;
function bind(id, operation) {
  get(id).onclick = async () => {
    if (busy) return;
    busy = true;
    try {
      const native = window.ExpoDomWebView?.expoModulesProxy.ExpoModuleShowcase;
      if (!native) throw new Error('原生模块未连接');
      const result = await operation(native);
      if (result !== undefined) show(result);
    } catch (error) {
      show([error?.code, error?.message || String(error)].filter(Boolean).join(' '));
    } finally {
      busy = false;
    }
  };
}
bind('echo', native => native.echo(get('text').value));
bind('echoAsync', native => native.echoAsync(get('text').value));
bind('failAsync', native => native.failAsync());
bind('listen', native => {
  subscription ??= native.addListener('onShowcaseEvent', show);
  return '已订阅 onShowcaseEvent';
});
bind('emit', native => native.emitEvent(get('text').value));
bind('remove', () => {
  subscription?.remove();
  subscription = undefined;
  return '已取消订阅';
});
bind('create', native => {
  counter?.release();
  counter = undefined;
  counter = new native.ShowcaseSharedCounter(Number(get('initial').value));
  return counter.value;
});
bind('increment', () => counter ? counter.increment(Number(get('delta').value)) : '请先创建计数器');
bind('incrementAsync', () => counter ? counter.incrementAsync(Number(get('delta').value)) : '请先创建计数器');
bind('release', () => {
  counter?.release();
  counter = undefined;
  return '计数器已释放';
});
window.addEventListener('pagehide', () => {
  subscription?.remove();
  counter?.release();
});
</script></body></html>`;

type NativeMessage = Parameters<NonNullable<DomWebViewProps['onMessage']>>[0]['nativeEvent'];

const IOS_TOGGLES = {
  allowsInlineMediaPlayback: { label: '视频行内播放', initial: true },
  allowsPictureInPictureMediaPlayback: { label: '视频画中画', initial: true },
  allowsAirPlayForMediaPlayback: { label: 'AirPlay', initial: true },
  hideKeyboardAccessoryView: { label: '隐藏键盘工具栏', initial: false },
  bounces: { label: '滚动回弹', initial: true },
  scrollEnabled: { label: '允许滚动', initial: true },
  pagingEnabled: { label: '分页滚动', initial: false },
  directionalLockEnabled: { label: '锁定滚动方向', initial: true },
  automaticallyAdjustContentInsets: { label: '自动调整内容边距', initial: true },
  automaticallyAdjustsScrollIndicatorInsets: { label: '自动调整滚动条边距', initial: true },
} satisfies Partial<Record<keyof DomWebViewProps, { label: string; initial: boolean }>>;

type IosToggle = keyof typeof IOS_TOGGLES;
const IOS_TOGGLE_NAMES = Object.keys(IOS_TOGGLES) as IosToggle[];
const INSET_BEHAVIORS = ['automatic', 'scrollableAxes', 'never', 'always'] as const;

function numberField(input: string, label: string): number | undefined {
  if (!input.trim()) return undefined;

  const value = Number(input);
  if (!Number.isFinite(value)) throw new Error(`${label}需要填写数字。`);
  return value;
}

function objectField(input: string): object {
  const value: unknown = JSON.parse(input);
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('请输入 JSON 对象。');
  return value;
}

function Toggle({ label, active, onPress, testID, disabled }: {
  label: string;
  active: boolean;
  onPress: () => void;
  testID?: string;
  disabled?: boolean;
}) {
  return (
    <ActionButton disabled={disabled} label={label} onPress={onPress} testID={testID} tone={active ? 'primary' : 'secondary'} />
  );
}

function DomComponentDemo() {
  const [count, setCount] = useState(0);
  const [matchContents, setMatchContents] = useState(true);

  return (
    <Panel title="DOM 组件">
      <ActionRow>
        <ActionButton label="原生端加一" onPress={() => setCount(value => value + 1)} testID="dom-component-increment" />
        <Toggle label="按内容调整高度" active={matchContents} onPress={() => setMatchContents(value => !value)} />
      </ActionRow>
      <DataRow label="原生计数" value={count} />
      <DomCounter
        count={count}
        dom={{
          useExpoDOMWebView: true,
          matchContents,
          containerStyle: [styles.component, !matchContents && styles.fixedComponent],
          testID: 'dom-component-preview',
        }}
        onChange={async (value) => {
          setCount(value);
          return value;
        }}
      />
    </Panel>
  );
}

export function DomWebViewDemo() {
  const view = useRef<DomWebViewRef>(null);
  const directory = useRef<Directory | null>(null);
  const [bridgeUri, setBridgeUri] = useState('');
  const [tab, setTab] = useState<'sample' | 'bridge'>('sample');
  const [bridge, setBridge] = useState(true);
  const [uriInput, setUriInput] = useState('');
  const [uri, setUri] = useState('');
  const [horizontal, setHorizontal] = useState(true);
  const [vertical, setVertical] = useState(true);
  const [nested, setNested] = useState(true);
  const [debugging, setDebugging] = useState(false);
  const [requiresGesture, setRequiresGesture] = useState(true);
  const [inset, setInset] = useState(false);
  const [rounded, setRounded] = useState(true);
  const [iosToggles, setIosToggles] = useState<Partial<Record<IosToggle, boolean>>>({});
  const [iosBehavior, setIosBehavior] = useState<NonNullable<DomWebViewProps['contentInsetAdjustmentBehavior']>>('automatic');
  const [iosDeceleration, setIosDeceleration] = useState('normal');
  const [iosInsets, setIosInsets] = useState('{"top":12,"left":0,"bottom":0,"right":0}');
  const [iosScrollOptions, setIosScrollOptions] = useState<Pick<DomWebViewProps, 'decelerationRate' | 'contentInset'>>({});
  const [before, setBefore] = useState('window.startMessage = "加载前脚本";');
  const [after, setAfter] = useState('document.getElementById("after").textContent = "加载后脚本";');
  const [object, setObject] = useState('{"text":"你好，WebView"}');
  const [scripts, setScripts] = useState({ before: '', after: '', object: {} });
  const [script, setScript] = useState('window.ReactNativeWebView.postMessage(document.title);');
  const [x, setX] = useState('0');
  const [y, setY] = useState('400');
  const [animated, setAnimated] = useState(true);
  const [message, setMessage] = useState<NativeMessage | null>(null);
  const [processEvents, setProcessEvents] = useState<Record<string, object>>({});
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const ios = Platform.OS === 'ios';
  const hasNestedScroll = Platform.OS === 'android' || String(Platform.OS) === 'harmony';

  useEffect(() => () => {
    if (directory.current?.exists) directory.current.delete();
    directory.current = null;
  }, []);

  async function preparePage(kind: 'sample' | 'bridge') {
    if (!directory.current) {
      const folder = new Directory(Paths.cache, `dom-webview-${Date.now()}`);
      folder.create();
      directory.current = folder;
    }

    const folder = directory.current;
    const page = new File(folder, `${kind}.html`);
    if (page.exists) return page.uri;
    if (kind === 'sample') {
      const video = await Asset.fromModule(videoSample).downloadAsync();
      if (!video.localUri) throw new Error('找不到内置视频。');
      if (directory.current !== folder) throw new Error('网页已关闭。');
      const sample = new File(folder, 'sample.mp4');
      if (!sample.exists) await new File(video.localUri).copy(sample);
      if (directory.current !== folder) {
        if (folder.exists) folder.delete();
        throw new Error('网页已关闭。');
      }
    }
    page.write(kind === 'sample' ? SAMPLE_HTML : BRIDGE_HTML);
    return page.uri;
  }

  function run(command: (webview: DomWebViewRef) => void, name: string) {
    return action.run(async () => {
      if (!view.current) throw new Error('请先打开网页。');

      await command(view.current);
      return name;
    });
  }

  function applyScripts() {
    return action.run(() => {
      setScripts({ before, after, object: objectField(object) });
      return '已应用脚本与注入对象';
    });
  }

  function selectTab(next: 'sample' | 'bridge') {
    setTab(next);
    action.clear();
  }

  function applyIosScrollOptions() {
    return action.run(() => {
      const rate = iosDeceleration.trim();
      const decelerationRate = rate === 'normal' || rate === 'fast' ? rate : numberField(rate, '减速率');
      const contentInset = objectField(iosInsets);
      for (const [key, value] of Object.entries(contentInset)) {
        if (!['top', 'left', 'bottom', 'right'].includes(key) || typeof value !== 'number' || !Number.isFinite(value)) {
          throw new Error('内容边距的 top、left、bottom 和 right 需要填写数字。');
        }
      }
      setIosScrollOptions({ decelerationRate, contentInset });
      return '滚动设置已应用';
    });
  }

  const initialMediaSettings = [
    requiresGesture,
    iosToggles.allowsInlineMediaPlayback,
    iosToggles.allowsPictureInPictureMediaPlayback,
    iosToggles.allowsAirPlayForMediaPlayback,
  ];
  const iosProps = ios
    ? { ...iosToggles, ...iosScrollOptions, contentInsetAdjustmentBehavior: iosBehavior }
    : {};

  if (Platform.OS === 'web') return <DomComponentDemo />;

  return (
    <>
      <DomComponentDemo />

      <Panel title="WebView">
        <ActionRow>
          <Toggle disabled={busy} label="网页与脚本" active={tab === 'sample'} onPress={() => selectTab('sample')} />
          <Toggle disabled={busy} label="Expo 原生模块" active={tab === 'bridge'} onPress={() => selectTab('bridge')} />
        </ActionRow>
        {tab === 'bridge'
          ? (
              <>
                <ActionRow>
                  <ActionButton
                    disabled={busy || !!bridgeUri}
                    label="打开内置网页"
                    onPress={() => void action.run(async () => {
                      const localUri = await preparePage('bridge');
                      setBridgeUri(localUri);
                      return localUri;
                    })}
                  />
                  <Toggle label="Expo 模块桥接" active={bridge} onPress={() => setBridge(value => !value)} />
                </ActionRow>
                {bridgeUri
                  ? (
                      <WebView
                        containerStyle={[styles.webview, styles.bridge]}
                        key={String(bridge)}
                        source={{ uri: bridgeUri }}
                        useExpoModulesBridge={bridge}
                        webviewDebuggingEnabled={false}
                      />
                    )
                  : null}
              </>
            )
          : (
              <>
                <Field label="网页 URI" value={uriInput} onChangeText={setUriInput} placeholder="https://example.com" />
                <ActionRow>
                  <ActionButton
                    disabled={busy || !uriInput.trim()}
                    label="打开网址"
                    onPress={() => void action.run(() => {
                      const url = new URL(uriInput.trim());
                      if (url.protocol !== 'https:' && url.protocol !== 'http:') throw new Error('请输入 HTTP 或 HTTPS 地址。');
                      setUri(url.href);
                      setMessage(null);
                      setProcessEvents({});
                      return url.href;
                    })}
                  />
                  <ActionButton
                    disabled={busy}
                    label="打开本地样例"
                    onPress={() => void action.run(async () => {
                      const localUri = await preparePage('sample');
                      setUri(localUri);
                      setMessage(null);
                      setProcessEvents({});
                      return localUri;
                    })}
                    testID="dom-webview-load"
                    tone="secondary"
                  />
                </ActionRow>
                {uri
                  ? (
                      <WebView
                        {...iosProps}
                        containerStyle={[styles.webview, rounded && styles.rounded]}
                        injectedJavaScript={scripts.after}
                        injectedJavaScriptBeforeContentLoaded={scripts.before}
                        injectedJavaScriptObject={scripts.object}
                        key={ios ? json(initialMediaSettings) : 'sample'}
                        mediaPlaybackRequiresUserAction={requiresGesture}
                        nestedScrollEnabled={nested}
                        onContentProcessDidTerminate={({ nativeEvent }) =>
                          setProcessEvents(current => ({ ...current, onContentProcessDidTerminate: nativeEvent }))}
                        onMessage={({ nativeEvent }) => setMessage(nativeEvent)}
                        onRenderProcessGone={({ nativeEvent }) =>
                          setProcessEvents(current => ({ ...current, onRenderProcessGone: nativeEvent }))}
                        ref={view}
                        showsHorizontalScrollIndicator={horizontal}
                        showsVerticalScrollIndicator={vertical}
                        source={{ uri }}
                        style={inset ? styles.inset : undefined}
                        testID="dom-webview-preview"
                        useExpoModulesBridge={false}
                        webviewDebuggingEnabled={debugging}
                      />
                    )
                  : null}
                {message ? <DataRow label="onMessage" value={json(message)} /> : null}
                {Object.entries(processEvents).map(([name, payload]) => (
                  <DataRow key={name} label={name} value={json(payload)} />
                ))}
              </>
            )}
        <ResultPanel state={action.state} />
      </Panel>

      {tab === 'sample'
        ? (
            <>
              <Panel title="视图设置">
                <ActionRow>
                  <Toggle label="横向滚动条" active={horizontal} onPress={() => setHorizontal(value => !value)} testID="dom-webview-indicators" />
                  <Toggle label="纵向滚动条" active={vertical} onPress={() => setVertical(value => !value)} />
                  {hasNestedScroll ? <Toggle label="嵌套滚动" active={nested} onPress={() => setNested(value => !value)} /> : null}
                  <Toggle label="媒体播放需要手势" active={requiresGesture} onPress={() => setRequiresGesture(value => !value)} />
                  <Toggle label="网页调试" active={debugging} onPress={() => setDebugging(value => !value)} />
                  <Toggle label="网页外边距" active={inset} onPress={() => setInset(value => !value)} />
                  <Toggle label="容器圆角" active={rounded} onPress={() => setRounded(value => !value)} />
                </ActionRow>
              </Panel>

              <Panel title="加载时注入">
                <Field label="加载前脚本" multiline value={before} onChangeText={setBefore} />
                <Field label="加载后脚本" multiline value={after} onChangeText={setAfter} />
                <Field label="注入对象（JSON）" multiline value={object} onChangeText={setObject} />
                <ActionButton disabled={busy} label="应用" onPress={() => void applyScripts()} />
              </Panel>

              <Panel title="视图方法">
                <Field label="JavaScript" multiline value={script} onChangeText={setScript} />
                <ActionButton
                  disabled={busy || !uri}
                  label="injectJavaScript"
                  onPress={() => void run(webview => webview.injectJavaScript(script), '脚本已提交')}
                  testID="dom-webview-inject"
                />
                <Field label="横坐标 x" value={x} onChangeText={setX} keyboardType="numbers-and-punctuation" />
                <Field label="纵坐标 y" value={y} onChangeText={setY} keyboardType="numbers-and-punctuation" />
                <ActionRow>
                  <Toggle label="滚动动画" active={animated} onPress={() => setAnimated(value => !value)} />
                  <ActionButton
                    disabled={busy || !uri}
                    label="scrollTo"
                    onPress={() => void run(webview => webview.scrollTo({
                      x: numberField(x, '横坐标'),
                      y: numberField(y, '纵坐标'),
                      animated,
                    }), '滚动位置已设置')}
                    testID="dom-webview-bottom"
                  />
                  <ActionButton disabled={busy || !uri} label="reload" onPress={() => void run(webview => webview.reload(), '已请求重载')} tone="secondary" />
                </ActionRow>
              </Panel>

              {ios
                ? (
                    <Panel title="iOS 视图设置">
                      <ActionRow>
                        {IOS_TOGGLE_NAMES.map((key) => {
                          const { initial, label } = IOS_TOGGLES[key];
                          const value = iosToggles[key] ?? initial;
                          return (
                            <Toggle
                              key={key}
                              label={label}
                              active={value}
                              onPress={() => setIosToggles(current => ({ ...current, [key]: !value }))}
                            />
                          );
                        })}
                      </ActionRow>
                      <Field label="减速率（normal、fast 或数值）" value={iosDeceleration} onChangeText={setIosDeceleration} />
                      <Field label="内容边距（JSON）" value={iosInsets} onChangeText={setIosInsets} />
                      <ActionRow>
                        {INSET_BEHAVIORS.map(value => (
                          <Toggle
                            key={value}
                            label={value}
                            active={iosBehavior === value}
                            onPress={() => setIosBehavior(value)}
                          />
                        ))}
                      </ActionRow>
                      <ActionButton
                        disabled={busy}
                        label="应用滚动设置"
                        onPress={() => void applyIosScrollOptions()}
                      />
                    </Panel>
                  )
                : null}
            </>
          )
        : null}
    </>
  );
}

const styles = StyleSheet.create({
  component: { flex: 0, width: '100%', borderRadius: 12, overflow: 'hidden' },
  fixedComponent: { height: 150 },
  webview: { flex: 0, height: 260, backgroundColor: '#C6DFFB', overflow: 'hidden' },
  bridge: { height: 400, borderRadius: 12 },
  rounded: { borderRadius: 12 },
  inset: { margin: 12 },
});

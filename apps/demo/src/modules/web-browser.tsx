/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Linking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';
import { useEffect, useRef, useState } from 'react';
import { Platform, Switch } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const ANDROID_TOGGLES = [
  ['enableBarCollapsing', '滚动时收起工具栏', false],
  ['showTitle', '显示网页标题', false],
  ['enableDefaultShareMenuItem', '显示分享菜单项', false],
  ['showInRecents', '在最近任务中显示', false],
  ['createTask', '新建任务', true],
  ['useProxyActivity', '通过代理 Activity 打开', true],
] as const;

export function WebBrowserDemo() {
  const [url, setUrl] = useState('https://example.com');
  const [redirect, setRedirect] = useState(() => Linking.createURL('module/web-browser'));
  const [options, setOptions] = useState<WebBrowser.WebBrowserOpenOptions>({});
  const [features, setFeatures] = useState('');
  const [ephemeral, setEphemeral] = useState(false);
  const [universalLinks, setUniversalLinks] = useState(false);
  const [skipRedirectCheck, setSkipRedirectCheck] = useState(false);
  const authOpen = useRef(false);
  const browser = useAsyncResult();
  const session = useAsyncResult();
  const auxiliary = useAsyncResult();
  const android = Platform.OS === 'android';
  const ios = Platform.OS === 'ios';
  const web = Platform.OS === 'web';
  const auxiliaryBusy = auxiliary.state.phase === 'running';
  const busy = browser.state.phase === 'running' || session.state.phase === 'running';

  useEffect(() => () => {
    if (authOpen.current && !android) WebBrowser.dismissAuthSession();
  }, [android]);

  const browserOptions = (): WebBrowser.WebBrowserOpenOptions => {
    if (!web || !features.trim()) return options;

    const windowFeatures = features.trim();
    return {
      ...options,
      windowFeatures: windowFeatures.startsWith('{') ? JSON.parse(windowFeatures) : windowFeatures,
    };
  };

  const open = (dismissAfterDelay = false) => browser.run(async () => {
    const timer = dismissAfterDelay
      ? setTimeout(() => {
          void auxiliary.run(async () => json(await WebBrowser.dismissBrowser()));
        }, 5000)
      : undefined;

    try {
      return json(await WebBrowser.openBrowserAsync(url, browserOptions()));
    } finally {
      clearTimeout(timer);
    }
  });

  const authenticate = (dismissAfterDelay = false) => session.run(async () => {
    authOpen.current = true;
    const timer = dismissAfterDelay ? setTimeout(WebBrowser.dismissAuthSession, 5000) : undefined;

    try {
      return json(await WebBrowser.openAuthSessionAsync(
        url,
        redirect.trim() || null,
        ios ? { preferEphemeralSession: ephemeral, preferUniversalLinks: universalLinks } : browserOptions()
      ));
    } finally {
      clearTimeout(timer);
      authOpen.current = false;
    }
  });

  return (
    <>
      <Panel title="打开网页">
        <Field label="网页 URL" onChangeText={setUrl} testID="web-browser-url" value={url} />
        {android
          ? (
              <>
                <Field label="浏览器包名" onChangeText={value => setOptions(current => ({ ...current, browserPackage: value || undefined }))} value={options.browserPackage ?? ''} />
                <Field label="辅助工具栏颜色" onChangeText={value => setOptions(current => ({ ...current, secondaryToolbarColor: value || undefined }))} value={options.secondaryToolbarColor ?? ''} />
                {ANDROID_TOGGLES.map(([key, label, fallback]) => (
                  <DataRow
                    key={key}
                    label={label}
                    value={
                      <Switch
                        accessibilityLabel={label}
                        onValueChange={value => setOptions(current => ({ ...current, [key]: value }))}
                        value={options[key] ?? fallback}
                      />
                    }
                  />
                ))}
              </>
            )
          : null}
        {android || ios
          ? (
              <>
                <Field label="工具栏颜色" onChangeText={value => setOptions(current => ({ ...current, toolbarColor: value || undefined }))} value={options.toolbarColor ?? ''} />
              </>
            )
          : null}
        {ios
          ? (
              <>
                <DataRow label="滚动时收起工具栏" value={<Switch accessibilityLabel="滚动时收起工具栏" onValueChange={value => setOptions(current => ({ ...current, enableBarCollapsing: value }))} value={options.enableBarCollapsing ?? false} />} />
                <Field label="控件颜色" onChangeText={value => setOptions(current => ({ ...current, controlsColor: value || undefined }))} value={options.controlsColor ?? ''} />
                <DataRow label="阅读模式" value={<Switch accessibilityLabel="阅读模式" onValueChange={value => setOptions(current => ({ ...current, readerMode: value }))} value={options.readerMode ?? false} />} />
                <DataRow label="关闭按钮样式" value={options.dismissButtonStyle ?? '默认'} />
                <ActionRow>
                  {(['done', 'close', 'cancel'] as const).map(style => (
                    <ActionButton key={style} label={style} onPress={() => setOptions(current => ({ ...current, dismissButtonStyle: style }))} tone={options.dismissButtonStyle === style ? 'primary' : 'secondary'} />
                  ))}
                </ActionRow>
                <DataRow label="浏览器呈现方式" value={options.presentationStyle ?? '默认'} />
                <ActionRow>
                  {Object.values(WebBrowser.WebBrowserPresentationStyle).map(style => (
                    <ActionButton key={style} label={style} onPress={() => setOptions(current => ({ ...current, presentationStyle: style }))} tone={options.presentationStyle === style ? 'primary' : 'secondary'} />
                  ))}
                </ActionRow>
              </>
            )
          : null}
        {web
          ? (
              <>
                <Field label="弹窗名称" onChangeText={value => setOptions(current => ({ ...current, windowName: value || undefined }))} value={options.windowName ?? ''} />
                <Field label="弹窗配置" onChangeText={setFeatures} placeholder="width=640,height=480" value={features} />
              </>
            )
          : null}
        <ActionRow>
          <ActionButton disabled={busy || !url.trim()} label="打开浏览器" onPress={() => void open()} testID="web-browser-open" />
          {ios ? <ActionButton disabled={busy || !url.trim()} label="打开浏览器，5 秒后关闭" onPress={() => void open(true)} tone="secondary" /> : null}
        </ActionRow>
        <ResultPanel state={browser.state} />
        {ios ? <ResultPanel state={auxiliary.state} /> : null}
      </Panel>

      <Panel title="浏览器认证">
        <Field label="回跳 URL" onChangeText={setRedirect} testID="web-browser-redirect" value={redirect} />
        {ios
          ? (
              <>
                <DataRow label="临时会话" value={<Switch accessibilityLabel="临时会话" onValueChange={setEphemeral} value={ephemeral} />} />
                <DataRow label="通用链接回跳" value={<Switch accessibilityLabel="通用链接回跳" onValueChange={setUniversalLinks} value={universalLinks} />} />
              </>
            )
          : null}
        <ActionRow>
          <ActionButton disabled={busy || !url.trim()} label="开始认证会话" onPress={() => void authenticate()} testID="web-browser-auth" />
          {ios ? <ActionButton disabled={busy || !url.trim()} label="开始认证，5 秒后结束" onPress={() => void authenticate(true)} tone="secondary" /> : null}
          {!android && !ios ? <ActionButton disabled={session.state.phase !== 'running'} label="结束认证会话" onPress={() => WebBrowser.dismissAuthSession()} testID="web-browser-dismiss" tone="secondary" /> : null}
        </ActionRow>
        <ResultPanel state={session.state} />
      </Panel>

      {android
        ? (
            <Panel title="Custom Tabs">
              <ActionRow>
                <ActionButton disabled={auxiliaryBusy} label="列出支持 Custom Tabs 的浏览器" onPress={() => void auxiliary.run(async () => json(await WebBrowser.getCustomTabsSupportingBrowsersAsync()))} />
                <ActionButton disabled={auxiliaryBusy} label="预热浏览器" onPress={() => void auxiliary.run(async () => json(await WebBrowser.warmUpAsync(options.browserPackage)))} tone="secondary" />
                <ActionButton disabled={auxiliaryBusy || !url.trim()} label="预加载网页" onPress={() => void auxiliary.run(async () => json(await WebBrowser.mayInitWithUrlAsync(url, options.browserPackage)))} tone="secondary" />
                <ActionButton disabled={auxiliaryBusy} label="释放预热连接" onPress={() => void auxiliary.run(async () => json(await WebBrowser.coolDownAsync(options.browserPackage)))} tone="secondary" />
              </ActionRow>
              <ResultPanel state={auxiliary.state} />
            </Panel>
          )
        : null}

      {web
        ? (
            <Panel title="网页回跳">
              <DataRow label="跳过回跳 URL 校验" value={<Switch accessibilityLabel="跳过回跳 URL 校验" onValueChange={setSkipRedirectCheck} value={skipRedirectCheck} />} />
              <ActionButton label="完成认证会话" onPress={() => void auxiliary.run(() => json(WebBrowser.maybeCompleteAuthSession({ skipRedirectCheck })))} />
              <ResultPanel state={auxiliary.state} />
            </Panel>
          )
        : null}
    </>
  );
}

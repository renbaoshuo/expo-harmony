/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as NavigationBar from 'expo-navigation-bar';
import { useEffect, useRef, useState } from 'react';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Panel, ResultPanel, useAsyncResult } from '../ui';
import { Cycle, Toggle } from './visual-controls';

const styles: NavigationBar.NavigationBarStyle[] = ['auto', 'inverted', 'light', 'dark'];

export function NavigationBarDemo() {
  const action = useAsyncResult();
  const observedVisibility = NavigationBar.useVisibility();
  const [style, setStyle] = useState<NavigationBar.NavigationBarStyle>('auto');
  const [hidden, setHidden] = useState(false);
  const [useComponent, setUseComponent] = useState(true);
  const [listening, setListening] = useState(false);
  const [event, setEvent] = useState<NavigationBar.NavigationBarVisibilityEvent>();
  const changed = useRef(false);

  useEffect(() => {
    if (!listening) return;

    const subscription = NavigationBar.addVisibilityListener(setEvent);
    return () => subscription.remove();
  }, [listening]);

  useEffect(() => () => {
    if (changed.current) {
      NavigationBar.NavigationBar.setStyle('dark');
      NavigationBar.NavigationBar.setHidden(false);
    }
  }, []);

  const call = (api: string, operation: () => void | Promise<void>) => void action.run(async () => {
    changed.current = true;
    await operation();
    return api;
  });

  return (
    <>
      {useComponent ? <NavigationBar.NavigationBar style={style} hidden={hidden} /> : null}
      <Panel title="NavigationBar">
        <ActionRow>
          <Cycle label="按键颜色" value={style} choices={styles} onChange={setStyle} />
          <Toggle label="隐藏导航栏" value={hidden} onChange={setHidden} />
          <Toggle label="应用组件属性" value={useComponent} onChange={setUseComponent} />
        </ActionRow>
        {useComponent
          ? null
          : (
              <ActionRow>
                <ActionButton label="应用颜色（setStyle）" onPress={() => call('NavigationBar.setStyle', () => NavigationBar.NavigationBar.setStyle(style))} />
                <ActionButton label="应用显隐（setHidden）" onPress={() => call('NavigationBar.setHidden', () => NavigationBar.NavigationBar.setHidden(hidden))} />
                <ActionButton label="setStyle" onPress={() => call('setStyle', () => NavigationBar.setStyle(style))} tone="secondary" />
                <ActionButton label="setVisibilityAsync" onPress={() => call('setVisibilityAsync', () => NavigationBar.setVisibilityAsync(hidden ? 'hidden' : 'visible'))} tone="secondary" />
              </ActionRow>
            )}
        <ActionButton label="读取可见性" onPress={() => void action.run(async () => await NavigationBar.getVisibilityAsync())} testID="navigation-bar-read" tone="secondary" />
        <ResultPanel state={action.state} />
      </Panel>
      <Panel title="可见性变化">
        <DataRow label="useVisibility" value={observedVisibility ?? '等待状态'} />
        {event ? <DataRow label="最近事件" value={json(event)} /> : null}
        <ActionButton label={listening ? '移除监听' : '监听可见性变化'} onPress={() => setListening(value => !value)} testID="navigation-bar-listen" tone="secondary" />
      </Panel>
    </>
  );
}

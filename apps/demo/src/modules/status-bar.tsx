/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { StatusBar, setStatusBarHidden, setStatusBarStyle, type StatusBarAnimation, type StatusBarStyle } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import { ActionButton, ActionRow, Panel } from '../ui';
import { Cycle, Toggle } from './visual-controls';

const styles: StatusBarStyle[] = ['auto', 'inverted', 'light', 'dark'];
const animations: StatusBarAnimation[] = ['none', 'fade', 'slide'];

export function StatusBarDemo() {
  const [style, setStyle] = useState<StatusBarStyle>('dark');
  const [hidden, setHidden] = useState(false);
  const [animated, setAnimated] = useState(false);
  const [animation, setAnimation] = useState<StatusBarAnimation>('fade');
  const [useComponent, setUseComponent] = useState(true);
  const changed = useRef(false);

  useEffect(() => () => {
    if (changed.current) {
      StatusBar.setStyle('dark');
      StatusBar.setHidden(false);
    }
  }, []);

  const applyStyle = (set: typeof setStatusBarStyle) => {
    changed.current = true;
    set(style, animated);
  };

  const applyHidden = (set: typeof setStatusBarHidden) => {
    changed.current = true;
    set(hidden, animation);
  };

  return (
    <Panel title="StatusBar">
      {useComponent
        ? <StatusBar style={style} hidden={hidden} animated={animated} hideTransitionAnimation={animation} />
        : null}
      <ActionRow>
        <Cycle label="文字颜色" value={style} choices={styles} onChange={setStyle} />
        <Toggle label="隐藏状态栏" value={hidden} onChange={setHidden} />
        <Toggle label="应用组件属性" value={useComponent} onChange={setUseComponent} />
        {Platform.OS === 'ios'
          ? (
              <>
                <Toggle label="启用动画" value={animated} onChange={setAnimated} />
                <Cycle label="显隐动画" value={animation} choices={animations} onChange={setAnimation} />
              </>
            )
          : null}
      </ActionRow>
      {useComponent
        ? null
        : (
            <ActionRow>
              <ActionButton label="应用颜色（setStyle）" onPress={() => applyStyle(StatusBar.setStyle)} />
              <ActionButton label="应用显隐（setHidden）" onPress={() => applyHidden(StatusBar.setHidden)} />
              <ActionButton label="setStatusBarStyle" onPress={() => applyStyle(setStatusBarStyle)} tone="secondary" />
              <ActionButton label="setStatusBarHidden" onPress={() => applyHidden(setStatusBarHidden)} tone="secondary" />
            </ActionRow>
          )}
    </Panel>
  );
}

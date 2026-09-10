import * as NavigationBar from 'expo-navigation-bar';
import { useEffect } from 'react';
import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Note, Panel, ResultPanel, Tag, useAsyncResult } from '../ui';
import { json } from '../format';

export function NavigationBarDemo() {
  const action = useAsyncResult();
  const observedVisibility = NavigationBar.useVisibility();

  useEffect(() => () => {
    void Promise.all([
      NavigationBar.setBackgroundColorAsync(palette.canvas),
      NavigationBar.setButtonStyleAsync('light'),
      NavigationBar.setPositionAsync('relative'),
      NavigationBar.setVisibilityAsync('visible'),
    ]).catch(() => undefined);
  }, []);

  const inspect = () => action.run(async () => json({
    backgroundColor: await NavigationBar.getBackgroundColorAsync(),
    buttonStyle: await NavigationBar.getButtonStyleAsync(),
    position: await NavigationBar.unstable_getPositionAsync(),
    visibility: await NavigationBar.getVisibilityAsync(),
  }));

  return (
    <>
      <Panel eyebrow="实时状态" title="读取 Harmony 导航栏">
        <DataRow
          label="可见性事件 Hook"
          value={<Tag tone={observedVisibility === 'hidden' ? 'danger' : 'success'}>{observedVisibility ?? '加载中'}</Tag>}
        />
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="读取原生状态"
          onPress={() => void inspect()}
          testID="navigation-bar-read"
        />
        <ResultPanel state={action.state} />
      </Panel>

      <Panel eyebrow="颜色与按键" title="修改原生系统栏属性">
        <ActionRow>
          <ActionButton
            label="设置主题色"
            onPress={() => void NavigationBar.setBackgroundColorAsync(palette.signal)}
            testID="navigation-bar-signal-color"
          />
          <ActionButton
            label="恢复默认背景"
            onPress={() => void NavigationBar.setBackgroundColorAsync(palette.canvas)}
            tone="secondary"
          />
        </ActionRow>
        <ActionRow>
          <ActionButton label="浅色按键" onPress={() => void NavigationBar.setButtonStyleAsync('light')} />
          <ActionButton label="深色按键" onPress={() => void NavigationBar.setButtonStyleAsync('dark')} tone="secondary" />
        </ActionRow>
      </Panel>

      <Panel eyebrow="布局与可见性" title="演练系统栏生命周期">
        <ActionRow>
          <ActionButton label="显示导航栏" onPress={() => void NavigationBar.setVisibilityAsync('visible')} />
          <ActionButton
            label="隐藏导航栏"
            onPress={() => void NavigationBar.setVisibilityAsync('hidden')}
            testID="navigation-bar-hide"
            tone="secondary"
          />
        </ActionRow>
        <ActionRow>
          <ActionButton label="相对定位" onPress={() => void NavigationBar.setPositionAsync('relative')} />
          <ActionButton label="绝对定位" onPress={() => void NavigationBar.setPositionAsync('absolute')} tone="secondary" />
        </ActionRow>
        <Note>
          绝对定位模式下 React 内容会延伸到系统栏下方。离开本页面时会自动恢复实验室默认设置。
        </Note>
      </Panel>
    </>
  );
}

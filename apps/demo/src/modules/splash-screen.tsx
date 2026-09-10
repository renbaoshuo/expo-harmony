import * as SplashScreen from 'expo-splash-screen';
import { palette } from '../theme';
import { ActionButton, DataRow, Note, Panel, ResultPanel, useAsyncResult } from '../ui';

export function SplashScreenDemo() {
  const action = useAsyncResult();

  return (
    <>
      <Panel eyebrow="启动交接" title="原生启动屏状态机">
        <Note>
          根布局在模块作用域调用 preventAutoHideAsync，加载内置字体后，恰好在 React 内容就绪时隐藏启动屏。
        </Note>
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="验证幂等交接"
          onPress={() => void action.run(async () => {
            SplashScreen.setOptions({ duration: 0, fade: false });
            const prevented = await SplashScreen.preventAutoHideAsync();
            SplashScreen.hide();
            await SplashScreen.hideAsync();
            return `就绪后 prevent → ${String(prevented)}；重复 hide 已完成`;
          })}
        />
        <ResultPanel state={action.state} />
      </Panel>
      <Panel eyebrow="CNG 资源" title="冷启动视觉契约">
        <DataRow label="背景色" value={palette.canvas} />
        <DataRow label="缩放模式" value="contain" />
        <DataRow label="图片" value="assets/app-icon.svg" />
      </Panel>
    </>
  );
}

import * as SystemUI from 'expo-system-ui';
import { palette } from '../theme';
import { ActionButton, ActionRow, Panel, ResultPanel, useAsyncResult } from '../ui';

export function SystemUIDemo() {
  const action = useAsyncResult();

  return (
    <Panel eyebrow="窗口根视图" title="运行时背景色">
      <ActionRow>
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="设为实验室背景"
          onPress={() => void action.run(async () => {
            await SystemUI.setBackgroundColorAsync(palette.canvas);
            return `getBackgroundColorAsync() → ${String(await SystemUI.getBackgroundColorAsync())}`;
          })}
          testID="system-ui-set-background"
        />
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="清除覆盖"
          onPress={() => void action.run(async () => {
            await SystemUI.setBackgroundColorAsync(null);
            return `getBackgroundColorAsync() → ${String(await SystemUI.getBackgroundColorAsync())}`;
          })}
          testID="system-ui-reset-background"
          tone="secondary"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

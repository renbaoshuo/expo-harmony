import { useState } from 'react';

import {
  HAPTICS_MANUAL_CASES,
  runHapticsArgumentProbe,
  runHapticsMatrix,
} from './hapticsProbe';
import {
  ActionButton,
  ActionRow,
  DataRow,
  Note,
  Panel,
  ResultPanel,
  Tag,
  useAsyncResult,
} from './ui';

export function HapticsDemo() {
  const matrix = useAsyncResult();
  const argumentsCheck = useAsyncResult();
  const manual = useAsyncResult();
  const [lastTrigger, setLastTrigger] = useState('暂无');
  const busy = matrix.state.phase === 'running'
    || argumentsCheck.state.phase === 'running'
    || manual.state.phase === 'running';

  const trigger = (label: string, run: () => Promise<void>) => manual.run(async () => {
    await run();
    setLastTrigger(label);

    return `${label} 的 Promise 已完成，请用手实际确认触感。`;
  });

  return (
    <>
      <Panel eyebrow="自动契约" title="Promise 完成情况与原生参数校验">
        <ActionRow>
          <ActionButton
            disabled={busy}
            label="运行触感矩阵"
            onPress={() => void matrix.run(runHapticsMatrix)}
            testID="haptics-run-matrix"
          />
          <ActionButton
            disabled={busy}
            label="检查非法输入"
            onPress={() => void argumentsCheck.run(runHapticsArgumentProbe)}
            testID="haptics-check-invalid-input"
            tone="secondary"
          />
        </ActionRow>
        <Note>
          自动通过仅表示官方 Expo Promise 已完成，或原生校验返回了预期的错误码，并不能证明马达确实震动——在不具备受支持震动引擎的设备上，HarmonyOS 可能对尽力而为的调用直接返回成功。
        </Note>
        <ResultPanel state={matrix.state} />
        <ResultPanel state={argumentsCheck.state} />
      </Panel>

      <Panel eyebrow="手动体感" title="逐个触发、感受并记录每种官方反馈样式">
        <Tag tone="signal">需人工确认体感</Tag>
        <DataRow label="最近触发" value={lastTrigger} />
        <ActionRow>
          {HAPTICS_MANUAL_CASES.map(item => (
            <ActionButton
              disabled={busy}
              key={item.id}
              label={item.label}
              onPress={() => void trigger(item.label, item.run)}
              testID={`haptics-${item.id}`}
              tone="secondary"
            />
          ))}
        </ActionRow>
        <Note>
          请在真机与目标模拟器上逐一尝试所有按钮，分别对比 light/soft、medium/rigid、heavy、selection
          以及各类通知样式。同时检查系统震动设置、静音模式以及设备是否真的配有震动马达；
          该 API 没有可视结果属于正常边界。
        </Note>
        <ResultPanel state={manual.state} />
      </Panel>
    </>
  );
}

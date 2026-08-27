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
import {
  clearAppMetricsStorage,
  markAppMetricsFirstRender,
  markAppMetricsInteractive,
  readAppMetricsStorage,
  runAppMetricsMatrix,
} from './appMetricsProbe';

export function AppMetricsDemo() {
  const matrix = useAsyncResult();
  const lifecycle = useAsyncResult();
  const storage = useAsyncResult();
  const busy = matrix.state.phase === 'running'
    || lifecycle.state.phase === 'running'
    || storage.state.phase === 'running';

  return (
    <>
      <Panel eyebrow="App Metrics 契约" title="运行真实的 HarmonyOS 存储与指标检测">
        <ActionButton
          disabled={busy}
          label="运行指标矩阵"
          onPress={() => void matrix.run(runAppMetricsMatrix)}
          testID="app-metrics-run-matrix"
        />
        <Note>
          该矩阵使用官方 expo-app-metrics JavaScript 门面：仅清空 App Metrics 存储、创建真实会话、持久化一条自定义指标、
          标记启动生命周期、读取 Harmony 诊断快照、验证会话已结束、校验必需的启动耗时与可选字段、
          校验存储的指标标识与内存快照，并验证原生返回的无效会话错误码。
        </Note>
        <ResultPanel state={matrix.state} />
      </Panel>

      <Panel eyebrow="启动生命周期" title="手动标记每次启动仅记录一次的事件">
        <ActionRow>
          <ActionButton
            disabled={busy}
            label="标记首次渲染"
            onPress={() => void lifecycle.run(markAppMetricsFirstRender)}
            testID="app-metrics-mark-first-render"
            tone="secondary"
          />
          <ActionButton
            disabled={busy}
            label="标记可交互"
            onPress={() => void lifecycle.run(markAppMetricsInteractive)}
            testID="app-metrics-mark-interactive"
          />
        </ActionRow>
        <DataRow label="原生平台" value={<Tag tone="signal">HarmonyOS</Tag>} />
        <Note>
          这些调用特意设计为手动触发。官方模块在进程内首次成功调用后会忽略重复的启动标记，因此第二次按下不会产生新的基准数据。
        </Note>
        <ResultPanel state={lifecycle.state} />
      </Panel>

      <Panel eyebrow="持久化会话" title="查看或清空本地 Preferences 存储">
        <ActionRow>
          <ActionButton
            disabled={busy}
            label="读取存储条目"
            onPress={() => void storage.run(readAppMetricsStorage)}
            testID="app-metrics-read-storage"
            tone="secondary"
          />
          <ActionButton
            disabled={busy}
            label="清空存储条目"
            onPress={() => void storage.run(clearAppMetricsStorage)}
            testID="app-metrics-clear-storage"
            tone="danger"
          />
        </ActionRow>
        <Note>
          getStoredEntries() 以 Harmony 上兼容 Android 的会话结构展示：每条记录包含会话元数据与指标。清空操作便于失败后重跑，同时也可验证存储恢复能力。
        </Note>
        <ResultPanel state={storage.state} />
      </Panel>
    </>
  );
}

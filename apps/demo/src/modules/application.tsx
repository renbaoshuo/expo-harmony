import * as Application from 'expo-application';
import { ActionButton, DataRow, Panel, ResultPanel, useAsyncResult } from '../ui';

export function ApplicationDemo() {
  const action = useAsyncResult();

  return (
    <>
      <Panel eyebrow="已安装应用" title="原生应用包标识">
        <DataRow label="applicationId" value={Application.applicationId || 'null'} />
        <DataRow label="applicationName" value={Application.applicationName || 'null'} />
        <DataRow label="nativeApplicationVersion" value={Application.nativeApplicationVersion || 'null'} />
        <DataRow label="nativeBuildVersion" value={Application.nativeBuildVersion || 'null'} />
      </Panel>
      <Panel eyebrow="安装记录" title="系统报告的时间戳">
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="读取安装时间"
          onPress={() => void action.run(async () => {
            const installedAt = await Application.getInstallationTimeAsync();
            if (Number.isNaN(installedAt.getTime())) throw new Error('原生安装时间无效。');
            return installedAt.toISOString();
          })}
        />
        <ResultPanel state={action.state} />
      </Panel>
    </>
  );
}

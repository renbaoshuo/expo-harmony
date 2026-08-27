import { Stack, useLocalSearchParams } from 'expo-router';

import { findModule } from '../../src/catalog';
import { ModuleDemo } from '../../src/modules';
import { LabScreen, Note } from '../../src/ui';

export default function ModuleScreen() {
  const params = useLocalSearchParams<{ module?: string | string[] }>();
  const module = findModule(params.module);

  if (!module) {
    return (
      <LabScreen description="当前分支暂不包含该包。" kicker="未知包" title="未找到模块">
        <Note>请返回首页，选择一个已安装的包。</Note>
      </LabScreen>
    );
  }

  return (
    <>
      <Stack.Screen options={{ title: module.title }} />
      <LabScreen
        description={module.summary}
        kicker={module.packageName}
        testID={`module-${module.id}`}
        title={module.title}
      >
        <ModuleDemo id={module.id} />
      </LabScreen>
    </>
  );
}

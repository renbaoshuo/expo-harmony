/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { AppMetricsErrorBoundary, AppMetricsRoot, type AppMetricsErrorBoundaryFallbackProps } from 'expo-app-metrics';
import { useState } from 'react';

import { ActionButton, ActionRow, DataRow, Panel } from '../../ui';

function Sample({ shouldThrow = false }: { shouldThrow?: boolean }) {
  if (shouldThrow) throw new Error('示例组件渲染失败');
  return <DataRow label="示例组件" value="已挂载" />;
}

const WrappedSample = AppMetricsRoot.wrap(Sample);

type SampleMode = 'root' | 'wrapped' | 'boundary';

export function MetricsRenderDemo() {
  const [mode, setMode] = useState<SampleMode>();
  const [shouldThrow, setShouldThrow] = useState(false);

  const show = (next: SampleMode) => {
    setShouldThrow(false);
    setMode(next);
  };

  const fallback = ({ error, resetError }: AppMetricsErrorBoundaryFallbackProps) => (
    <>
      <DataRow label="已捕获的错误" value={error instanceof Error ? error.message : String(error)} />
      <ActionButton
        label="重新渲染"
        onPress={() => {
          setShouldThrow(false);
          resetError();
        }}
        tone="secondary"
      />
    </>
  );

  return (
    <Panel title="渲染与错误边界">
      <ActionRow>
        <ActionButton label="AppMetricsRoot" onPress={() => show('root')} tone={mode === 'root' ? 'primary' : 'secondary'} />
        <ActionButton label="AppMetricsRoot.wrap" onPress={() => show('wrapped')} tone={mode === 'wrapped' ? 'primary' : 'secondary'} />
        <ActionButton label="AppMetricsErrorBoundary" onPress={() => show('boundary')} tone={mode === 'boundary' ? 'primary' : 'secondary'} />
      </ActionRow>
      {mode === 'root' || mode === 'boundary'
        ? (
            <ActionButton disabled={shouldThrow} label="触发渲染错误" onPress={() => setShouldThrow(true)} />
          )
        : null}
      {mode === 'root'
        ? (
            <AppMetricsRoot errorBoundaryFallback={fallback}>
              <Sample shouldThrow={shouldThrow} />
            </AppMetricsRoot>
          )
        : null}
      {mode === 'wrapped' ? <WrappedSample /> : null}
      {mode === 'boundary'
        ? (
            <AppMetricsErrorBoundary fallback={fallback}>
              <Sample shouldThrow={shouldThrow} />
            </AppMetricsErrorBoundary>
          )
        : null}
    </Panel>
  );
}

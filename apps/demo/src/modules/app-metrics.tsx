/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import AppMetrics, {
  type AppStartupTimes,
  type FrameRateMetrics,
  type LogAttributeValue,
  type LogSeverity,
  type MemoryUsageSnapshot,
  type Session,
} from 'expo-app-metrics';
import { useState } from 'react';
import { Switch } from 'react-native';

import { DataRow, Field, Panel } from '../ui';
import { MetricsRenderDemo } from './app-metrics/render';
import { MetricsRequestDemo } from './app-metrics/requests';
import { SystemApiActions } from './system-api-actions';

const diagnostics = AppMetrics as typeof AppMetrics & {
  getAppStartupTimesAsync?(): Promise<AppStartupTimes>;
  getFrameRateMetricsAsync?(): Promise<FrameRateMetrics>;
  getMemoryUsageSnapshotAsync?(): Promise<MemoryUsageSnapshot>;
  takeMemoryUsageSnapshotAsync?(sessionId?: string): Promise<MemoryUsageSnapshot>;
};
const hasMemoryDiagnostics = diagnostics.getMemoryUsageSnapshotAsync
  || diagnostics.getFrameRateMetricsAsync || diagnostics.takeMemoryUsageSnapshotAsync;

function readAttributes<T>(input: string): Record<string, T> | undefined {
  if (!input.trim()) return undefined;
  const value: unknown = JSON.parse(input);
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('请输入 JSON 对象。');
  }
  return value as Record<string, T>;
}

function MetricsSessionsDemo() {
  const [session, setSession] = useState<Session | null>(null);
  const [timestamp, setTimestamp] = useState('');
  const [category, setCategory] = useState('demo');
  const [name, setName] = useState('sample');
  const [value, setValue] = useState('1.25');
  const [routeName, setRouteName] = useState('');
  const [params, setParams] = useState('{"source":"demo"}');

  return (
    <>
      <Panel title="会话">
        <SystemApiActions
          actions={[
            ['获取主会话', () => {
              const main = AppMetrics.getMainSession();
              setSession(main);
              return main.id;
            }],
            ['获取前台会话', async () => {
              const foreground = await AppMetrics.getForegroundSession();
              setSession(foreground);
              return foreground?.id ?? null;
            }],
            ['读取历史会话', () => AppMetrics.getInactiveSessions()],
          ]}
        />
        <DataRow label="会话 ID" value={session?.id ?? '未选择会话'} />
        <DataRow label="会话类型" value={session?.type ?? '未选择会话'} />
        <DataRow label="开始时间" value={session?.startDate ?? '未选择会话'} />
        <SystemApiActions
          key={session?.id}
          actions={[
            ['查询会话是否活动', () => session?.isActive(), undefined, !session],
            ['读取结束时间', () => session?.getEndDate(), undefined, !session],
            ['读取会话指标', () => session?.getMetrics(), undefined, !session],
            ['读取会话日志', () => session?.getLogs(), undefined, !session],
          ]}
        />
      </Panel>

      <Panel title="记录会话指标">
        <Field label="时间戳（ISO 8601）" onChangeText={setTimestamp} placeholder="留空使用当前时间" value={timestamp} />
        <Field label="指标类别" onChangeText={setCategory} value={category} />
        <Field label="指标名称" onChangeText={setName} value={name} />
        <Field keyboardType="decimal-pad" label="指标值" onChangeText={setValue} value={value} />
        <Field label="路由名称（选填）" onChangeText={setRouteName} value={routeName} />
        <Field label="指标参数（JSON）" multiline onChangeText={setParams} value={params} />
        <SystemApiActions
          actions={[
            ['写入所选会话', () => session?.addMetric({
              timestamp: timestamp || new Date().toISOString(),
              category,
              name,
              value: Number(value),
              ...(routeName ? { routeName } : {}),
              ...(params.trim() ? { params: readAttributes(params) } : {}),
            }), undefined, !session || !category || !name || !value.trim() || !Number.isFinite(Number(value))],
          ]}
        />
      </Panel>
    </>
  );
}

function MetricsStartupDemo() {
  const [routeName, setRouteName] = useState('');
  const [params, setParams] = useState('{"source":"demo"}');
  const [sessionId, setSessionId] = useState('');

  return (
    <>
      <Panel title="启动时间">
        <SystemApiActions
          actions={[
            ['标记首次渲染', () => AppMetrics.markFirstRender(), 'app-metrics-mark-first-render'],
          ]}
        />
        <Field label="路由名称（选填）" onChangeText={setRouteName} value={routeName} />
        <Field label="可交互事件参数（JSON）" multiline onChangeText={setParams} value={params} />
        <SystemApiActions
          actions={[
            ['标记可交互', () => AppMetrics.markInteractive({
              ...(routeName ? { routeName } : {}),
              ...(params.trim() ? { params: readAttributes(params) } : {}),
            }), 'app-metrics-mark-interactive'],
            ...(diagnostics.getAppStartupTimesAsync
              ? [['读取启动耗时（秒）', () => diagnostics.getAppStartupTimesAsync?.()] as const]
              : []),
          ]}
        />
      </Panel>

      {hasMemoryDiagnostics
        ? (
            <Panel title="内存与帧率">
              <SystemApiActions
                actions={[
                  ...(diagnostics.getMemoryUsageSnapshotAsync
                    ? [['读取内存用量（字节）', () => diagnostics.getMemoryUsageSnapshotAsync?.()] as const]
                    : []),
                  ...(diagnostics.getFrameRateMetricsAsync
                    ? [['读取帧率指标', () => diagnostics.getFrameRateMetricsAsync?.()] as const]
                    : []),
                ]}
              />
              {diagnostics.takeMemoryUsageSnapshotAsync
                ? (
                    <>
                      <Field label="会话 ID（选填）" onChangeText={setSessionId} value={sessionId} />
                      <SystemApiActions
                        actions={[
                          ['获取内存快照', () => diagnostics.takeMemoryUsageSnapshotAsync?.(sessionId.trim() || undefined)],
                        ]}
                      />
                    </>
                  )
                : null}
            </Panel>
          )
        : null}
    </>
  );
}

const SEVERITIES: readonly LogSeverity[] = ['trace', 'debug', 'info', 'warn', 'error', 'fatal'];

function MetricsLogsDemo() {
  const [name, setName] = useState('demo.opened');
  const [displayName, setDisplayName] = useState('打开示例');
  const [body, setBody] = useState('');
  const [severity, setSeverity] = useState('info');
  const [attributes, setAttributes] = useState('{"screen":"app-metrics"}');
  const [globalAttributes, setGlobalAttributes] = useState('{"source":"demo"}');

  return (
    <>
      <Panel title="事件日志">
        <Field label="事件名称" onChangeText={setName} value={name} />
        <Field label="显示名称（选填）" onChangeText={setDisplayName} value={displayName} />
        <Field label="日志正文（选填）" multiline onChangeText={setBody} value={body} />
        <Field label="日志级别" onChangeText={setSeverity} placeholder={SEVERITIES.join(' / ')} value={severity} />
        <Field label="日志属性（JSON）" multiline onChangeText={setAttributes} value={attributes} />
        <SystemApiActions
          actions={[
            ['记录事件', () => {
              const level = severity.trim() as LogSeverity;
              if (level && !SEVERITIES.includes(level)) throw new Error('请选择支持的日志级别。');
              AppMetrics.logEvent(name, {
                ...(displayName ? { displayName } : {}),
                ...(body ? { body } : {}),
                ...(level ? { severity: level } : {}),
                ...(attributes.trim() ? { attributes: readAttributes<LogAttributeValue>(attributes) } : {}),
              });
            }, undefined, !name.trim()],
          ]}
        />
      </Panel>

      <Panel title="全局属性">
        <Field label="属性（JSON）" multiline onChangeText={setGlobalAttributes} value={globalAttributes} />
        <SystemApiActions
          actions={[
            ['设置全局属性', () => AppMetrics.setGlobalAttributes(readAttributes<LogAttributeValue>(globalAttributes))],
            ['清除全局属性', () => AppMetrics.setGlobalAttributes(null)],
          ]}
        />
      </Panel>
    </>
  );
}

type ErrorSource = Parameters<typeof AppMetrics.reportError>[0]['source'];

function MetricsErrorsDemo() {
  const [source, setSource] = useState<ErrorSource>('reportedByUser');
  const [type, setType] = useState('Error');
  const [message, setMessage] = useState('示例错误');
  const [stacktrace, setStacktrace] = useState('');
  const [componentStack, setComponentStack] = useState('');
  const [isFatal, setIsFatal] = useState(false);

  return (
    <Panel title="错误记录">
      <Field label="错误类型（选填）" onChangeText={setType} value={type} />
      <Field label="错误消息" onChangeText={setMessage} value={message} />
      <Field label="调用栈（选填）" multiline onChangeText={setStacktrace} value={stacktrace} />
      <Field label="组件栈（选填）" multiline onChangeText={setComponentStack} value={componentStack} />
      <Field
        label="错误来源"
        onChangeText={value => setSource(value as ErrorSource)}
        placeholder="reportedByUser / errorBoundary / global"
        value={source}
      />
      <DataRow label="标记为致命错误" value={<Switch accessibilityLabel="标记为致命错误" onValueChange={setIsFatal} value={isFatal} />} />
      <SystemApiActions
        actions={[
          ['记录错误', () => AppMetrics.reportError({
            source,
            message,
            isFatal,
            ...(type ? { type } : {}),
            ...(stacktrace ? { stacktrace } : {}),
            ...(componentStack ? { componentStack } : {}),
          }), undefined, !message.trim() || !['reportedByUser', 'errorBoundary', 'global'].includes(source)],
          ...(AppMetrics.getAllCrashReports
            ? [['读取崩溃报告', () => AppMetrics.getAllCrashReports?.()] as const]
            : []),
        ]}
      />
    </Panel>
  );
}

export function AppMetricsDemo() {
  return (
    <>
      <MetricsStartupDemo />
      <MetricsSessionsDemo />
      <MetricsLogsDemo />
      <MetricsErrorsDemo />
      <MetricsRenderDemo />
      <MetricsRequestDemo />

      <Panel title="会话存储">
        <SystemApiActions
          actions={[
            ['清空已保存的会话', () => AppMetrics.clearStoredEntries(), 'app-metrics-clear-storage'],
          ]}
        />
      </Panel>
    </>
  );
}

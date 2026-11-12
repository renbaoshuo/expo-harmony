/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  Accelerometer,
  Barometer,
  DeviceMotion,
  DeviceSensor,
  Gyroscope,
  LightSensor,
  Magnetometer,
  MagnetometerUncalibrated,
  Pedometer,
} from 'expo-sensors';
import { useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const SENSORS = [
  { id: 'accelerometer', label: '加速度计', source: Accelerometer },
  { id: 'gyroscope', label: '陀螺仪', source: Gyroscope },
  { id: 'magnetometer', label: '磁力计', source: Magnetometer },
  { id: 'uncalibrated', label: '未校准磁力计', source: MagnetometerUncalibrated },
  { id: 'barometer', label: '气压计', source: Barometer },
  { id: 'light', label: '环境光传感器', source: LightSensor },
  { id: 'motion', label: '设备运动', source: DeviceMotion },
] as const satisfies readonly { id: string; label: string; source: DeviceSensor<unknown> }[];

type Sensor = (typeof SENSORS)[number];
type Subscription = ReturnType<DeviceSensor<unknown>['addListener']>;

function SensorCard({ sensor }: { sensor: Sensor }) {
  const { source } = sensor;
  const action = useAsyncResult();
  const subscription = useRef<Subscription | null>(null);
  const [interval, setInterval] = useState('250');
  const [listening, setListening] = useState(false);
  const [sample, setSample] = useState<unknown>(null);
  const busy = action.state.phase === 'running';

  useEffect(() => () => subscription.current?.remove(), []);

  const listen = () => action.run(() => {
    setSample(null);
    subscription.current = source.addListener(setSample);
    setListening(true);
    return '已开始接收测量数据';
  });

  const remove = (method: 'one' | 'all' | 'legacy') => action.run(() => {
    if (method === 'all') source.removeAllListeners();
    else if (method === 'legacy' && subscription.current) source.removeSubscription(subscription.current);
    else subscription.current?.remove();
    subscription.current = null;
    setListening(false);
    return '已停止接收测量数据';
  });

  return (
    <Panel title={sensor.label}>
      <ActionRow>
        <ActionButton label="检查可用性" disabled={busy} onPress={() => void action.run(async () => json(await source.isAvailableAsync()))} testID="sensors-inspect" />
        <ActionButton label="读取权限" disabled={busy} tone="secondary" onPress={() => void action.run(async () => json(await source.getPermissionsAsync()))} />
        <ActionButton label="申请权限" disabled={busy} tone="secondary" onPress={() => void action.run(async () => json(await source.requestPermissionsAsync()))} />
      </ActionRow>
      <Field label="更新间隔（毫秒）" value={interval} onChangeText={setInterval} keyboardType="number-pad" />
      <ActionButton
        label="设置更新间隔"
        disabled={busy || !interval.trim()}
        onPress={() => void action.run(() => {
          const value = Number(interval);
          if (!Number.isFinite(value) || value <= 0) throw new Error('更新间隔须大于 0 毫秒');
          source.setUpdateInterval(value);
          return json({ interval: value });
        })}
      />
      <ActionRow>
        <ActionButton label="开始监听" disabled={busy || listening} onPress={() => void listen()} testID="sensors-start" />
        <ActionButton label="移除当前监听" tone="secondary" disabled={busy || !listening} onPress={() => void remove('one')} testID="sensors-stop" />
        <ActionButton label="移除所有监听" tone="secondary" disabled={busy || !listening} onPress={() => void remove('all')} />
        <ActionButton label="用 removeSubscription 移除监听" tone="secondary" disabled={busy || !listening} onPress={() => void remove('legacy')} />
        <ActionButton label="查询是否有监听" tone="secondary" disabled={busy} onPress={() => void action.run(() => json(source.hasListeners()))} />
        <ActionButton label="读取监听数量" tone="secondary" disabled={busy} onPress={() => void action.run(() => json(source.getListenerCount()))} />
      </ActionRow>
      {sensor.id === 'motion' ? <DataRow label="标准重力加速度（米/秒²）" value={DeviceMotion.Gravity} /> : null}
      <DataRow label="最近一次测量" value={sample === null ? '暂无数据' : json(sample)} />
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function PedometerCard() {
  const action = useAsyncResult();
  const subscription = useRef<ReturnType<typeof Pedometer.watchStepCount> | null>(null);
  const [listening, setListening] = useState(false);
  const [steps, setSteps] = useState<number>();
  const [start, setStart] = useState(() => new Date(Date.now() - 3600000).toISOString());
  const [end, setEnd] = useState(() => new Date().toISOString());
  const busy = action.state.phase === 'running';

  useEffect(() => () => subscription.current?.remove(), []);

  return (
    <Panel title="计步器">
      <ActionRow>
        <ActionButton label="检查计步器可用性" disabled={busy} onPress={() => void action.run(async () => json(await Pedometer.isAvailableAsync()))} />
        <ActionButton label="读取运动权限" disabled={busy} tone="secondary" onPress={() => void action.run(async () => json(await Pedometer.getPermissionsAsync()))} testID="sensors-permission-read" />
        <ActionButton label="申请运动权限" disabled={busy} onPress={() => void action.run(async () => json(await Pedometer.requestPermissionsAsync()))} testID="sensors-permission-request" />
      </ActionRow>
      <ActionRow>
        <ActionButton
          label="开始计步"
          disabled={busy || listening}
          onPress={() => void action.run(() => {
            subscription.current = Pedometer.watchStepCount(result => setSteps(result.steps));
            setSteps(undefined);
            setListening(true);
            return '已开始计步';
          })}
          testID="sensors-pedometer-start"
        />
        <ActionButton
          label="停止计步"
          disabled={busy || !listening}
          tone="secondary"
          onPress={() => {
            subscription.current?.remove();
            subscription.current = null;
            setListening(false);
          }}
          testID="sensors-pedometer-stop"
        />
      </ActionRow>
      <DataRow label="当前步数" value={steps ?? '暂无数据'} />
      {Platform.OS === 'ios'
        ? (
            <>
              <Field label="开始时间（ISO 8601）" value={start} onChangeText={setStart} />
              <Field label="结束时间（ISO 8601）" value={end} onChangeText={setEnd} />
              <ActionButton label="查询历史步数" disabled={busy} tone="secondary" onPress={() => void action.run(async () => json(await Pedometer.getStepCountAsync(new Date(start), new Date(end))))} testID="sensors-history" />
            </>
          )
        : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

export function SensorsDemo() {
  const [selected, setSelected] = useState<Sensor>(SENSORS[0]);

  return (
    <>
      <Panel title="传感器">
        <ActionRow>
          {SENSORS.map(sensor => (
            <ActionButton key={sensor.id} label={sensor.label} tone={selected === sensor ? 'primary' : 'secondary'} onPress={() => setSelected(sensor)} testID={`sensors-select-${sensor.id}`} />
          ))}
        </ActionRow>
      </Panel>
      <SensorCard key={selected.id} sensor={selected} />
      <PedometerCard />
    </>
  );
}

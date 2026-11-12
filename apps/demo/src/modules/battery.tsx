/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Battery from 'expo-battery';

import { json } from '../format';
import { DataRow, Panel } from '../ui';
import { SystemApiActions, SystemEvent } from './system-api-actions';

export function BatteryDemo() {
  const level = Battery.useBatteryLevel();
  const state = Battery.useBatteryState();
  const lowPowerMode = Battery.useLowPowerMode();
  const powerState = Battery.usePowerState();

  return (
    <>
      <Panel title="电池状态">
        <SystemApiActions
          actions={[
            ['检查电池信息是否可用', Battery.isAvailableAsync],
            ['读取电量', Battery.getBatteryLevelAsync],
            ['读取充电状态', async () => {
              const state = await Battery.getBatteryStateAsync();
              return { state, name: Battery.BatteryState[state] };
            }],
            ['查询低电量模式', Battery.isLowPowerModeEnabledAsync],
            ['查询电池优化', Battery.isBatteryOptimizationEnabledAsync],
            ['读取电源状态', Battery.getPowerStateAsync, 'battery-read-state'],
          ]}
        />
      </Panel>

      <Panel title="实时电源状态">
        <DataRow label="useBatteryLevel" value={String(level)} />
        <DataRow label="useBatteryState" value={Battery.BatteryState[state]} />
        <DataRow label="useLowPowerMode" value={String(lowPowerMode)} />
        <DataRow label="usePowerState" value={json(powerState)} />
      </Panel>

      <Panel title="电池事件">
        <SystemEvent label="电量变化" subscribe={Battery.addBatteryLevelListener} />
        <SystemEvent label="充电状态变化" subscribe={Battery.addBatteryStateListener} />
        <SystemEvent label="低电量模式变化" subscribe={Battery.addLowPowerModeListener} />
      </Panel>
    </>
  );
}

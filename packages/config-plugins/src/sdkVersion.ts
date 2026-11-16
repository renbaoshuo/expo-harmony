/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { HarmonyConfigPluginError } from './errors';

export interface HarmonySdkVersion {
  api: number | string;
  native: string;
}

const Labels = new Map([
  [12, '5.0.0(12)'], [13, '5.0.1(13)'], [14, '5.0.2(14)'], [15, '5.0.3(15)'],
  [16, '5.0.4(16)'], [17, '5.0.5(17)'], [18, '5.1.0(18)'], [19, '5.1.1(19)'],
  [20, '6.0.0(20)'], [21, '6.0.1(21)'], [22, '6.0.2(22)'], [23, '6.1.0(23)'], [24, '6.1.1(24)'],
]);

export function parseHarmonySdkVersion(value: unknown, field = 'SDK version'): HarmonySdkVersion {
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value) || value < 1 || value > 999) {
      throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `${field}: expected a positive API level.`);
    }
    if (value >= 26) return { api: `${value}.0.0`, native: `${value}.0.0` };

    const label = Labels.get(value);
    if (!label) {
      throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `${field}: API ${value} requires an explicit HarmonyOS SDK label.`);
    }

    return { api: value, native: label };
  }
  if (typeof value !== 'string') {
    throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `${field}: expected an API number or HarmonyOS SDK version.`);
  }

  const version = value.trim();
  const dotted = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(version);
  if (dotted && Number(dotted[1]) >= 26
    && dotted.slice(1).every(part => String(Number(part)) === part)) {
    return { api: version, native: version };
  }

  const label = /^\d+\.\d+\.\d+\(([1-9]\d*)\)$/.exec(version);
  if (label && Number(label[1]) < 26) {
    const api = Number(label[1]);
    const native = Labels.get(api);
    if (native !== undefined && native !== version) {
      throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `${field}: API ${api} is labeled ${native}.`);
    }

    return { api, native: version };
  }

  throw new HarmonyConfigPluginError(
    'ERR_HARMONY_CONFIG_INVALID',
    `${field}: expected an SDK label such as "6.1.1(24)", or a dotted API version such as "26.0.0".`
  );
}

export function compareHarmonyApiVersions(left: number | string, right: number | string): number {
  const a = String(left).split('.').map(Number);
  const b = String(right).split('.').map(Number);

  for (let i = 0; i < 3; i++) {
    const delta = (a[i] ?? 0) - (b[i] ?? 0);
    if (delta) return delta;
  }

  return 0;
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { stableHarmonyJson } from '@expo-harmony/config-plugins';

import { HarmonyPrebuildError } from './errors';

function readRecord(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function appendUnique(items, values) {
  return [...new Map([...(items || []), ...values].map(value => [stableHarmonyJson(value), value])).values()];
}

function upsertNamed(items, name, create) {
  const values = Array.isArray(items) ? items : [];
  const index = values.findIndex(item => item?.name === name);
  if (index === -1) return [...values, create({})];
  return values.flatMap((item, current) => {
    if (current === index) return [create(item && typeof item === 'object' ? item : {})];
    return item?.name === name ? [] : [item];
  });
}

function upsertManagedNamed(items, name, previousName, placeholderName, create, field) {
  const values = Array.isArray(items) ? items : [];
  const previous = typeof previousName === 'string' && previousName ? previousName : placeholderName;
  const named = values.filter(item => item?.name === name);
  const stale = values.filter(item => item?.name === previous);

  if (named.length > 1 || stale.length > 1) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_IDENTITY_COLLISION',
      `Harmony ${field} identity is ambiguous because its profile contains duplicate named entries.`,
      { operation: 'reconcile-identity' }
    );
  }
  if (name !== previous && named.length > 0) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_IDENTITY_COLLISION',
      `Cannot rename the managed Harmony ${field} from '${previous}' to '${name}' because '${name}' is already user-owned.`,
      { operation: 'reconcile-identity' }
    );
  }

  const names = new Set([name, previous]);
  const index = values.findIndex(item => names.has(item?.name));
  const existing = index === -1 ? undefined : values[index];
  const next = create(existing && typeof existing === 'object' ? existing : {});

  if (index === -1) return [...values, next];

  return values.map((item, current) => current === index ? next : item);
}

function replaceManagedString(items, value, previousValue, placeholderValue) {
  const previous = typeof previousValue === 'string' && previousValue ? previousValue : placeholderValue;

  return [...new Set(
    (Array.isArray(items) ? items : [])
      .filter(item => item !== value && item !== previous)
      .concat(value)
  )];
}

export {
  appendUnique,
  readRecord,
  replaceManagedString,
  upsertManagedNamed,
  upsertNamed,
};

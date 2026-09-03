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
  const existing = values.find(item => item?.name === name);
  const remaining = values.filter(item => item?.name !== name);

  remaining.push(create(existing && typeof existing === 'object' ? existing : {}));

  return remaining;
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

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
  const previousManagedName = typeof previousName === 'string' && previousName ? previousName : placeholderName;
  const named = values.filter(item => item?.name === name);
  const previous = values.filter(item => item?.name === previousManagedName);

  if (named.length > 1 || previous.length > 1) {
    throw new HarmonyPrebuildError('ERR_HARMONY_IDENTITY_COLLISION', `Harmony ${field} identity is ambiguous because its profile contains duplicate named entries.`, { operation: 'reconcile-identity' });
  }
  if (name !== previousManagedName && named.length > 0) {
    throw new HarmonyPrebuildError('ERR_HARMONY_IDENTITY_COLLISION', `Cannot rename the managed Harmony ${field} from '${previousManagedName}' to '${name}' because '${name}' is already user-owned.`, { operation: 'reconcile-identity' });
  }

  const managedNames = new Set([name, previousManagedName]);
  const existingIndex = values.findIndex(item => managedNames.has(item?.name));
  const existing = existingIndex === -1 ? undefined : values[existingIndex];
  const next = create(existing && typeof existing === 'object' ? existing : {});

  if (existingIndex === -1) return [...values, next];

  return values.map((item, index) => index === existingIndex ? next : item);
}

function replaceManagedString(items, value, previousValue, placeholderValue) {
  const previousManagedValue = typeof previousValue === 'string' && previousValue ? previousValue : placeholderValue;
  return [...new Set(
    (Array.isArray(items) ? items : [])
      .filter(item => item !== value && item !== previousManagedValue)
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

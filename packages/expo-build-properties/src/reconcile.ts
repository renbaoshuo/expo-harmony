/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { isDeepStrictEqual } from 'node:util';

type Json = Record<string, unknown>;

const Scopes = ['product', 'entry', 'release', 'module'] as const;
type BuildPropertiesScope = typeof Scopes[number];

interface Change {
  before?: Json;
  after: Json;
}

type ManagedBuildProperties = Partial<Record<BuildPropertiesScope, Change>>;

type ReconcileBuildProperties = (
  scope: BuildPropertiesScope, current: Json | undefined, desired: Json
) => Json | undefined;

function isRecord(value: unknown): value is Json {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isManagedBuildProperties(value: unknown): value is ManagedBuildProperties {
  return isRecord(value) && Object.entries(value).every(([scope, change]) => (
    (Scopes as readonly string[]).includes(scope) && isRecord(change)
    && (change.before === undefined || isRecord(change.before)) && isRecord(change.after)
  ));
}

function restore(current: Json | undefined, { before, after }: Change): Json | undefined {
  if (current === undefined) return undefined;

  const restored = Object.fromEntries(Object.entries(current).flatMap(([key, value]) => {
    if (!Object.hasOwn(after, key)) return [[key, value]];

    const original = before && Object.hasOwn(before, key) ? before[key] : undefined;
    const written = after[key];
    if (isDeepStrictEqual(value, written)) return original === undefined ? [] : [[key, original]];
    if (!isRecord(value) || !isRecord(written)) return [[key, value]];

    const nested = restore(value, { before: isRecord(original) ? original : undefined, after: written });
    return nested === undefined ? [] : [[key, nested]];
  }));

  // Keep an authored empty container. Drop an empty container created by prebuild.
  return before !== undefined || Object.keys(restored).length > 0 ? restored : undefined;
}

function apply(current: Json | undefined, desired: Json): { value: Json | undefined; change?: Change } {
  const before: [string, unknown][] = [];
  const after: [string, unknown][] = [];
  const updates: [string, unknown][] = [];

  for (const [key, next] of Object.entries(desired)) {
    const existing = current && Object.hasOwn(current, key) ? current[key] : undefined;
    if (next === undefined || isDeepStrictEqual(existing, next)) continue;

    if (isRecord(existing) && isRecord(next)) {
      const nested = apply(existing, next);
      if (!nested.change) continue;
      before.push([key, nested.change.before]);
      after.push([key, nested.change.after]);
      updates.push([key, nested.value]);
    } else {
      if (existing !== undefined) before.push([key, existing]);
      after.push([key, next]);
      updates.push([key, next]);
    }
  }

  if (!updates.length) return { value: current };
  return {
    value: { ...current, ...Object.fromEntries(updates) },
    change: {
      ...(current === undefined ? {} : { before: Object.fromEntries(before) }),
      after: Object.fromEntries(after),
    },
  };
}

function createBuildPropertiesReconciler(
  previous: ManagedBuildProperties | undefined, managed: ManagedBuildProperties
): ReconcileBuildProperties {
  return (scope, current, desired) => {
    const ownership = previous?.[scope];
    const authored = ownership ? restore(current, ownership) : current;
    const { value, change } = apply(authored, desired);
    if (change) managed[scope] = structuredClone(change);
    else delete managed[scope];
    return value;
  };
}

function mergeBuildProperties(current: Json | undefined, desired: Json): Json | undefined {
  return apply(current, desired).value;
}

export { createBuildPropertiesReconciler, isManagedBuildProperties, mergeBuildProperties };
export type { BuildPropertiesScope, ManagedBuildProperties, ReconcileBuildProperties };

import { Want } from '@kit.AbilityKit';
import { ExpoModuleError, ExpoRecordShape, ExpoValueTypes } from '@expo-harmony/expo-modules-core';

const MIN_INT32: number = -2147483648;
const MAX_INT32: number = 2147483647;
// Long.MAX_VALUE rounds to 2^63 when represented as a JavaScript number.
const MIN_INT64: number = -(2 ** 63);
const MAX_INT64: number = 2 ** 63 - 1;

const EXTRA_VALUE = ExpoValueTypes.custom<Object>(
  'Want parameter',
  (value: ESObject): Object => {
    if (typeof value === 'number') {
      // Match Kotlin Double.toLong() for top-level extras only.
      return toInteger(value, MIN_INT64, MAX_INT64);
    }
    return value;
  },
  (value: Object): ESObject => value,
);

export const INTENT_PARAMS = ExpoValueTypes.shapedRecord<Record<string, ESObject>>(
  'IntentLauncherParams',
  new ExpoRecordShape()
    .field('type', ExpoValueTypes.string().nullable().optional())
    .field('category', ExpoValueTypes.string().nullable().optional())
    .field('extra', ExpoValueTypes.record(EXTRA_VALUE).nullable().optional())
    .field('data', ExpoValueTypes.string().nullable().optional())
    .field('flags', ExpoValueTypes.number().nullable().optional())
    .field('packageName', ExpoValueTypes.string().nullable().optional())
    .field('className', ExpoValueTypes.string().nullable().optional()),
  (fields: Record<string, ESObject>): Record<string, ESObject> => fields,
  (fields: Record<string, ESObject>): Record<string, ESObject> => fields,
);

export function createWant(action: string, params: Record<string, ESObject>, bundle: string): Want {
  if (action.length === 0) {
    throw new ExpoModuleError('ERR_INTENT_LAUNCHER_INVALID_ARGUMENT', 'activityAction must be a non-empty string.');
  }

  const ability = params['className'] as string | null | undefined;
  const data = params['data'] as string | null | undefined;
  const type = params['type'] as string | null | undefined;
  const category = params['category'] as string | null | undefined;
  const extra = params['extra'] as Record<string, Object> | null | undefined;
  const flags = params['flags'] as number | null | undefined;

  const want: Want = { action };
  if (ability !== undefined && ability !== null) {
    want.abilityName = ability;
    want.bundleName = (params['packageName'] as string | null | undefined) ?? bundle;
  }
  if (data !== undefined && data !== null) want.uri = data;
  if (type !== undefined && type !== null) want.type = type;
  if (category !== undefined && category !== null) want.entities = [category];
  if (extra !== undefined && extra !== null) want.parameters = extra;
  if (flags !== undefined && flags !== null) {
    want.flags = toInteger(flags, MIN_INT32, MAX_INT32);
  }

  return want;
}

function toInteger(value: number, min: number, max: number): number {
  if (Number.isNaN(value)) return 0;
  return Math.trunc(Math.max(min, Math.min(max, value))) || 0;
}

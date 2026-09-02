import { EXPO_SHARED_OBJECT_MARKER } from '../protocol/Protocol';
import { defineExpoRecordValue } from './ExpoRecord';

const MAX_EVENT_SNAPSHOT_DEPTH = 64;

/** Snapshots queued event values while preserving Core-owned SharedObject markers. */
export function snapshotExpoEventArguments(args: ESObject[]): ESObject[] {
  return args.map(
    (value: ESObject): ESObject => snapshotExpoEventValue(value, 0),
  );
}

function snapshotExpoEventValue(value: ESObject, depth: number): ESObject {
  if (depth > MAX_EVENT_SNAPSHOT_DEPTH) {
    throw new Error('Expo typed event value exceeds the maximum nesting depth.');
  }

  if (value === null || value === undefined) return value;

  const kind = typeof value;
  if (kind === 'string' || kind === 'number' || kind === 'boolean') {
    return value;
  }

  if (value instanceof ArrayBuffer) return value.slice(0) as ESObject;
  if (value instanceof Int8Array) return value.slice() as ESObject;
  if (value instanceof Uint8Array) return value.slice() as ESObject;
  if (value instanceof Uint8ClampedArray) return value.slice() as ESObject;
  if (value instanceof Int16Array) return value.slice() as ESObject;
  if (value instanceof Uint16Array) return value.slice() as ESObject;
  if (value instanceof Int32Array) return value.slice() as ESObject;
  if (value instanceof Uint32Array) return value.slice() as ESObject;
  if (value instanceof Float32Array) return value.slice() as ESObject;
  if (value instanceof Float64Array) return value.slice() as ESObject;
  if (value instanceof BigInt64Array) return value.slice() as ESObject;
  if (value instanceof BigUint64Array) return value.slice() as ESObject;
  if (ArrayBuffer.isView(value)) {
    throw new Error(
      'Expo typed events cannot transport DataView or an unknown ArrayBuffer view.',
    );
  }

  if (Array.isArray(value)) {
    return value.map(
      (item: ESObject): ESObject => snapshotExpoEventValue(item, depth + 1),
    );
  }

  if (kind !== 'object') {
    throw new Error(`Expo typed events cannot transport value type '${kind}'.`);
  }

  // Preserve Core-owned markers and their staging identity.
  if (value[EXPO_SHARED_OBJECT_MARKER] !== undefined) return value;

  const output: Record<string, ESObject> = {};

  Object.keys(value).forEach((key: string): void => {
    defineExpoRecordValue(output, key, snapshotExpoEventValue(value[key], depth + 1));
  });

  return output;
}

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

/// <reference path="./EASClient.d.ts" />

import preferences from '@ohos.data.preferences';
import type common from '@ohos.app.ability.common';
import util from '@ohos.util';
import client from 'libexpo_eas_client.so';

const name = 'expo-eas-client';
const key = 'clientID';
const filename = 'expo-eas-client.id';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Migration = (context: common.ApplicationContext) => string | undefined;

export class EASClientID {
  private static migration?: Migration;
  private readonly path: string;

  constructor(private readonly context: common.ApplicationContext) {
    this.path = `${context.filesDir}/${filename}`;
  }

  static registerMigration(migration: Migration): void {
    EASClientID.migration = migration;
  }

  /** Matches the SDK 57 SplitMix64 finalizer over the UUID's two big-endian halves. */
  static deterministicUniformValue(clientID: string): number {
    if (!uuid.test(clientID)) throw new Error('The EAS client ID must be a valid UUID.');

    const hex = clientID.replace(/-/g, '');
    const high = BigInt('0x' + hex.slice(0, 16));
    const low = BigInt('0x' + hex.slice(16));

    let z = high ^ low;
    // BigInt multiplication does not wrap; truncate each product like UInt64/ULong.
    z = BigInt.asUintN(64, (z ^ (z >> BigInt(30))) * BigInt('0xbf58476d1ce4e5b9'));
    z = BigInt.asUintN(64, (z ^ (z >> BigInt(27))) * BigInt('0x94d049bb133111eb'));
    z = z ^ (z >> BigInt(31));

    // The top 53 bits are exactly representable, and dividing by 2^53 excludes 1.
    return Number(z >> BigInt(11)) / 2 ** 53;
  }

  get clientID(): string {
    const existing = client.clientID(this.path);
    if (existing !== undefined) return existing;

    // Drop cached values that may predate another ExtensionAbility's flush.
    preferences.removePreferencesFromCacheSync(this.context, { name });
    const store = preferences.getPreferencesSync(this.context, { name });

    let candidate: string;
    if (store.hasSync(key)) {
      const value = store.getSync(key, '');

      if (typeof value !== 'string' || !uuid.test(value)) throw new Error('The persisted EAS client ID is invalid.');

      candidate = value;
    } else {
      candidate = EASClientID.migration?.(this.context) ?? util.generateRandomUUID();

      if (!uuid.test(candidate)) throw new Error('The EAS client ID must be a valid UUID.');
    }

    return client.clientID(this.path, candidate);
  }

  get deterministicUniformValue(): number {
    return EASClientID.deterministicUniformValue(this.clientID);
  }
}

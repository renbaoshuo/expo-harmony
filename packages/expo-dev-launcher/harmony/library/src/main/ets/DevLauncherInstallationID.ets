/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import util from '@ohos.util';

const STORE = 'expo.modules.devlauncher.installation';
const KEY = 'installationID';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

let installationID: Promise<string> | undefined;

export function getOrCreateInstallationID(context: common.ApplicationContext): Promise<string> {
  installationID ??= readOrCreateInstallationID(context);
  return installationID;
}

async function readOrCreateInstallationID(context: common.ApplicationContext): Promise<string> {
  let id: string | undefined;

  try {
    const store = preferences.getPreferencesSync(context, { name: STORE });
    const saved = store.getSync(KEY, '');
    if (typeof saved === 'string' && UUID.test(saved)) return saved;

    id = util.generateRandomUUID();
    store.putSync(KEY, id);
    await store.flush();
  } catch (error) {
    console.warn(`Unable to store the Expo Dev Launcher installation ID: ${String(error)}`);
  }

  return id ?? util.generateRandomUUID();
}

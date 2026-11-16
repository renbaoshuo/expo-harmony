/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { getQueryValue, isEASUpdateURL } from './DevLauncherProtocol';

export class RecentApp {
  readonly url: string;
  readonly name: string;
  readonly openedAt: number;
  readonly branchName?: string;
  readonly updateMessage?: string;

  constructor(url: string, name: string, openedAt: number, branchName?: string, updateMessage?: string) {
    this.url = url;
    this.name = name;
    this.openedAt = openedAt;
    this.branchName = branchName;
    this.updateMessage = updateMessage;
  }
}

const STORE = 'expo-dev-launcher';
const RECENT_KEY = 'recent-apps';
const FAILURE_KEY = 'last-runtime-error';
const RECENT_RETENTION_MS = 3 * 24 * 60 * 60 * 1000;

export class RecentApps {
  private readonly store?: preferences.Preferences;

  constructor(context: common.ApplicationContext) {
    try {
      this.store = preferences.getPreferencesSync(context, { name: STORE });
    } catch (error) {
      console.warn(`Unable to open Expo Dev Launcher history: ${String(error)}`);
    }
  }

  all(): RecentApp[] {
    try {
      const raw = this.store?.getSync(RECENT_KEY, '[]');
      if (typeof raw !== 'string') return [];

      let values: ESObject;
      values = JSON.parse(raw);
      if (!Array.isArray(values)) return [];

      const result: RecentApp[] = [];
      for (let index = 0; index < values.length; index++) {
        const item: ESObject = values[index];
        if (item === null || typeof item !== 'object' || Array.isArray(item)) continue;
        const value = item as Record<string, ESObject>;
        if (typeof value.url !== 'string' || typeof value.name !== 'string' || !Number.isSafeInteger(value.openedAt)) continue;
        const branchName = typeof value.branchName === 'string' ? value.branchName : undefined;
        const updateMessage = typeof value.updateMessage === 'string' ? value.updateMessage : undefined;
        result.push(new RecentApp(value.url, value.name, value.openedAt, branchName, updateMessage));
      }

      const threshold = Date.now() - RECENT_RETENTION_MS;

      return result
        .filter((item: RecentApp): boolean => item.openedAt >= threshold)
        .sort((left: RecentApp, right: RecentApp): number => right.openedAt - left.openedAt);
    } catch (_) {
      return [];
    }
  }

  async remember(url: string, name: string, manifest: Record<string, ESObject> | undefined, link: string): Promise<void> {
    if (this.store === undefined) return;

    const recent = this.all();
    let branchName: string | undefined;
    let updateMessage: string | undefined;
    if (isEASUpdateURL(url)) {
      const previous = recent.find((app: RecentApp): boolean => app.url === url);
      const branch: ESObject = manifest?.metadata?.branchName;
      branchName = typeof branch === 'string' ? branch : previous?.branchName;
      updateMessage = getQueryValue(link, 'updateMessage') ?? previous?.updateMessage;
    }

    const next = new RecentApp(url, name || url, Date.now(), branchName, updateMessage);
    const others = recent.filter((item: RecentApp): boolean => item.url !== url);

    this.store.putSync(RECENT_KEY, JSON.stringify([next, ...others]));
    await this.store.flush();
  }

  async clear(): Promise<void> {
    if (this.store === undefined) return;
    this.store.deleteSync(RECENT_KEY);
    await this.store.flush();
  }

  takeFailure(): string | undefined {
    try {
      const raw = this.store?.getSync(FAILURE_KEY, '');
      this.clearFailure();
      if (typeof raw !== 'string' || raw.length === 0) return undefined;
      const value: ESObject = JSON.parse(raw);
      if (typeof value?.message !== 'string' || typeof value?.time !== 'number' || Date.now() - value.time > RECENT_RETENTION_MS) return undefined;
      return value.message;
    } catch (_) {
      return undefined;
    }
  }

  rememberFailure(error: Error): void {
    try {
      this.store?.putSync(FAILURE_KEY, JSON.stringify({ time: Date.now(), message: `${error.message}\n${error.stack ?? ''}`.slice(0, 32768) }));
      this.store?.flush().catch((): void => {});
    } catch (_) {}
  }

  clearFailure(): void {
    try {
      this.store?.deleteSync(FAILURE_KEY);
      this.store?.flush().catch((): void => {});
    } catch (_) {}
  }
}

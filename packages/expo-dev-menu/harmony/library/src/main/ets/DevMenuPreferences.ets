/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common, bundleManager } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { FabPoint } from './DevMenuFabGeometry';

const STORE_NAME: string = 'expo.modules.devmenu.preferences';
const FAST_REFRESH: string = 'hotLoadingEnabled';
const AUTO_LAUNCH_METADATA: string = 'DEV_CLIENT_TRY_TO_LAUNCH_LAST_BUNDLE';
const LEGACY_LAUNCH_MODE_METADATA: string = 'expo.devLauncher.launchMode';
const PREFERENCES_TYPE = ExpoValueTypes.custom<Record<string, ESObject>>(
  'DevMenuPreferences',
  (value: ESObject): Record<string, ESObject> => {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('Preferences must be an object.');
    return value as Record<string, ESObject>;
  },
  (value: Record<string, ESObject>): ESObject => value,
);

export enum DevMenuPreference {
  MotionGesture = 'motionGestureEnabled',
  TouchGesture = 'touchGestureEnabled',
  KeyCommands = 'keyCommandsEnabled',
  ShowsAtLaunch = 'showsAtLaunch',
  OnboardingFinished = 'isOnboardingFinished',
  ShowFab = 'showFloatingActionButton',
  TryToLaunchLastBundle = 'tryToLaunchLastBundle',
}

export class DevMenuPreferences {
  private static readonly sessionValues: Map<string, boolean> = new Map<string, boolean>();
  private static readonly sessionListeners: Set<() => void> = new Set<() => void>();
  private static sessionPosition?: FabPoint;

  private readonly store?: preferences.Preferences;
  private readonly defaults: Map<string, boolean>;
  private readonly listeners: Set<() => void> = new Set<() => void>();
  private readonly onChange = (): void => this.listeners.forEach((listener: () => void): void => listener());

  constructor(context: common.Context) {
    try {
      this.store = preferences.getPreferencesSync(context.getApplicationContext(), { name: STORE_NAME });
    } catch (error) {
      console.warn(`Expo Dev Menu preferences are unavailable; using session defaults: ${String(error)}`);
    }
    const metadata = this.metadata();
    this.defaults = new Map<string, boolean>([
      [DevMenuPreference.MotionGesture, true],
      [DevMenuPreference.TouchGesture, true],
      [DevMenuPreference.KeyCommands, true],
      [DevMenuPreference.ShowsAtLaunch, metadata.get('EXDevMenuShowsAtLaunch') ?? true],
      [DevMenuPreference.OnboardingFinished, metadata.get('EXDevMenuIsOnboardingFinished') ?? false],
      [DevMenuPreference.ShowFab, metadata.get('EXDevMenuShowFloatingActionButton') ?? true],
      [DevMenuPreference.TryToLaunchLastBundle, metadata.get(AUTO_LAUNCH_METADATA) ?? true],
    ]);
    if (this.store === undefined) DevMenuPreferences.sessionListeners.add(this.onChange);
    else this.store.on('change', this.onChange);
  }

  get(key: DevMenuPreference): boolean {
    const fallback = this.defaults.get(key) ?? false;
    const value = this.store?.getSync(key, fallback) ?? DevMenuPreferences.sessionValues.get(key) ?? fallback;
    return typeof value === 'boolean' ? value : fallback;
  }

  async set(key: DevMenuPreference, value: boolean): Promise<void> {
    await this.setBooleans(new Map<string, boolean>([[key, value]]));
  }

  getFastRefreshEnabled(): boolean {
    const value = this.store?.getSync(FAST_REFRESH, true) ?? DevMenuPreferences.sessionValues.get(FAST_REFRESH) ?? true;
    return typeof value === 'boolean' ? value : true;
  }

  async setFastRefreshEnabled(value: boolean): Promise<void> {
    await this.setBooleans(new Map<string, boolean>([[FAST_REFRESH, value]]));
  }

  private async setBooleans(values: Map<string, boolean>): Promise<void> {
    if (values.size === 0) return;

    const store = this.store;
    if (store === undefined) {
      values.forEach((value: boolean, key: string): void => {
        DevMenuPreferences.sessionValues.set(key, value);
      });
      DevMenuPreferences.sessionListeners.forEach((listener: () => void): void => listener());

      throw new Error('Preferences storage is unavailable. This change applies only to the current session.');
    }

    let changed = false;
    values.forEach((value: boolean, key: string): void => {
      if (store.getSync(key, !value) === value) return;
      store.putSync(key, value);
      changed = true;
    });
    // Notify locally before flush; storage events synchronize other runtimes.
    if (changed) this.onChange();
    await store.flush();
  }

  snapshot(): Record<string, boolean> {
    const result: Record<string, boolean> = {};
    this.defaults.forEach((_value: boolean, key: string): void => {
      result[key] = this.get(key as DevMenuPreference);
    });

    return result;
  }

  getFabPosition(): FabPoint | undefined {
    const x = this.store?.getSync('fabPositionX', -1) ?? DevMenuPreferences.sessionPosition?.x;
    const y = this.store?.getSync('fabPositionY', -1) ?? DevMenuPreferences.sessionPosition?.y;
    return typeof x === 'number' && typeof y === 'number' && Number.isFinite(x) && Number.isFinite(y) && x >= 0 && y >= 0
      ? new FabPoint(x, y)
      : undefined;
  }

  async saveFabPosition(position: FabPoint): Promise<void> {
    const store = this.store;
    if (store === undefined) {
      DevMenuPreferences.sessionPosition = position;
      throw new Error('FAB position storage is unavailable; keeping the position for this session.');
    }

    store.putSync('fabPositionX', position.x);
    store.putSync('fabPositionY', position.y);
    await store.flush();
  }

  async setPreferences(values: Record<string, ESObject>): Promise<void> {
    const changes = new Map<string, boolean>();
    for (const key of this.defaults.keys()) {
      if (key !== DevMenuPreference.OnboardingFinished && typeof values[key] === 'boolean') {
        changes.set(key, values[key] as boolean);
      }
    }
    await this.setBooleans(changes);
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return (): void => {
      this.listeners.delete(listener);
    };
  }

  dispose(): void {
    if (this.store === undefined) DevMenuPreferences.sessionListeners.delete(this.onChange);
    else this.store.off('change', this.onChange);
    this.listeners.clear();
  }

  private metadata(): Map<string, boolean> {
    const result = new Map<string, boolean>();
    let legacyAutoLaunch: boolean | undefined;
    try {
      const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION | bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_METADATA;
      const info = bundleManager.getBundleInfoForSelfSync(flags);

      for (const module of info.appInfo.metadataArray ?? []) {
        for (const entry of module.metadata) {
          if (entry.name === LEGACY_LAUNCH_MODE_METADATA) {
            if (entry.value === 'launcher' || entry.value === 'most-recent') legacyAutoLaunch = entry.value === 'most-recent';
          } else if (entry.value === 'true' || entry.value === 'false') {
            result.set(entry.name, entry.value === 'true');
          }
        }
      }
    } catch (error) {
      console.warn(`Unable to read Expo Dev Menu metadata; using SDK defaults: ${String(error)}`);
    }

    // Preserve the launch mode of native projects generated before the boolean metadata was introduced.
    if (!result.has(AUTO_LAUNCH_METADATA) && legacyAutoLaunch !== undefined) result.set(AUTO_LAUNCH_METADATA, legacyAutoLaunch);
    return result;
  }
}

export class DevMenuPreferencesModule extends ExpoModule {
  private preferences?: DevMenuPreferences;

  definition(): ExpoModuleDefinition {
    if (!this.context.isDebug) return new ExpoModuleDefinition().name('DevMenuPreferencesStub');
    return new ExpoModuleDefinition()
      .name('DevMenuPreferences')
      .asyncFunction(
        'getPreferencesAsync',
        ExpoFunction.typed0(async (): Promise<Record<string, boolean>> => this.requirePreferences().snapshot()),
      )
      .asyncFunction(
        'setPreferencesAsync',
        ExpoFunction.typed1(PREFERENCES_TYPE, async (values: Record<string, ESObject>): Promise<void> => {
          await this.requirePreferences().setPreferences(values);
        }),
      )
      .onDestroy((): void => {
        this.preferences?.dispose();
        this.preferences = undefined;
      });
  }

  private requirePreferences(): DevMenuPreferences {
    if (this.preferences === undefined) this.preferences = new DevMenuPreferences(this.context.uiAbilityContext);
    return this.preferences;
  }
}

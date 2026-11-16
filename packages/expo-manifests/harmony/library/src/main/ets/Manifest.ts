/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { JSONObjectUtils, JSONUtilsError } from '@expo-harmony/expo-json-utils';

export class ExpoManifestError extends Error {
  readonly code = 'ERR_MANIFEST_INVALID';

  constructor(message: string) {
    super(message);
    this.name = 'ExpoManifestError';
  }
}

function isRecord(value: unknown): value is Record<string, ESObject> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;

  const prototype = Object.getPrototypeOf(value);

  return prototype === Object.prototype || prototype === null;
}

function ownDataProperty(value: object, key: string | number): PropertyDescriptor | undefined {
  const field = Object.getOwnPropertyDescriptor(value, key);
  if (field !== undefined && !Object.prototype.hasOwnProperty.call(field, 'value')) {
    throw new ExpoManifestError(`Manifest field '${key}' must be a data property.`);
  }

  return field;
}

function clonePluginProperties(value: Record<string, ESObject>): Record<string, ESObject> {
  const ancestors = new Set<object>();

  function clone(item: ESObject): ESObject {
    if (!Array.isArray(item) && !isRecord(item)) return item;
    if (ancestors.has(item)) throw new ExpoManifestError('Plugin properties must not contain circular references.');

    ancestors.add(item);

    try {
      if (Array.isArray(item)) {
        const copy = new Array<ESObject>(item.length);
        for (let index = 0; index < item.length; index++) {
          const field = ownDataProperty(item, index);
          if (field !== undefined) copy[index] = clone(field.value);
        }

        return copy;
      }

      return Object.fromEntries(Object.keys(item).map(key => [key, clone(ownDataProperty(item, key)?.value)]));
    } finally {
      ancestors.delete(item);
    }
  }

  try {
    return clone(value);
  } catch (error) {
    throw new ExpoManifestError(error instanceof ExpoManifestError ? error.message : 'Plugin properties could not be copied.');
  }
}

type FieldType = 'object' | 'array' | 'string' | 'boolean';

function requiredField(value: Record<string, ESObject>, key: string): ESObject {
  try {
    return JSONObjectUtils.require(value, key);
  } catch (error) {
    if (error instanceof JSONUtilsError) throw new ExpoManifestError(error.message);
    throw error;
  }
}

function appearanceField(value: Record<string, ESObject>, key: string): ESObject {
  try {
    return JSONObjectUtils.getNullable(value, key);
  } catch (error) {
    if (error instanceof JSONUtilsError) return null;
    throw error;
  }
}

export abstract class Manifest {
  protected readonly json: Record<string, ESObject>;

  constructor(value: unknown) {
    if (!isRecord(value)) throw new ExpoManifestError('A manifest must be a JSON object.');

    this.json = value;
  }

  static fromManifestJson(value: unknown): Manifest {
    if (!isRecord(value)) throw new ExpoManifestError('A manifest must be a JSON object.');
    if (JSONObjectUtils.hasValue(value, 'releaseId')) throw new ExpoManifestError('Legacy manifests are no longer supported.');

    return JSONObjectUtils.hasValue(value, 'metadata') ? new ExpoUpdatesManifest(value) : new EmbeddedManifest(value);
  }

  getRawJson(): Record<string, ESObject> { return this.json; }
  toString(): string { return JSON.stringify(this.json); }
  getID(): string { return this.string(this.json, 'id'); }
  getLegacyID(): string { return this.getID(); }
  getMetadata(): Record<string, ESObject> | null { return this.value(this.json, 'metadata', 'object'); }
  getAssets(): ESObject[] | null { return this.value(this.json, 'assets', 'array'); }
  isVerified(): boolean { return this.value(this.json, 'isVerified', 'boolean') ?? false; }
  abstract getStableLegacyID(): string | null;
  abstract getScopeKey(): string;
  abstract getEASProjectID(): string | null;
  abstract getBundleURL(): string;
  abstract getExpoGoSDKVersion(): string | null;
  abstract getExpoGoConfigRootObject(): Record<string, ESObject> | null;
  abstract getExpoClientConfigRootObject(): Record<string, ESObject> | null;
  abstract getSlug(): string | null;
  abstract getAppKey(): string | null;

  isDevelopmentMode(): boolean {
    try {
      const config = this.getExpoGoConfigRootObject();
      return config !== null && JSONObjectUtils.hasValue(config, 'developer')
        && (this.value(this.value(config, 'packagerOpts', 'object'), 'dev', 'boolean') ?? false);
    } catch (error) {
      if (error instanceof ExpoManifestError) return false;
      throw error;
    }
  }

  isDevelopmentSilentLaunch(): boolean { return this.value(this.value(this.getExpoGoConfigRootObject(), 'developmentClient', 'object'), 'silentLaunch', 'boolean') ?? false; }
  isUsingDeveloperTool(): boolean {
    const developer = this.value(this.getExpoGoConfigRootObject(), 'developer', 'object');

    return developer !== null && JSONObjectUtils.hasValue(developer, 'tool');
  }
  getRevisionId(): string { return this.string(this.getExpoClientConfigRootObject(), 'revisionId'); }
  getDebuggerHost(): string { return this.string(this.getExpoGoConfigRootObject(), 'debuggerHost'); }
  getMainModuleName(): string {
    const config = this.getExpoGoConfigRootObject();

    return config === null ? 'main' : this.string(config, 'mainModuleName');
  }
  getHostUri(): string | null { return this.value(this.getExpoClientConfigRootObject(), 'hostUri', 'string'); }
  getExpoGoUsername(): string | null { return this.value(this.getExpoGoConfigRootObject(), 'username', 'string'); }
  getName(): string | null { return this.value(this.getExpoClientConfigRootObject(), 'name', 'string'); }
  getVersion(): string | null { return this.value(this.getExpoClientConfigRootObject(), 'version', 'string'); }
  getUpdatesInfo(): Record<string, ESObject> | null { return this.value(this.getExpoClientConfigRootObject(), 'updates', 'object'); }
  getPrimaryColor(): string | null { return this.value(this.getExpoClientConfigRootObject(), 'primaryColor', 'string'); }
  getOrientation(): string | null { return this.value(this.getExpoClientConfigRootObject(), 'orientation', 'string'); }
  getIconUrl(): string | null { return this.value(this.getExpoClientConfigRootObject(), 'iconUrl', 'string'); }
  getFacebookAppId(): string { return this.string(this.getExpoClientConfigRootObject(), 'facebookAppId'); }
  getFacebookApplicationName(): string { return this.string(this.getExpoClientConfigRootObject(), 'facebookDisplayName'); }
  getFacebookAutoInitEnabled(): boolean {
    const value = this.value(this.getExpoClientConfigRootObject(), 'facebookAutoInitEnabled', 'boolean');
    if (value === null) throw new ExpoManifestError("Manifest field 'facebookAutoInitEnabled' must be boolean.");

    return value;
  }
  getPlatformConfig(): Record<string, ESObject> | null { return this.value(this.getExpoClientConfigRootObject(), 'harmony', 'object'); }

  private platformStringOrRoot(key: string): string | null {
    let config: Record<string, ESObject> | null;
    try {
      config = this.getExpoClientConfigRootObject();
    } catch (error) {
      if (error instanceof ExpoManifestError) return null;
      throw error;
    }

    if (config === null) return null;

    const platform = appearanceField(config, 'harmony');
    if (isRecord(platform)) {
      const override = appearanceField(platform, key);
      if (typeof override === 'string') return override;
    }

    const fallback = appearanceField(config, key);

    return typeof fallback === 'string' ? fallback : null;
  }

  getUserInterfaceStyle(): string | null { return this.platformStringOrRoot('userInterfaceStyle'); }
  getBackgroundColor(): string | null { return this.platformStringOrRoot('backgroundColor'); }

  getPluginProperties(name: string): Record<string, ESObject> | null {
    const plugins = this.value(this.getExpoClientConfigRootObject(), 'plugins', 'array');
    if (plugins === null) return null;

    let result: Record<string, ESObject> | null = null;

    for (let index = 0; index < plugins.length; index++) {
      const plugin = ownDataProperty(plugins, index)?.value;

      if (typeof plugin === 'string') continue;
      if (!Array.isArray(plugin) || plugin.length === 0) throw new ExpoManifestError(`Manifest plugins entry ${index} must contain a name or nonempty array.`);

      if (result === null && plugin.length === 2 && ownDataProperty(plugin, 0)?.value === name) {
        const properties = ownDataProperty(plugin, 1)?.value;
        if (isRecord(properties)) result = clonePluginProperties(properties);
      }
    }

    return result;
  }

  protected value(value: Record<string, ESObject> | null, key: string, type: FieldType): ESObject {
    if (value === null || !JSONObjectUtils.hasValue(value, key)) return null;

    const field = requiredField(value, key);
    const valid = type === 'object' ? isRecord(field) : type === 'array' ? Array.isArray(field) : typeof field === type;
    if (!valid) throw new ExpoManifestError(`Manifest field '${key}' must be ${type}.`);

    return field;
  }

  protected string(value: Record<string, ESObject> | null, key: string): string {
    if (value === null) throw new ExpoManifestError(`Manifest object containing '${key}' is missing.`);
    if (!JSONObjectUtils.hasValue(value, key)) throw new ExpoManifestError(`Required manifest field '${key}' is missing.`);

    const field = requiredField(value, key);
    if (typeof field !== 'string') throw new ExpoManifestError(`Manifest field '${key}' must be a string.`);

    return field;
  }
}

export class ExpoUpdatesManifest extends Manifest {
  getStableLegacyID(): null { return null; }
  getScopeKey(): string { return this.string(this.value(this.json, 'extra', 'object'), 'scopeKey'); }
  getEASProjectID(): string | null { return this.value(this.value(this.value(this.json, 'extra', 'object'), 'eas', 'object'), 'projectId', 'string'); }
  getRuntimeVersion(): string { return this.string(this.json, 'runtimeVersion'); }
  getBundleURL(): string { return this.string(this.getLaunchAsset(), 'url'); }
  getExpoGoSDKVersion(): string | null { return this.value(this.getExpoClientConfigRootObject(), 'sdkVersion', 'string'); }
  getCreatedAt(): string { return this.string(this.json, 'createdAt'); }
  getExpoGoConfigRootObject(): Record<string, ESObject> | null { return this.value(this.value(this.json, 'extra', 'object'), 'expoGo', 'object'); }
  getExpoClientConfigRootObject(): Record<string, ESObject> | null { return this.value(this.value(this.json, 'extra', 'object'), 'expoClient', 'object'); }
  getSlug(): null { return null; }
  getAppKey(): null { return null; }

  getLaunchAsset(): Record<string, ESObject> {
    const asset = this.value(this.json, 'launchAsset', 'object');
    if (asset === null) throw new ExpoManifestError('A remote manifest requires a launchAsset.');

    return asset;
  }
}

export class EmbeddedManifest extends Manifest {
  getStableLegacyID(): string { return this.value(this.json, 'originalFullName', 'string') ?? this.getID(); }
  getScopeKey(): string { return this.value(this.json, 'scopeKey', 'string') ?? this.getStableLegacyID(); }
  getEASProjectID(): string | null { return this.value(this.json, 'projectId', 'string'); }
  getBundleURL(): string { return this.string(this.json, 'bundleUrl'); }
  getExpoGoSDKVersion(): string | null { return this.value(this.json, 'sdkVersion', 'string'); }
  getExpoGoConfigRootObject(): Record<string, ESObject> { return this.json; }
  getExpoClientConfigRootObject(): Record<string, ESObject> { return this.json; }
  getSlug(): string | null { return this.value(this.json, 'slug', 'string'); }
  getAppKey(): string | null { return this.value(this.json, 'appKey', 'string'); }

  getCommitTimeLong(): number {
    let time: number;
    try {
      time = Math.trunc(JSONObjectUtils.requireNumber(this.json, 'commitTime'));
    } catch (error) {
      if (error instanceof JSONUtilsError) throw new ExpoManifestError(`Invalid embedded manifest commitTime: ${error.message}.`);
      throw error;
    }

    if (!Number.isSafeInteger(time)) throw new ExpoManifestError('An embedded manifest requires a safely representable integer commitTime.');

    return time;
  }
}

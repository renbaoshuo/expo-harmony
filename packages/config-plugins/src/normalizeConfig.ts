/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type {
  ExpoConfigWithHarmony,
  HarmonyConfig,
  HarmonyDeviceType,
  HarmonyPermission,
  HarmonySkill,
} from './config';
import { HarmonyConfigPluginError } from './errors';
import { toArgb } from './resources';
import { parseHarmonySdkVersion } from './sdkVersion';

type HarmonyExpoConfig = ExpoConfigWithHarmony;

interface NormalizedHarmonyConfig {
  abiFilters: string[];
  abilityName: string;
  backgroundColor: string;
  bundleName: string;
  compatibleSdkVersionString: string;
  deviceTypes: NonNullable<HarmonyConfig['deviceTypes']>;
  icon?: string;
  label: string;
  moduleName: string;
  moduleBuilds?: NonNullable<HarmonyConfig['moduleBuilds']>;
  nativeOrientation: Exclude<NonNullable<HarmonyConfig['orientation']>, 'default'> | 'unspecified';
  permissions: NonNullable<HarmonyConfig['permissions']>;
  productName: string;
  querySchemes: string[];
  signingConfigFile?: string;
  skills: NonNullable<HarmonyConfig['skills']>;
  targetApiVersion: number | string;
  targetSdkVersionString: string;
  vendor: string;
  versionCode: number;
  versionName: string;
}

const BundlePattern = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*){2,}$/;
const IdentifierPattern = /^[A-Za-z][A-Za-z0-9_]*$/;
const DefaultCompatibleApi = 20;
const TargetApi = 24;

class HarmonyConfigError extends HarmonyConfigPluginError {
  constructor(message: string) {
    super('ERR_HARMONY_CONFIG_INVALID', message, { operation: 'normalize-config' });
    this.name = 'HarmonyConfigError';
  }
}

function readString(value: unknown, field: string, fallback?: string): string {
  const result = value === undefined ? fallback : value;

  if (typeof result !== 'string' || !result.trim()) {
    throw new HarmonyConfigError(`${field} must be a non-empty string.`);
  }
  if (/\0|[\r\n]/.test(result)) {
    throw new HarmonyConfigError(`${field} must not contain control characters.`);
  }

  return result.trim();
}

function normalizeColor(value: unknown, field: string, fallback: string): string {
  const color = value === undefined ? fallback : value;
  if (typeof color !== 'string') {
    throw new HarmonyConfigError(`${field} must be a valid React Native color.`);
  }

  try {
    return toArgb(color);
  } catch {
    throw new HarmonyConfigError(`${field} must be a valid React Native color.`);
  }
}

function normalizeStringArray(value: unknown, field: string): string[] {
  if (!Array.isArray(value)) {
    throw new HarmonyConfigError(`${field} must be an array.`);
  }

  const result: string[] = [];
  for (const item of value) {
    if (typeof item !== 'string' || !item) {
      throw new HarmonyConfigError(`Invalid ${field} entry: ${item}`);
    }

    if (!result.includes(item)) result.push(item);
  }

  return result;
}

function normalizePermission(permission: HarmonyPermission): HarmonyPermission {
  if (!permission || typeof permission !== 'object' || Array.isArray(permission)) {
    throw new HarmonyConfigError('harmony.permissions entries must be objects.');
  }

  const { name, reason, usedScene, ...nativeFields } = permission;
  const result: HarmonyPermission = { ...nativeFields, name: readString(name, 'harmony.permissions[].name') };

  if (reason !== undefined) {
    result.reason = readString(reason, 'harmony.permissions[].reason');
  }

  if (usedScene !== undefined) {
    if (!usedScene || typeof usedScene !== 'object' || Array.isArray(usedScene)) {
      throw new HarmonyConfigError('permission.usedScene must be an object.');
    }

    const { abilities, when = 'inuse', ...sceneFields } = usedScene;
    if (!['inuse', 'always'].includes(when)) {
      throw new HarmonyConfigError('permission.usedScene.when must be inuse or always.');
    }

    result.usedScene = { ...sceneFields, when };
    if (abilities !== undefined) {
      result.usedScene.abilities = normalizeStringArray(abilities, 'permission.usedScene.abilities');
    }
  }

  return result;
}

export function mergePermissions(
  current: readonly HarmonyPermission[],
  additions: readonly HarmonyPermission[]
): HarmonyPermission[] {
  if (!Array.isArray(current) || !Array.isArray(additions)) {
    throw new HarmonyConfigError('Harmony permissions must be arrays.');
  }

  const permissions = new Map<string, HarmonyPermission>();
  for (const entry of [...current, ...additions]) {
    const permission = normalizePermission(entry);
    const existing = permissions.get(permission.name);
    const merged = { ...existing, ...permission };
    const previousScene = existing?.usedScene;
    const nextScene = permission.usedScene;
    if (previousScene && nextScene) {
      merged.usedScene = {
        ...previousScene,
        ...nextScene,
        ...(previousScene.abilities || nextScene.abilities
          ? { abilities: [...new Set([...(previousScene.abilities ?? []), ...(nextScene.abilities ?? [])])] }
          : {}),
        when: previousScene.when === 'always' || nextScene.when === 'always' ? 'always' : 'inuse',
      };
    }
    permissions.set(permission.name, merged);
  }

  return [...permissions.values()];
}

function normalizeSkill(skill: HarmonySkill) {
  if (!skill || typeof skill !== 'object') {
    throw new HarmonyConfigError('harmony.skills entries must be objects.');
  }

  const result: {
    actions?: string[];
    entities?: string[];
    uris?: HarmonySkill['uris'];
  } = {};

  for (const field of ['entities', 'actions'] as const) {
    if (skill[field] !== undefined) result[field] = normalizeStringArray(skill[field], `harmony.skills[].${field}`);
  }

  if (skill.uris !== undefined) {
    if (!Array.isArray(skill.uris)) {
      throw new HarmonyConfigError('harmony.skills[].uris must be an array.');
    }

    result.uris = skill.uris.map((uri) => {
      if (!uri || typeof uri !== 'object' || Array.isArray(uri)) {
        throw new HarmonyConfigError('Harmony skill URI must be an object.');
      }

      const result: NonNullable<HarmonySkill['uris']>[number] = {};
      for (const [key, value] of Object.entries(uri)) {
        result[key] = typeof value === 'boolean' || (typeof value === 'number' && Number.isFinite(value))
          ? value
          : readString(value, `harmony.skills[].uris[].${key}`);
      }

      return result;
    });
  }

  if (Object.keys(result).length === 0) {
    throw new HarmonyConfigError('Harmony skill must contain entities, actions, or uris.');
  }

  return result;
}

function readExpoSchemes(config: HarmonyExpoConfig) {
  const values = Array.isArray(config.scheme) ? config.scheme : config.scheme ? [config.scheme] : [];
  return values.map(value => readString(value, 'scheme'));
}

function normalizeHarmonyConfig(config: HarmonyExpoConfig): NormalizedHarmonyConfig {
  const harmony = config.harmony;

  if (!harmony || typeof harmony !== 'object' || Array.isArray(harmony)) {
    throw new HarmonyConfigError('Expo config must contain a harmony object.');
  }

  const bundle = readString(harmony.bundleName, 'harmony.bundleName');
  if (!BundlePattern.test(bundle)) {
    throw new HarmonyConfigError(
      'harmony.bundleName must contain at least three valid dot-separated segments.'
    );
  }

  const module = readString(harmony.moduleName, 'harmony.moduleName', 'entry');
  const ability = readString(harmony.abilityName, 'harmony.abilityName', 'EntryAbility');
  if (!IdentifierPattern.test(module)) {
    throw new HarmonyConfigError('harmony.moduleName must be a valid Harmony identifier.');
  }
  if (!IdentifierPattern.test(ability)) {
    throw new HarmonyConfigError('harmony.abilityName must be a valid Harmony identifier.');
  }

  const version = readString(harmony.versionName, 'harmony.versionName', config.version || '1.0.0');
  const code = harmony.versionCode ?? 1;

  const target = parseHarmonySdkVersion(
    harmony.targetSdkVersion ?? harmony.targetApiVersion ?? TargetApi, 'harmony.targetSdkVersion'
  );

  const compatible = parseHarmonySdkVersion(harmony.compatibleSdkVersion ?? DefaultCompatibleApi, 'harmony.compatibleSdkVersion');
  const orientation = readString(harmony.orientation ?? config.orientation, 'harmony.orientation', 'default');

  const background = normalizeColor(
    harmony.backgroundColor || config.backgroundColor,
    'harmony.backgroundColor',
    '#FFFFFF'
  );

  const engine = harmony.jsEngine || 'hermes';
  if (engine !== 'hermes') {
    throw new HarmonyConfigError('Expo Harmony currently supports only the Hermes JavaScript engine.');
  }

  const abis = harmony.abiFilters === undefined
    ? ['arm64-v8a', 'x86_64']
    : normalizeStringArray(harmony.abiFilters, 'harmony.abiFilters');

  const permissions = mergePermissions(harmony.permissions ?? [], []);

  if (!permissions.some(permission => permission.name === 'ohos.permission.INTERNET')) {
    permissions.unshift({ name: 'ohos.permission.INTERNET' });
  }

  const schemes = readExpoSchemes(config);
  let skills = (harmony.skills || []).map(normalizeSkill);

  for (const scheme of schemes) {
    skills.push({
      actions: ['ohos.want.action.viewData'],
      entities: ['entity.system.browsable'],
      uris: [{ scheme }],
    });
  }

  skills = [...new Map(skills.map(skill => [JSON.stringify(skill), skill])).values()];

  const queries = [...new Set([
    'http',
    'https',
    'tel',
    'sms',
    ...schemes,
    ...(harmony.querySchemes === undefined
      ? []
      : normalizeStringArray(harmony.querySchemes, 'harmony.querySchemes')),
  ])];

  const signing = harmony.signingConfigFile === undefined
    ? undefined
    : readString(harmony.signingConfigFile, 'harmony.signingConfigFile');
  const devices: HarmonyDeviceType[] = harmony.deviceTypes === undefined
    ? ['phone', 'tablet']
    : normalizeStringArray(harmony.deviceTypes, 'harmony.deviceTypes');

  const moduleBuilds = harmony.moduleBuilds;
  if (moduleBuilds !== undefined) {
    if (!moduleBuilds || typeof moduleBuilds !== 'object' || Array.isArray(moduleBuilds)) {
      throw new HarmonyConfigError('harmony.moduleBuilds must be an object.');
    }
    for (const [name, options] of Object.entries(moduleBuilds)) {
      if (!/^(@[a-z0-9._~-]+\/)?[a-z0-9._~-]+$/u.test(name)
        || !options || typeof options !== 'object' || Array.isArray(options)
        || Object.values(options).some(value => !['boolean', 'string', 'number'].includes(typeof value)
          || (typeof value === 'number' && !Number.isFinite(value)))) {
        throw new HarmonyConfigError(`Invalid native module build options for ${name}.`);
      }
    }
  }

  return Object.freeze({
    ...(moduleBuilds && Object.keys(moduleBuilds).length ? { moduleBuilds: structuredClone(moduleBuilds) } : {}),
    abiFilters: abis,
    abilityName: ability,
    backgroundColor: background,
    bundleName: bundle,
    compatibleSdkVersionString: compatible.native,
    deviceTypes: devices,
    icon: harmony.icon || config.icon,
    label: readString(harmony.label, 'harmony.label', config.name),
    moduleName: module,
    nativeOrientation: orientation === 'default' ? 'unspecified' : orientation,
    permissions,
    productName: readString(harmony.productName, 'harmony.productName', 'default'),
    querySchemes: queries,
    signingConfigFile: signing,
    skills,
    targetApiVersion: target.api,
    targetSdkVersionString: target.native,
    vendor: readString(harmony.vendor, 'harmony.vendor', 'expo-harmony'),
    versionCode: code,
    versionName: version,
  });
}

export { normalizeHarmonyConfig };
export type { HarmonyExpoConfig, NormalizedHarmonyConfig };

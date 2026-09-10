import type {
  ExpoConfigWithHarmony,
  HarmonyConfig,
  HarmonyDeviceType,
  HarmonyPermission,
  HarmonySkill,
} from './config';
import { HarmonyConfigPluginError } from './errors';
import { toArgb } from './resources';

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
  nativeOrientation: Exclude<NonNullable<HarmonyConfig['orientation']>, 'default'> | 'unspecified';
  permissions: NonNullable<HarmonyConfig['permissions']>;
  productName: string;
  querySchemes: string[];
  signingConfigFile?: string;
  skills: NonNullable<HarmonyConfig['skills']>;
  targetApiVersion: number;
  targetSdkVersionString: string;
  vendor: string;
  versionCode: number;
  versionName: string;
}

const BundlePattern = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*){2,}$/;
const IdentifierPattern = /^[A-Za-z][A-Za-z0-9_]*$/;
const ColorPattern = /^(#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{8})$/;
const Orientations = new Set([
  'default',
  'portrait',
  'landscape',
  'portrait_inverted',
  'landscape_inverted',
  'auto_rotation',
]);
const DeviceTypes = new Set<HarmonyDeviceType>(['phone', 'tablet', '2in1']);
const MinimumApi = 13;
const TargetApi = 24;
const SdkVersions = new Map([
  [13, '5.0.1(13)'],
  [14, '5.0.2(14)'],
  [20, '6.0.0(20)'],
  [21, '6.0.1(21)'],
  [23, '6.1.0(23)'],
  [24, '6.1.1(24)'],
]);

class HarmonyConfigError extends HarmonyConfigPluginError {
  constructor(message: string) {
    super('ERR_HARMONY_CONFIG_INVALID', message, { operation: 'normalize-config' });
    this.name = 'HarmonyConfigError';
  }
}

function readPositiveInteger(value: unknown, field: string, fallback: number): number {
  const result = value === undefined ? fallback : value;

  if (typeof result !== 'number' || !Number.isSafeInteger(result) || result <= 0) {
    throw new HarmonyConfigError(`harmony.${field} must be a positive integer.`);
  }

  return result as number;
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

  if (typeof color !== 'string' || !ColorPattern.test(color)) {
    throw new HarmonyConfigError(`${field} must be #RRGGBB or #RRGGBBAA.`);
  }

  return toArgb(color);
}

function parseSdkApi(value: unknown, field: string): number | null {
  if (value === undefined) return null;
  if (typeof value === 'number' && Number.isSafeInteger(value) && value > 0) return value;
  if (typeof value !== 'string') {
    throw new HarmonyConfigError(`harmony.${field} must be a positive API number or an SDK label.`);
  }

  const match = /\((\d+)\)$/u.exec(value.trim());
  const api = Number(match?.[1]);

  if (!match || !Number.isSafeInteger(api) || api <= 0) {
    throw new HarmonyConfigError(
      `harmony.${field} must end with its API level in parentheses, for example "6.0.0(20)".`
    );
  }

  return api;
}

function resolveSdkVersion(api: number, field: string, value?: unknown): string {
  if (value !== undefined) {
    if (typeof value === 'number' && Number.isSafeInteger(value) && value > 0) {
      if (value !== api) {
        throw new HarmonyConfigError(
          `harmony.${field} is API ${value}, but the configured API level is ${api}.`
        );
      }
    } else {
      const version = readString(value, `harmony.${field}`);
      const parsed = parseSdkApi(version, field);

      if (parsed !== api) {
        throw new HarmonyConfigError(
          `harmony.${field} describes API ${parsed}, but the configured API level is ${api}.`
        );
      }

      return version;
    }
  }

  const version = SdkVersions.get(api);

  if (!version) {
    throw new HarmonyConfigError(
      `Harmony API ${api} has no built-in SDK label. Set harmony.${field} explicitly so new SDK releases do not require a package update.`
    );
  }

  return version;
}

function normalizeStringArray<T extends string = string>(
  value: unknown,
  field: string,
  allowed?: ReadonlySet<T>
): T[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new HarmonyConfigError(`${field} must be a non-empty array.`);
  }

  const result: T[] = [];
  for (const item of value) {
    if (typeof item !== 'string' || !item || (allowed && !allowed.has(item as T))) {
      throw new HarmonyConfigError(`Invalid ${field} entry: ${item}`);
    }

    if (!result.includes(item as T)) result.push(item as T);
  }

  return result;
}

export function normalizePermission(permission: HarmonyPermission) {
  if (!permission || typeof permission !== 'object') {
    throw new HarmonyConfigError('harmony.permissions entries must be objects.');
  }

  const name = readString(permission.name, 'harmony.permissions[].name');

  if (!/^ohos\.permission\.[A-Z0-9_]+$/.test(name)) {
    throw new HarmonyConfigError(`Invalid Harmony permission: ${name}`);
  }

  const result: {
    name: string;
    reason?: string;
    usedScene?: { abilities?: string[]; when: 'always' | 'inuse' };
  } = { name };

  if (permission.reason !== undefined) {
    result.reason = readString(permission.reason, 'harmony.permissions[].reason');
  }

  if (permission.usedScene !== undefined) {
    if (!permission.usedScene || typeof permission.usedScene !== 'object') {
      throw new HarmonyConfigError('permission.usedScene must be an object.');
    }

    const when: 'always' | 'inuse' = permission.usedScene.when === undefined
      ? 'inuse'
      : permission.usedScene.when;
    if (!['inuse', 'always'].includes(when)) {
      throw new HarmonyConfigError('permission.usedScene.when must be inuse or always.');
    }

    const abilities = permission.usedScene.abilities === undefined
      ? undefined
      : normalizeStringArray(permission.usedScene.abilities, 'permission.usedScene.abilities');

    result.usedScene = { ...(abilities ? { abilities } : {}), when };
  }

  return result;
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
  const code = readPositiveInteger(harmony.versionCode, 'versionCode', 1);

  const target = readPositiveInteger(
    harmony.targetApiVersion,
    'targetApiVersion',
    parseSdkApi(harmony.targetSdkVersion, 'targetSdkVersion') ?? TargetApi
  );
  const compatible = readPositiveInteger(
    parseSdkApi(harmony.compatibleSdkVersion, 'compatibleSdkVersion') ?? undefined,
    'compatibleSdkVersion',
    MinimumApi
  );

  if (compatible < MinimumApi) {
    throw new HarmonyConfigError(
      `Harmony compatible API must be ${MinimumApi} or newer.`
    );
  }
  if (compatible > target) {
    throw new HarmonyConfigError('Harmony compatibleSdkVersion cannot exceed targetApiVersion.');
  }

  const orientation = harmony.orientation || config.orientation || 'default';
  if (!Orientations.has(orientation)) {
    throw new HarmonyConfigError(`Unsupported Harmony orientation: ${orientation}`);
  }

  const style = harmony.userInterfaceStyle || config.userInterfaceStyle || 'light';
  if (!['light', 'dark', 'automatic'].includes(style)) {
    throw new HarmonyConfigError(`Unsupported Harmony UI style: ${style}`);
  }

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

  for (const abi of abis) {
    if (!/^[A-Za-z0-9_-]+$/.test(abi)) {
      throw new HarmonyConfigError(`Invalid Harmony ABI filter: ${abi}`);
    }
  }

  const permissions = (harmony.permissions || []).map(normalizePermission);

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
    : normalizeStringArray<HarmonyDeviceType>(
        harmony.deviceTypes,
        'harmony.deviceTypes',
        DeviceTypes
      );

  return Object.freeze({
    abiFilters: abis,
    abilityName: ability,
    backgroundColor: background,
    bundleName: bundle,
    compatibleSdkVersionString: resolveSdkVersion(
      compatible,
      'compatibleSdkVersion',
      harmony.compatibleSdkVersion
    ),
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
    targetApiVersion: target,
    targetSdkVersionString: resolveSdkVersion(
      target,
      'targetSdkVersion',
      harmony.targetSdkVersion
    ),
    vendor: readString(harmony.vendor, 'harmony.vendor', 'expo-harmony'),
    versionCode: code,
    versionName: version,
  });
}

export { normalizeHarmonyConfig };
export type { HarmonyExpoConfig, NormalizedHarmonyConfig };

import type {
  ExpoConfigWithHarmony,
  HarmonyConfig,
  HarmonyDeviceType,
  HarmonyPermission,
  HarmonySkill,
} from './config';
import { HarmonyConfigPluginError } from './errors';

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

const BundleNamePattern = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*){2,}$/;
const IdentifierPattern = /^[A-Za-z][A-Za-z0-9_]*$/;
const ColorPattern = /^(#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{8})$/;
const ValidOrientations = new Set([
  'default',
  'portrait',
  'landscape',
  'portrait_inverted',
  'landscape_inverted',
  'auto_rotation',
]);
const ValidDeviceTypes = new Set<HarmonyDeviceType>(['phone', 'tablet', '2in1']);
const SupportedMinimumHarmonyApi = 13;
const DefaultHarmonyCompatibleApi = 23;
const DefaultHarmonyTargetApi = 24;
const HarmonySdkVersions = new Map([
  [13, '5.0.1(13)'],
  [20, '6.0.0(20)'],
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
  const selected = value === undefined ? fallback : value;
  if (typeof selected !== 'number' || !Number.isSafeInteger(selected) || selected <= 0) {
    throw new HarmonyConfigError(`harmony.${field} must be a positive integer.`);
  }
  return selected as number;
}

function readString(value: unknown, field: string, fallback?: string): string {
  const selected = value === undefined ? fallback : value;
  if (typeof selected !== 'string' || !selected.trim()) {
    throw new HarmonyConfigError(`${field} must be a non-empty string.`);
  }
  if (/\0|[\r\n]/.test(selected)) {
    throw new HarmonyConfigError(`${field} must not contain control characters.`);
  }
  return selected.trim();
}

function normalizeColor(value: unknown, field: string, fallback: string): string {
  const selected = value === undefined ? fallback : value;
  if (typeof selected !== 'string' || !ColorPattern.test(selected)) {
    throw new HarmonyConfigError(`${field} must be #RRGGBB or #RRGGBBAA.`);
  }
  const normalized = selected.toUpperCase();
  return normalized.length === 9
    ? `#${normalized.slice(7, 9)}${normalized.slice(1, 7)}`
    : normalized;
}

function parseSdkApi(value: unknown, field: string): number | null {
  if (value === undefined) return null;
  if (typeof value === 'number' && Number.isSafeInteger(value) && value > 0) return value;
  if (typeof value !== 'string') {
    throw new HarmonyConfigError(`harmony.${field} must be a positive API number or an SDK label.`);
  }
  const match = /\((\d+)\)$/u.exec(value.trim());
  if (!match || !Number.isSafeInteger(Number(match[1])) || Number(match[1]) <= 0) {
    throw new HarmonyConfigError(
      `harmony.${field} must end with its API level in parentheses, for example "6.0.0(20)".`
    );
  }
  return Number(match[1]);
}

function resolveSdkVersion(value: number, field: string, explicit?: unknown): string {
  if (explicit !== undefined) {
    if (typeof explicit === 'number' && Number.isSafeInteger(explicit) && explicit > 0) {
      if (explicit !== value) {
        throw new HarmonyConfigError(
          `harmony.${field} is API ${explicit}, but the configured API level is ${value}.`
        );
      }
    } else {
      const version = readString(explicit, `harmony.${field}`);
      const api = parseSdkApi(version, field);
      if (api !== value) {
        throw new HarmonyConfigError(
          `harmony.${field} describes API ${api}, but the configured API level is ${value}.`
        );
      }
      return version;
    }
  }
  const version = HarmonySdkVersions.get(value);
  if (!version) {
    throw new HarmonyConfigError(
      `Harmony API ${value} has no built-in SDK label. Set harmony.${field} explicitly so new SDK releases do not require a package update.`
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
  const output: T[] = [];
  for (const item of value) {
    if (typeof item !== 'string' || !item || (allowed && !allowed.has(item as T))) {
      throw new HarmonyConfigError(`Invalid ${field} entry: ${item}`);
    }
    if (!output.includes(item as T)) output.push(item as T);
  }
  return output;
}

function normalizePermission(permission: HarmonyPermission) {
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
    uris?: Array<Record<string, string>>;
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
      const normalized: Record<string, string> = {};
      for (const [key, value] of Object.entries(uri)) {
        normalized[key] = readString(value, `harmony.skills[].uris[].${key}`);
      }
      return normalized;
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
  const input = config.harmony;
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new HarmonyConfigError('Expo config must contain a harmony object.');
  }
  const bundleName = readString(input.bundleName, 'harmony.bundleName');
  if (!BundleNamePattern.test(bundleName)) {
    throw new HarmonyConfigError(
      'harmony.bundleName must contain at least three valid dot-separated segments.'
    );
  }
  const moduleName = readString(input.moduleName, 'harmony.moduleName', 'entry');
  const abilityName = readString(input.abilityName, 'harmony.abilityName', 'EntryAbility');
  if (!IdentifierPattern.test(moduleName)) {
    throw new HarmonyConfigError('harmony.moduleName must be a valid Harmony identifier.');
  }
  if (!IdentifierPattern.test(abilityName)) {
    throw new HarmonyConfigError('harmony.abilityName must be a valid Harmony identifier.');
  }
  const versionName = readString(input.versionName, 'harmony.versionName', config.version || '1.0.0');
  const versionCode = readPositiveInteger(input.versionCode, 'versionCode', 1);
  const targetSdkApi = parseSdkApi(input.targetSdkVersion, 'targetSdkVersion');
  const targetApiVersion = readPositiveInteger(
    input.targetApiVersion,
    'targetApiVersion',
    targetSdkApi ?? DefaultHarmonyTargetApi
  );
  const compatibleSdkApi = parseSdkApi(input.compatibleSdkVersion, 'compatibleSdkVersion');
  const compatibleSdkVersion = readPositiveInteger(
    compatibleSdkApi ?? undefined,
    'compatibleSdkVersion',
    DefaultHarmonyCompatibleApi
  );
  const legacy = input as typeof input & {
    minApiVersion?: unknown;
    roundIcon?: unknown;
  };
  if (legacy.minApiVersion !== undefined) {
    throw new HarmonyConfigError(
      'harmony.minApiVersion is redundant; use harmony.compatibleSdkVersion.'
    );
  }
  if (compatibleSdkVersion < SupportedMinimumHarmonyApi) {
    throw new HarmonyConfigError(
      `Harmony compatible API must be ${SupportedMinimumHarmonyApi} or newer.`
    );
  }
  if (compatibleSdkVersion > targetApiVersion) {
    throw new HarmonyConfigError('Harmony compatibleSdkVersion cannot exceed targetApiVersion.');
  }
  const orientation = input.orientation || config.orientation || 'default';
  if (!ValidOrientations.has(orientation)) {
    throw new HarmonyConfigError(`Unsupported Harmony orientation: ${orientation}`);
  }
  const userInterfaceStyle = input.userInterfaceStyle || config.userInterfaceStyle || 'light';
  if (!['light', 'dark', 'automatic'].includes(userInterfaceStyle)) {
    throw new HarmonyConfigError(`Unsupported Harmony UI style: ${userInterfaceStyle}`);
  }
  const backgroundColor = normalizeColor(
    input.backgroundColor || config.backgroundColor,
    'harmony.backgroundColor',
    '#FFFFFF'
  );
  const jsEngine = input.jsEngine || 'hermes';
  if (jsEngine !== 'hermes') {
    throw new HarmonyConfigError('Expo Harmony currently supports only the Hermes JavaScript engine.');
  }
  const abiFilters = input.abiFilters === undefined
    ? ['arm64-v8a', 'x86_64']
    : normalizeStringArray(input.abiFilters, 'harmony.abiFilters');
  for (const abi of abiFilters) {
    if (!/^[A-Za-z0-9_-]+$/.test(abi)) {
      throw new HarmonyConfigError(`Invalid Harmony ABI filter: ${abi}`);
    }
  }
  const permissions = (input.permissions || []).map(normalizePermission);
  if (!permissions.some(permission => permission.name === 'ohos.permission.INTERNET')) {
    permissions.unshift({ name: 'ohos.permission.INTERNET' });
  }
  const schemes = readExpoSchemes(config);
  const skills = (input.skills || []).map(normalizeSkill);
  for (const scheme of schemes) {
    skills.push({
      actions: ['ohos.want.action.viewData'],
      entities: ['entity.system.browsable'],
      uris: [{ scheme }],
    });
  }
  const dedupedSkills = [...new Map(skills.map(skill => [JSON.stringify(skill), skill])).values()];
  const querySchemes = [...new Set([
    'http',
    'https',
    'tel',
    'sms',
    ...schemes,
    ...(input.querySchemes === undefined
      ? []
      : normalizeStringArray(input.querySchemes, 'harmony.querySchemes')),
  ])];
  if (legacy.roundIcon !== undefined) {
    throw new HarmonyConfigError(
      'HarmonyOS has no separate round icon manifest field; use harmony.icon instead.'
    );
  }
  const signingConfigFile = input.signingConfigFile === undefined
    ? undefined
    : readString(input.signingConfigFile, 'harmony.signingConfigFile');
  const deviceTypes: HarmonyDeviceType[] = input.deviceTypes === undefined
    ? ['phone', 'tablet']
    : normalizeStringArray<HarmonyDeviceType>(
        input.deviceTypes,
        'harmony.deviceTypes',
        ValidDeviceTypes
      );

  return Object.freeze({
    abiFilters,
    abilityName,
    backgroundColor,
    bundleName,
    compatibleSdkVersionString: resolveSdkVersion(
      compatibleSdkVersion,
      'compatibleSdkVersion',
      input.compatibleSdkVersion
    ),
    deviceTypes,
    icon: input.icon || config.icon,
    label: readString(input.label, 'harmony.label', config.name),
    moduleName,
    nativeOrientation: orientation === 'default' ? 'unspecified' : orientation,
    permissions,
    productName: readString(input.productName, 'harmony.productName', 'default'),
    querySchemes,
    signingConfigFile,
    skills: dedupedSkills,
    targetApiVersion,
    targetSdkVersionString: resolveSdkVersion(
      targetApiVersion,
      'targetSdkVersion',
      input.targetSdkVersion
    ),
    vendor: readString(input.vendor, 'harmony.vendor', 'expo-harmony'),
    versionCode,
    versionName,
  });
}

export { HarmonySdkVersions, normalizeHarmonyConfig };
export type { HarmonyExpoConfig, NormalizedHarmonyConfig };

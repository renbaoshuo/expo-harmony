import type { ExpoConfig } from '@expo/config-types';

export interface HarmonyConfigPluginOwnership {
  readonly owner: string;
  readonly ability?: Readonly<Partial<{
    startWindowBackground: string;
    startWindowIcon: string;
  }>>;
  readonly resources?: Readonly<Partial<{
    colors: Readonly<Partial<Record<'entry' | 'entryDark', readonly string[]>>>;
    media: Readonly<Partial<Record<'app' | 'entry' | 'entryDark', readonly string[]>>>;
    strings: Readonly<Partial<Record<'app' | 'entry', readonly string[]>>>;
  }>>;
}

const ResourceScopes = {
  colors: new Set(['entry', 'entryDark']),
  media: new Set(['app', 'entry', 'entryDark']),
  strings: new Set(['app', 'entry']),
} as const;
const AbilityFields = new Set(['startWindowBackground', 'startWindowIcon']);
const ResourceName = /^[A-Za-z0-9_.-]+$/u;

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function normalizeStringList(value: unknown, field: string): string[] {
  if (!Array.isArray(value)) {
    throw new TypeError(`Invalid Harmony config-plugin ownership: ${field} must be an array.`);
  }

  const result: string[] = [];
  for (const item of value) {
    if (typeof item !== 'string' || !item || !ResourceName.test(item) || item.includes('..')) {
      throw new TypeError(`Invalid Harmony config-plugin ownership: ${field} contains an invalid resource name.`);
    }
    if (!result.includes(item)) result.push(item);
  }

  return result.sort((left, right) => left.localeCompare(right, 'en'));
}

function normalizeResources(value: unknown): NonNullable<HarmonyConfigPluginOwnership['resources']> {
  if (value === undefined) return {};
  if (!isRecord(value)) {
    throw new TypeError('Invalid Harmony config-plugin ownership: resources must be an object.');
  }

  const resources: Record<string, Record<string, string[]>> = {};
  for (const kind of Object.keys(value).sort()) {
    if (!Object.hasOwn(ResourceScopes, kind)) {
      throw new TypeError(`Invalid Harmony config-plugin ownership: resources.${kind} is not supported.`);
    }

    const scopes = value[kind];
    if (!isRecord(scopes)) {
      throw new TypeError(`Invalid Harmony config-plugin ownership: resources.${kind} must be an object.`);
    }

    const allowed = ResourceScopes[kind as keyof typeof ResourceScopes];
    resources[kind] = {};
    for (const scope of Object.keys(scopes).sort()) {
      if (!allowed.has(scope)) {
        throw new TypeError(`Invalid Harmony config-plugin ownership: resources.${kind}.${scope} is not a supported scope.`);
      }
      resources[kind][scope] = normalizeStringList(scopes[scope], `resources.${kind}.${scope}`);
    }
  }

  return resources as NonNullable<HarmonyConfigPluginOwnership['resources']>;
}

function normalizeAbility(value: unknown): NonNullable<HarmonyConfigPluginOwnership['ability']> {
  if (value === undefined) return {};
  if (!isRecord(value)) {
    throw new TypeError('Invalid Harmony config-plugin ownership: ability must be an object.');
  }

  const ability: Record<string, string> = {};
  for (const field of Object.keys(value).sort()) {
    if (!AbilityFields.has(field)) {
      throw new TypeError(`Invalid Harmony config-plugin ownership: ability.${field} is not supported.`);
    }
    if (typeof value[field] !== 'string' || !value[field]) {
      throw new TypeError(`Invalid Harmony config-plugin ownership: ability.${field} must be a non-empty string.`);
    }
    ability[field] = value[field];
  }

  return ability;
}

export function normalizeHarmonyConfigPlugins(value: unknown): readonly HarmonyConfigPluginOwnership[] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) {
    throw new TypeError('Invalid Harmony config-plugin ownership: the plugin list must be an array.');
  }

  const owners = new Set<string>();
  const result = value.map((descriptor: unknown, index) => {
    if (!isRecord(descriptor)) {
      throw new TypeError(`Invalid Harmony config-plugin ownership: plugin ${index} must be an object.`);
    }
    if (typeof descriptor.owner !== 'string' || !descriptor.owner.trim()) {
      throw new TypeError(`Invalid Harmony config-plugin ownership: plugin ${index}.owner must be a non-empty string.`);
    }
    if (owners.has(descriptor.owner)) {
      throw new TypeError(`Invalid Harmony config-plugin ownership: owner ${descriptor.owner} is duplicated.`);
    }
    owners.add(descriptor.owner);

    return {
      ability: normalizeAbility(descriptor.ability),
      owner: descriptor.owner,
      resources: normalizeResources(descriptor.resources),
    };
  });

  return result.sort((left, right) => left.owner.localeCompare(right.owner, 'en'));
}

export function registerHarmonyConfigPlugin(
  config: ExpoConfig,
  owner: string,
  claims: Omit<HarmonyConfigPluginOwnership, 'owner'> = {}
): ExpoConfig {
  const descriptor = normalizeHarmonyConfigPlugins([{ ...claims, owner }])[0];
  config._internal ??= {};
  const current = normalizeHarmonyConfigPlugins(config._internal.harmonyConfigPlugins);
  config._internal.harmonyConfigPlugins = normalizeHarmonyConfigPlugins([
    ...current.filter(item => item.owner !== owner),
    descriptor,
  ]);

  return config;
}

export function getHarmonyConfigPlugins(config: ExpoConfig): readonly HarmonyConfigPluginOwnership[] {
  return normalizeHarmonyConfigPlugins(config?._internal?.harmonyConfigPlugins);
}

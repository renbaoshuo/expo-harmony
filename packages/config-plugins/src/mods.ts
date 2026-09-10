import fs from 'node:fs';
import path from 'node:path';

import {
  withBaseMod, withMod,
  type ExportedConfig, type ModPlatform,
} from '@expo/config-plugins';
import type { ExpoConfig } from '@expo/config-types';

import { HarmonyConfigPluginError } from './errors';
import type { ExpoConfigWithHarmony } from './config';
import type { HarmonyModuleJson } from './manifest';
import type { HarmonyConfigPlugin, HarmonyModAction, HarmonyModConfig } from './pluginTypes';
import type { HarmonyResourceFile } from './resources';
import { atomicWrite, readJson5, readText, writeJson5 } from './files';
import {
  ManagedPaths, ProjectPaths, ResourcePaths,
  resolveHarmonyPath, resolveProjectPath, toPosixRelative,
} from './paths';

export type HarmonyModName
  = | 'dangerous'
    | 'reactNativeConfig'
    | 'appJson'
    | 'projectBuildProfile'
    | 'rootOhPackage'
    | 'rootHvigor'
    | 'hvigorConfig'
    | 'entryBuildProfile'
    | 'entryOhPackage'
    | 'entryHvigor'
    | 'moduleJson'
    | 'strings'
    | 'colors'
    | 'media'
    | 'profiles'
    | 'entryAbility'
    | 'indexPage'
    | 'worker'
    | 'arktsPackageProvider'
    | 'cppPackageProvider'
    | 'cmakeLists'
    | 'autolinking';

type InternalModName = 'nativeInputsStamp' | 'manifest' | 'prepare' | 'patch';
type AnyModName = HarmonyModName | InternalModName;

export type HarmonyJson = Record<string, unknown>;
export type HarmonyResourceMap = Record<string, HarmonyResourceFile>;
export type HarmonyMediaDescriptor
  = | {
    source: string;
    content?: never;
    replaceBase?: boolean;
  }
  | {
    source?: never;
    content: string | Uint8Array;
    replaceBase?: boolean;
  };
export type HarmonyMediaMap = Record<string, Record<string, HarmonyMediaDescriptor>>;

type FileModName = keyof typeof ManagedPaths | keyof typeof ProjectPaths;
type ResourceModName = keyof typeof ResourcePaths;
type FileResult = HarmonyJson | string;
type ResourceResult = HarmonyResourceMap | HarmonyMediaMap;
type ModEntry = {
  isProvider?: boolean;
  expoHarmonyLateActions?: HarmonyModAction[];
};
type ModTable = Record<string, Record<string, ModEntry> | undefined>;

interface ManagedConfig {
  _internal?: ExpoConfig['_internal'];
  modRequest: { projectRoot: string };
}

interface MediaWrite {
  content: string | Uint8Array;
  directory: string;
  name: string;
  replaceBase: boolean;
}

const JsonMods = new Set<FileModName>([
  'appJson',
  'projectBuildProfile',
  'rootOhPackage',
  'hvigorConfig',
  'entryBuildProfile',
  'entryOhPackage',
  'moduleJson',
  'profiles',
]);
const TextMods = new Set<FileModName>([
  'reactNativeConfig',
  'rootHvigor',
  'nativeInputsStamp',
  'entryHvigor',
  'entryAbility',
  'indexPage',
  'worker',
  'arktsPackageProvider',
  'cppPackageProvider',
  'cmakeLists',
]);
const ResourceMods = new Set<HarmonyModName>(['strings', 'colors', 'media']);
const VirtualMods = new Set<AnyModName>(['dangerous', 'autolinking', 'manifest', 'prepare', 'patch']);
const ResourceModNames: readonly ResourceModName[] = ['strings', 'colors', 'media'];

const AllModNames: readonly AnyModName[] = Object.freeze([
  'dangerous',
  'prepare',
  'reactNativeConfig',
  'appJson',
  'projectBuildProfile',
  'rootOhPackage',
  'rootHvigor',
  'nativeInputsStamp',
  'hvigorConfig',
  'entryBuildProfile',
  'entryOhPackage',
  'entryHvigor',
  'moduleJson',
  'strings',
  'colors',
  'media',
  'profiles',
  'entryAbility',
  'indexPage',
  'worker',
  'arktsPackageProvider',
  'cppPackageProvider',
  'cmakeLists',
  'autolinking',
  'patch',
  'manifest',
]);

export const HarmonyModNames: readonly HarmonyModName[] = Object.freeze(
  AllModNames.filter((name): name is HarmonyModName => name !== 'manifest' && name !== 'nativeInputsStamp' && name !== 'prepare' && name !== 'patch')
);

export function recordManagedFile(config: ManagedConfig, file: string, owner: string): void {
  config._internal ??= {};
  config._internal.harmonyManagedFiles ??= [];

  const entry = toPosixRelative(config.modRequest.projectRoot, file);
  const files = config._internal.harmonyManagedFiles.filter((item: { path: string }) => item.path !== entry);

  files.push({ path: entry, owner });
  files.sort((left: { path: string }, right: { path: string }) => left.path.localeCompare(right.path, 'en'));
  config._internal.harmonyManagedFiles = files;
}

function assertModResults(name: AnyModName, value: unknown, kind: 'json' | 'resource' | 'text'): void {
  const valid = kind === 'text'
    ? typeof value === 'string'
    : value !== null && typeof value === 'object' && !Array.isArray(value);

  if (!valid) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MOD_RESULTS_INVALID',
      `harmony.${name} must return ${kind === 'text' ? 'a string' : 'an object'} modResults.`,
      { operation: `harmony.${name}.write` }
    );
  }
}

function withFileProvider(config: ExpoConfig, name: FileModName): ExpoConfig {
  return withBaseMod<FileResult>(config, {
    platform: 'harmony' as ModPlatform,
    mod: name,
    isProvider: true,
    isIntrospective: JsonMods.has(name),
    saveToInternal: JsonMods.has(name),
    async action(value) {
      const { nextMod: next, ...request } = value.modRequest;
      const project = name in ProjectPaths;
      const root = project ? request.projectRoot : request.platformProjectRoot;
      const file = project
        ? await resolveProjectPath(root, name as keyof typeof ProjectPaths)
        : await resolveHarmonyPath(root, ManagedPaths[name as keyof typeof ManagedPaths]);
      const exists = !request.ignoreExistingNativeFiles && fs.existsSync(file);
      const template = value._internal?.harmonyTemplateDirectory;
      const input = !exists && !project && typeof template === 'string'
        ? await resolveHarmonyPath(template, ManagedPaths[name as keyof typeof ManagedPaths])
        : file;

      const data = request.ignoreExistingNativeFiles && input === file
        ? (JsonMods.has(name) ? {} : '')
        : JsonMods.has(name)
          ? await readJson5<HarmonyJson>(input, {}, name)
          : await readText(file);

      const context = { ...request, modFile: file, modFileExists: exists } as typeof value.modRequest;
      const result = await next!({ ...value, modRequest: context, modResults: data });
      assertModResults(name, result.modResults, JsonMods.has(name) ? 'json' : 'text');

      if (!result.modRequest.introspect) {
        if (typeof result.modResults === 'string') {
          await atomicWrite(file, result.modResults.replace(/\r\n?/g, '\n').replace(/\n?$/, '\n'));
        } else {
          await writeJson5(file, result.modResults);
        }

        recordManagedFile(result, file, name);
      }

      return result;
    },
  });
}

async function readResourceMap(
  root: string,
  entries: Readonly<Record<string, string>>,
  name: ResourceModName,
  template?: string,
  ignore = false
): Promise<HarmonyResourceMap> {
  const resources: HarmonyResourceMap = {};

  for (const [scope, relative] of Object.entries(entries)) {
    const file = await resolveHarmonyPath(root, relative);
    const fallback = ignore || !fs.existsSync(file);
    const input = fallback && template ? await resolveHarmonyPath(template, relative) : file;

    resources[scope] = ignore && input === file ? {} : await readJson5<HarmonyJson>(input, {}, name);
  }

  return resources;
}

async function readMediaMap(root: string): Promise<HarmonyMediaMap> {
  const media: HarmonyMediaMap = {};

  for (const [scope, relative] of Object.entries(ResourcePaths.media)) {
    const directory = await resolveHarmonyPath(root, relative);

    media[scope] = {};
    let names: string[] = [];

    try {
      names = await fs.promises.readdir(directory);
    } catch (cause) {
      if ((cause as NodeJS.ErrnoException).code !== 'ENOENT') {
        throw new HarmonyConfigPluginError(
          'ERR_HARMONY_RESOURCE_READ',
          `Cannot read Harmony media directory ${directory}: ${(cause as Error).message}`,
          { cause, file: directory, operation: 'harmony.media.read' }
        );
      }
    }

    for (const name of names.sort()) {
      const file = path.join(directory, name);

      if ((await fs.promises.lstat(file)).isFile()) media[scope][name] = { source: file };
    }
  }

  return media;
}

async function writeMediaMap(
  root: string,
  media: HarmonyMediaMap,
  config: ManagedConfig,
  previous: Record<string, string[]> = {}
): Promise<void> {
  const writes: MediaWrite[] = [];

  for (const [scope, files] of Object.entries(media || {})) {
    if (!(scope in ResourcePaths.media)) continue;

    if (!files || typeof files !== 'object' || Array.isArray(files)) {
      throw new HarmonyConfigPluginError(
        'ERR_HARMONY_CONFIG_INVALID',
        `Harmony media scope ${scope} must be an object.`,
        { operation: 'harmony.media.write' }
      );
    }

    const directory = await resolveHarmonyPath(root, ResourcePaths.media[scope as keyof typeof ResourcePaths.media]);

    for (const [name, descriptor] of Object.entries(files)) {
      if (!/^[A-Za-z0-9_.-]+$/.test(name) || name.includes('..')) {
        throw new HarmonyConfigPluginError(
          'ERR_HARMONY_CONFIG_INVALID',
          `Invalid Harmony media file name: ${name}`,
          { operation: 'harmony.media.write' }
        );
      }
      if (!descriptor || typeof descriptor !== 'object' || Array.isArray(descriptor)) {
        throw new HarmonyConfigPluginError(
          'ERR_HARMONY_CONFIG_INVALID',
          `Harmony media ${scope}/${name} must use a descriptor object.`,
          { operation: 'harmony.media.write' }
        );
      }

      const item = descriptor as Partial<HarmonyMediaDescriptor>;
      if (Object.hasOwn(item, 'source') === Object.hasOwn(item, 'content')) {
        throw new HarmonyConfigPluginError(
          'ERR_HARMONY_CONFIG_INVALID',
          `Harmony media ${scope}/${name} must define exactly one of source or content.`,
          { operation: 'harmony.media.write' }
        );
      }
      if (item.replaceBase !== undefined && typeof item.replaceBase !== 'boolean') {
        throw new HarmonyConfigPluginError(
          'ERR_HARMONY_CONFIG_INVALID',
          `Harmony media ${scope}/${name} replaceBase must be a boolean.`,
          { operation: 'harmony.media.write' }
        );
      }

      let content: string | Uint8Array;

      if (Object.hasOwn(item, 'source')) {
        if (typeof item.source !== 'string' || item.source.length === 0) {
          throw new HarmonyConfigPluginError(
            'ERR_HARMONY_CONFIG_INVALID',
            `Harmony media ${scope}/${name} source must be a non-empty path.`,
            { operation: 'harmony.media.write' }
          );
        }

        content = Uint8Array.from(await fs.promises.readFile(item.source));
      } else {
        if (typeof item.content !== 'string' && !(item.content instanceof Uint8Array)) {
          throw new HarmonyConfigPluginError(
            'ERR_HARMONY_CONFIG_INVALID',
            `Harmony media ${scope}/${name} content must be a string or Uint8Array.`,
            { operation: 'harmony.media.write' }
          );
        }

        content = item.content;
      }

      writes.push({
        content,
        directory,
        name,
        replaceBase: item.replaceBase === true,
      });
    }
  }

  for (const [scope, names] of Object.entries(previous)) {
    if (!(scope in ResourcePaths.media)) continue;

    const directory = await resolveHarmonyPath(
      root,
      ResourcePaths.media[scope as keyof typeof ResourcePaths.media]
    );
    const next = media?.[scope];

    for (const name of names) {
      if (!next || typeof next !== 'object' || !Object.hasOwn(next, name)) {
        const file = await resolveHarmonyPath(directory, name);

        await fs.promises.rm(file, { force: true });
      }
    }
  }

  for (const { content, directory, name, replaceBase } of writes) {
    await fs.promises.mkdir(directory, { recursive: true });

    if (replaceBase) {
      const base = path.parse(name).name;

      for (const entry of await fs.promises.readdir(directory)) {
        if (path.parse(entry).name === base && entry !== name) {
          await fs.promises.rm(path.join(directory, entry), { force: true });
        }
      }
    }

    const file = await resolveHarmonyPath(directory, name);

    await atomicWrite(file, content);
    recordManagedFile(config, file, 'media');
  }
}

function withResourceProvider(config: ExpoConfig, name: ResourceModName): ExpoConfig {
  const introspective = name !== 'media';

  return withBaseMod<ResourceResult>(config, {
    platform: 'harmony' as ModPlatform,
    mod: name,
    isProvider: true,
    isIntrospective: introspective,
    saveToInternal: introspective,
    async action(value) {
      const { nextMod: next, ...request } = value.modRequest;
      const root = request.platformProjectRoot;
      const data = name === 'media'
        ? (request.ignoreExistingNativeFiles
            ? Object.fromEntries(Object.keys(ResourcePaths.media).map(scope => [scope, {}]))
            : await readMediaMap(root))
        : await readResourceMap(
            root, ResourcePaths[name], name,
            value._internal?.harmonyTemplateDirectory, request.ignoreExistingNativeFiles
          );
      const previous = name === 'media'
        ? Object.fromEntries(
            Object.entries(data).map(([scope, files]) => [scope, Object.keys(files)])
          )
        : {};

      const result = await next!({ ...value, modRequest: request, modResults: data });
      assertModResults(name, result.modResults, 'resource');

      if (!result.modRequest.introspect) {
        if (name === 'media') {
          await writeMediaMap(root, result.modResults as HarmonyMediaMap, result, previous);
        } else {
          const paths = ResourcePaths[name];

          for (const [scope, resource] of Object.entries(result.modResults)) {
            if (!(scope in paths)) continue;

            if (!resource || typeof resource !== 'object' || Array.isArray(resource)) {
              throw new HarmonyConfigPluginError(
                'ERR_HARMONY_CONFIG_INVALID',
                `Harmony ${name} scope ${scope} must be an object.`,
                { operation: `harmony.${name}.write` }
              );
            }

            const file = await resolveHarmonyPath(root, paths[scope as keyof typeof paths]);

            // Harmony's resource compiler rejects an empty JSON root.
            if (Object.keys(resource).length === 0) {
              await fs.promises.rm(file, { force: true });

              continue;
            }

            await writeJson5(file, resource);
            recordManagedFile(result, file, name);
          }
        }
      }

      return result;
    },
  });
}

function withVirtualProvider(config: ExpoConfig, name: AnyModName): ExpoConfig {
  return withBaseMod<null>(config, {
    platform: 'harmony' as ModPlatform,
    mod: name,
    isProvider: true,
    isIntrospective: name === 'prepare',
    async action(value) {
      const { nextMod: next, ...request } = value.modRequest;
      return next!({ ...value, modRequest: request, modResults: null });
    },
  });
}

function withProvider(config: ExpoConfig, name: AnyModName): ExpoConfig {
  const actions: HarmonyModAction[] = [];

  config = withMod(config, {
    platform: 'harmony' as ModPlatform,
    mod: name,
    async action(value) {
      let result = value;

      // Late mods must follow Expo's last-registered-first order.
      for (let index = actions.length - 1; index >= 0; index -= 1) {
        result = await actions[index](result as unknown as HarmonyModConfig<unknown>) as unknown as typeof result;
      }

      return result;
    },
  });

  if (JsonMods.has(name as FileModName) || TextMods.has(name as FileModName)) {
    config = withFileProvider(config, name as FileModName);
  } else if (ResourceMods.has(name as HarmonyModName)) {
    config = withResourceProvider(config, name as ResourceModName);
  } else if (VirtualMods.has(name)) {
    config = withVirtualProvider(config, name);
  } else {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MOD_NOT_REGISTERED',
      `Unknown Harmony mod: ${name}`,
      { operation: 'register-base-mods' }
    );
  }

  const mods = (config as ExportedConfig).mods as unknown as ModTable | undefined;
  const provider = mods?.harmony?.[name];

  if (provider?.isProvider) provider.expoHarmonyLateActions = actions;

  return config;
}

export function withHarmonyBaseMods<Config extends ExpoConfigWithHarmony>(config: Config): Config {
  for (const name of AllModNames) {
    const mods = (config as ExportedConfig).mods as unknown as ModTable;

    if (!mods?.harmony?.[name]?.isProvider) config = withProvider(config as ExpoConfig, name) as Config;
  }

  const mods = (config as ExportedConfig).mods as unknown as ModTable;
  const table = mods.harmony!;

  mods.harmony = Object.fromEntries([
    ...AllModNames.filter(name => table[name] && name !== 'manifest' && name !== 'patch').map(name => [name, table[name]]),
    ...Object.entries(table).filter(([name]) => !AllModNames.includes(name as AnyModName)),
    ['patch', table.patch],
    ['manifest', table.manifest],
  ]);

  return config;
}

export function withHarmonyMod<T = unknown, Config extends ExpoConfigWithHarmony = ExpoConfigWithHarmony>(
  config: Config,
  tuple: [HarmonyModName, HarmonyModAction<T>]
): Config {
  if (!Array.isArray(tuple) || tuple.length !== 2) {
    throw new TypeError('withHarmonyMod expects [modName, action].');
  }

  const [name, action] = tuple;
  if (!HarmonyModNames.includes(name) || typeof action !== 'function') {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MOD_NOT_REGISTERED',
      `Cannot register Harmony mod: ${name}`,
      { operation: 'register-mod' }
    );
  }

  return registerMod(config, name, action);
}

export function registerMod<T, Config extends ExpoConfigWithHarmony>(
  config: Config,
  name: string,
  action: HarmonyModAction<T>
): Config {
  const mods = (config as ExportedConfig).mods as unknown as ModTable | undefined;
  const provider = mods?.harmony?.[name];

  if (provider?.isProvider && provider.expoHarmonyLateActions) {
    // Build an ordinary Expo interceptor on an isolated mod table, preserving
    // its registration stack, error behavior and execution trace for late mods.
    const carrier = withMod<T>({ ...config, mods: {} } as ExpoConfig, {
      platform: 'harmony' as ModPlatform,
      mod: name,
      action: action as unknown as Parameters<typeof withMod<T>>[1]['action'],
    });
    const interceptor = (carrier.mods as unknown as Record<string, Record<string, HarmonyModAction>>).harmony[name];
    provider.expoHarmonyLateActions.push(interceptor);

    return config;
  }

  return withMod<T>(config as ExpoConfig, {
    platform: 'harmony' as ModPlatform,
    mod: name,
    action: action as unknown as Parameters<typeof withMod<T>>[1]['action'],
  }) as Config;
}

export const withReactNativeConfig: HarmonyConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['reactNativeConfig', action]);
export const withAppJson: HarmonyConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['appJson', action]);
export const withProjectBuildProfile: HarmonyConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['projectBuildProfile', action]);
export const withRootOhPackage: HarmonyConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['rootOhPackage', action]);
export const withRootHvigor: HarmonyConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['rootHvigor', action]);
export const withNativeInputsStamp: HarmonyConfigPlugin<HarmonyModAction<string>>
  = (config, action) => registerMod(config, 'nativeInputsStamp', action);
export const withHvigorConfig: HarmonyConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['hvigorConfig', action]);
export const withEntryBuildProfile: HarmonyConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['entryBuildProfile', action]);
export const withEntryOhPackage: HarmonyConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['entryOhPackage', action]);
export const withEntryHvigor: HarmonyConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['entryHvigor', action]);
export const withModuleJson: HarmonyConfigPlugin<HarmonyModAction<HarmonyModuleJson>>
  = (config, action) => withHarmonyMod(config, ['moduleJson', action]);
export const withStrings: HarmonyConfigPlugin<HarmonyModAction<HarmonyResourceMap>>
  = (config, action) => withHarmonyMod(config, ['strings', action]);
export const withColors: HarmonyConfigPlugin<HarmonyModAction<HarmonyResourceMap>>
  = (config, action) => withHarmonyMod(config, ['colors', action]);
export const withMedia: HarmonyConfigPlugin<HarmonyModAction<HarmonyMediaMap>>
  = (config, action) => withHarmonyMod(config, ['media', action]);
export const withProfiles: HarmonyConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['profiles', action]);
export const withEntryAbility: HarmonyConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['entryAbility', action]);
export const withIndexPage: HarmonyConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['indexPage', action]);
export const withWorker: HarmonyConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['worker', action]);
export const withArkTSPackageProvider: HarmonyConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['arktsPackageProvider', action]);
export const withCppPackageProvider: HarmonyConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['cppPackageProvider', action]);
export const withCMakeLists: HarmonyConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['cmakeLists', action]);
export const withHarmonyAutolinking: HarmonyConfigPlugin<HarmonyModAction<null>>
  = (config, action) => withHarmonyMod(config, ['autolinking', action]);
export const withCngManifest: HarmonyConfigPlugin<HarmonyModAction<null>>
  = (config, action) => registerMod(config, 'manifest', action);
export const withPreparation: HarmonyConfigPlugin<HarmonyModAction<null>>
  = (config, action) => registerMod(config, 'prepare', action);
export const withProjectPatch: HarmonyConfigPlugin<HarmonyModAction<null>>
  = (config, action) => registerMod(config, 'patch', action);
export const withHarmonyDangerousMod: HarmonyConfigPlugin<HarmonyModAction<null>>
  = (config, action) => withHarmonyMod(config, ['dangerous', action]);

export const withHarmonyResources: HarmonyConfigPlugin<HarmonyModAction<unknown>> = (config, action) => {
  for (const name of ResourceModNames) {
    withHarmonyMod(config, [name, action]);
  }

  return config;
};

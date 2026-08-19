import fs from 'node:fs';
import path from 'node:path';

import {
  withBaseMod, withMod,
  type ConfigPlugin, type ExportedConfig, type ExportedConfigWithProps, type ModPlatform,
} from '@expo/config-plugins';
import type { ExpoConfig } from '@expo/config-types';

import { HarmonyConfigPluginError } from './errors';
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
    | 'autolinking'
    | 'manifest';

export type HarmonyModAction<T = unknown> = (
  config: ExportedConfigWithProps<T>
) => ExportedConfigWithProps<T> | Promise<ExportedConfigWithProps<T>>;

export type HarmonyJson = Record<string, unknown>;
export type HarmonyResourceMap = Record<string, HarmonyJson>;
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
type ModEntry = { isProvider?: boolean };

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
  'entryHvigor',
  'entryAbility',
  'indexPage',
  'worker',
  'arktsPackageProvider',
  'cppPackageProvider',
  'cmakeLists',
]);
const ResourceMods = new Set<HarmonyModName>(['strings', 'colors', 'media']);
const VirtualMods = new Set<HarmonyModName>(['dangerous', 'autolinking', 'manifest']);
const ResourceModNames: readonly ResourceModName[] = ['strings', 'colors', 'media'];

export const HarmonyModNames: readonly HarmonyModName[] = Object.freeze([
  'dangerous',
  'reactNativeConfig',
  'appJson',
  'projectBuildProfile',
  'rootOhPackage',
  'rootHvigor',
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
  'manifest',
]);

export function recordManagedFile(config: ManagedConfig, file: string, owner: string): void {
  config._internal ??= {};
  config._internal.harmonyManagedFiles ??= [];
  const relative = toPosixRelative(config.modRequest.projectRoot, file);
  const current = config._internal.harmonyManagedFiles.filter((item: { path: string }) => item.path !== relative);
  current.push({ path: relative, owner });
  current.sort((left: { path: string }, right: { path: string }) => left.path.localeCompare(right.path, 'en'));
  config._internal.harmonyManagedFiles = current;
}

function assertModResults(modName: HarmonyModName, value: unknown, kind: 'json' | 'resource' | 'text'): void {
  const valid = kind === 'text'
    ? typeof value === 'string'
    : value !== null && typeof value === 'object' && !Array.isArray(value);
  if (!valid) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MOD_RESULTS_INVALID',
      `harmony.${modName} must return ${kind === 'text' ? 'a string' : 'an object'} modResults.`,
      { operation: `harmony.${modName}.write` }
    );
  }
}

function withFileProvider(config: ExpoConfig, modName: FileModName): ExpoConfig {
  return withBaseMod<FileResult>(config, {
    platform: 'harmony' as ModPlatform,
    mod: modName,
    isProvider: true,
    isIntrospective: JsonMods.has(modName),
    saveToInternal: JsonMods.has(modName),
    async action(value) {
      const { nextMod, ...modRequest } = value.modRequest;
      const isProjectFile = modName in ProjectPaths;
      const root = isProjectFile ? modRequest.projectRoot : modRequest.platformProjectRoot;
      const file = isProjectFile
        ? await resolveProjectPath(root, modName as keyof typeof ProjectPaths)
        : await resolveHarmonyPath(root, ManagedPaths[modName as keyof typeof ManagedPaths]);
      const modFileExists = fs.existsSync(file);
      const modResults = JsonMods.has(modName)
        ? await readJson5<HarmonyJson>(file, {}, modName)
        : await readText(file);
      const request = { ...modRequest, modFile: file, modFileExists } as typeof value.modRequest;
      const result = await nextMod!({ ...value, modRequest: request, modResults });

      assertModResults(modName, result.modResults, JsonMods.has(modName) ? 'json' : 'text');
      if (!result.modRequest.introspect) {
        if (typeof result.modResults === 'string') {
          await atomicWrite(file, result.modResults.replace(/\r\n?/g, '\n').replace(/\n?$/, '\n'));
        } else {
          await writeJson5(file, result.modResults);
        }
        recordManagedFile(result, file, modName);
      }

      return result;
    },
  });
}

async function readResourceMap(
  root: string,
  entries: Readonly<Record<string, string>>,
  modName: ResourceModName
): Promise<HarmonyResourceMap> {
  const result: HarmonyResourceMap = {};
  for (const [scope, relative] of Object.entries(entries)) {
    const file = await resolveHarmonyPath(root, relative);
    result[scope] = await readJson5<HarmonyJson>(file, {}, modName);
  }

  return result;
}

async function readMediaMap(root: string): Promise<HarmonyMediaMap> {
  const result: HarmonyMediaMap = {};
  for (const [scope, relative] of Object.entries(ResourcePaths.media)) {
    const directory = await resolveHarmonyPath(root, relative);
    result[scope] = {};
    let names: string[] = [];
    try {
      names = await fs.promises.readdir(directory);
    } catch (cause) {
      if ((cause as NodeJS.ErrnoException).code !== 'ENOENT') return Promise.reject(cause);
    }

    for (const name of names.sort()) {
      const file = path.join(directory, name);
      if ((await fs.promises.lstat(file)).isFile()) result[scope][name] = { source: file };
    }
  }

  return result;
}

async function writeMediaMap(
  root: string,
  result: HarmonyMediaMap,
  config: ManagedConfig,
  previous: Record<string, string[]> = {}
): Promise<void> {
  const writes: MediaWrite[] = [];
  for (const [scope, files] of Object.entries(result || {})) {
    if (!(scope in ResourcePaths.media)) continue;
    if (!files || typeof files !== 'object' || Array.isArray(files)) {
      throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `Harmony media scope ${scope} must be an object.`, { operation: 'harmony.media.write' });
    }

    const directory = await resolveHarmonyPath(root, ResourcePaths.media[scope as keyof typeof ResourcePaths.media]);
    for (const [name, descriptor] of Object.entries(files)) {
      if (!/^[A-Za-z0-9_.-]+$/.test(name) || name.includes('..')) {
        throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `Invalid Harmony media file name: ${name}`, { operation: 'harmony.media.write' });
      }
      if (!descriptor || typeof descriptor !== 'object' || Array.isArray(descriptor)) {
        throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `Harmony media ${scope}/${name} must use a descriptor object.`, { operation: 'harmony.media.write' });
      }

      const media = descriptor as Partial<HarmonyMediaDescriptor>;
      const hasSource = Object.hasOwn(media, 'source');
      const hasContent = Object.hasOwn(media, 'content');
      if (hasSource === hasContent) {
        throw new HarmonyConfigPluginError(
          'ERR_HARMONY_CONFIG_INVALID',
          `Harmony media ${scope}/${name} must define exactly one of source or content.`,
          { operation: 'harmony.media.write' }
        );
      }
      if (media.replaceBase !== undefined && typeof media.replaceBase !== 'boolean') {
        throw new HarmonyConfigPluginError(
          'ERR_HARMONY_CONFIG_INVALID',
          `Harmony media ${scope}/${name} replaceBase must be a boolean.`,
          { operation: 'harmony.media.write' }
        );
      }

      let content: string | Uint8Array;
      if (hasSource) {
        if (typeof media.source !== 'string' || media.source.length === 0) {
          throw new HarmonyConfigPluginError(
            'ERR_HARMONY_CONFIG_INVALID',
            `Harmony media ${scope}/${name} source must be a non-empty path.`,
            { operation: 'harmony.media.write' }
          );
        }
        content = Uint8Array.from(await fs.promises.readFile(media.source));
      } else {
        if (typeof media.content !== 'string' && !(media.content instanceof Uint8Array)) {
          throw new HarmonyConfigPluginError(
            'ERR_HARMONY_CONFIG_INVALID',
            `Harmony media ${scope}/${name} content must be a string or Uint8Array.`,
            { operation: 'harmony.media.write' }
          );
        }
        content = media.content;
      }
      writes.push({
        content,
        directory,
        name,
        replaceBase: media.replaceBase === true,
      });
    }
  }

  // Resolve and read every desired input before removing stale resources. A
  // malformed descriptor or missing source therefore cannot partially mutate
  // an otherwise valid generated project.
  for (const [scope, names] of Object.entries(previous)) {
    if (!(scope in ResourcePaths.media)) continue;
    const directory = await resolveHarmonyPath(
      root,
      ResourcePaths.media[scope as keyof typeof ResourcePaths.media]
    );
    const next = result?.[scope];
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
      for (const oldName of await fs.promises.readdir(directory)) {
        if (path.parse(oldName).name === base && oldName !== name) {
          await fs.promises.rm(path.join(directory, oldName), { force: true });
        }
      }
    }

    const file = await resolveHarmonyPath(directory, name);
    await atomicWrite(file, content);
    recordManagedFile(config, file, 'media');
  }
}

function withResourceProvider(config: ExpoConfig, modName: ResourceModName): ExpoConfig {
  const isIntrospective = modName !== 'media';

  return withBaseMod<ResourceResult>(config, {
    platform: 'harmony' as ModPlatform,
    mod: modName,
    isProvider: true,
    isIntrospective,
    saveToInternal: isIntrospective,
    async action(value) {
      const { nextMod, ...modRequest } = value.modRequest;
      const root = modRequest.platformProjectRoot;
      const modResults = modName === 'media'
        ? await readMediaMap(root)
        : await readResourceMap(root, ResourcePaths[modName], modName);
      const previousMedia = modName === 'media'
        ? Object.fromEntries(
            Object.entries(modResults).map(([scope, files]) => [scope, Object.keys(files)])
          )
        : {};
      const result = await nextMod!({ ...value, modRequest, modResults });

      assertModResults(modName, result.modResults, 'resource');
      if (!result.modRequest.introspect) {
        if (modName === 'media') {
          await writeMediaMap(root, result.modResults as HarmonyMediaMap, result, previousMedia);
        } else {
          const paths = ResourcePaths[modName];
          for (const [scope, resource] of Object.entries(result.modResults)) {
            if (!(scope in paths)) continue;
            const file = await resolveHarmonyPath(root, paths[scope as keyof typeof paths]);
            await writeJson5(file, resource);
            recordManagedFile(result, file, modName);
          }
        }
      }

      return result;
    },
  });
}

function withVirtualProvider(config: ExpoConfig, modName: HarmonyModName): ExpoConfig {
  return withBaseMod<null>(config, {
    platform: 'harmony' as ModPlatform,
    mod: modName,
    isProvider: true,
    async action(value) {
      const { nextMod, ...modRequest } = value.modRequest;

      return nextMod!({ ...value, modRequest, modResults: null });
    },
  });
}

function withProvider(config: ExpoConfig, modName: HarmonyModName): ExpoConfig {
  if (JsonMods.has(modName as FileModName) || TextMods.has(modName as FileModName)) {
    return withFileProvider(config, modName as FileModName);
  }
  if (ResourceMods.has(modName)) return withResourceProvider(config, modName as ResourceModName);
  if (VirtualMods.has(modName)) return withVirtualProvider(config, modName);

  throw new HarmonyConfigPluginError(
    'ERR_HARMONY_MOD_NOT_REGISTERED',
    `Unknown Harmony mod: ${modName}`,
    { operation: 'register-base-mods' }
  );
}

export function withHarmonyBaseMods(config: ExpoConfig): ExpoConfig {
  for (const modName of HarmonyModNames) {
    const platforms = (config as ExportedConfig).mods as unknown as Record<
      string,
      Record<string, ModEntry> | undefined
    >;
    if (!platforms?.harmony?.[modName]?.isProvider) config = withProvider(config, modName);
  }

  const platforms = (config as ExportedConfig).mods as unknown as Record<
    string,
    Record<string, ModEntry>
  >;
  const table = platforms.harmony;
  platforms.harmony = Object.fromEntries([
    ...HarmonyModNames.filter(name => table[name]).map(name => [name, table[name]]),
    ...Object.entries(table).filter(([name]) => !HarmonyModNames.includes(name as HarmonyModName)),
  ]);

  return config;
}

export function withHarmonyMod<T = unknown>(
  config: ExpoConfig,
  tuple: [HarmonyModName, HarmonyModAction<T>]
): ExpoConfig {
  if (!Array.isArray(tuple) || tuple.length !== 2) {
    throw new TypeError('withHarmonyMod expects [modName, action].');
  }

  const [modName, action] = tuple;
  if (!HarmonyModNames.includes(modName) || typeof action !== 'function') {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MOD_NOT_REGISTERED',
      `Cannot register Harmony mod: ${modName}`,
      { operation: 'register-mod' }
    );
  }

  return withMod<T>(config, { platform: 'harmony' as ModPlatform, mod: modName, action });
}

export const withReactNativeConfig: ConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['reactNativeConfig', action]);
export const withAppJson: ConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['appJson', action]);
export const withProjectBuildProfile: ConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['projectBuildProfile', action]);
export const withRootOhPackage: ConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['rootOhPackage', action]);
export const withRootHvigor: ConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['rootHvigor', action]);
export const withHvigorConfig: ConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['hvigorConfig', action]);
export const withEntryBuildProfile: ConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['entryBuildProfile', action]);
export const withEntryOhPackage: ConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['entryOhPackage', action]);
export const withEntryHvigor: ConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['entryHvigor', action]);
export const withModuleJson: ConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['moduleJson', action]);
export const withStrings: ConfigPlugin<HarmonyModAction<HarmonyResourceMap>>
  = (config, action) => withHarmonyMod(config, ['strings', action]);
export const withColors: ConfigPlugin<HarmonyModAction<HarmonyResourceMap>>
  = (config, action) => withHarmonyMod(config, ['colors', action]);
export const withMedia: ConfigPlugin<HarmonyModAction<HarmonyMediaMap>>
  = (config, action) => withHarmonyMod(config, ['media', action]);
export const withProfiles: ConfigPlugin<HarmonyModAction<HarmonyJson>>
  = (config, action) => withHarmonyMod(config, ['profiles', action]);
export const withEntryAbility: ConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['entryAbility', action]);
export const withIndexPage: ConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['indexPage', action]);
export const withWorker: ConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['worker', action]);
export const withArkTSPackageProvider: ConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['arktsPackageProvider', action]);
export const withCppPackageProvider: ConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['cppPackageProvider', action]);
export const withCMakeLists: ConfigPlugin<HarmonyModAction<string>>
  = (config, action) => withHarmonyMod(config, ['cmakeLists', action]);
export const withHarmonyAutolinking: ConfigPlugin<HarmonyModAction<null>>
  = (config, action) => withHarmonyMod(config, ['autolinking', action]);
export const withCngManifest: ConfigPlugin<HarmonyModAction<null>>
  = (config, action) => withHarmonyMod(config, ['manifest', action]);
export const withHarmonyDangerousMod: ConfigPlugin<HarmonyModAction<null>>
  = (config, action) => withHarmonyMod(config, ['dangerous', action]);

export const withHarmonyResources: ConfigPlugin<HarmonyModAction<unknown>> = (config, action) => {
  for (const modName of ResourceModNames) {
    withHarmonyMod(config, [modName, action]);
  }

  return config;
};

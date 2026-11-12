/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { getConfigFilePaths } from '@expo/config';
import { getHarmonyProjectConfig } from '@expo-harmony/expo__config/internal/project-config';

import { ExpoArtifacts, ModuleBuildOptionsArtifact, Platform } from './constants';
import type { InlineModulesOptions, LinkOptions } from '../types';
import { HarmonyAutolinkingError } from '../errors';
import { isObject, readJsonAsync, realpathExistingAsync, normalizeSlashes, normalizeStringArray, uniqueStrings } from '../utilities/values';

const ListFields = ['searchPaths', 'exclude', 'include'];
const NpmPackageNamePattern = /^(?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*$/u;
const RnohPackageListDelimiterPattern = /[;\0\r\n]/;

function selectConfiguredValue(input, platform, shared, field, fallback) {
  if (input[field] !== undefined) return input[field];
  if (platform[field] !== undefined) return platform[field];
  if (shared[field] !== undefined) return shared[field];
  return fallback;
}

function configuredList(platform, shared, field) {
  const normalize = (value) => {
    if (value === undefined) return [];

    const values = field === 'searchPaths' && typeof value === 'string'
      ? [value]
      : Array.isArray(value) ? value : [];

    return values.filter(item => typeof item === 'string' && item.trim());
  };

  if (field === 'include') {
    return [
      ...normalize(shared.include),
      ...normalize(platform.include),
    ];
  }

  return normalize(platform[field] !== undefined ? platform[field] : shared[field]);
}

function validateConfigObject(value, field) {
  if (value === undefined) return {};

  if (!isObject(value)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', `${field} must be an object.`, { stage: 'options' });
  }

  return value;
}

function normalizeBuildType(value) {
  const buildType = value === undefined ? 'debug' : value;

  if (buildType !== 'debug' && buildType !== 'release') {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'buildType must be either "debug" or "release".', { stage: 'options' });
  }

  return buildType;
}

function assertSafeRnohPackageList(values, field, stage = 'options') {
  if (!Array.isArray(values)
    || values.some(value => typeof value !== 'string'
      || !value.trim()
      || RnohPackageListDelimiterPattern.test(value))) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', `${field} entries must not contain semicolons or NUL/CR/LF control characters.`, { stage });
  }
}

function normalizeNativeModulesDirectory(value, root) {
  if (value === null) return null;

  if (typeof value !== 'string' || !value.trim()) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'nativeModulesDir must be a non-empty string or null.', { stage: 'options' });
  }

  return path.resolve(root, value);
}

function normalizeInlineModules(value: unknown, root: string): InlineModulesOptions | null {
  if (value === undefined || value === null || value === false) return null;
  if (!isObject(value)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'inlineModules must be an object or null.', { stage: 'options' });
  }

  const configured = value as Record<string, unknown>;
  const directories = normalizeStringArray(configured.watchedDirectories, 'inlineModules.watchedDirectories');
  const targets = configured.targets === undefined ? undefined : normalizeStringArray(configured.targets, 'inlineModules.targets');
  const entry = ExpoArtifacts.hostProvider.split('/')[0];

  if (targets && !targets.includes(entry)) return null;

  return {
    watchedDirectories: directories.map(directory => path.resolve(root, directory)),
    ...(targets ? { targets } : {}),
  };
}

function readRawExpoInlineModules(root: string, buildType: LinkOptions['buildType']): InlineModulesOptions | null {
  const { staticConfigPath, dynamicConfigPath } = getConfigFilePaths(root);
  const value = staticConfigPath || dynamicConfigPath
    ? getHarmonyProjectConfig(root, {
      skipSDKVersionRequirement: true,
      skipPlugins: true,
    }, buildType === 'release' ? 'production' : 'development').exp.experiments?.inlineModules
    : undefined;

  return normalizeInlineModules(value, root);
}

type ModuleBuildOptions = Pick<LinkOptions, 'moduleBuilds' | 'moduleBuildSettings' | 'expoInlineModules'>;

async function readModuleBuildOptionsAsync(root: string, stage = 'options'): Promise<ModuleBuildOptions | null> {
  let content: string;

  try {
    content = await fs.promises.readFile(path.join(root, ModuleBuildOptionsArtifact), 'utf8');
  } catch (cause) {
    if (cause.code === 'ENOENT') return null;
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', `Cannot read ${ModuleBuildOptionsArtifact}.`, { cause, stage });
  }

  try {
    const options = JSON.parse(content);
    if (!isObject(options) || options.schemaVersion !== 1 || !isObject(options.moduleBuilds)) {
      throw new TypeError('Invalid module build options');
    }

    return options;
  } catch (cause) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', `Invalid ${ModuleBuildOptionsArtifact}. Run Harmony prebuild again.`, { cause, stage });
  }
}

interface ModuleOverrideOptions {
  allowPackageRoot?: boolean;
  code?: string;
  field?: string;
  stage?: string;
}

function normalizeModuleOverrides(
  value: unknown, options: ModuleOverrideOptions = {}
): Readonly<Record<string, Readonly<Record<string, unknown>>>> {
  const code = options.code || 'INVALID_OPTIONS';
  const field = options.field || 'package.json#expo.autolinking.harmony.modules';
  const stage = options.stage || 'options';

  if (value === undefined) return Object.freeze({});
  if (!isObject(value)) {
    throw new HarmonyAutolinkingError(code, `${field} must be an object.`, { stage });
  }

  const overrides: Record<string, Readonly<Record<string, unknown>>> = Object.create(null);

  for (const packageName of Object.keys(value).sort()) {
    const metadata = value[packageName];
    if (!NpmPackageNamePattern.test(packageName) || !isObject(metadata)) {
      throw new HarmonyAutolinkingError(code, `Invalid Harmony sidecar module registration for ${packageName} in ${field}.`, { stage });
    }

    if (metadata.version !== undefined
      && (typeof metadata.version !== 'string'
        || !metadata.version
        || /^[*~^]|^(?:file|link|workspace):/u.test(metadata.version))) {
      throw new HarmonyAutolinkingError(code, `Harmony sidecar module ${packageName} in ${field} must use an exact version.`, { stage });
    }

    if (metadata.packageRoot !== undefined
      && (!options.allowPackageRoot || !metadata.version || typeof metadata.packageRoot !== 'string' || !metadata.packageRoot.trim())) {
      throw new HarmonyAutolinkingError(code, `Harmony sidecar module ${packageName} in ${field} requires an exact version and a packageRoot inside its declaring package.`, { stage });
    }

    overrides[packageName] = Object.freeze({ ...metadata });
  }

  return Object.freeze(overrides);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function normalizeOptionsAsync(input: Record<string, any> = {}) {
  if (!isObject(input)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'Options must be an object.', { stage: 'options' });
  }

  if (input.logger !== undefined) {
    if (!isObject(input.logger)
      || ['debug', 'info', 'warn', 'error'].some((level) => {
        return input.logger[level] !== undefined && typeof input.logger[level] !== 'function';
      })) {
      throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'logger must expose only callable debug/info/warn/error methods.', { stage: 'options' });
    }
  }

  if (input.platform != null && input.platform !== Platform) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'Only platform "harmony" is supported.', { stage: 'options' });
  }

  const origin = input.projectRoot === undefined ? process.cwd() : input.projectRoot;
  if (typeof origin !== 'string' || !origin) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'projectRoot must be a non-empty string.', { stage: 'options' });
  }

  let root = await realpathExistingAsync(origin, {
    type: 'directory',
    field: 'projectRoot',
    stage: 'options',
  });

  let file = path.join(root, 'package.json');
  while (!fs.existsSync(file) && path.dirname(root) !== root) {
    root = path.dirname(root);
    file = path.join(root, 'package.json');
  }

  if (!fs.existsSync(file)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', `No package.json exists at projectRoot: ${root}`, { stage: 'options' });
  }

  const pkg = await readJsonAsync(file, 'INVALID_OPTIONS', 'options');
  const expo = pkg.expo === undefined ? {} : validateConfigObject(pkg.expo, 'package.json#expo');
  const shared = expo.autolinking === undefined ? {} : validateConfigObject(expo.autolinking, 'package.json#expo.autolinking');
  const platform = shared.harmony === undefined ? {} : validateConfigObject(shared.harmony, 'package.json#expo.autolinking.harmony');

  const configured = Object.fromEntries(ListFields.map(field => [field, configuredList(platform, shared, field)]));

  const lists = {
    searchPaths: input.searchPaths === undefined
      ? configured.searchPaths
      : [...normalizeStringArray(input.searchPaths, 'searchPaths'), ...configured.searchPaths],
    exclude: input.exclude === undefined
      ? configured.exclude
      : [...configured.exclude, ...normalizeStringArray(input.exclude, 'exclude')],
    include: input.include === undefined
      ? configured.include
      : [...configured.include, ...normalizeStringArray(input.include, 'include')],
  };

  assertSafeRnohPackageList(lists.include, 'include');
  assertSafeRnohPackageList(lists.exclude, 'exclude');

  const paths = [];

  for (const value of lists.searchPaths) {
    const target = path.resolve(root, value);
    paths.push(fs.existsSync(target) ? await fs.promises.realpath(target) : target);
  }

  const searchPaths = uniqueStrings(paths);
  const directory = selectConfiguredValue(input, platform, shared, 'nativeModulesDir', './modules');
  let native = normalizeNativeModulesDirectory(directory, root);

  if (native && fs.existsSync(native)) {
    native = await fs.promises.realpath(native);
  }

  const inlineOverride = selectConfiguredValue(input, platform, shared, 'inlineModules', undefined);
  const buildType = normalizeBuildType(selectConfiguredValue(input, platform, shared, 'buildType', 'debug'));
  let expoInlineModules: InlineModulesOptions | null | undefined;
  let persistedExpoInlineModules: InlineModulesOptions | null | undefined;
  if (input.expoInlineModules !== undefined) {
    expoInlineModules = normalizeInlineModules(input.expoInlineModules, root);
    // Keep the raw app config live unless a plugin changed the effective experiment.
    if (input.moduleBuilds !== undefined
      && !isDeepStrictEqual(expoInlineModules, readRawExpoInlineModules(root, buildType))) {
      persistedExpoInlineModules = expoInlineModules && {
        ...expoInlineModules,
        watchedDirectories: expoInlineModules.watchedDirectories.map(directory => normalizeSlashes(path.relative(root, directory)) || '.'),
      };
    }
  } else if (inlineOverride === undefined || input.moduleBuilds !== undefined) {
    persistedExpoInlineModules = (await readModuleBuildOptionsAsync(root))?.expoInlineModules;
    if (persistedExpoInlineModules !== undefined) {
      expoInlineModules = normalizeInlineModules(persistedExpoInlineModules, root);
    }
  }
  const inlineModules = inlineOverride !== undefined
    ? normalizeInlineModules(inlineOverride, root)
    : expoInlineModules !== undefined
      ? expoInlineModules
      : readRawExpoInlineModules(root, buildType);

  return {
    projectRoot: root,
    platform: Platform,
    searchPaths,
    nativeModulesDir: native,
    exclude: uniqueStrings(lists.exclude),
    include: uniqueStrings(lists.include),
    moduleOverrides: normalizeModuleOverrides(platform.modules),
    buildType,
    inlineModules,
    persistedExpoInlineModules,
  };
}

export {
  assertSafeRnohPackageList,
  normalizeOptionsAsync,
  normalizeModuleOverrides,
  readModuleBuildOptionsAsync,
};

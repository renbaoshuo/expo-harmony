import * as fs from 'node:fs';
import * as path from 'node:path';

import { Platform } from './constants';
import { HarmonyAutolinkingError } from '../errors';
import { isObject, readJsonAsync, realpathExistingAsync, normalizeStringArray, uniqueStrings } from '../utilities/values';

const ListFields = ['searchPaths', 'exclude', 'include'];
const NpmPackageNamePattern = /^(?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*$/u;
const RnohPackageListDelimiterPattern = /[;\0\r\n]/;

function selectConfiguredValue(rawOptions, platform, sharedConfig, field, fallback) {
  if (rawOptions[field] !== undefined) return rawOptions[field];
  if (platform[field] !== undefined) return platform[field];
  if (sharedConfig[field] !== undefined) return sharedConfig[field];
  return fallback;
}

function configuredList(platform, sharedConfig, field) {
  const normalize = (value) => {
    if (value === undefined) return [];
    const values = field === 'searchPaths' && typeof value === 'string'
      ? [value]
      : Array.isArray(value) ? value : [];
    return values.filter(item => typeof item === 'string' && item.trim());
  };

  if (field === 'include') {
    return [
      ...normalize(sharedConfig.include),
      ...normalize(platform.include),
    ];
  }

  return normalize(platform[field] !== undefined ? platform[field] : sharedConfig[field]);
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

function normalizeNativeModulesDirectory(value, projectRoot) {
  if (value === null) return null;

  if (typeof value !== 'string' || !value.trim()) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'nativeModulesDir must be a non-empty string or null.', { stage: 'options' });
  }
  return path.resolve(projectRoot, value);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function normalizeModuleOverrides(value, options: Record<string, any> = {}) {
  const code = options.code || 'INVALID_OPTIONS';
  const field = options.field || 'package.json#expo.autolinking.harmony.modules';
  const stage = options.stage || 'options';

  if (value === undefined) return Object.freeze({});
  if (!isObject(value)) {
    throw new HarmonyAutolinkingError(code, `${field} must be an object.`, { stage });
  }
  const overrides = {};

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

    overrides[packageName] = Object.freeze({ ...metadata });
  }
  return Object.freeze(overrides);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function normalizeOptionsAsync(rawOptions: Record<string, any> = {}) {
  if (!isObject(rawOptions)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'Options must be an object.', { stage: 'options' });
  }

  if (rawOptions.logger !== undefined) {
    if (!isObject(rawOptions.logger)
      || ['debug', 'info', 'warn', 'error'].some((level) => {
        return rawOptions.logger[level] !== undefined && typeof rawOptions.logger[level] !== 'function';
      })) {
      throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'logger must expose only callable debug/info/warn/error methods.', { stage: 'options' });
    }
  }

  if (rawOptions.platform != null && rawOptions.platform !== Platform) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'Only platform "harmony" is supported.', { stage: 'options' });
  }

  const rawRoot = rawOptions.projectRoot === undefined ? process.cwd() : rawOptions.projectRoot;
  if (typeof rawRoot !== 'string' || !rawRoot) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'projectRoot must be a non-empty string.', { stage: 'options' });
  }

  let projectRoot = await realpathExistingAsync(rawRoot, {
    type: 'directory',
    field: 'projectRoot',
    stage: 'options',
  });

  let pkgPath = path.join(projectRoot, 'package.json');
  while (!fs.existsSync(pkgPath) && path.dirname(projectRoot) !== projectRoot) {
    projectRoot = path.dirname(projectRoot);
    pkgPath = path.join(projectRoot, 'package.json');
  }

  if (!fs.existsSync(pkgPath)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', `No package.json exists at projectRoot: ${projectRoot}`, { stage: 'options' });
  }

  const packageJson = await readJsonAsync(pkgPath, 'INVALID_OPTIONS', 'options');
  const expo = packageJson.expo === undefined ? {} : validateConfigObject(packageJson.expo, 'package.json#expo');
  const shared = expo.autolinking === undefined ? {} : validateConfigObject(expo.autolinking, 'package.json#expo.autolinking');
  const platform = shared.harmony === undefined ? {} : validateConfigObject(shared.harmony, 'package.json#expo.autolinking.harmony');

  const configured = Object.fromEntries(ListFields.map(field => [field, configuredList(platform, shared, field)]));

  const lists = {
    searchPaths: rawOptions.searchPaths === undefined
      ? configured.searchPaths
      : [...normalizeStringArray(rawOptions.searchPaths, 'searchPaths'), ...configured.searchPaths],
    exclude: rawOptions.exclude === undefined
      ? configured.exclude
      : [...configured.exclude, ...normalizeStringArray(rawOptions.exclude, 'exclude')],
    include: rawOptions.include === undefined
      ? configured.include
      : [...configured.include, ...normalizeStringArray(rawOptions.include, 'include')],
  };
  assertSafeRnohPackageList(lists.include, 'include');
  assertSafeRnohPackageList(lists.exclude, 'exclude');

  const paths = [];
  for (const value of lists.searchPaths) {
    const target = path.resolve(projectRoot, value);
    paths.push(fs.existsSync(target) ? await fs.promises.realpath(target) : target);
  }

  const searchPaths = uniqueStrings(paths);
  const rawDir = selectConfiguredValue(rawOptions, platform, shared, 'nativeModulesDir', './modules');
  let nativeDir = normalizeNativeModulesDirectory(rawDir, projectRoot);

  if (nativeDir && fs.existsSync(nativeDir)) {
    nativeDir = await fs.promises.realpath(nativeDir);
  }

  return {
    projectRoot,
    platform: Platform,
    searchPaths,
    nativeModulesDir: nativeDir,
    exclude: uniqueStrings(lists.exclude),
    include: uniqueStrings(lists.include),
    moduleOverrides: normalizeModuleOverrides(platform.modules),
    buildType: normalizeBuildType(selectConfiguredValue(rawOptions, platform, shared, 'buildType', 'debug')),
  };
}

export {
  assertSafeRnohPackageList,
  normalizeOptionsAsync,
  normalizeModuleOverrides,
};

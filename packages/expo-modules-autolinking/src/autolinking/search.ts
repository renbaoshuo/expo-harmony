import * as expoAutolinking from 'expo-modules-autolinking/exports';
import fs from 'node:fs';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';

import type { SearchOptions, SearchResult } from '../types';
import { Platform } from '../config/constants';
import { HarmonyAutolinkingError } from '../errors';
import { normalizeModuleOverrides, normalizeOptionsAsync } from '../config/options';
import { compareText, emitLog, isObject, isPathInside, pathExistsAsync, readJsonAsync } from '../utilities/values';

function loadUpstreamAutolinkingApi() {
  const upstreamApi = expoAutolinking;

  for (const name of ['makeCachedDependenciesLinker']) {
    if (typeof upstreamApi[name] !== 'function') {
      throw new HarmonyAutolinkingError('INVALID_OPTIONS', `expo-modules-autolinking public export ${name} is unavailable.`, { stage: 'search' });
    }
  }
  return upstreamApi;
}

function supportsHarmony(config) {
  return Array.isArray(config?.platforms) && config.platforms.includes(Platform);
}

function hasHarmonyExpoMetadata(config) {
  return supportsHarmony(config);
}

async function readExpoModuleConfigAsync(packageRoot) {
  const target = path.join(packageRoot, 'expo-module.config.json');
  return await pathExistsAsync(target)
    ? readJsonAsync(target, 'INVALID_METADATA', 'search')
    : null;
}

function nodeModulesDepth(originPath) {
  return String(originPath).split(`${path.sep}node_modules${path.sep}`).length;
}

function isPreferredRevision(left, right) {
  const leftDepth = Number.isInteger(left.depth) ? left.depth : Number.POSITIVE_INFINITY;
  const rightDepth = Number.isInteger(right.depth) ? right.depth : Number.POSITIVE_INFINITY;

  if (leftDepth !== rightDepth) return leftDepth < rightDepth;

  const leftNest = nodeModulesDepth(left.originPath);
  const rightNest = nodeModulesDepth(right.originPath);

  if (leftNest !== rightNest) return leftNest < rightNest;
  if (left.source !== right.source) return left.source < right.source;
  return compareText(left.originPath, right.originPath) < 0;
}

function mergeRevisions(resultSets) {
  const merged = Object.create(null);

  for (const results of resultSets) {
    for (const packageName of Object.keys(results)) {
      const incoming = results[packageName];
      if (!incoming) continue;

      const current = merged[packageName];
      if (!current) {
        merged[packageName] = {
          ...incoming,
          duplicates: [...(incoming.duplicates || [])],
        };
        continue;
      }

      if (current.path === incoming.path) {
        if (!current.version && incoming.version) current.version = incoming.version;
        for (const candidate of incoming.duplicates || []) {
          if (candidate.path !== current.path
            && !current.duplicates.some(item => item.path === candidate.path)) {
            current.duplicates.push(candidate);
          }
        }
        continue;
      }

      let winner = current;
      let duplicate = incoming;
      if (isPreferredRevision(incoming, current)) {
        winner = { ...incoming, duplicates: [...(incoming.duplicates || [])] };
        duplicate = current;
        merged[packageName] = winner;
      }

      const candidates = [
        { ...duplicate, duplicates: undefined },
        ...(duplicate.duplicates || []),
      ];
      for (const candidate of candidates) {
        if (candidate.path !== winner.path
          && !(winner.duplicates || []).some(item => item.path === candidate.path)) {
          winner.duplicates.push(candidate);
        }
      }
    }
  }
  return merged;
}

function classifySource(revision, packageRoot, options) {
  if (revision.source === 2) {
    return 'reactNativeProjectConfig';
  }
  if (options.nativeModulesDir
    && isPathInside(options.nativeModulesDir, packageRoot)) {
    return 'nativeModulesDir';
  }
  if (options.searchPaths.some(searchPath => isPathInside(searchPath, packageRoot))) {
    return 'searchPath';
  }
  return 'dependency';
}

async function resolveDependencyRevisionsAsync(upstreamApi, options) {
  const linker = upstreamApi.makeCachedDependenciesLinker({ projectRoot: options.projectRoot });
  const resultSets = [];

  if (options.includeReactNativeProjectConfig) {
    resultSets.push(await linker.scanDependenciesFromRNProjectConfig());
  }
  if (options.nativeModulesDir && await pathExistsAsync(options.nativeModulesDir)) {
    resultSets.push(await linker.scanDependenciesInSearchPath(options.nativeModulesDir));
  }

  for (const searchPath of options.searchPaths) {
    if (await pathExistsAsync(searchPath)) {
      resultSets.push(await linker.scanDependenciesInSearchPath(searchPath));
    }
  }

  resultSets.push(await linker.scanDependenciesRecursively());
  return mergeRevisions(resultSets);
}

async function loadOverridesAsync(deps) {
  const overrides = Object.create(null);
  const owners = Object.create(null);
  const required = new Set();

  for (const name of Object.keys(deps).sort(compareText)) {
    const revision = deps[name];
    if (!revision) continue;
    let packageRoot;
    let packageJson;
    try {
      packageRoot = await fs.promises.realpath(revision.path);
      packageJson = await readJsonAsync(path.join(packageRoot, 'package.json'), 'INVALID_METADATA', 'search');
    } catch (_cause) {
      continue;
    }

    const packageName = typeof packageJson.name === 'string' && packageJson.name ? packageJson.name : name;
    const harmony = isObject(packageJson.harmony) ? packageJson.harmony : {};
    const declared = normalizeModuleOverrides(harmony.modules, {
      code: 'INVALID_METADATA',
      field: `${packageName} package.json#harmony.modules`,
      stage: 'search',
    });

    const dependencies = isObject(packageJson.dependencies) ? packageJson.dependencies : {};
    const optional = isObject(packageJson.optionalDependencies) ? packageJson.optionalDependencies : {};
    const peers = isObject(packageJson.peerDependencies) ? packageJson.peerDependencies : {};
    const peerMeta = isObject(packageJson.peerDependenciesMeta) ? packageJson.peerDependenciesMeta : {};

    for (const [target, metadata] of Object.entries(declared)) {
      if (![dependencies, optional, peers].some(group => Object.hasOwn(group, target))) {
        throw new HarmonyAutolinkingError('INVALID_METADATA', `${packageName} declares Harmony module ${target} but does not list it in a production dependency field.`, { packageName, stage: 'search' });
      }
      if (Object.hasOwn(dependencies, target)
        || (Object.hasOwn(peers, target) && peerMeta[target]?.optional !== true)) {
        required.add(target);
      }
      if (overrides[target] !== undefined && !isDeepStrictEqual(overrides[target], metadata)) {
        throw new HarmonyAutolinkingError('INVALID_METADATA', `${packageName} and ${owners[target]} declare conflicting Harmony metadata for ${target}.`, { packageName: target, stage: 'search' });
      }
      overrides[target] = metadata;
      owners[target] = packageName;
    }
  }

  return {
    requiredTargets: required,
    overrides: Object.freeze(overrides),
    owners: Object.freeze(owners),
  };
}

async function createSearchRecordAsync(revision, options) {
  let packageRoot;
  try {
    packageRoot = await fs.promises.realpath(revision.path);
  } catch (_cause) {
    return null;
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let packageJson: Record<string, any> = {};
  try {
    packageJson = await readJsonAsync(path.join(packageRoot, 'package.json'), 'INVALID_METADATA', 'search');
  } catch (_cause) {
    // Expo's search-path scanner tolerates roots without a readable
    // package.json and falls back to the dependency revision name.
  }

  const packageName = typeof packageJson.name === 'string' && packageJson.name
    ? packageJson.name
    : revision.name;
  if (options.exclude.includes(revision.name || packageName)) return null;
  const expo = await readExpoModuleConfigAsync(packageRoot);
  const harmony = hasHarmonyExpoMetadata(expo);
  const metadata = isObject(packageJson.harmony) ? packageJson.harmony : null;
  const sidecar = options.moduleOverrides[packageName];

  let rnohMetadata = metadata?.autolinking === undefined ? null : metadata.autolinking;
  if (sidecar !== undefined) {
    const { version: _version, ...metadata } = sidecar;
    rnohMetadata = metadata;
  }

  const included = options.include.includes(revision.name || packageName);

  return {
    packageName,
    packageVersion: typeof packageJson.version === 'string' ? packageJson.version : String(revision.version || ''),
    packageRoot,
    source: classifySource(revision, packageRoot, options),
    supportsHarmony: harmony,
    expoModuleConfig: expo,
    rnohMetadata,
    nativeCandidate: harmony || rnohMetadata != null,
    includedForVerification: included,
    revision: {
      depth: Number.isInteger(revision.depth) ? revision.depth : null,
      originPath: typeof revision.originPath === 'string' ? revision.originPath : packageRoot,
    },
  };
}

function compareSearchRecords(left, right) {
  return compareText(left.packageName, right.packageName)
    || compareText(left.packageVersion, right.packageVersion)
    || compareText(left.packageRoot, right.packageRoot);
}

function findDuplicates(records) {
  const byName = new Map();

  for (const record of records) {
    const revisions = byName.get(record.packageName) || [];
    revisions.push({ version: record.packageVersion, path: record.packageRoot });
    byName.set(record.packageName, revisions);
  }

  return [...byName.entries()]
    .filter(([, revisions]) => new Set(revisions.map(revision => `${revision.version}\0${revision.path}`)).size > 1)
    .map(([packageName, revisions]) => ({
      packageName,
      revisions: revisions.sort((left, right) => compareText(left.version, right.version)
        || compareText(left.path, right.path)),
    }))
    .sort((left, right) => compareText(left.packageName, right.packageName));
}

type SearchImplementationOptions = SearchOptions & {
  includeReactNativeProjectConfig?: boolean;
};

async function searchModulesAsync(rawOptions: SearchOptions = {}): Promise<SearchResult> {
  const input = rawOptions as SearchImplementationOptions;
  const options = {
    ...await normalizeOptionsAsync(rawOptions),
    includeReactNativeProjectConfig: input.includeReactNativeProjectConfig === true,
  };

  const upstreamApi = loadUpstreamAutolinkingApi();
  const deps = await resolveDependencyRevisionsAsync(upstreamApi, options);
  const overrides = await loadOverridesAsync(deps);

  const modules = Object.freeze({
    ...overrides.overrides,
    ...options.moduleOverrides,
  });
  const search = { ...options, moduleOverrides: modules };
  const selected = new Map();
  const unique = new Map();

  for (const name of Object.keys(deps).sort(compareText)) {
    const resolution = deps[name];
    if (!resolution) continue;

    const revisions = [
      resolution,
      ...(resolution.duplicates || []).map(duplicate => ({
        ...resolution,
        ...duplicate,
        duplicates: null,
      })),
    ];

    const records = (await Promise.all(revisions.map(revision => createSearchRecordAsync(revision, search))))
      .filter(Boolean);
    const winner = records[0];
    let chosen = winner?.nativeCandidate || winner?.includedForVerification ? winner : null;

    if (!chosen && resolution.source === 1) {
      chosen = records.slice(1).find(record => record.nativeCandidate || record.includedForVerification) || null;
    }
    if (!chosen) continue;

    if (chosen.nativeCandidate) selected.set(chosen.packageName, chosen);
    for (const record of records) {
      const key = `${record.packageName}\0${record.packageVersion}\0${record.packageRoot}`;
      if (!unique.has(key)) unique.set(key, record);
    }
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  for (const [packageName, sidecar] of Object.entries(modules) as Array<[string, Record<string, any>]>) {
    const record = selected.get(packageName);
    if (record && sidecar.version !== undefined && sidecar.version !== record.packageVersion) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `Harmony sidecar module ${packageName} targets ${sidecar.version}, but ${record.packageVersion} is installed.`, { packageName, stage: 'search' });
    }
  }

  const all = [...unique.values()];
  const found = new Set(all.map(record => record.packageName));
  for (const [packageName, owner] of Object.entries(overrides.owners)) {
    if (!found.has(packageName) && overrides.requiredTargets.has(packageName)) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `${owner} declares Harmony module ${packageName}, but that dependency is not installed.`, { packageName, stage: 'search' });
    }
  }

  const verified = all.filter(record =>
    modules[record.packageName] === undefined || selected.get(record.packageName)?.packageRoot === record.packageRoot);
  const records = [...selected.values()].map(({
    includedForVerification: _includedForVerification,
    nativeCandidate: _nativeCandidate,
    ...record
  }) => record).sort(compareSearchRecords);

  const result: SearchResult = {
    platform: Platform,
    modules: records,
    duplicates: findDuplicates(verified),
    missingIncludes: options.include.filter(name => !found.has(name)).sort(compareText),
    options: {
      projectRoot: options.projectRoot,
      searchPaths: options.searchPaths,
      nativeModulesDir: options.nativeModulesDir,
      exclude: options.exclude,
      include: options.include,
      buildType: options.buildType,
    },
  };

  emitLog(rawOptions.logger, 'debug', 'Harmony module search completed.', { moduleCount: records.length, duplicateCount: result.duplicates.length });
  return result;
}

export {
  searchModulesAsync,
};

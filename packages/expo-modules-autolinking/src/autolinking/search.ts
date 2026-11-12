/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as expoAutolinking from 'expo-modules-autolinking/exports';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';

import type { SearchOptions, SearchResult } from '../types';
import { Platform } from '../config/constants';
import { searchInlineModulesAsync } from '../harmony/inlineModules';
import { HarmonyAutolinkingError } from '../errors';
import { normalizeModuleOverrides, normalizeOptionsAsync } from '../config/options';
import { compareText, emitLog, isObject, isPathInside, pathExistsAsync, readJsonAsync, resolveInsideAsync } from '../utilities/values';

// SDK 57 exposes DependencyResolutionSource as a type-only const enum.
const DependencySource = { recursive: 0, searchPath: 1, reactNativeConfig: 2 } as const satisfies
  Record<string, expoAutolinking.DependencyResolutionSource>;

function supportsHarmony(config) {
  return Array.isArray(config?.platforms) && config.platforms.includes(Platform);
}

async function readExpoModuleConfigAsync(root) {
  for (const filename of ['expo-module.config.json', 'unimodule.json']) {
    const target = path.join(root, filename);
    if (await pathExistsAsync(target)) return readJsonAsync(target, 'INVALID_METADATA', 'search');
  }
  return null;
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

function mergeRevisions(sets) {
  const merged = Object.create(null);

  for (const results of sets) {
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
        if (isPreferredRevision(incoming, current)) {
          Object.assign(current, { depth: incoming.depth, originPath: incoming.originPath, source: incoming.source });
        }
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

function classifySource(revision, root, options) {
  if (revision.source === DependencySource.reactNativeConfig) {
    return 'reactNativeProjectConfig';
  }
  if (options.nativeModulesDir
    && (isPathInside(options.nativeModulesDir, root) || isPathInside(options.nativeModulesDir, revision.originPath))) {
    return 'nativeModulesDir';
  }
  // A search-path symlink may have a canonical root outside that search path.
  if (options.searchPaths.some(searchPath =>
    isPathInside(searchPath, root) || isPathInside(searchPath, revision.originPath))) {
    return 'searchPath';
  }
  return 'dependency';
}

async function resolveDependencyRevisionsAsync(options) {
  const linker = expoAutolinking.makeCachedDependenciesLinker({ projectRoot: options.projectRoot });
  const paths = [...new Set([options.nativeModulesDir, ...options.searchPaths].filter(Boolean))];
  const [projectConfig, ...sets] = await Promise.all([
    linker.loadReactNativeProjectConfig(),
    linker.scanDependenciesFromRNProjectConfig(),
    ...paths.map(searchPath => linker.scanDependenciesInSearchPath(searchPath)),
    linker.scanDependenciesRecursively(),
  ]);

  return {
    revisions: mergeRevisions(sets),
    projectConfig,
  };
}

async function resolveSidecarTargetAsync(requireFromOwner: NodeRequire, name: string) {
  // Resolve the npm revision even when the library does not export package.json.
  for (const directory of requireFromOwner.resolve.paths(name) ?? []) {
    const originPath = path.join(directory, name);
    try {
      const root = await fs.promises.realpath(originPath);
      const version = JSON.parse(await fs.promises.readFile(path.join(root, 'package.json'), 'utf8')).version;
      return { name, version, path: root, originPath };
    } catch (cause) {
      if (cause.code !== 'ENOENT' && cause.code !== 'ENOTDIR') throw cause;
    }
  }
  return null;
}

async function loadOverridesAsync(deps: expoAutolinking.ResolutionResult, options) {
  const overrides = new Map<string, { metadata: Readonly<Record<string, unknown>>; owner: string; root: string }>();
  const resolved: expoAutolinking.ResolutionResult[] = [];
  const visited = new Set<string>();

  for (const name of Object.keys(deps).sort(compareText)) {
    const revision = deps[name];
    if (!revision) continue;

    let root;
    let pkg;

    try {
      root = await fs.promises.realpath(revision.path);
      if (visited.has(root)) continue;
      visited.add(root);
      pkg = await readJsonAsync(path.join(root, 'package.json'), 'INVALID_METADATA', 'search');
    } catch (_cause) {
      continue;
    }

    const packageName = typeof pkg.name === 'string' && pkg.name ? pkg.name : name;
    const harmony = isObject(pkg.harmony) ? pkg.harmony : {};
    const declared = normalizeModuleOverrides(harmony.modules, {
      code: 'INVALID_METADATA',
      field: `${packageName} package.json#harmony.modules`,
      stage: 'search',
      allowPackageRoot: true,
    });

    const dependencies = isObject(pkg.dependencies) ? pkg.dependencies : {};
    const optional = isObject(pkg.optionalDependencies) ? pkg.optionalDependencies : {};
    const peers = isObject(pkg.peerDependencies) ? pkg.peerDependencies : {};
    const peerMeta = isObject(pkg.peerDependenciesMeta) ? pkg.peerDependenciesMeta : {};
    const requireFromOwner = createRequire(path.join(root, 'package.json'));

    for (const [target, metadata] of Object.entries(declared)) {
      if (options.exclude.includes(target) || Object.hasOwn(options.moduleOverrides, target)) continue;
      if (![dependencies, optional, peers].some(group => Object.hasOwn(group, target))) {
        throw new HarmonyAutolinkingError('INVALID_METADATA', `${packageName} declares Harmony module ${target} but does not list it in a production dependency field.`, { packageName, stage: 'search' });
      }
      const dependency = await resolveSidecarTargetAsync(requireFromOwner, target);
      if (!dependency) {
        if (Object.hasOwn(dependencies, target)
          || (Object.hasOwn(peers, target) && peerMeta[target]?.optional !== true)) {
          throw new HarmonyAutolinkingError('INVALID_METADATA', `${packageName} declares Harmony module ${target}, but that dependency is not installed.`, { packageName: target, stage: 'search' });
        }
        continue;
      }
      if (metadata.version !== undefined && metadata.version !== dependency.version) {
        throw new HarmonyAutolinkingError('INVALID_METADATA', `Harmony sidecar module ${target} declared by ${packageName} targets ${metadata.version}, but ${dependency.version} is installed at ${dependency.path}.`, { packageName: target, stage: 'search' });
      }

      const previous = overrides.get(dependency.path);
      if (previous && (!isDeepStrictEqual(previous.metadata, metadata)
        || (metadata.packageRoot !== undefined && previous.root !== root))) {
        throw new HarmonyAutolinkingError('INVALID_METADATA', `${packageName} and ${previous.owner} declare conflicting Harmony metadata for ${target} at ${dependency.path}.`, { packageName: target, stage: 'search' });
      }
      overrides.set(dependency.path, { metadata, owner: packageName, root });

      // The upstream recursive scan skips optional-only dependencies.
      if (![deps[target], ...(deps[target]?.duplicates ?? [])].some(candidate => candidate?.path === dependency.path)) {
        resolved.push({
          [target]: { ...dependency, source: DependencySource.recursive, depth: revision.depth + 1, duplicates: null },
        });
      }
    }
  }

  return { overrides, resolved };
}

async function createSearchRecordAsync(revision, options, appOverrideAllowed) {
  let root;

  try {
    root = await fs.promises.realpath(revision.path);
  } catch (_cause) {
    return null;
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let pkg: Record<string, any> = {};

  try {
    pkg = await readJsonAsync(path.join(root, 'package.json'), 'INVALID_METADATA', 'search');
  } catch (_cause) {
    // Upstream traversal can report a leftover dependency directory without a manifest.
    return null;
  }
  if (!isObject(pkg)) return null;

  const packageName = typeof pkg.name === 'string' && pkg.name
    ? pkg.name
    : revision.name;
  if (options.exclude.includes(revision.name) || options.exclude.includes(packageName)) return null;

  const expo = await readExpoModuleConfigAsync(root);
  const harmony = supportsHarmony(expo);
  const metadata = isObject(pkg.harmony) ? pkg.harmony : null;
  const producer = options.sidecars.get(root);
  const appOverride = appOverrideAllowed
    && (options.moduleOverrides[revision.name] ?? options.moduleOverrides[packageName]);
  const sidecar = appOverride || producer?.metadata;

  let rnohMetadata = metadata?.autolinking === undefined ? null : metadata.autolinking;
  if (sidecar !== undefined) {
    const { version: _version, packageRoot: _packageRoot, ...metadata } = sidecar;
    rnohMetadata = metadata;
  }

  const dependencyConfig = options.projectConfig?.dependencies?.[revision.name || packageName];
  const override = dependencyConfig?.platforms?.harmony;
  if (override === null) rnohMetadata = null;
  else if (isObject(override)) rnohMetadata = { ...(rnohMetadata || {}), ...override };

  const included = options.include.includes(revision.name) || options.include.includes(packageName);
  if (appOverride && rnohMetadata !== null
    && appOverride.version !== undefined && appOverride.version !== pkg.version) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `Harmony sidecar module ${packageName} targets ${appOverride.version}, but ${pkg.version} is installed at ${root}.`, { packageName, stage: 'search' });
  }

  const packageRoot = !appOverride && producer?.metadata.packageRoot !== undefined && rnohMetadata !== null
    ? await resolveInsideAsync(producer.root, producer.metadata.packageRoot, 'sidecar packageRoot', {
        packageName, stage: 'search', type: 'directory',
      })
    : root;

  return {
    packageName,
    packageVersion: typeof pkg.version === 'string' ? pkg.version : String(revision.version || ''),
    packageRoot,
    source: classifySource(revision, root, options),
    supportsHarmony: harmony,
    expoModuleConfig: expo,
    rnohMetadata,
    npmRoot: root,
    producerSidecar: !appOverride && !!producer && rnohMetadata !== null,
    nativeCandidate: harmony || rnohMetadata != null,
    includedForVerification: included,
    revision: {
      depth: Number.isInteger(revision.depth) ? revision.depth : null,
      originPath: typeof revision.originPath === 'string' ? revision.originPath : root,
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
    revisions.push({ version: record.packageVersion, path: record.npmRoot });
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

async function searchModulesAsync(rawOptions: SearchOptions = {}): Promise<SearchResult> {
  const options = await normalizeOptionsAsync(rawOptions);
  const { revisions, projectConfig } = await resolveDependencyRevisionsAsync(options);
  const { overrides, resolved } = await loadOverridesAsync(revisions, options);
  const deps = mergeRevisions([revisions, ...resolved]);
  const search = { ...options, sidecars: overrides, projectConfig };
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

    const records = (await Promise.all(
      revisions.map((revision, index) => createSearchRecordAsync(revision, search, index === 0))
    )).filter(Boolean);

    const winner = records[0];
    const sidecars = records.filter(record => record.producerSidecar);
    if (sidecars.length > 0 && resolution.source !== DependencySource.reactNativeConfig) {
      const competing = records.filter(
        record => record.nativeCandidate && record.packageName === sidecars[0].packageName
      );
      if (new Set(competing.map(record => record.npmRoot)).size > 1) {
        throw new HarmonyAutolinkingError('INVALID_METADATA', `Competing native revisions of ${sidecars[0].packageName}: ${competing.map(record => record.npmRoot).join(', ')}. Use a single native revision or configure an explicit app override.`, { packageName: sidecars[0].packageName, stage: 'search' });
      }
    }
    const chosen = winner?.nativeCandidate
      ? winner
      : sidecars[0] ?? (resolution.source === DependencySource.searchPath
        ? records.slice(1).find(record => record.nativeCandidate)
        : null);
    if (chosen) selected.set(chosen.packageName, chosen);
    if (!chosen && !records.some(record => record.includedForVerification)) continue;

    for (const record of records) {
      const key = `${record.packageName}\0${record.packageVersion}\0${record.npmRoot}`;
      if (!unique.has(key)) unique.set(key, record);
    }
  }

  const all = [...unique.values()];
  const found = new Set(all.map(record => record.packageName));
  const records = [...selected.values()].map(({
    includedForVerification: _includedForVerification,
    nativeCandidate: _nativeCandidate,
    npmRoot: _npmRoot,
    producerSidecar: _producerSidecar,
    ...record
  }) => record).sort(compareSearchRecords);

  const inline = await searchInlineModulesAsync(options.projectRoot, options.inlineModules);
  if (inline) {
    records.push(inline);
    records.sort(compareSearchRecords);
  }

  const result: SearchResult = {
    platform: Platform,
    modules: records,
    duplicates: findDuplicates(all),
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

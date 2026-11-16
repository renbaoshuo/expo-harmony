/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import type { InputConfigT } from 'metro-config';

import { DefaultReactNativeHarmonyPackage, HarmonyPlatform, HarmonyScreensPackage } from './constants';
import {
  createWithHarmonyConfig,
  type CreateHarmonyMetroConfig,
  type MergeConfig,
  type WithHarmonyConfigOptions,
} from './createWithHarmonyConfig';
import { ExpoHarmonyMetroError } from './errors';
import { getEntries, type HarmonyRedirect } from './resolver';
import { getHarmonyPackageRoot } from './runtime';

interface MetroConfigPeer {
  mergeConfig: MergeConfig;
}

interface HarmonyMetroConfigPeer {
  createHarmonyMetroConfig: CreateHarmonyMetroConfig;
}

interface AutolinkingPlatforms {
  getSupportPackageForPlatform: (platform: string) => string | null;
}

type WithHarmonyConfig = ReturnType<typeof createWithHarmonyConfig>;

const Implementations = new Map<string, WithHarmonyConfig>();
const RouterPackage = '@expo-harmony/expo-router';
const RedirectCarriers = ['@expo-harmony/expo', '@expo-harmony/expo-modules-core', RouterPackage];
// eslint-disable-next-line @typescript-eslint/no-require-imports -- semver does not bundle TypeScript declarations.
const { satisfies } = require('semver') as { satisfies(version: string, range: string): boolean };

interface PackageManifest {
  dependencies?: Record<string, string>;
  devDependencies?: Record<string, string>;
  name?: string;
  optionalDependencies?: Record<string, string>;
  harmony?: {
    metro?: { redirects?: ScopedRedirect[]; entrypoints?: EntryRedirect[] };
    modules?: Record<string, { packageRoot?: string; version?: string }>;
  };
  peerDependencies?: Record<string, string>;
  version?: string;
}

interface EntryRedirect {
  upstream: string;
  target: string;
}

type ScopedRedirect = {
  upstream: string;
  origin: string;
  request: string;
} & ({ target: string; upstreamTarget?: never } | { target?: never; upstreamTarget: string });

function patchAutolinking(root: string, runtime: string): void {
  const require = createRequire(path.join(root, 'package.json'));
  const expo = createRequire(require.resolve('expo/package.json'));

  // SDK 57's wildcard exports append .js, so the directory subpath no longer resolves.
  const autolinking = createRequire(expo.resolve('expo-modules-autolinking/package.json'));
  const platforms = autolinking('./build/platforms') as AutolinkingPlatforms;

  const original = platforms.getSupportPackageForPlatform;
  if (typeof original !== 'function') {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_INCOMPATIBLE_PEER_DEPENDENCY',
      'Expo autolinking must expose getSupportPackageForPlatform().'
    );
  }

  try {
    if (original(HarmonyPlatform) === runtime) return;
  } catch {
    // Expo rejects platforms without a registered support package.
  }

  // Expo re-exports this module with getters, so the CLI sees the replacement.
  platforms.getSupportPackageForPlatform = (platform: string) => platform === HarmonyPlatform
    ? runtime
    : original(platform);
}

function loadPeer<T>(require: NodeRequire, request: string, name = request): T {
  try {
    return require(request) as T;
  } catch (cause) {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_MISSING_PEER_DEPENDENCY',
      `@expo-harmony/metro-config could not load "${name}" from the project's SDK toolchain.`,
      { cause }
    );
  }
}

function getImplementation(root: string, runtime: string): WithHarmonyConfig {
  const key = `${root}\0${runtime}`;
  const cached = Implementations.get(key);
  if (cached) return cached;

  const require = createRequire(path.join(root, 'package.json'));
  const metro = loadPeer<MetroConfigPeer>(require, 'metro-config');
  const runtimeRoot = getHarmonyPackageRoot(runtime, root);
  let configPath = path.join(runtimeRoot, 'metro.config.js');
  if (runtime !== DefaultReactNativeHarmonyPackage) {
    try {
      configPath = require.resolve(`${runtime}/metro.config`);
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      if (code !== 'ERR_PACKAGE_PATH_NOT_EXPORTED' && code !== 'MODULE_NOT_FOUND') throw error;
    }
  }
  const harmony = loadPeer<HarmonyMetroConfigPeer>(require, configPath, `${runtime}/metro.config`);

  const apply = createWithHarmonyConfig({
    createHarmonyMetroConfig: harmony.createHarmonyMetroConfig,
    mergeConfig: metro.mergeConfig,
  });
  Implementations.set(key, apply);

  return apply;
}

function resolveManifest(require: NodeRequire, name: string): string | undefined {
  try {
    return require.resolve(`${name}/package.json`);
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code !== 'MODULE_NOT_FOUND' && code !== 'ERR_PACKAGE_PATH_NOT_EXPORTED') throw error;
  }

  // A package may export its entry while keeping its package.json private.
  let entry: string;
  try {
    entry = require.resolve(name);
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code !== 'MODULE_NOT_FOUND' && code !== 'ERR_PACKAGE_PATH_NOT_EXPORTED') throw error;
    return;
  }

  for (let directory = path.dirname(entry); ; directory = path.dirname(directory)) {
    const manifest = path.join(directory, 'package.json');
    if (fs.existsSync(manifest) && (require(manifest) as PackageManifest).name === name) return manifest;
    if (path.dirname(directory) === directory || path.basename(directory) === 'node_modules') return;
  }
}

function isInside(root: string, file: string): boolean {
  const relative = path.relative(root, file);
  return relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

function resolvePackageFile(root: string, entry: string): string | undefined {
  if (typeof entry !== 'string' || path.isAbsolute(entry)) return;

  const file = path.resolve(root, entry);
  if (!isInside(root, file)) return;

  try {
    if (fs.statSync(file, { throwIfNoEntry: false })?.isFile()) {
      const real = fs.realpathSync(file);
      if (isInside(root, real)) return real;
    }
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOTDIR') throw error;
  }
}

function addScopedRedirects(
  require: NodeRequire,
  manifestPaths: Iterable<string>,
  redirects: Map<string, HarmonyRedirect>,
  hasAlias: (name: string) => boolean
): void {
  const byRequest = new Map<string, {
    upstream: string;
    range: string;
    origin: string;
    target?: string;
    upstreamTarget?: string;
  }[]>();
  for (const manifestPath of manifestPaths) {
    const manifest = require(manifestPath) as PackageManifest;
    const entries = manifest.harmony?.metro?.redirects;
    if (!Array.isArray(entries)) continue;

    for (const entry of entries) {
      if (!entry || typeof entry.request !== 'string' || typeof entry.upstream !== 'string'
        || typeof entry.origin !== 'string'
        || redirects.has(entry.request) || hasAlias(entry.request)) continue;

      const range = manifest.peerDependencies?.[entry.upstream];
      if (typeof range !== 'string') continue;

      const target = entry.target && resolvePackageFile(path.dirname(manifestPath), entry.target);
      if (!target && !entry.upstreamTarget) continue;

      const rules = byRequest.get(entry.request) ?? [];
      rules.push({
        upstream: entry.upstream,
        origin: path.normalize(entry.origin),
        range,
        target,
        upstreamTarget: entry.upstreamTarget,
      });
      byRequest.set(entry.request, rules);
    }
  }
  for (const [request, rules] of byRequest) {
    redirects.set(request, ({ context }) => {
      // Resolve against the importing copy, including nested copies of the Expo peer.
      const origin = context.getPackageForModule(context.originModulePath);
      if (!origin) return;

      const { name, version } = origin.packageJson as PackageManifest;
      if (typeof version !== 'string') return;

      let target: string | undefined;
      for (const rule of rules) {
        if (name !== rule.upstream || origin.packageRelativePath !== rule.origin
          || !satisfies(version, rule.range)) continue;

        const next = rule.upstreamTarget ? resolvePackageFile(origin.rootPath, rule.upstreamTarget) : rule.target;
        if (!next) continue;

        if (target && target !== next) {
          throw new ExpoHarmonyMetroError(
            'ERR_EXPO_HARMONY_CONFLICTING_REDIRECT',
            `Conflicting Harmony redirects for "${request}" from ${context.originModulePath}: ${target} and ${next}.`
          );
        }
        target = next;
      }
      return target;
    });
  }
}

function addEntryRedirects(
  require: NodeRequire,
  manifestPaths: Iterable<string>,
  redirects: Map<string, HarmonyRedirect>,
  hasUserOverride: (name: string) => boolean
): void {
  const registry = new Map<string, { carrier: string; range: string; target: string }[]>();

  for (const manifestPath of manifestPaths) {
    const carrier = path.dirname(manifestPath);
    const manifest = require(manifestPath) as PackageManifest;
    const entries = manifest.harmony?.metro?.entrypoints;
    if (!Array.isArray(entries)) continue;

    for (const entry of entries) {
      if (typeof entry?.upstream !== 'string' || hasUserOverride(entry.upstream)) continue;

      const target = resolvePackageFile(carrier, entry.target);
      const range = manifest.peerDependencies?.[entry.upstream];
      if (!target || typeof range !== 'string') continue;

      const rules = registry.get(entry.upstream) ?? [];
      rules.push({ carrier, range, target });
      registry.set(entry.upstream, rules);
    }
  }

  for (const [name, rules] of registry) {
    const scoped = redirects.get(name);
    redirects.set(name, (request) => {
      const override = typeof scoped === 'function' ? scoped(request) : scoped;
      if (override != null) return override;

      const { context } = request;
      const original = request.resolveHarmony();
      if (original.type !== 'sourceFile') return original;

      const upstream = context.getPackageForModule(original.filePath);
      const manifest = upstream?.packageJson as PackageManifest | undefined;
      if (!upstream || manifest?.name !== name || typeof manifest.version !== 'string') return original;
      if (isInside(upstream.rootPath, context.originModulePath)
        || rules.some(({ carrier }) => isInside(carrier, context.originModulePath))) return original;

      let target: string | undefined;
      for (const rule of rules) {
        if (!satisfies(manifest.version, rule.range)) continue;
        if (target && target !== rule.target) {
          throw new ExpoHarmonyMetroError(
            'ERR_EXPO_HARMONY_CONFLICTING_REDIRECT',
            `Conflicting Harmony entrypoints for "${name}" from ${upstream.rootPath}: ${target} and ${rule.target}.`
          );
        }
        target = rule.target;
      }

      return target ?? original;
    });
  }
}

function getPackageConfig(
  require: NodeRequire,
  projectRoot: string,
  options: WithHarmonyConfigOptions
): { redirects: WithHarmonyConfigOptions['redirects']; getScreensPackageRoot?: () => string } {
  const appManifestPath = path.join(projectRoot, 'package.json');
  const app: PackageManifest = fs.existsSync(appManifestPath) ? require(appManifestPath) : {};

  const names = new Set([
    ...RedirectCarriers,
    ...Object.keys(app.dependencies ?? {}),
    ...Object.keys(app.devDependencies ?? {}),
    ...Object.keys(app.optionalDependencies ?? {}),
  ]);
  const carriers = new Map<string, string>();
  for (const name of names) {
    const manifest = resolveManifest(require, name);
    if (manifest) carriers.set(name, manifest);
  }

  const aliases = getEntries(options.aliases, 'options.aliases').map(([name]) => name);
  const hasAlias = (name: string) => aliases.some(alias => name === alias || name.startsWith(`${alias}/`));
  const redirects = new Map(getEntries<HarmonyRedirect>(options.redirects, 'options.redirects'));
  const userRedirects = new Set(redirects.keys());
  addScopedRedirects(require, carriers.values(), redirects, hasAlias);
  addEntryRedirects(require, carriers.values(), redirects, name => userRedirects.has(name) || hasAlias(name));

  const manifestPath = carriers.get(RouterPackage);
  if (!manifestPath) return { redirects };

  const manifest = require(manifestPath) as PackageManifest;
  const sidecar = manifest.harmony?.modules?.[HarmonyScreensPackage];
  if (!sidecar?.packageRoot) return { redirects };

  const root = path.resolve(path.dirname(manifestPath), sidecar.packageRoot);
  const defaults = ['react-native-screens', HarmonyScreensPackage].flatMap(name => [
    [name, path.join(root, 'src/index.ts')],
    [`${name}/experimental`, path.join(root, 'src/experimental/index.ts')],
  ].filter(([entry]) => !redirects.has(entry) && !hasAlias(entry)));
  let validated = false;
  function getScreensPackageRoot(): string {
    if (validated) return root;

    const manifest = path.join(root, 'package.json');
    const missing = [manifest, ...defaults.map(([, file]) => file)]
      .find(file => !fs.statSync(file, { throwIfNoEntry: false })?.isFile());
    const built = missing ? undefined : JSON.parse(fs.readFileSync(manifest, 'utf8'));
    if (missing || !sidecar?.version || built?.name !== HarmonyScreensPackage || built?.version !== sidecar.version) {
      throw new ExpoHarmonyMetroError(
        'ERR_EXPO_HARMONY_INVALID_SCREENS_SIDECAR',
        `The patched Screens package from ${RouterPackage} is missing or out of date at ${root}. `
        + `Reinstall ${RouterPackage} or run its build script in the monorepo.`
      );
    }

    validated = true;
    return root;
  }
  for (const [name, file] of defaults) {
    redirects.set(name, () => {
      getScreensPackageRoot();
      return file;
    });
  }
  return { redirects, getScreensPackageRoot: hasAlias(HarmonyScreensPackage) ? undefined : getScreensPackageRoot };
}

export function withHarmonyConfig<T extends InputConfigT>(
  config: T,
  options: WithHarmonyConfigOptions = {}
): T & InputConfigT {
  if (options.enabled === false) return config;

  const root = path.resolve(options.projectRoot ?? config.projectRoot ?? process.cwd());
  const runtime = options.reactNativeHarmonyPackageName ?? DefaultReactNativeHarmonyPackage;

  const require = createRequire(path.join(root, 'package.json'));
  const apply = getImplementation(root, runtime);
  const { redirects, getScreensPackageRoot } = getPackageConfig(require, root, options);
  const result = apply(config, { ...options, redirects, projectRoot: root }, getScreensPackageRoot);
  patchAutolinking(root, runtime);
  return result;
}

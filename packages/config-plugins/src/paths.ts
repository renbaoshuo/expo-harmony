import fs from 'node:fs';
import path from 'node:path';

import { HarmonyConfigPluginError } from './errors';

export interface HarmonyManagedPaths {
  readonly appJson: string;
  readonly projectBuildProfile: string;
  readonly rootOhPackage: string;
  readonly rootHvigor: string;
  readonly hvigorConfig: string;
  readonly entryBuildProfile: string;
  readonly entryOhPackage: string;
  readonly entryHvigor: string;
  readonly moduleJson: string;
  readonly profiles: string;
  readonly entryAbility: string;
  readonly indexPage: string;
  readonly worker: string;
  readonly arktsPackageProvider: string;
  readonly cppPackageProvider: string;
  readonly cmakeLists: string;
}

export interface HarmonyProjectPaths {
  readonly reactNativeConfig: string;
}

export interface HarmonyProjectPathCandidates {
  readonly reactNativeConfig: readonly string[];
}

export interface HarmonyResourcePaths {
  readonly strings: Readonly<{ app: string; entry: string }>;
  readonly colors: Readonly<{ entry: string; entryDark: string }>;
  readonly media: Readonly<{ app: string; entry: string; entryDark: string }>;
}

export interface HarmonyPathsApi {
  readonly HARMONY_PATHS: HarmonyManagedPaths;
  readonly PROJECT_PATH_CANDIDATES: HarmonyProjectPathCandidates;
  readonly PROJECT_PATHS: HarmonyProjectPaths;
  readonly RESOURCE_PATHS: HarmonyResourcePaths;
  assertNoExternalSymlink(root: string, target: string): Promise<void>;
  isInside(root: string, target: string): boolean;
  resolveHarmonyPath(platformProjectRoot: string, relativePath: string): Promise<string>;
  resolveProjectPath(projectRoot: string, modName: keyof HarmonyProjectPaths): Promise<string>;
  toPosixRelative(projectRoot: string, target: string): string;
}

const ManagedPaths: HarmonyManagedPaths = Object.freeze({
  appJson: 'AppScope/app.json5',
  projectBuildProfile: 'build-profile.json5',
  rootOhPackage: 'oh-package.json5',
  rootHvigor: 'hvigorfile.ts',
  hvigorConfig: 'hvigor/hvigor-config.json5',
  entryBuildProfile: 'entry/build-profile.json5',
  entryOhPackage: 'entry/oh-package.json5',
  entryHvigor: 'entry/hvigorfile.ts',
  moduleJson: 'entry/src/main/module.json5',
  profiles: 'entry/src/main/resources/base/profile/main_pages.json',
  entryAbility: 'entry/src/main/ets/entryability/EntryAbility.ets',
  indexPage: 'entry/src/main/ets/pages/Index.ets',
  worker: 'entry/src/main/ets/workers/RNOHWorker.ets',
  arktsPackageProvider: 'entry/src/main/ets/PackageProvider.ets',
  cppPackageProvider: 'entry/src/main/cpp/PackageProvider.cpp',
  cmakeLists: 'entry/src/main/cpp/CMakeLists.txt',
});

const ProjectPaths: HarmonyProjectPaths = Object.freeze({
  reactNativeConfig: 'react-native.config.js',
});

const ProjectPathCandidates: HarmonyProjectPathCandidates = Object.freeze({
  // Keep this order aligned with @react-native-community/cli-config's async
  // search places. The first entry is also the file created for new projects.
  reactNativeConfig: Object.freeze([
    'react-native.config.js',
    'react-native.config.cjs',
    'react-native.config.ts',
    'react-native.config.mjs',
  ]),
});

const ResourcePaths: HarmonyResourcePaths = Object.freeze({
  strings: Object.freeze({
    app: 'AppScope/resources/base/element/string.json',
    entry: 'entry/src/main/resources/base/element/string.json',
  }),
  colors: Object.freeze({
    entry: 'entry/src/main/resources/base/element/color.json',
    entryDark: 'entry/src/main/resources/dark/element/color.json',
  }),
  media: Object.freeze({
    app: 'AppScope/resources/base/media',
    entry: 'entry/src/main/resources/base/media',
    entryDark: 'entry/src/main/resources/dark/media',
  }),
});

export function isInside(root: string, target: string): boolean {
  const relative = path.relative(root, target);

  return relative === ''
    || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

export async function assertNoExternalSymlink(root: string, target: string): Promise<void> {
  const absoluteRoot = path.resolve(root);
  const rootReal = await fs.promises.realpath(absoluteRoot).catch(() => absoluteRoot);
  const relative = path.relative(absoluteRoot, target);
  let cursor = absoluteRoot;

  for (const segment of relative.split(path.sep).filter(Boolean)) {
    cursor = path.join(cursor, segment);
    let stat: fs.Stats;
    try {
      stat = await fs.promises.lstat(cursor);
    } catch (cause) {
      if ((cause as NodeJS.ErrnoException).code === 'ENOENT') break;

      return Promise.reject(cause);
    }
    if (stat.isSymbolicLink()) {
      const real = await fs.promises.realpath(cursor);
      if (!isInside(rootReal, real)) {
        throw new HarmonyConfigPluginError(
          'ERR_HARMONY_PATH_ESCAPE',
          `Refusing to follow a symlink outside the Harmony project: ${cursor}`,
          { file: cursor, operation: 'resolve-path' }
        );
      }
    }
  }
}

export async function resolveHarmonyPath(
  platformProjectRoot: string,
  relativePath: string
): Promise<string> {
  if (typeof relativePath !== 'string' || !relativePath || path.isAbsolute(relativePath)) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_PATH_ESCAPE',
      `Invalid managed path: ${relativePath}`,
      { operation: 'resolve-path' }
    );
  }

  const root = path.resolve(platformProjectRoot);
  const target = path.resolve(root, relativePath);
  if (!isInside(root, target)) {
    throw new HarmonyConfigPluginError('ERR_HARMONY_PATH_ESCAPE', `Managed path escapes the Harmony project: ${relativePath}`, { file: target, operation: 'resolve-path' });
  }

  await assertNoExternalSymlink(root, target);

  return target;
}

export async function resolveProjectPath(projectRoot: string, modName: keyof HarmonyProjectPaths): Promise<string> {
  const candidates = ProjectPathCandidates[modName] || [ProjectPaths[modName]];
  const resolved = await Promise.all(candidates.map(candidate => resolveHarmonyPath(projectRoot, candidate)));
  const existing = resolved.filter(file => fs.existsSync(file));
  if (existing.length > 1) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_CONFIG_INVALID',
      `Multiple files provide harmony.${modName}: ${existing.map(file => path.basename(file)).join(', ')}`,
      { file: existing[0], operation: `harmony.${modName}.read` }
    );
  }

  return existing[0] || resolved[0];
}

export function toPosixRelative(projectRoot: string, target: string): string {
  return path.relative(projectRoot, target).split(path.sep).join('/');
}

export const HarmonyPaths: HarmonyPathsApi = {
  HARMONY_PATHS: ManagedPaths,
  PROJECT_PATH_CANDIDATES: ProjectPathCandidates,
  PROJECT_PATHS: ProjectPaths,
  RESOURCE_PATHS: ResourcePaths,
  assertNoExternalSymlink,
  isInside,
  resolveHarmonyPath,
  resolveProjectPath,
  toPosixRelative,
};

export { ManagedPaths, ProjectPathCandidates, ProjectPaths, ResourcePaths };

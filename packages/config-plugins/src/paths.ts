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
  readonly abilityStage: string;
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
  resolveHarmonyPath(directory: string, relative: string): Promise<string>;
  resolveProjectPath(root: string, name: keyof HarmonyProjectPaths): Promise<string>;
  toPosixRelative(root: string, target: string): string;
}

const ManagedPaths: HarmonyManagedPaths & { readonly nativeInputsStamp: string } = Object.freeze({
  appJson: 'AppScope/app.json5',
  projectBuildProfile: 'build-profile.json5',
  rootOhPackage: 'oh-package.json5',
  rootHvigor: 'hvigorfile.ts',
  nativeInputsStamp: 'native-inputs-stamp.ts',
  hvigorConfig: 'hvigor/hvigor-config.json5',
  entryBuildProfile: 'entry/build-profile.json5',
  entryOhPackage: 'entry/oh-package.json5',
  entryHvigor: 'entry/hvigorfile.ts',
  moduleJson: 'entry/src/main/module.json5',
  profiles: 'entry/src/main/resources/base/profile/main_pages.json',
  abilityStage: 'entry/src/main/ets/abilitystage/EntryAbilityStage.ets',
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
  // Match React Native CLI lookup precedence; new projects use the first path.
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
  const absolute = path.resolve(root);
  const canonical = await fs.promises.realpath(absolute).catch(() => absolute);
  const relative = path.relative(absolute, target);
  let current = absolute;

  for (const segment of relative.split(path.sep).filter(Boolean)) {
    current = path.join(current, segment);

    let stat: fs.Stats;

    try {
      stat = await fs.promises.lstat(current);
    } catch (cause) {
      if ((cause as NodeJS.ErrnoException).code === 'ENOENT') break;

      throw new HarmonyConfigPluginError(
        'ERR_HARMONY_PATH_INVALID',
        `Cannot inspect managed Harmony path ${current}: ${(cause as Error).message}`,
        { cause, file: current, operation: 'resolve-path' }
      );
    }

    if (stat.isSymbolicLink()) {
      const real = await fs.promises.realpath(current);

      if (!isInside(canonical, real)) {
        throw new HarmonyConfigPluginError(
          'ERR_HARMONY_PATH_ESCAPE',
          `Refusing to follow a symlink outside the Harmony project: ${current}`,
          { file: current, operation: 'resolve-path' }
        );
      }
    }
  }
}

export async function resolveHarmonyPath(
  directory: string,
  relative: string
): Promise<string> {
  if (typeof relative !== 'string' || !relative || path.isAbsolute(relative)) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_PATH_ESCAPE',
      `Invalid managed path: ${relative}`,
      { operation: 'resolve-path' }
    );
  }

  const root = path.resolve(directory);
  const target = path.resolve(root, relative);

  if (!isInside(root, target)) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_PATH_ESCAPE',
      `Managed path escapes the Harmony project: ${relative}`,
      { file: target, operation: 'resolve-path' }
    );
  }

  await assertNoExternalSymlink(root, target);

  return target;
}

export async function resolveProjectPath(
  root: string,
  name: keyof HarmonyProjectPaths
): Promise<string> {
  const candidates = ProjectPathCandidates[name] || [ProjectPaths[name]];

  for (const candidate of candidates) {
    if (fs.existsSync(path.join(root, candidate))) return resolveHarmonyPath(root, candidate);
  }

  return resolveHarmonyPath(root, candidates[0]);
}

export function toPosixRelative(root: string, target: string): string {
  return path.relative(root, target).split(path.sep).join('/');
}

const { nativeInputsStamp: NativeInputsStampPath, ...PublicManagedPaths } = ManagedPaths;

export const HarmonyPaths: Readonly<HarmonyPathsApi> = Object.freeze({
  HARMONY_PATHS: Object.freeze(PublicManagedPaths),
  PROJECT_PATH_CANDIDATES: ProjectPathCandidates,
  PROJECT_PATHS: ProjectPaths,
  RESOURCE_PATHS: ResourcePaths,
  assertNoExternalSymlink,
  isInside,
  resolveHarmonyPath,
  resolveProjectPath,
  toPosixRelative,
});

export { ManagedPaths, NativeInputsStampPath, ProjectPathCandidates, ProjectPaths, ResourcePaths };

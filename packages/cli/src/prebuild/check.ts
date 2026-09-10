import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  compareAsync,
  stageAsync,
} from '@expo-harmony/prebuild-config/internal';

import { HarmonyCliError } from '../errors';
import { isInside } from '../path';
import { spawnAsync } from '../process';
import { withHarmonyProjectLockAsync } from '../projectLock';
import { createHarmonyToolchainEnv, resolveHarmonyBuildPlanAsync, type HarmonyBuildPlan } from '../tools';
import { resolveExpoCli } from '../expo';
import { packAsync } from './template';

export type { Change as CheckChange } from '@expo-harmony/prebuild-config/internal';

const IgnoredProjectDirectories = new Set(['.expo', '.git', '.hvigor', '.yarn', 'node_modules']);
const IgnoredHarmonyGeneratedDirectories = new Set([
  '.cxx',
  '.git',
  '.hvigor',
  'build',
  'node_modules',
  'oh_modules',
]);

interface CheckOptions {
  buildType?: 'debug' | 'release';
}

function mirrorRoot(temp, project) {
  const absolute = path.resolve(project);
  const parsed = path.parse(absolute);
  const volume = parsed.root.replace(/[^A-Za-z0-9]+/gu, '') || 'root';
  const segments = absolute.slice(parsed.root.length).split(path.sep).filter(Boolean);

  return path.join(temp, 'filesystem', volume, ...segments);
}

async function linkModuleEntryAsync(
  source: string,
  target: string,
  entry: fs.Dirent
) {
  const directory = entry.isSymbolicLink()
    ? (await fs.promises.stat(source)).isDirectory()
    : entry.isDirectory();

  if (process.platform === 'win32' && !directory) {
    await fs.promises.copyFile(source, target);
    return;
  }

  await fs.promises.symlink(
    path.resolve(source),
    target,
    directory ? process.platform === 'win32' ? 'junction' : 'dir' : 'file'
  );
}

async function linkModulesAsync(source: string, target: string) {
  await fs.promises.mkdir(target, { recursive: true });

  for (const entry of await fs.promises.readdir(source, { withFileTypes: true })) {
    const from = path.join(source, entry.name);
    const to = path.join(target, entry.name);

    if (entry.name.startsWith('@') && entry.isDirectory() && !entry.isSymbolicLink()) {
      await fs.promises.mkdir(to);

      for (const child of await fs.promises.readdir(from, { withFileTypes: true })) {
        await linkModuleEntryAsync(
          path.join(from, child.name),
          path.join(to, child.name),
          child
        );
      }
      continue;
    }

    await linkModuleEntryAsync(from, to, entry);
  }
}

function isAppLocalHarmonyPath(project: string, source: string): boolean {
  const segments = path.relative(project, source).split(path.sep);

  return segments.length >= 3
    && segments[0] === 'modules'
    && segments[1] !== ''
    && segments[2] === 'harmony';
}

function shouldCopyPrebuildCheckPath(
  project: string,
  source: string,
  plan: HarmonyBuildPlan
): boolean {
  const relative = path.relative(project, source);
  if (!relative) return true;

  const segments = relative.split(path.sep);
  if (IgnoredProjectDirectories.has(segments[0])) return false;

  const nativeRoot = isInside(plan.harmonyRoot, source)
    ? plan.harmonyRoot
    : isAppLocalHarmonyPath(project, source)
      ? path.join(project, ...segments.slice(0, 3))
      : null;
  if (nativeRoot) {
    const native = path.relative(nativeRoot, source).split(path.sep);
    if (native.some(segment => IgnoredHarmonyGeneratedDirectories.has(segment))) return false;
  }

  return source !== plan.exportPaths.bundle;
}

async function copyAsync(
  project: string,
  target: string,
  plan: HarmonyBuildPlan,
  temp = path.dirname(target)
) {
  await fs.promises.cp(project, target, {
    recursive: true,
    filter: source => shouldCopyPrebuildCheckPath(project, source, plan),
  });

  const modules = path.join(project, 'node_modules');

  if (!fs.existsSync(modules)) {
    throw new HarmonyCliError('ERR_HARMONY_DEPENDENCIES_MISSING', 'node_modules is required for --check.', {
      operation: 'check',
    });
  }

  // Keep a real node_modules directory in the isolated project and link its
  // entries. Dependency scanners then retain the isolated lexical package path
  // (including scoped packages) instead of collapsing the entire node_modules
  // root to the source project's realpath. Package directories stay linked;
  // Windows copies loose files to avoid requiring file-symlink privileges.
  await linkModulesAsync(modules, path.join(target, 'node_modules'));
  await stageAsync(project, target, temp);
}

async function checkUnlockedAsync(project, options: CheckOptions) {
  project = path.resolve(project);
  const plan = await resolveHarmonyBuildPlanAsync(project);
  const temp = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-harmony-check-'));
  const expected = mirrorRoot(temp, project);
  let packed;

  try {
    await copyAsync(project, expected, plan, temp);
    packed = await packAsync(project);

    const expo = resolveExpoCli(project);
    const result = await spawnAsync(process.execPath, [
      expo.cliPath,
      'prebuild',
      expected,
      '--platform', 'harmony',
      '--template', packed.tarball,
      '--no-install',
    ], {
      capture: true,
      cwd: expected,
      env: {
        ...createHarmonyToolchainEnv(),
        ...packed.env,
        ...(options.buildType ? { EXPO_HARMONY_BUILD_TYPE: options.buildType } : {}),
        EXPO_HARMONY_CHECK_MIRROR_ROOT: temp,
      },
      operation: 'check-prebuild',
    });

    if (result.code !== 0) {
      throw new HarmonyCliError(
        'ERR_HARMONY_MANIFEST_DRIFT',
        `Isolated Expo prebuild failed:\n${result.stderr || result.stdout}`,
        { exitCode: result.code, operation: 'check-prebuild' }
      );
    }

    return compareAsync(project, expected);
  } finally {
    if (packed) await packed.cleanup();
    await fs.promises.rm(temp, { recursive: true, force: true });
  }
}

async function checkAsync(project, options: CheckOptions = {}) {
  return withHarmonyProjectLockAsync(
    project,
    'prebuild-check',
    () => checkUnlockedAsync(project, options)
  );
}

export { checkAsync };

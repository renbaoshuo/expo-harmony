import { createHash } from 'node:crypto';
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
import { createHarmonyToolchainEnv } from '../native/toolchain';
import { resolveHarmonyBuildPlanAsync } from '../native/project';
import { type HarmonyBuildPlan } from '../native/types';
import { resolveExpoCli } from '../expo';
import { packAsync } from './template';

export type { Change as CheckChange } from '@expo-harmony/prebuild-config/internal';

const IgnoredDirectories = new Set(['.expo', '.git', '.hvigor', '.yarn', 'node_modules']);
const GeneratedDirectories = new Set([
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
  if (IgnoredDirectories.has(segments[0])) return false;

  const root = isInside(plan.harmonyRoot, source)
    ? plan.harmonyRoot
    : isAppLocalHarmonyPath(project, source)
      ? path.join(project, ...segments.slice(0, 3))
      : null;
  if (root) {
    const native = path.relative(root, source).split(path.sep);
    if (GeneratedDirectories.has(native[0])
      || (GeneratedDirectories.has(native[1])
        && fs.existsSync(path.join(root, native[0], 'src/main/module.json5')))) return false;
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
    verbatimSymlinks: true,
    filter: source => shouldCopyPrebuildCheckPath(project, source, plan),
  });

  const modules = path.join(project, 'node_modules');

  if (!fs.existsSync(modules)) {
    throw new HarmonyCliError('ERR_HARMONY_DEPENDENCIES_MISSING', 'node_modules is required for --check.', {
      operation: 'check',
    });
  }

  // Link individual packages so dependency scanners retain paths inside the mirror.
  await linkModulesAsync(modules, path.join(target, 'node_modules'));
  await stageAsync(project, target, temp);
}

async function withGeneratedProjectAsync<T>(
  project: string,
  options: CheckOptions & { clean?: boolean; skipPatches?: boolean },
  action: (expected: string, checksum: string) => Promise<T>
): Promise<T> {
  project = path.resolve(project);
  const plan = await resolveHarmonyBuildPlanAsync(project);
  const temp = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-harmony-check-'));
  const expected = mirrorRoot(temp, project);
  let packed;

  try {
    await copyAsync(project, expected, plan, temp);
    if (options.clean) await fs.promises.rm(path.join(expected, 'harmony'), { recursive: true, force: true });

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
        ...(options.skipPatches ? { EXPO_HARMONY_SKIP_PATCHES: '1' } : {}),
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

    const checksum = createHash('md5').update(Uint8Array.from(await fs.promises.readFile(packed.tarball))).digest('hex');

    return await action(expected, checksum);
  } finally {
    if (packed) await packed.cleanup();
    await fs.promises.rm(temp, { recursive: true, force: true });
  }
}

async function checkAsync(project, options: CheckOptions = {}) {
  return withHarmonyProjectLockAsync(
    project,
    'prebuild-check',
    () => withGeneratedProjectAsync(project, options, expected => compareAsync(project, expected))
  );
}

export { checkAsync, withGeneratedProjectAsync };

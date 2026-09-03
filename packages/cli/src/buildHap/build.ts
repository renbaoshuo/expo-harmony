import path from 'node:path';

import { HarmonyCliError } from '../errors';
import { exportEmbedAsync } from '../exportEmbed/export';
import type { HarmonyExportManifest } from '../exportEmbed/manifest';
import { toPosixPath } from '../path';
import { withHarmonyProjectLockAsync } from '../projectLock';
import {
  commitHarmonyNativeBuildCacheAsync,
  prepareHarmonyNativeBuildCacheAsync,
} from '../run/cache';
import { installHarmonyDependenciesAsync } from '../run/install';
import {
  resolveHarmonyBuildPlanAsync,
  resolveHarmonyToolchain,
} from '../tools';
import {
  ensureGeneratedProjectAsync,
  isNonEmptyRegularFile,
  progress,
  runCheckedAsync,
  timed,
} from './common';

export interface HarmonyBuildOptions {
  io?: Pick<Console, 'error' | 'log' | 'warn'>;
  /** @internal For release verification after a successful isolated prebuild check. */
  skipGeneratedProjectCheck?: boolean;
  sync?: boolean;
  variant?: 'debug' | 'release';
}

export interface HarmonyBuildResult {
  bundleName: string;
  export: null | { assetCount: number; bundleSha256: string; sourceMapSha256: string };
  hapPath: string;
  headless: true;
  installed: false;
  launched: false;
  ok: true;
  schemaVersion: 1;
  steps: Record<string, number>;
  variant: 'debug' | 'release';
}

type NormalizedBuildOptions = Required<HarmonyBuildOptions> & {
  requireDeviceTools: false;
};

async function buildHarmonyUnlockedAsync(
  projectRoot: string,
  options: HarmonyBuildOptions = {}
): Promise<HarmonyBuildResult> {
  const normalizedOptions: NormalizedBuildOptions = {
    io: options.io || console,
    requireDeviceTools: false,
    skipGeneratedProjectCheck: Boolean(options.skipGeneratedProjectCheck),
    sync: Boolean(options.sync),
    variant: options.variant || 'debug',
  };
  const steps: Record<string, number> = {
    device: 0,
    install: 0,
    launch: 0,
    metro: 0,
    metroPort: 0,
  };

  await ensureGeneratedProjectAsync(projectRoot, normalizedOptions, steps);

  const plan = await timed(steps, 'buildPlan', () => resolveHarmonyBuildPlanAsync(
    projectRoot,
    { buildMode: normalizedOptions.variant }
  ));
  const toolchain = resolveHarmonyToolchain();

  let exportManifest: HarmonyExportManifest | null = null;
  if (normalizedOptions.variant === 'release') {
    progress(normalizedOptions, 'Exporting the release Hermes bundle');
    exportManifest = await timed(steps, 'export', () => exportEmbedAsync(
      projectRoot,
      { skipDoctor: true }
    ));
  } else {
    steps.export = 0;
  }

  progress(normalizedOptions, 'Installing Harmony project dependencies');
  await timed(steps, 'ohpm', () => installHarmonyDependenciesAsync(plan, toolchain));

  progress(normalizedOptions, 'Checking Harmony native dependency cache');
  const nativeBuildCache = await timed(steps, 'nativeCache', () => (
    prepareHarmonyNativeBuildCacheAsync(projectRoot, plan)
  ));

  if (nativeBuildCache.changed) {
    progress(normalizedOptions, 'Invalidated stale Harmony native build objects');
  }

  progress(normalizedOptions, `Building the ${normalizedOptions.variant} HAP without a device`);
  const buildEnv = {
    ...process.env,
    EXPO_HARMONY_NODE: process.env.EXPO_HARMONY_NODE || process.execPath,
    EXPO_METRO_TARGET: 'harmony',
    HERMES_V1_ENABLED: 'true',
    ...(normalizedOptions.variant === 'release' ? { EXPO_HARMONY_BUNDLE_PREBUILT: '1' } : {}),
    ...(toolchain.sdkHome && !process.env.DEVECO_SDK_HOME
      ? { DEVECO_SDK_HOME: toolchain.sdkHome }
      : {}),
  };
  await timed(steps, 'build', () => runCheckedAsync(toolchain.hvigor.command, [
    ...toolchain.hvigor.args,
    ...plan.hvigorArgs,
  ], {
    code: 'ERR_HARMONY_BUILD_FAILED',
    cwd: plan.harmonyRoot,
    env: buildEnv,
    message: 'Hvigor build',
    operation: 'hvigor-build',
    timeoutMs: 15 * 60_000,
  }));

  if (!isNonEmptyRegularFile(plan.expectedHap)) {
    throw new HarmonyCliError(
      'ERR_HARMONY_HAP_MISSING',
      'Hvigor completed without producing the expected non-empty regular HAP.',
      { operation: 'verify-hap' }
    );
  }

  await timed(steps, 'nativeCacheCommit', () => commitHarmonyNativeBuildCacheAsync(nativeBuildCache));

  return {
    bundleName: plan.bundleName,
    export: exportManifest
      ? {
          assetCount: exportManifest.assets.length,
          bundleSha256: exportManifest.bundle.sha256,
          sourceMapSha256: exportManifest.sourceMap.sha256,
        }
      : null,
    hapPath: toPosixPath(path.relative(projectRoot, plan.expectedHap)),
    headless: true,
    installed: false,
    launched: false,
    ok: true,
    schemaVersion: 1,
    steps,
    variant: normalizedOptions.variant,
  };
}

async function buildHarmonyAsync(
  projectRoot: string,
  options: HarmonyBuildOptions = {}
): Promise<HarmonyBuildResult> {
  return withHarmonyProjectLockAsync(
    projectRoot,
    'build',
    () => buildHarmonyUnlockedAsync(projectRoot, options)
  );
}

export { buildHarmonyAsync };

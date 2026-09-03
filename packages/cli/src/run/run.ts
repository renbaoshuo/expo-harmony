import path from 'node:path';

import {
  configureMetroPortAsync,
  installHapAsync,
  launchAppAsync,
  selectDeviceAsync,
} from './devices';
import { HarmonyCliError } from '../errors';
import { exportEmbedAsync } from '../exportEmbed/export';
import type { HarmonyExportManifest } from '../exportEmbed/manifest';
import {
  resolveHarmonyBuildPlanAsync,
  resolveHarmonyToolchain,
  type HarmonyBuildPlan,
} from '../tools';
import { installHarmonyDependenciesAsync } from './install';
import {
  requireExistingMetroAsync,
  startExpoMetroAsync,
  type MetroSession,
} from './metro';
import {
  commitHarmonyNativeBuildCacheAsync,
  prepareHarmonyNativeBuildCacheAsync,
} from './cache';
import { toPosixPath } from '../path';
import { withHarmonyProjectLockAsync } from '../projectLock';
import {
  ensureGeneratedProjectAsync,
  isNonEmptyRegularFile,
  progress,
  runCheckedAsync,
  timed,
} from '../buildHap/common';

export interface HarmonyRunOptions {
  appId?: string;
  device?: string;
  io?: Pick<Console, 'error' | 'log' | 'warn'>;
  noBundler?: boolean;
  noInstall?: boolean;
  port?: number;
  resetCache?: boolean;
  sync?: boolean;
  variant?: 'debug' | 'release';
}

export interface HarmonyRunResult {
  bundleName: string;
  device: { id: string; transport: string };
  export: null | { assetCount: number; bundleSha256: string; sourceMapSha256: string };
  hapPath: string;
  installed: boolean;
  launched: true;
  metro: { owner: 'disabled' | 'existing' | 'started'; port: number };
  ok: true;
  schemaVersion: 1;
  steps: Record<string, number>;
  variant: 'debug' | 'release';
}

interface HarmonyRunSessionOptions extends HarmonyRunOptions {
  /** Give a CLI-started Metro process ownership of the current terminal. */
  interactiveBundler?: boolean;
}

interface HarmonyRunSession {
  metro: MetroSession | {
    owner: 'disabled';
    port: number;
    stop(): Promise<void>;
    waitAsync(): Promise<void>;
  };
  result: HarmonyRunResult;
}

type NormalizedRunOptions = Required<Omit<HarmonyRunSessionOptions, 'appId' | 'device'>>
  & Pick<HarmonyRunSessionOptions, 'appId' | 'device'>;

const BundleName = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*){2,}$/u;

function resolveRunIdentity(plan: HarmonyBuildPlan, options: NormalizedRunOptions) {
  if (options.appId && !BundleName.test(options.appId)) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', '--app-id must contain at least three valid dot-separated segments.', { operation: 'resolve-run' });
  }

  if (options.appId && !options.noInstall && options.appId !== plan.bundleName) {
    throw new HarmonyCliError(
      'ERR_HARMONY_APP_ID_MISMATCH',
      `--app-id can differ from the generated bundle name only with --no-install; expected ${plan.bundleName}.`,
      { operation: 'resolve-run' }
    );
  }

  return {
    abilityName: plan.abilityName,
    bundleName: options.appId || plan.bundleName,
  };
}

async function runHarmonyUnlockedAsync(
  projectRoot: string,
  options: HarmonyRunSessionOptions = {}
): Promise<HarmonyRunSession> {
  const normalizedOptions: NormalizedRunOptions = {
    appId: options.appId,
    device: options.device,
    interactiveBundler: Boolean(options.interactiveBundler),
    io: options.io || console,
    noBundler: Boolean(options.noBundler),
    noInstall: Boolean(options.noInstall),
    port: options.port || 8081,
    resetCache: Boolean(options.resetCache),
    sync: Boolean(options.sync),
    variant: options.variant || 'debug',
  };
  const steps: Record<string, number> = {};

  await ensureGeneratedProjectAsync(projectRoot, normalizedOptions, steps);

  const plan = await timed(steps, 'buildPlan', () => resolveHarmonyBuildPlanAsync(
    projectRoot,
    { buildMode: normalizedOptions.variant }
  ));
  const identity = resolveRunIdentity(plan, normalizedOptions);
  const toolchain = resolveHarmonyToolchain();

  progress(normalizedOptions, 'Selecting a connected Harmony device');
  const device = await timed(steps, 'device', () => selectDeviceAsync(
    toolchain.hdc,
    normalizedOptions.device,
    { cwd: plan.harmonyRoot }
  ));

  let exportManifest: HarmonyExportManifest | null = null;
  if (normalizedOptions.variant === 'release') {
    progress(normalizedOptions, 'Exporting the release Hermes bundle');
    exportManifest = await timed(steps, 'export', () => exportEmbedAsync(
      projectRoot,
      { resetCache: normalizedOptions.resetCache, skipDoctor: true }
    ));
  } else {
    steps.export = 0;
  }

  progress(normalizedOptions, 'Installing Harmony project dependencies');
  await timed(steps, 'ohpm', () => installHarmonyDependenciesAsync(plan, toolchain));

  let metro: HarmonyRunSession['metro'] = {
    owner: 'disabled',
    port: normalizedOptions.port,
    stop: async () => {},
    waitAsync: async () => {},
  };
  try {
    progress(normalizedOptions, 'Checking Harmony native dependency cache');
    const nativeBuildCache = await timed(steps, 'nativeCache', () => (
      prepareHarmonyNativeBuildCacheAsync(projectRoot, plan)
    ));

    if (nativeBuildCache.changed) {
      progress(normalizedOptions, 'Invalidated stale Harmony native build objects');
    }

    progress(normalizedOptions, `Building the ${normalizedOptions.variant} HAP`);
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
      throw new HarmonyCliError('ERR_HARMONY_HAP_MISSING', 'Hvigor completed without producing the expected non-empty regular HAP.', { operation: 'verify-hap' });
    }

    await timed(steps, 'nativeCacheCommit', () => commitHarmonyNativeBuildCacheAsync(nativeBuildCache));

    if (normalizedOptions.variant === 'debug') {
      progress(normalizedOptions, normalizedOptions.noBundler
        ? 'Connecting to the existing Expo Metro server'
        : 'Starting Expo Metro');
      metro = await timed(steps, 'metro', () => normalizedOptions.noBundler
        ? requireExistingMetroAsync(normalizedOptions.port)
        : startExpoMetroAsync(projectRoot, {
            interactive: normalizedOptions.interactiveBundler,
            port: normalizedOptions.port,
            resetCache: normalizedOptions.resetCache,
          }));

      await timed(steps, 'metroPort', () => configureMetroPortAsync(
        toolchain.hdc,
        device,
        normalizedOptions.port,
        { cwd: plan.harmonyRoot }
      ));
    } else {
      steps.metro = 0;
      steps.metroPort = 0;
    }

    if (normalizedOptions.noInstall) {
      steps.install = 0;
    } else {
      progress(normalizedOptions, `Installing the HAP on ${device.id}`);
      await timed(steps, 'install', () => installHapAsync(
        toolchain.hdc,
        device,
        plan.expectedHap,
        { cwd: plan.harmonyRoot }
      ));
    }

    progress(normalizedOptions, `Launching ${identity.bundleName}`);
    await timed(steps, 'launch', () => launchAppAsync(
      toolchain.hdc,
      device,
      identity.bundleName,
      identity.abilityName,
      { cwd: plan.harmonyRoot }
    ));

    const result: HarmonyRunResult = {
      bundleName: identity.bundleName,
      device: {
        id: device.id,
        transport: device.transport,
      },
      export: exportManifest
        ? {
            assetCount: exportManifest.assets.length,
            bundleSha256: exportManifest.bundle.sha256,
            sourceMapSha256: exportManifest.sourceMap.sha256,
          }
        : null,
      hapPath: toPosixPath(path.relative(projectRoot, plan.expectedHap)),
      installed: !normalizedOptions.noInstall,
      launched: true,
      metro: {
        owner: metro.owner,
        port: metro.port,
      },
      ok: true,
      schemaVersion: 1,
      steps,
      variant: normalizedOptions.variant,
    };

    return { metro, result };
  } catch (error) {
    await metro.stop();
    throw error;
  }
}

async function runHarmonySessionAsync(
  projectRoot: string,
  options: HarmonyRunSessionOptions = {}
): Promise<HarmonyRunSession> {
  return withHarmonyProjectLockAsync(
    projectRoot,
    'run',
    () => runHarmonyUnlockedAsync(projectRoot, options)
  );
}

async function runHarmonyAsync(
  projectRoot: string,
  options: HarmonyRunOptions = {}
): Promise<HarmonyRunResult> {
  const session = await runHarmonySessionAsync(projectRoot, options);

  try {
    return session.result;
  } finally {
    await session.metro.stop();
  }
}

export { runHarmonyAsync, runHarmonySessionAsync };

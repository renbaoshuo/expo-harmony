import fs from 'node:fs';
import path from 'node:path';

import { verifyModulesAsync } from '@expo-harmony/expo-modules-autolinking';

import { checkAsync } from '../prebuild/check';
import {
  configureMetroPortAsync,
  installHapAsync,
  launchAppAsync,
  selectDeviceAsync,
} from './devices';
import { doctorAsync, type DoctorResult } from '../doctor/doctor';
import { HarmonyCliError } from '../errors';
import { exportEmbedAsync } from '../exportEmbed/export';
import type { HarmonyExportManifest } from '../exportEmbed/manifest';
import {
  resolveHarmonyBuildPlanAsync,
  resolveHarmonyBuildPlanIfPresentAsync,
  resolveHarmonyToolchain,
  type HarmonyBuildPlan,
} from '../tools';
import { installHarmonyDependenciesAsync } from './install';
import { requireExistingMetroAsync, startExpoMetroAsync } from './metro';
import {
  commitHarmonyNativeBuildCacheAsync,
  prepareHarmonyNativeBuildCacheAsync,
} from './cache';
import { prebuildParsedAsync } from '../prebuild/prebuild';
import { formatDiagnostics, spawnAsync } from '../process';
import { inspectPublicCliContractsAsync } from '../contract';
import { toPosixPath } from '../path';

export interface HarmonyRunOptions {
  appId?: string;
  device?: string;
  io?: Pick<Console, 'error' | 'log' | 'warn'>;
  json?: boolean;
  noBundler?: boolean;
  noInstall?: boolean;
  port?: number;
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

type NormalizedRunOptions = Required<Omit<HarmonyRunOptions, 'appId' | 'device'>>
  & Pick<HarmonyRunOptions, 'appId' | 'device'>;

interface CheckedProcessOptions {
  code: string;
  cwd: string;
  env?: NodeJS.ProcessEnv;
  message: string;
  operation: string;
  outputLimit?: number;
  timeoutMs?: number;
}

const BundleName = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*){2,}$/u;

function progress(options: NormalizedRunOptions, message: string): void {
  if (!options.json) options.io?.log?.(`› ${message}`);
}

async function timed<T>(
  steps: Record<string, number>,
  name: string,
  operation: () => Promise<T> | T
): Promise<T> {
  const started = performance.now();
  try {
    return await operation();
  } finally {
    steps[name] = Math.max(0, Math.round(performance.now() - started));
  }
}

function assertDoctor(result: DoctorResult): void {
  if (result.ok) return;

  const failing = result.checks.filter(check => check.status === 'error').map(check => check.id);

  throw new HarmonyCliError('ERR_HARMONY_DOCTOR_FAILED', `Harmony doctor found blocking checks: ${failing.join(', ') || 'unknown'}.`, { operation: 'doctor' });
}

async function runCheckedAsync(
  command: string,
  args: string[],
  options: CheckedProcessOptions
) {
  const result = await spawnAsync(command, args, {
    capture: true,
    cwd: options.cwd,
    env: options.env,
    operation: options.operation,
    outputLimit: options.outputLimit || 2 * 1024 * 1024,
    timeoutMs: options.timeoutMs,
  });

  if (result.code !== 0 || result.timedOut) {
    const diagnostics = formatDiagnostics(result);
    throw new HarmonyCliError(
      options.code,
      `${options.message} exited with code ${result.code}${result.timedOut ? ' after timing out' : ''}.${diagnostics ? `\n${diagnostics}` : ''}`,
      { exitCode: result.code || 1, operation: options.operation }
    );
  }

  return result;
}

async function verifyAutolinkingAsync(
  projectRoot: string,
  variant: 'debug' | 'release'
) {
  let result;

  try {
    result = await verifyModulesAsync({ buildType: variant, platform: 'harmony', projectRoot });
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_AUTOLINKING_FAILED', `Harmony autolinking verification failed: ${cause.message}`, { cause, operation: 'verify-autolinking' });
  }

  if (!result.valid) {
    const diagnostics = result.diagnostics
      .filter(diagnostic => diagnostic.severity === 'error')
      .slice(0, 8)
      .map(diagnostic => `${diagnostic.code}: ${diagnostic.message}`)
      .join('\n');
    throw new HarmonyCliError('ERR_HARMONY_AUTOLINKING_FAILED', `Harmony autolinking verification failed.${diagnostics ? `\n${diagnostics}` : ''}`, { operation: 'verify-autolinking' });
  }

  return result;
}

async function ensureGeneratedProjectAsync(
  projectRoot: string,
  options: NormalizedRunOptions,
  steps: Record<string, number>
) {
  const plan = await resolveHarmonyBuildPlanIfPresentAsync(projectRoot, {
    buildMode: options.variant,
  });
  const exists = Boolean(plan && fs.existsSync(plan.harmonyRoot));

  progress(options, 'Checking the Harmony project');
  const doctor = await timed(steps, 'doctor', () => doctorAsync(projectRoot, {
    requireBuildTools: true,
    validateGeneratedProject: exists,
  }));
  assertDoctor(doctor);

  if (!exists) {
    progress(options, 'Generating the missing Harmony project');
    await timed(steps, 'prebuild', () => prebuildParsedAsync(
      projectRoot,
      [],
      { buildType: options.variant, capture: options.json }
    ));
  } else {
    steps.prebuild = 0;
  }

  progress(options, 'Checking CNG ownership and drift');
  let check = await timed(steps, 'cngCheck', () => checkAsync(projectRoot));

  if (!check.clean && options.sync) {
    progress(options, 'Synchronizing the generated Harmony project');
    await timed(steps, 'prebuild', () => prebuildParsedAsync(
      projectRoot,
      [],
      { buildType: options.variant, capture: options.json }
    ));
    check = await timed(steps, 'cngCheckAfterSync', () => checkAsync(projectRoot));
  }

  if (!check.clean) {
    const summary = check.changes.slice(0, 8).map(change => `${change.type}:${change.path}`).join(', ');
    throw new HarmonyCliError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      `Generated Harmony files differ from CNG desired state${summary ? ` (${summary})` : ''}. Run expo-harmony prebuild or retry with --sync.`,
      { operation: 'check' }
    );
  }
}

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

async function runHarmonyAsync(
  projectRoot: string,
  options: HarmonyRunOptions = {}
): Promise<HarmonyRunResult> {
  const normalizedOptions: NormalizedRunOptions = {
    appId: options.appId,
    device: options.device,
    io: options.io || console,
    json: Boolean(options.json),
    noBundler: Boolean(options.noBundler),
    noInstall: Boolean(options.noInstall),
    port: options.port || 8081,
    sync: Boolean(options.sync),
    variant: options.variant || 'debug',
  };
  const steps: Record<string, number> = {};

  await ensureGeneratedProjectAsync(projectRoot, normalizedOptions, steps);

  progress(normalizedOptions, 'Verifying project-local Expo and RNOH command contracts');
  await timed(steps, 'publicCliContract', () => inspectPublicCliContractsAsync(projectRoot));

  progress(normalizedOptions, 'Verifying Harmony native modules');
  await timed(steps, 'autolinking', () => verifyAutolinkingAsync(projectRoot, normalizedOptions.variant));

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
      { skipContract: true, skipDoctor: true }
    ));
  } else {
    steps.export = 0;
  }

  progress(normalizedOptions, 'Installing Harmony project dependencies');
  const installLease = await timed(steps, 'ohpm', () => installHarmonyDependenciesAsync(
    projectRoot,
    plan,
    toolchain
  ));

  if (installLease.usedFallback) {
    progress(normalizedOptions, `OHPM registry resolution failed; using ${installLease.fallbackPackages.length} HARs from installed npm packages`);
  }

  let metro: {
    owner: HarmonyRunResult['metro']['owner'];
    port: number;
    stop(): Promise<unknown>;
  } = { owner: 'disabled', port: normalizedOptions.port, stop: async () => {} };
  try {
    progress(normalizedOptions, 'Checking Harmony native dependency cache');
    const nativeBuildCache = await timed(steps, 'nativeCache', () => (
      prepareHarmonyNativeBuildCacheAsync(projectRoot, plan)
    ));

    if (nativeBuildCache.changed) {
      progress(normalizedOptions, 'Invalidated stale Harmony native build objects');
    }

    if (normalizedOptions.variant === 'debug') {
      progress(normalizedOptions, normalizedOptions.noBundler
        ? 'Connecting to the existing Expo Metro server'
        : 'Starting Expo Metro');
      metro = await timed(steps, 'metro', () => normalizedOptions.noBundler
        ? requireExistingMetroAsync(normalizedOptions.port)
        : startExpoMetroAsync(projectRoot, { port: normalizedOptions.port }));

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

    if (!fs.existsSync(plan.expectedHap)) {
      throw new HarmonyCliError('ERR_HARMONY_HAP_MISSING', 'Hvigor completed without producing the expected HAP.', { operation: 'verify-hap' });
    }

    await timed(steps, 'nativeCacheCommit', () => commitHarmonyNativeBuildCacheAsync(nativeBuildCache));

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

    return {
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
  } finally {
    await metro.stop();
    await installLease.restoreAsync();
  }
}

export { runHarmonyAsync };

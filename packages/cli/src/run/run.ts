import path from 'node:path';

import {
  configureMetroPortAsync,
  installHapAsync,
  launchAppAsync,
  selectDeviceAsync,
} from './devices';
import { HarmonyCliError } from '../errors';
import { resolveHarmonyEmulator, resolveHarmonyToolchain } from '../native/toolchain';
import { type HarmonyBuildPlan } from '../native/types';
import {
  requireExistingMetroAsync,
  startExpoMetroAsync,
  type MetroSession,
} from './metro';
import { withHarmonyProjectLockAsync } from '../projectLock';
import { buildNativeAsync, type NativeBuildResult } from '../native/build';
import { prepareNativeProjectAsync } from '../native/prepareProject';
import { progress } from '../log';
import { timedAsync } from '../profile';

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

export interface HarmonyRunResult extends NativeBuildResult {
  bundleName: string;
  device: { id: string; transport: string };
  installed: boolean;
  launched: true;
  metro: { owner: 'disabled' | 'existing' | 'started'; port: number };
  ok: true;
  schemaVersion: 1;
  steps: Record<string, number>;
  variant: 'debug' | 'release';
}

interface HarmonyRunSessionOptions extends HarmonyRunOptions {
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
  root: string,
  options: HarmonyRunSessionOptions = {}
): Promise<HarmonyRunSession> {
  const settings: NormalizedRunOptions = {
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

  const plan = await prepareNativeProjectAsync(root, {
    ...settings,
    check: false,
  }, steps);

  const identity = resolveRunIdentity(plan, settings);
  const tools = resolveHarmonyToolchain();

  progress(settings, 'Selecting a Harmony device or emulator');
  const device = await timedAsync(steps, 'device', () => selectDeviceAsync(
    tools.hdc,
    settings.device,
    {
      cwd: plan.harmonyRoot,
      emulator: resolveHarmonyEmulator(tools),
      emulatorLogFile: path.join(root, '.expo', 'harmony', 'emulator.log'),
      onProgress: message => progress(settings, message),
    }
  ));

  const built = await buildNativeAsync(root, plan, tools, settings, steps);

  let metro: HarmonyRunSession['metro'] = {
    owner: 'disabled',
    port: settings.port,
    stop: async () => {},
    waitAsync: async () => {},
  };

  try {
    if (settings.variant === 'debug') {
      progress(settings, settings.noBundler
        ? 'Connecting to the existing Expo Metro server'
        : 'Starting Expo Metro');
      metro = await timedAsync(steps, 'metro', () => settings.noBundler
        ? requireExistingMetroAsync(settings.port)
        : startExpoMetroAsync(root, {
            interactive: settings.interactiveBundler,
            port: settings.port,
            resetCache: settings.resetCache,
          }));

      await timedAsync(steps, 'metroPort', () => configureMetroPortAsync(
        tools.hdc,
        device,
        settings.port,
        { cwd: plan.harmonyRoot }
      ));
    } else {
      steps.metro = 0;
      steps.metroPort = 0;
    }

    if (settings.noInstall) {
      steps.install = 0;
    } else {
      progress(settings, `Installing the HAP on ${device.id}`);
      await timedAsync(steps, 'install', () => installHapAsync(
        tools.hdc,
        device,
        plan.expectedHap,
        { cwd: plan.harmonyRoot }
      ));
    }

    progress(settings, `Launching ${identity.bundleName}`);
    await timedAsync(steps, 'launch', () => launchAppAsync(
      tools.hdc,
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
      ...built,
      installed: !settings.noInstall,
      launched: true,
      metro: {
        owner: metro.owner,
        port: metro.port,
      },
      ok: true,
      schemaVersion: 1,
      steps,
      variant: settings.variant,
    };

    return { metro, result };
  } catch (error) {
    await metro.stop();

    throw new HarmonyCliError(error?.code || 'ERR_HARMONY_UNKNOWN', error?.message || 'Harmony run failed.', {
      cause: error,
      exitCode: error?.exitCode,
      operation: error?.operation,
    });
  }
}

async function runHarmonySessionAsync(
  root: string,
  options: HarmonyRunSessionOptions = {}
): Promise<HarmonyRunSession> {
  return withHarmonyProjectLockAsync(
    root,
    'run',
    () => runHarmonyUnlockedAsync(root, options)
  );
}

async function runHarmonyAsync(
  root: string,
  options: HarmonyRunOptions = {}
): Promise<HarmonyRunResult> {
  const session = await runHarmonySessionAsync(root, options);

  try {
    return session.result;
  } finally {
    await session.metro.stop();
  }
}

export { runHarmonyAsync, runHarmonySessionAsync };

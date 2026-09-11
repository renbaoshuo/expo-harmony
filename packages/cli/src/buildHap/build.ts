import { withHarmonyProjectLockAsync } from '../projectLock';
import { buildNativeAsync, type NativeBuildResult } from '../native/build';
import { prepareNativeProjectAsync } from '../native/prepareProject';
import { resolveHarmonyToolchain } from '../native/toolchain';

export interface HarmonyBuildOptions {
  io?: Pick<Console, 'error' | 'log' | 'warn'>;
  sync?: boolean;
  variant?: 'debug' | 'release';
}

export interface HarmonyBuildResult extends NativeBuildResult {
  bundleName: string;
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
  root: string,
  options: HarmonyBuildOptions = {}
): Promise<HarmonyBuildResult> {
  const settings: NormalizedBuildOptions = {
    io: options.io || console,
    requireDeviceTools: false,
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

  const plan = await prepareNativeProjectAsync(root, settings, steps);
  const built = await buildNativeAsync(root, plan, resolveHarmonyToolchain(), settings, steps);

  return {
    bundleName: plan.bundleName,
    ...built,
    headless: true,
    installed: false,
    launched: false,
    ok: true,
    schemaVersion: 1,
    steps,
    variant: settings.variant,
  };
}

async function buildHarmonyAsync(
  root: string,
  options: HarmonyBuildOptions = {}
): Promise<HarmonyBuildResult> {
  return withHarmonyProjectLockAsync(
    root,
    'build',
    () => buildHarmonyUnlockedAsync(root, options)
  );
}

export { buildHarmonyAsync };

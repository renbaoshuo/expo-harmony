import fs from 'node:fs';
import { linkModulesAsync } from '@expo-harmony/expo-modules-autolinking';

import { doctorAsync } from '../doctor/doctor';
import { HarmonyCliError } from '../errors';
import { progress, type Log } from '../log';
import { timedAsync } from '../profile';
import { checkAsync } from '../prebuild/check';
import { prebuildParsedAsync } from '../prebuild/prebuild';
import { createHarmonyToolchainEnv } from './toolchain';
import { resolveHarmonyBuildPlanAsync, resolveHarmonyBuildPlanIfPresentAsync } from './project';
import type { HarmonyBuildPlan } from './types';

interface PrepareProjectOptions {
  io?: Log;
  requireDeviceTools?: boolean;
  check?: boolean;
  sync: boolean;
  variant: 'debug' | 'release';
}

async function prepareNativeProjectAsync(
  root: string,
  options: PrepareProjectOptions,
  steps: Record<string, number>
): Promise<HarmonyBuildPlan> {
  const plan = await timedAsync(steps, 'buildPlan', () => resolveHarmonyBuildPlanIfPresentAsync(root, {
    buildMode: options.variant,
  }));
  const exists = Boolean(plan && fs.existsSync(plan.harmonyRoot));

  if (plan?.workflow === 'bare' && options.sync) {
    throw new HarmonyCliError('ERR_HARMONY_BARE_SYNC', '--sync regenerates CNG projects and cannot be used with a manually maintained bare project.', { operation: 'build' });
  }

  progress(options, 'Checking the Harmony project');
  const doctor = await timedAsync(steps, 'doctor', () => doctorAsync(root, {
    requireBuildTools: true,
    requireDeviceTools: options.requireDeviceTools,
    validateGeneratedProject: exists,
    validateModules: false,
  }));
  if (!doctor.ok) {
    const checks = doctor.checks.filter(check => check.status === 'error').map(check => check.id);

    throw new HarmonyCliError('ERR_HARMONY_DOCTOR_FAILED', `Harmony doctor found blocking checks: ${checks.join(', ') || 'unknown'}.`, { operation: 'doctor' });
  }

  if (plan?.workflow === 'bare') {
    progress(options, 'Autolinking the bare Harmony project');
    await timedAsync(steps, 'autolinking', () => linkModulesAsync({
      projectRoot: root,
      harmonyProjectPath: plan.harmonyRoot,
      buildType: options.variant,
      env: createHarmonyToolchainEnv(),
    }));

    steps.prebuild = 0;
    steps.cngCheck = 0;

    return plan;
  }

  if (!exists || options.sync) {
    progress(options, exists
      ? 'Synchronizing the generated Harmony project'
      : 'Generating the missing Harmony project');
    await timedAsync(steps, 'prebuild', () => prebuildParsedAsync(
      root,
      [],
      { buildType: options.variant }
    ));
    steps.cngCheck = 0;

    return timedAsync(steps, 'buildPlan', () => resolveHarmonyBuildPlanAsync(root, { buildMode: options.variant }));
  }

  steps.prebuild = 0;
  if (options.check === false) {
    steps.cngCheck = 0;
    return plan;
  }

  progress(options, 'Checking CNG ownership and drift');
  const check = await timedAsync(steps, 'cngCheck', () => checkAsync(root, { buildType: options.variant }));
  if (!check.clean) {
    const summary = check.changes.slice(0, 8).map(change => `${change.type}:${change.path}`).join(', ');

    throw new HarmonyCliError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      `Generated Harmony files differ from CNG desired state${summary ? ` (${summary})` : ''}. Run expo-harmony prebuild or retry with --sync.`,
      { operation: 'check' }
    );
  }

  return plan;
}

export { prepareNativeProjectAsync };

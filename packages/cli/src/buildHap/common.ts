import fs from 'node:fs';

import { doctorAsync, type DoctorResult } from '../doctor/doctor';
import { HarmonyCliError } from '../errors';
import { checkAsync } from '../prebuild/check';
import { prebuildParsedAsync } from '../prebuild/prebuild';
import { formatDiagnostics, spawnAsync } from '../process';
import { resolveHarmonyBuildPlanIfPresentAsync } from '../tools';

interface HarmonyBuildPipelineOptions {
  io?: Pick<Console, 'error' | 'log' | 'warn'>;
  requireDeviceTools?: boolean;
  /** @internal The caller already completed an isolated prebuild check. */
  skipGeneratedProjectCheck?: boolean;
  sync: boolean;
  variant: 'debug' | 'release';
}

interface CheckedProcessOptions {
  code: string;
  cwd: string;
  env?: NodeJS.ProcessEnv;
  message: string;
  operation: string;
  outputLimit?: number;
  timeoutMs?: number;
}

function progress(options: HarmonyBuildPipelineOptions, message: string): void {
  options.io?.log?.(`› ${message}`);
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

function isNonEmptyRegularFile(file: string): boolean {
  try {
    const stat = fs.lstatSync(file);
    return !stat.isSymbolicLink() && stat.isFile() && stat.size > 0;
  } catch {
    return false;
  }
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

async function ensureGeneratedProjectAsync(
  projectRoot: string,
  options: HarmonyBuildPipelineOptions,
  steps: Record<string, number>
) {
  const plan = await resolveHarmonyBuildPlanIfPresentAsync(projectRoot, {
    buildMode: options.variant,
  });
  const exists = Boolean(plan && fs.existsSync(plan.harmonyRoot));

  progress(options, 'Checking the Harmony project');
  const doctor = await timed(steps, 'doctor', () => doctorAsync(projectRoot, {
    requireBuildTools: true,
    requireDeviceTools: options.requireDeviceTools,
    validateGeneratedProject: exists,
    validateModules: false,
  }));
  assertDoctor(doctor);

  if (!exists || options.sync) {
    progress(options, exists
      ? 'Synchronizing the generated Harmony project'
      : 'Generating the missing Harmony project');
    await timed(steps, 'prebuild', () => prebuildParsedAsync(
      projectRoot,
      [],
      { buildType: options.variant }
    ));
    steps.cngCheck = 0;
    return;
  }

  steps.prebuild = 0;
  if (options.skipGeneratedProjectCheck) {
    steps.cngCheck = 0;
    return;
  }
  progress(options, 'Checking CNG ownership and drift');
  const check = await timed(steps, 'cngCheck', () => checkAsync(projectRoot));
  if (!check.clean) {
    const summary = check.changes.slice(0, 8).map(change => `${change.type}:${change.path}`).join(', ');
    throw new HarmonyCliError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      `Generated Harmony files differ from CNG desired state${summary ? ` (${summary})` : ''}. Run expo-harmony prebuild or retry with --sync.`,
      { operation: 'check' }
    );
  }
}

export {
  ensureGeneratedProjectAsync,
  isNonEmptyRegularFile,
  progress,
  runCheckedAsync,
  timed,
};
export type { CheckedProcessOptions, HarmonyBuildPipelineOptions };

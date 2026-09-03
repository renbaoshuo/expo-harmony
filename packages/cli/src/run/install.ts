import { HarmonyCliError } from '../errors';
import type { HarmonyBuildPlan, HarmonyToolchain } from '../tools';
import { formatDiagnostics, spawnAsync, type ProcessResult } from '../process';

interface InstallOptions {
  timeoutMs?: number;
}

function installMessage(result: ProcessResult): string {
  const diagnostics = formatDiagnostics(result);
  return `OHPM install exited with code ${result.code}${result.timedOut ? ' after timing out' : ''}.`
    + `${diagnostics ? `\n${diagnostics}` : ''}`;
}

/** Runs OHPM against the generated project without rewriting its manifest. */
async function installHarmonyDependenciesAsync(
  plan: HarmonyBuildPlan,
  toolchain: HarmonyToolchain,
  options: InstallOptions = {}
): Promise<void> {
  const result = await spawnAsync(
    toolchain.ohpm.command,
    [...toolchain.ohpm.args, 'install', '--all'],
    {
      capture: true,
      cwd: plan.harmonyRoot,
      operation: 'ohpm-install',
      outputLimit: 2 * 1024 * 1024,
      timeoutMs: options.timeoutMs || 5 * 60_000,
    }
  );

  if (result.code !== 0 || result.timedOut) {
    throw new HarmonyCliError('ERR_HARMONY_OHPM_FAILED', installMessage(result), {
      exitCode: result.code || 1,
      operation: 'ohpm-install',
    });
  }
}

export { installHarmonyDependenciesAsync };

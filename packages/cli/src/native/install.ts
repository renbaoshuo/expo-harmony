import type { HarmonyBuildPlan } from './types';
import type { HarmonyToolchain } from './toolchain';
import { runCheckedAsync } from '../process';

export async function installHarmonyDependenciesAsync(
  plan: Pick<HarmonyBuildPlan, 'harmonyRoot'>,
  tools: HarmonyToolchain,
  options: { timeoutMs?: number } = {}
): Promise<void> {
  await runCheckedAsync(tools.ohpm.command, [...tools.ohpm.args, 'install', '--all'], {
    code: 'ERR_HARMONY_OHPM_FAILED',
    cwd: plan.harmonyRoot,
    message: 'OHPM install',
    operation: 'ohpm-install',
    timeoutMs: options.timeoutMs || 5 * 60_000,
  });
}

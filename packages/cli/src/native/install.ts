/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { HarmonyBuildPlan } from './types';
import type { HarmonyToolchain } from './toolchain';
import path from 'node:path';
import { prepareLocalOhpmOverrides } from './ohpm';
import { runCheckedAsync } from '../process';
import { resolveTimeoutMs } from '../timeout';

export async function installHarmonyDependenciesAsync(
  plan: Pick<HarmonyBuildPlan, 'harmonyRoot'>,
  tools: HarmonyToolchain,
  options: { timeoutMs?: number } = {}
): Promise<void> {
  const restore = prepareLocalOhpmOverrides(path.dirname(plan.harmonyRoot), plan.harmonyRoot);
  try {
    await runCheckedAsync(tools.ohpm.command, [...tools.ohpm.args, 'install', '--all'], {
      code: 'ERR_HARMONY_OHPM_FAILED',
      cwd: plan.harmonyRoot,
      message: 'OHPM install',
      operation: 'ohpm-install',
      timeoutMs: resolveTimeoutMs('ohpm-install', 30 * 60_000, options.timeoutMs),
    });
  } finally {
    restore();
  }
}

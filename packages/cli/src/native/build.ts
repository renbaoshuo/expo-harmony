import path from 'node:path';

import { commitHarmonyNativeBuildCacheAsync, prepareHarmonyNativeBuildCacheAsync } from './cache';
import { installHarmonyDependenciesAsync } from './install';
import type { HarmonyToolchain } from './toolchain';
import type { HarmonyBuildPlan } from './types';
import { HarmonyCliError } from '../errors';
import { exportEmbedAsync } from '../exportEmbed/export';
import { isNonEmptyRegularFile } from '../file';
import { progress, type Log } from '../log';
import { toPosixPath } from '../path';
import { runCheckedAsync } from '../process';
import { timedAsync } from '../profile';

export interface NativeBuildResult {
  export: null | { assetCount: number; bundleSha256: string; sourceMapSha256: string };
  hapPath: string;
}

export async function buildNativeAsync(
  root: string,
  plan: HarmonyBuildPlan,
  tools: HarmonyToolchain,
  options: { io?: Log; resetCache?: boolean },
  steps: Record<string, number>
): Promise<NativeBuildResult> {
  let exported: NativeBuildResult['export'] = null;
  if (plan.buildMode === 'release') {
    progress(options, 'Exporting the release Hermes bundle');
    const manifest = await timedAsync(steps, 'export', () => exportEmbedAsync(root, {
      resetCache: options.resetCache,
      skipDoctor: true,
    }));

    exported = {
      assetCount: manifest.assets.length,
      bundleSha256: manifest.bundle.sha256,
      sourceMapSha256: manifest.sourceMap.sha256,
    };
  } else {
    steps.export = 0;
  }

  progress(options, 'Installing Harmony project dependencies');
  await timedAsync(steps, 'ohpm', () => installHarmonyDependenciesAsync(plan, tools));

  progress(options, 'Checking Harmony native dependency cache');
  const cache = await timedAsync(steps, 'nativeCache', () => prepareHarmonyNativeBuildCacheAsync(root, plan));
  if (cache.changed) progress(options, 'Invalidated stale Harmony native build objects');

  progress(options, `Building the ${plan.buildMode} HAP`);
  await timedAsync(steps, 'build', () => runCheckedAsync(tools.hvigor.command, [
    ...tools.hvigor.args,
    ...plan.hvigorArgs,
  ], {
    code: 'ERR_HARMONY_BUILD_FAILED',
    cwd: plan.harmonyRoot,
    env: {
      ...process.env,
      EXPO_HARMONY_NODE: process.env.EXPO_HARMONY_NODE || process.execPath,
      EXPO_METRO_TARGET: 'harmony',
      HERMES_V1_ENABLED: 'true',
      ...(plan.workflow === 'bare' ? { EXPO_HARMONY_NATIVE_PREPARED: '1' } : {}),
      ...(plan.buildMode === 'release' ? { EXPO_HARMONY_BUNDLE_PREBUILT: '1' } : {}),
      ...(tools.sdkHome && !process.env.DEVECO_SDK_HOME
        ? { DEVECO_SDK_HOME: tools.sdkHome }
        : {}),
    },
    message: 'Hvigor build',
    operation: 'hvigor-build',
    timeoutMs: 15 * 60_000,
  }));

  if (!isNonEmptyRegularFile(plan.expectedHap)) {
    throw new HarmonyCliError('ERR_HARMONY_HAP_MISSING', 'Hvigor completed without producing the expected non-empty regular HAP.', { operation: 'verify-hap' });
  }

  await timedAsync(steps, 'nativeCacheCommit', () => commitHarmonyNativeBuildCacheAsync(cache));

  return { export: exported, hapPath: toPosixPath(path.relative(root, plan.expectedHap)) };
}

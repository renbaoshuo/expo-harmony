import { readManifestIfPresentAsync, resolveHarmonyBuildPath, type HarmonyBuildDescriptor } from '@expo-harmony/prebuild-config/internal';

import { HarmonyCliError } from '../errors';
import { isBareHarmonyProject, resolveBareHarmonyBuildPlan } from './bare';
import type { CngHarmonyBuildPlan, HarmonyBuildPlan } from './types';

function createHarmonyBuildPlan(
  root: string,
  build: HarmonyBuildDescriptor,
  mode: 'debug' | 'release'
): CngHarmonyBuildPlan {
  const resolve = relative => resolveHarmonyBuildPath(root, relative);
  const variant = build.variants[mode];

  return {
    workflow: 'cng',
    abilityName: build.identity.abilityName,
    buildMode: mode,
    bundleName: build.identity.bundleName,
    expectedHap: resolve(variant.expectedHap),
    exportPaths: Object.fromEntries(
      Object.entries(build.export).map(([name, relative]) => [name, resolve(relative)])
    ) as HarmonyBuildPlan['exportPaths'],
    harmonyRoot: resolve(build.harmonyRoot),
    hvigorArgs: [...variant.hvigorArgs],
    moduleName: build.identity.moduleName,
    moduleRoot: resolve(build.moduleRoot),
    nativeCache: {
      invalidationRoots: build.nativeCache.invalidationRoots.map(resolve),
      stateFile: resolve(build.nativeCache.stateFile),
    },
    nativeInputs: {
      lockfile: resolve(build.nativeInputs.lockfile),
      manifest: resolve(build.nativeInputs.manifest),
    },
    productName: build.identity.productName,
    projectFiles: Object.fromEntries(
      Object.entries(build.projectFiles).map(([name, relative]) => [name, resolve(relative)])
    ) as CngHarmonyBuildPlan['projectFiles'],
    targetName: build.identity.targetName,
  };
}

async function resolveHarmonyBuildPlanIfPresentAsync(
  root: string,
  options: { buildMode?: 'debug' | 'release' } = {}
): Promise<HarmonyBuildPlan | null> {
  const mode = options.buildMode || 'debug';
  if (!['debug', 'release'].includes(mode)) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', `Harmony buildMode must be debug or release, received: ${mode}`, { operation: 'resolve-build' });
  }

  let manifest;

  try {
    manifest = await readManifestIfPresentAsync(root);
  } catch (cause) {
    throw new HarmonyCliError(
      cause.code || 'ERR_HARMONY_TEMPLATE_INVALID',
      `Cannot read the generated Harmony build descriptor: ${cause.message}`,
      { cause, operation: 'resolve-build' }
    );
  }

  if (!manifest) {
    return isBareHarmonyProject(root) ? resolveBareHarmonyBuildPlan(root, mode) : null;
  }

  return createHarmonyBuildPlan(root, manifest.build, mode);
}

async function resolveHarmonyBuildPlanAsync(
  root: string,
  options: { buildMode?: 'debug' | 'release' } = {}
): Promise<HarmonyBuildPlan> {
  const plan = await resolveHarmonyBuildPlanIfPresentAsync(root, options);
  if (!plan) {
    throw new HarmonyCliError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      'Cannot read the generated Harmony build descriptor because the CNG manifest is missing.',
      { operation: 'resolve-build' }
    );
  }

  return plan;
}

export { resolveHarmonyBuildPlanAsync, resolveHarmonyBuildPlanIfPresentAsync };

import fs from 'node:fs';
import path from 'node:path';

import {
  HarmonyNativeInputsFingerprintVersion,
  fingerprintHarmonyNativeInputsSync,
} from '@expo-harmony/config-plugins/native-inputs';

import { HarmonyCliError } from '../errors';
import type { HarmonyBuildPlan } from '../tools';

export interface HarmonyNativeBuildCacheState {
  artifactCount: number;
  cacheFile: string;
  changed: boolean;
  fingerprint: string;
  fingerprintVersion: number;
}

const CacheSchemaVersion = 1;

async function readOptionalFile(file) {
  try {
    return await fs.promises.readFile(file);
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw new HarmonyCliError(
      error.code || 'ERR_HARMONY_NATIVE_CACHE',
      error.message || `Cannot read a Harmony native cache input: ${file}`,
      { cause: error, exitCode: error.exitCode, operation: error.operation }
    );
  }
}

async function resolveNativeDependencyFingerprintAsync(
  projectRoot: string,
  plan: HarmonyBuildPlan
) {
  try {
    return fingerprintHarmonyNativeInputsSync({
      lockfile: plan.nativeInputs.lockfile,
      manifest: plan.nativeInputs.manifest,
      projectRoot,
    });
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_NATIVE_CACHE',
      `Cannot fingerprint generated Harmony native dependencies: ${cause.message}`,
      { cause, operation: 'native-cache' }
    );
  }
}

async function prepareHarmonyNativeBuildCacheAsync(
  projectRoot: string,
  plan: HarmonyBuildPlan
): Promise<HarmonyNativeBuildCacheState> {
  const current = await resolveNativeDependencyFingerprintAsync(projectRoot, plan);
  const file = plan.nativeCache.stateFile;
  const source = await readOptionalFile(file);
  let saved = null;

  if (source) {
    try {
      saved = JSON.parse(source.toString('utf8'));
    } catch {
      saved = null;
    }
  }

  const changed = saved?.schemaVersion !== CacheSchemaVersion
    || saved?.fingerprintVersion !== HarmonyNativeInputsFingerprintVersion
    || saved?.fingerprint !== current.fingerprint;

  if (changed) {
    for (const root of plan.nativeCache.invalidationRoots) {
      await fs.promises.rm(root, { force: true, recursive: true });
    }
  }

  return {
    ...current,
    cacheFile: file,
    changed,
  };
}

async function commitHarmonyNativeBuildCacheAsync(state: HarmonyNativeBuildCacheState): Promise<void> {
  const root = path.dirname(state.cacheFile);
  const temp = `${state.cacheFile}.${process.pid}.tmp`;

  await fs.promises.mkdir(root, { recursive: true });
  await fs.promises.writeFile(temp, `${JSON.stringify({
    artifactCount: state.artifactCount,
    fingerprint: state.fingerprint,
    fingerprintVersion: state.fingerprintVersion,
    schemaVersion: CacheSchemaVersion,
  }, null, 2)}\n`);
  await fs.promises.rename(temp, state.cacheFile);
}

export {
  commitHarmonyNativeBuildCacheAsync,
  prepareHarmonyNativeBuildCacheAsync,
};

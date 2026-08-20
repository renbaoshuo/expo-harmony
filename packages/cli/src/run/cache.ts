import nodeCrypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

import JSON5 from 'json5';

import { HarmonyCliError } from '../errors';
import { toPosixPath } from '../path';
import type { HarmonyBuildPlan } from '../tools';

export interface HarmonyNativeBuildCacheState {
  artifactCount: number;
  cacheFile: string;
  changed: boolean;
  fingerprint: string;
}

const CacheSchemaVersion = 1;
const CacheFileName = '.expo-harmony-native-dependencies.json';

function localHarPath(harmonyRoot, value) {
  if (typeof value !== 'string' || !/^\.\.?[\\/]/u.test(value)) return null;

  const relative = value;

  if (!relative.toLowerCase().endsWith('.har')) return null;

  return path.resolve(harmonyRoot, relative);
}

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

function nativeArtifactPaths(harmonyRoot, descriptor) {
  return [...new Set([
    ...Object.values(descriptor.dependencies || {}),
    ...Object.values(descriptor.overrides || {}),
  ].map(value => localHarPath(harmonyRoot, value)).filter(Boolean))].sort();
}

async function resolveNativeDependencyFingerprintAsync(
  projectRoot: string,
  plan: HarmonyBuildPlan
) {
  const descriptorPath = path.join(plan.harmonyRoot, 'oh-package.json5');
  let descriptorSource;
  let descriptor;

  try {
    descriptorSource = await fs.promises.readFile(descriptorPath);
    descriptor = JSON5.parse(descriptorSource.toString('utf8'));
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', `Cannot read generated Harmony dependencies: ${descriptorPath}`, { cause, operation: 'native-cache' });
  }

  const artifactPaths = nativeArtifactPaths(plan.harmonyRoot, descriptor);
  const hash = nodeCrypto.createHash('sha256');
  hash.update(`expo-harmony-native-dependencies-v${CacheSchemaVersion}\0`);
  hash.update(descriptorSource);
  const lockPath = path.join(plan.harmonyRoot, 'oh-package-lock.json5');
  const lockSource = await readOptionalFile(lockPath);

  if (lockSource) hash.update(Uint8Array.from(lockSource));

  for (const artifactPath of artifactPaths) {
    let artifactStat;
    let artifact;

    try {
      artifactStat = await fs.promises.stat(artifactPath);
      if (!artifactStat.isFile()) throw new Error('not a regular file');
      artifact = await fs.promises.readFile(artifactPath);
    } catch (cause) {
      throw new HarmonyCliError('ERR_HARMONY_NATIVE_ARTIFACT_MISSING', `Cannot fingerprint Harmony native artifact: ${artifactPath}`, { cause, operation: 'native-cache' });
    }

    hash.update('\0artifact\0');
    hash.update(toPosixPath(path.relative(projectRoot, artifactPath)));
    hash.update('\0');
    hash.update(artifact);
  }

  return {
    artifactCount: artifactPaths.length,
    fingerprint: hash.digest('hex'),
  };
}

async function prepareHarmonyNativeBuildCacheAsync(
  projectRoot: string,
  plan: HarmonyBuildPlan
): Promise<HarmonyNativeBuildCacheState> {
  const current = await resolveNativeDependencyFingerprintAsync(projectRoot, plan);
  const cacheFile = path.join(plan.moduleRoot, '.cxx', CacheFileName);
  let previous = null;

  const cached = await readOptionalFile(cacheFile);

  if (cached) {
    try {
      previous = JSON.parse(cached.toString('utf8'));
    } catch {
      previous = null;
    }
  }

  const changed = previous?.schemaVersion !== CacheSchemaVersion
    || previous?.fingerprint !== current.fingerprint;

  if (changed) {
    await fs.promises.rm(path.join(plan.moduleRoot, '.cxx'), { force: true, recursive: true });
    await fs.promises.rm(path.join(plan.moduleRoot, 'build'), { force: true, recursive: true });
  }

  return {
    ...current,
    cacheFile,
    changed,
  };
}

async function commitHarmonyNativeBuildCacheAsync(state: HarmonyNativeBuildCacheState): Promise<void> {
  const directory = path.dirname(state.cacheFile);
  const temporary = `${state.cacheFile}.${process.pid}.tmp`;

  await fs.promises.mkdir(directory, { recursive: true });
  await fs.promises.writeFile(temporary, `${JSON.stringify({
    artifactCount: state.artifactCount,
    fingerprint: state.fingerprint,
    schemaVersion: CacheSchemaVersion,
  }, null, 2)}\n`);
  await fs.promises.rename(temporary, state.cacheFile);
}

export {
  commitHarmonyNativeBuildCacheAsync,
  prepareHarmonyNativeBuildCacheAsync,
};

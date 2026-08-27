import fs from 'node:fs';
import path from 'node:path';

import { localOhpmDependenciesFromManifest, readManifestAsync } from '@expo-harmony/expo-modules-autolinking';
import JSON5 from 'json5';

import { HarmonyCliError } from '../errors';
import type { HarmonyBuildPlan, HarmonyToolchain } from '../tools';
import { formatDiagnostics, spawnAsync, type ProcessResult } from '../process';

export interface HarmonyOhpmInstallLease {
  fallbackPackages: string[];
  restoreAsync(): Promise<void>;
  usedFallback: boolean;
}

interface InstallOptions {
  timeoutMs?: number;
}

async function readOptionalFileAsync(file) {
  try {
    return await fs.promises.readFile(file);
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw new HarmonyCliError(
      error.code || 'ERR_HARMONY_OHPM_FALLBACK_FAILED',
      error.message || `Cannot read an optional OHPM file: ${file}`,
      { cause: error, exitCode: error.exitCode, operation: error.operation }
    );
  }
}

async function restoreFileAsync(file, content) {
  if (content === null) {
    await fs.promises.rm(file, { force: true });
  } else {
    await fs.promises.writeFile(file, content);
  }
}

function installMessage(result: ProcessResult, suffix = ''): string {
  const diagnostics = formatDiagnostics(result);
  return `OHPM install exited with code ${result.code}${result.timedOut ? ' after timing out' : ''}.`
    + `${diagnostics ? `\n${diagnostics}` : ''}${suffix}`;
}

function renderFallbackManifest(content, specifiers) {
  const manifest = JSON5.parse(content);

  for (const field of ['dependencies', 'overrides']) {
    for (const [packageName, specifier] of Object.entries(specifiers)) {
      manifest[field][packageName] = specifier;
    }
  }

  return `${JSON5.stringify(manifest, null, 2)}\n`;
}

async function installHarmonyDependenciesAsync(
  projectRoot: string,
  plan: HarmonyBuildPlan,
  toolchain: HarmonyToolchain,
  options: InstallOptions = {}
): Promise<HarmonyOhpmInstallLease> {
  const manifest = plan.nativeInputs.manifest;
  const lockfile = plan.nativeInputs.lockfile;
  const source = await fs.promises.readFile(manifest);
  const lock = await readOptionalFileAsync(lockfile);

  const args = [...toolchain.ohpm.args, 'install', '--all'];
  const installAsync = () => spawnAsync(toolchain.ohpm.command, args, {
    capture: true,
    cwd: plan.harmonyRoot,
    operation: 'ohpm-install',
    outputLimit: 2 * 1024 * 1024,
    timeoutMs: options.timeoutMs || 5 * 60_000,
  });

  const first = await installAsync();

  if (first.code === 0 && !first.timedOut) {
    return { fallbackPackages: [], restoreAsync: async () => {}, usedFallback: false };
  }

  let fallbackActive = false;
  const restoreAsync = async () => {
    if (!fallbackActive) return;

    fallbackActive = false;

    await restoreFileAsync(manifest, source);
    await restoreFileAsync(lockfile, lock);
  };

  try {
    const autolinkingManifest = await readManifestAsync(path.join(projectRoot, '.expo/harmony/autolinking.json'));
    const specifiers = localOhpmDependenciesFromManifest(autolinkingManifest, plan.harmonyRoot);

    if (Object.keys(specifiers).length === 0) {
      throw new HarmonyCliError('ERR_HARMONY_OHPM_FAILED', installMessage(first), { exitCode: first.code || 1, operation: 'ohpm-install' });
    }

    fallbackActive = true;

    await fs.promises.writeFile(manifest, renderFallbackManifest(source.toString('utf8'), specifiers));

    const retry = await installAsync();

    if (retry.code !== 0 || retry.timedOut) {
      throw new HarmonyCliError('ERR_HARMONY_OHPM_FAILED', installMessage(retry, '\nLocal HAR fallback also failed.'), { exitCode: retry.code || 1, operation: 'ohpm-install' });
    }

    return {
      fallbackPackages: Object.keys(specifiers).sort((left, right) => left.localeCompare(right, 'en')),
      restoreAsync,
      usedFallback: true,
    };
  } catch (cause) {
    await restoreAsync();

    if (cause instanceof HarmonyCliError && cause.code === 'ERR_HARMONY_OHPM_FAILED') {
      throw new HarmonyCliError(cause.code, cause.message, {
        cause,
        exitCode: cause.exitCode,
        operation: cause.operation,
      });
    }

    throw new HarmonyCliError(
      cause.code || 'ERR_HARMONY_OHPM_FALLBACK_FAILED',
      `${installMessage(first)}\nLocal HAR fallback could not be prepared: ${cause.message}`,
      { cause, operation: 'ohpm-fallback' }
    );
  }
}

export { installHarmonyDependenciesAsync };

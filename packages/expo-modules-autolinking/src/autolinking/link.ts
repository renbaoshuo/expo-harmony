import path from 'node:path';

import type { LinkOptions, LinkResult, VerifyOptions } from '../types';
import { ExpoArtifacts, ManifestArtifact, RnohArtifacts, managedArtifactsForHarmonyRoot } from '../config/constants';
import { renderArkTsHostProviderSource } from '../harmony/providers/host';
import { serializeManifest } from '../harmony/manifest/generate';
import { HarmonyAutolinkingError } from '../errors';
import { normalizeOptionsAsync } from '../config/options';
import { linkRnohAsync } from '../harmony/rnoh/link';
import { cleanupStagingProjectAsync, stageProjectAsync } from '../harmony/transaction/stageProject';
import { publishArtifactsAsync } from '../harmony/transaction/publish';
import { readPreviousAutolinkingStateAsync } from '../harmony/transaction/previousState';
import { assertVerificationSucceeded, verifyModulesAsync } from './verify';
import { emitLog } from '../utilities/values';
import { materializeLocalSourcesAsync } from '../harmony/materialize';

function buildPublishEntries(staging, hostProviderSource, manifest) {
  return [
    ...Object.entries(RnohArtifacts).map(([name, relative]) => ({
      source: staging.rnohArtifacts[name].path,
      target: path.join(staging.harmonyProjectPath, relative),
    })),
    {
      content: hostProviderSource,
      target: path.join(staging.harmonyProjectPath, ExpoArtifacts.hostProvider),
    },
    {
      content: manifest,
      target: path.join(staging.projectRoot, ManifestArtifact),
    },
  ];
}

async function linkModulesAsync(rawOptions: LinkOptions): Promise<LinkResult> {
  const options = await normalizeOptionsAsync(rawOptions);

  if (typeof rawOptions.harmonyProjectPath !== 'string' || !rawOptions.harmonyProjectPath) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'link requires harmonyProjectPath.', { stage: 'link' });
  }

  const verify = await verifyModulesAsync((rawOptions.modules !== undefined
    ? { modules: rawOptions.modules }
    : { ...options, searchResult: rawOptions.searchResult }) as VerifyOptions);
  assertVerificationSucceeded(verify, 'link');

  const modules = verify.modules;
  const pendingSource = modules.filter(module => module.artifact.kind === 'local-source');
  if (pendingSource.length > 0) {
    if (pendingSource.some(module => module.source !== 'nativeModulesDir')) {
      throw new HarmonyAutolinkingError(
        'SOURCE_ARTIFACT_MATERIALIZATION_REQUIRED',
        'Only nativeModulesDir modules may build a local Harmony HAR.',
        { stage: 'link', details: pendingSource.map(module => module.packageName).sort() }
      );
    }
    await materializeLocalSourcesAsync(pendingSource, {
      projectRoot: options.projectRoot,
      timeoutMs: rawOptions.timeoutMs,
      outputLimit: rawOptions.outputLimit,
      env: rawOptions.env,
    });
  }

  const hostProviderSource = renderArkTsHostProviderSource(modules);

  let staging;
  let failure;
  let cleanupWarning;
  const warnings = [];

  try {
    const previous = await readPreviousAutolinkingStateAsync(options.projectRoot);

    if (previous.warning) {
      warnings.push(previous.warning);
      emitLog(rawOptions.logger, 'warn', previous.warning.message, previous.warning);
    }

    staging = await stageProjectAsync({
      projectRoot: options.projectRoot,
      harmonyProjectPath: rawOptions.harmonyProjectPath,
      nodeModulesPath: rawOptions.nodeModulesPath,
      modules,
      buildType: options.buildType,
      previousManagedOhpmPackageNames: previous.managedOhpmPackageNames,
      rnohCliPackageJsonPath: rawOptions.rnohCliPackageJsonPath,
    });

    staging.rnohArtifacts = await linkRnohAsync({
      ...staging,
      modules,
      buildType: options.buildType,
      exclude: staging.rnohRuntimePackages,
      commandNodeModulesPath: staging.sourceNodeModulesPath,
      reactNativeExecutable: rawOptions.reactNativeExecutable,
      rnohCliPackageJsonPath: rawOptions.rnohCliPackageJsonPath,
      timeoutMs: rawOptions.timeoutMs,
      outputLimit: rawOptions.outputLimit,
      env: rawOptions.env,
    });

    const harmonyRoot = path.relative(staging.projectRoot, staging.harmonyProjectPath)
      .split(path.sep).join('/');
    const managed = managedArtifactsForHarmonyRoot(harmonyRoot);

    const manifest = serializeManifest(modules, {
      buildType: options.buildType,
      managedArtifacts: managed,
    });

    const published = await publishArtifactsAsync({
      allowedRoot: staging.projectRoot,
      lockPath: path.join(staging.projectRoot, '.expo/harmony/autolinking.lock'),
      files: buildPublishEntries(staging, hostProviderSource, manifest),
      stale: previous.artifacts.filter(artifact => !managed.some((relative) => {
        return artifact === path.join(staging.projectRoot, ...relative.split('/'));
      })),
    });

    const result: LinkResult = {
      platform: 'harmony',
      modules,
      buildType: options.buildType,
      managedArtifacts: [...managed],
      changedArtifacts: published.changed.map(target => path.relative(staging.projectRoot, target).split(path.sep).join('/')),
      unchangedArtifacts: published.unchanged.map(target => path.relative(staging.projectRoot, target).split(path.sep).join('/')),
      diagnostics: verify.diagnostics,
      warnings,
    };

    emitLog(rawOptions.logger, 'info', 'Harmony autolinking completed.', {
      moduleCount: result.modules.length,
      changedArtifactCount: result.changedArtifacts.length,
    });
    return result;
  } catch (error) {
    failure = error;
    emitLog(rawOptions.logger, 'error', 'Harmony autolinking failed.', {
      code: error.code || 'ERR_EXPO_HARMONY_UNKNOWN',
      stage: error.stage || 'link',
    });
  } finally {
    if (staging) {
      const cleanup = await cleanupStagingProjectAsync(staging);
      if (cleanup) {
        const warning = { ...cleanup };
        delete warning.cause;
        warnings.push(warning);
        emitLog(rawOptions.logger, 'warn', warning.message, warning);
        if (failure) cleanupWarning = warning;
      }
    }
  }

  throw new HarmonyAutolinkingError(
    typeof failure.code === 'string' ? failure.code : 'UNKNOWN',
    failure.message || 'Harmony autolinking failed.',
    {
      cause: failure,
      stage: failure.stage || 'link',
      packageName: failure.packageName,
      diagnostics: failure.diagnostics,
      details: cleanupWarning
        ? { ...(failure.details || {}), cleanupWarning }
        : failure.details,
    }
  );
}

export { linkModulesAsync };

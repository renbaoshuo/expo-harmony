import path from 'node:path';

import type { LinkOptions, LinkResult, VerifyOptions } from '../types';
import { ExpoArtifacts, ManifestArtifact, RnohArtifacts, managedArtifactsForHarmonyRoot } from '../config/constants';
import { createProviderArtifactsAsync } from '../harmony/providers/artifacts';
import { serializeManifest } from '../harmony/manifest/generate';
import { HarmonyAutolinkingError } from '../errors';
import { normalizeOptionsAsync } from '../config/options';
import { linkRnohAsync } from '../harmony/rnoh/link';
import { cleanupStagingProjectAsync, stageProjectAsync } from '../harmony/transaction/stageProject';
import { publishArtifactsAsync } from '../harmony/transaction/publish';
import { readPreviousAutolinkingStateAsync } from '../harmony/transaction/previousState';
import { assertVerificationSucceeded, verifyModulesAsync } from './verify';
import { emitLog } from '../utilities/values';

function buildPublishEntries(staging, artifacts, manifest) {
  return [
    ...Object.entries(RnohArtifacts).map(([name, relative]) => ({
      source: staging.rnohArtifacts[name].path,
      target: path.join(staging.harmonyProjectPath, relative),
    })),
    {
      content: artifacts.source,
      target: path.join(staging.harmonyProjectPath, ExpoArtifacts.provider),
    },
    {
      content: artifacts.cmake,
      target: path.join(staging.harmonyProjectPath, ExpoArtifacts.cmake),
    },
    {
      content: artifacts.hostSource,
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

  const artifacts = await createProviderArtifactsAsync({
    verifiedDescriptors: verify.modules,
    buildType: options.buildType,
  });

  let staging;
  let primaryError;
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
      modules: verify.modules,
      buildType: options.buildType,
      previousManagedOhpmPackageNames: previous.managedOhpmPackageNames,
      rnohCliPackageJsonPath: rawOptions.rnohCliPackageJsonPath,
    });

    const rnoh = await linkRnohAsync({
      ...staging,
      modules: verify.modules,
      buildType: options.buildType,
      exclude: staging.rnohRuntimePackages,
      commandNodeModulesPath: staging.sourceNodeModulesPath,
      reactNativeExecutable: rawOptions.reactNativeExecutable,
      rnohCliPackageJsonPath: rawOptions.rnohCliPackageJsonPath,
      timeoutMs: rawOptions.timeoutMs,
      outputLimit: rawOptions.outputLimit,
      env: rawOptions.env,
      protectedPaths: [staging.harmonyProjectPath],
      protectedShallowPaths: [staging.nodeModulesPath, ...staging.rnohPackageRoots],
    });

    staging.rnohArtifacts = rnoh.artifacts;
    const harmonyRoot = path.relative(staging.projectRoot, staging.harmonyProjectPath)
      .split(path.sep).join('/');
    const managed = managedArtifactsForHarmonyRoot(harmonyRoot);

    const manifest = serializeManifest(verify.modules, {
      buildType: options.buildType,
      managedArtifacts: managed,
    });

    const published = await publishArtifactsAsync({
      allowedRoot: staging.projectRoot,
      lockPath: path.join(staging.projectRoot, '.expo/harmony/autolinking.lock'),
      files: buildPublishEntries(staging, artifacts, manifest),
      stale: previous.artifacts.filter(artifact => !managed.some((relative) => {
        return artifact === path.join(staging.projectRoot, ...relative.split('/'));
      })),
    });

    const result: LinkResult = {
      platform: 'harmony',
      modules: verify.modules,
      providerCount: artifacts.providerCount,
      buildType: artifacts.buildType,
      managedArtifacts: [...managed],
      changedArtifacts: published.changed.map(target => path.relative(staging.projectRoot, target).split(path.sep).join('/')),
      unchangedArtifacts: published.unchanged.map(target => path.relative(staging.projectRoot, target).split(path.sep).join('/')),
      diagnostics: verify.diagnostics,
      warnings,
    };

    emitLog(rawOptions.logger, 'info', 'Harmony autolinking completed.', {
      moduleCount: result.modules.length,
      providerCount: result.providerCount,
      changedArtifactCount: result.changedArtifacts.length,
    });
    return result;
  } catch (error) {
    primaryError = error;
    emitLog(rawOptions.logger, 'error', 'Harmony autolinking failed.', {
      code: error.code || 'ERR_EXPO_HARMONY_UNKNOWN',
      stage: error.stage || 'link',
    });
    throw error;
  } finally {
    if (staging) {
      const warning = await cleanupStagingProjectAsync(staging);
      if (warning) {
        const safeWarning = { ...warning };
        delete safeWarning.cause;
        warnings.push(safeWarning);
        emitLog(rawOptions.logger, 'warn', safeWarning.message, safeWarning);
        if (primaryError) primaryError.cleanupWarning = safeWarning;
      }
    }
  }
}

export { linkModulesAsync };

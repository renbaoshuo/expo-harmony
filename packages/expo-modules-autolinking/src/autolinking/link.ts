/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import path from 'node:path';

import type { LinkOptions, LinkResult } from '../types';
import { ExpoArtifacts, ManifestArtifact, ModuleBuildOptionsArtifact, RnohArtifacts, managedArtifactsForHarmonyRoot } from '../config/constants';
import { renderArkTsHostProviderSource } from '../harmony/providers/host';
import { inlineModuleArtifacts, readInlineModuleContent } from '../harmony/inlineModules';
import { serializeManifest } from '../harmony/manifest/generate';
import { createNativeModuleContracts } from '../harmony/manifest/runtime';
import { HarmonyAutolinkingError } from '../errors';
import { linkRnohAsync } from '../harmony/rnoh/link';
import { renderRnohEtsFactories } from '../harmony/rnoh/etsFactory';
import { cleanupStagingProjectAsync, readOhpmManifestSourceAsync, stageProjectAsync } from '../harmony/transaction/stageProject';
import { publishArtifactsAsync } from '../harmony/transaction/publish';
import { readPreviousAutolinkingStateAsync } from '../harmony/transaction/previousState';
import { emitLog } from '../utilities/values';
import { prepareModulesAsync } from './prepare';

function buildPublishEntries(stage, modules, provider, manifest) {
  const factories = renderRnohEtsFactories(modules);
  return [
    ...Object.entries(RnohArtifacts).map(([name, relative]) => ({
      ...(name === 'etsFactory'
        ? { content: factories.ui }
        : name === 'ohPackage'
          ? { content: stage.ohpmManifest }
          : { source: stage.rnohArtifacts[name].path }),
      target: path.join(stage.harmonyProjectPath, relative),
    })),
    {
      content: factories.worker,
      target: path.join(stage.harmonyProjectPath, ExpoArtifacts.workerFactory),
    },
    {
      content: provider,
      target: path.join(stage.harmonyProjectPath, ExpoArtifacts.hostProvider),
    },
    ...modules.flatMap(module => inlineModuleArtifacts(module).map((relative, index) => ({
      content: readInlineModuleContent(module.packageRoot, module.inlineModules.files[index]),
      target: path.join(stage.harmonyProjectPath, relative),
    }))),
    {
      content: manifest,
      target: path.join(stage.projectRoot, ManifestArtifact),
    },
  ];
}

async function linkPreparedModulesAsync(
  input: LinkOptions,
  prepared: Awaited<ReturnType<typeof prepareModulesAsync>>
): Promise<LinkResult> {
  const { options, modules, diagnostics } = prepared;
  if (modules.some(module => module.inlineModules && module.packageRoot !== options.projectRoot)) {
    throw new HarmonyAutolinkingError('INVALID_INLINE_MODULE', 'Inline module sources must belong to the app being linked.', { stage: 'link' });
  }

  const provider = renderArkTsHostProviderSource(modules);

  let stage;
  let failure;
  let cleanupWarning;
  const warnings = [];

  try {
    const previous = await readPreviousAutolinkingStateAsync(options.projectRoot, input.harmonyProjectPath);

    if (previous.warning) {
      warnings.push(previous.warning);
      emitLog(input.logger, 'warn', previous.warning.message, previous.warning);
    }

    stage = await stageProjectAsync({
      projectRoot: options.projectRoot,
      harmonyProjectPath: input.harmonyProjectPath,
      nodeModulesPath: input.nodeModulesPath,
      modules,
      buildType: options.buildType,
      previousManagedOhpmPackageNames: previous.managedOhpmPackageNames,
      rnohCliPackageJsonPath: input.rnohCliPackageJsonPath,
    });

    stage.rnohArtifacts = await linkRnohAsync({
      ...stage,
      modules,
      buildType: options.buildType,
      exclude: stage.rnohRuntimePackages,
      commandNodeModulesPath: stage.sourceNodeModulesPath,
      reactNativeExecutable: input.reactNativeExecutable,
      rnohCliPackageJsonPath: input.rnohCliPackageJsonPath,
      timeoutMs: input.timeoutMs,
      outputLimit: input.outputLimit,
      env: input.env,
    });

    const harmonyRoot = path.relative(stage.projectRoot, stage.harmonyProjectPath)
      .split(path.sep).join('/');
    const managed = [
      ...managedArtifactsForHarmonyRoot(harmonyRoot),
      ...modules.flatMap(inlineModuleArtifacts).map(file => path.posix.join(harmonyRoot, file)),
    ];

    const manifest = serializeManifest(modules, {
      buildType: options.buildType,
      managedArtifacts: managed,
      runtimeModules: createNativeModuleContracts(modules),
    });

    const published = await publishArtifactsAsync({
      allowedRoot: stage.projectRoot,
      lockPath: path.join(stage.projectRoot, '.expo/harmony/autolinking.lock'),
      async validateSnapshot() {
        const current = await readPreviousAutolinkingStateAsync(stage.projectRoot, stage.harmonyProjectPath);
        if (current.source !== previous.source) {
          throw new HarmonyAutolinkingError('PUBLISH_FAILED', 'Another process changed the Harmony autolinking manifest. Retry autolinking.', { stage: 'publish' });
        }
        if (await readOhpmManifestSourceAsync(stage.harmonyProjectPath) !== stage.previousOhpmManifest) {
          throw new HarmonyAutolinkingError('PUBLISH_FAILED', 'Another process changed the Harmony OHPM manifest. Retry autolinking.', { stage: 'publish' });
        }
      },
      files: [
        ...buildPublishEntries(stage, modules, provider, manifest),
        ...(input.moduleBuilds !== undefined
          ? [{
              target: path.join(stage.projectRoot, ModuleBuildOptionsArtifact),
              content: JSON.stringify({
                schemaVersion: 1,
                moduleBuilds: input.moduleBuilds,
                moduleBuildSettings: input.moduleBuildSettings,
                expoInlineModules: options.persistedExpoInlineModules,
              }, null, 2) + '\n',
            }]
          : []),
      ],
      stale: previous.artifacts.filter(artifact => !managed.some((relative) => {
        return artifact === path.join(stage.projectRoot, ...relative.split('/'));
      })),
    });

    const result: LinkResult = {
      platform: 'harmony',
      modules,
      buildType: options.buildType,
      managedArtifacts: [...managed],
      changedArtifacts: published.changed.map(target => path.relative(stage.projectRoot, target).split(path.sep).join('/')),
      unchangedArtifacts: published.unchanged.map(target => path.relative(stage.projectRoot, target).split(path.sep).join('/')),
      diagnostics,
      warnings,
    };

    emitLog(input.logger, 'info', 'Harmony autolinking completed.', {
      moduleCount: result.modules.length,
      changedArtifactCount: result.changedArtifacts.length,
    });

    return result;
  } catch (error) {
    failure = error;
    emitLog(input.logger, 'error', 'Harmony autolinking failed.', {
      code: error.code || 'ERR_EXPO_HARMONY_UNKNOWN',
      stage: error.stage || 'link',
    });
  } finally {
    if (stage) {
      const cleanup = await cleanupStagingProjectAsync(stage);
      if (cleanup) {
        const warning = { ...cleanup };
        delete warning.cause;
        warnings.push(warning);
        emitLog(input.logger, 'warn', warning.message, warning);
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

async function linkModulesAsync(input: LinkOptions): Promise<LinkResult> {
  return linkPreparedModulesAsync(input, await prepareModulesAsync(input));
}

export { linkModulesAsync, linkPreparedModulesAsync };

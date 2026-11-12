/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { LinkOptions, VerificationResult } from '../types';
import { HarmonyAutolinkingError } from '../errors';
import { normalizeOptionsAsync } from '../config/options';
import { materializeLocalSourcesAsync } from '../harmony/materialize';
import { buildConfiguredModulesAsync } from '../harmony/configuredBuild';
import { assertVerificationSucceeded, verifyModulesAsync } from './verify';

export async function prepareModulesAsync(raw: LinkOptions) {
  const options = await normalizeOptionsAsync(raw);
  if (typeof raw.harmonyProjectPath !== 'string' || !raw.harmonyProjectPath) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'link requires harmonyProjectPath.', { stage: 'link' });
  }

  const verify = await verifyModulesAsync({
    ...raw,
    projectRoot: options.projectRoot,
    buildType: options.buildType,
    inlineModules: options.inlineModules,
    searchResult: raw.modules === undefined ? raw.searchResult : undefined,
  });

  assertVerificationSucceeded(verify, 'link');

  let modules = verify.modules;
  const pending = modules.filter(module => module.artifact.kind === 'local-source');
  if (pending.length > 0) {
    if (pending.some(module => module.source !== 'nativeModulesDir')) {
      throw new HarmonyAutolinkingError(
        'SOURCE_ARTIFACT_MATERIALIZATION_REQUIRED',
        'Only nativeModulesDir modules may build a local Harmony HAR.',
        { stage: 'link', details: pending.map(module => module.packageName).sort() }
      );
    }

    const built = await materializeLocalSourcesAsync(pending, {
      dependencies: modules,
      projectRoot: options.projectRoot,
      timeoutMs: raw.timeoutMs,
      outputLimit: raw.outputLimit,
      env: raw.env,
    });

    const artifacts = new Map(built.map(module => [module.packageName, module.builtHarPath]));
    modules = modules.map((module) => {
      const builtHarPath = artifacts.get(module.packageName);
      return builtHarPath ? { ...module, arkTs: { ...module.arkTs, builtHarPath } } : module;
    });
  }

  return {
    options,
    diagnostics: verify.diagnostics,
    modules: await buildConfiguredModulesAsync(modules, {
      ...raw, projectRoot: options.projectRoot, buildType: options.buildType,
    }),
  };
}

export async function prepareRuntimeModulesAsync(
  raw: Omit<LinkOptions, 'harmonyProjectPath'>
): Promise<VerificationResult> {
  const options = await normalizeOptionsAsync(raw);
  const result = await verifyModulesAsync({
    ...raw,
    projectRoot: options.projectRoot,
    buildType: options.buildType,
    inlineModules: options.inlineModules,
  });

  if (!result.valid) return result;

  return {
    ...result,
    modules: await buildConfiguredModulesAsync(result.modules, {
      ...raw, projectRoot: options.projectRoot, buildType: options.buildType,
    }),
  };
}

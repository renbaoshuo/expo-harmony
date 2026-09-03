import {
  resolveModulesAsync,
  searchModulesAsync,
  verifyModulesAsync,
  type BuildType,
  type Diagnostic,
  type ModuleDescriptor,
  type ModuleSource,
} from '@expo-harmony/expo-modules-autolinking';

import { HarmonyCliError } from '../errors';
import type { ModulesAction } from './options';

interface ModulesCommandOptions {
  action: ModulesAction;
  nativeModulesDir?: string;
  packageName?: string;
  variant?: BuildType;
}

interface ListedModule {
  packageName: string;
  packageVersion: string;
  source: ModuleSource;
  supportsHarmony: boolean;
}

interface ModulesListResult {
  action: 'list';
  duplicates: ReadonlyArray<{
    packageName: string;
    revisions: ReadonlyArray<{ path: string; version: string }>;
  }>;
  missingIncludes: ReadonlyArray<string>;
  modules: ReadonlyArray<ListedModule>;
  ok: boolean;
}

interface ModulesInspectResult {
  action: 'inspect';
  modules: ReadonlyArray<ModuleDescriptor>;
  ok: boolean;
}

interface ModulesVerifyResult {
  action: 'verify';
  diagnostics: ReadonlyArray<Diagnostic>;
  modules: ReadonlyArray<ModuleDescriptor>;
  ok: boolean;
}

export type ModulesCommandResult = ModulesInspectResult | ModulesListResult | ModulesVerifyResult;

function apiOptions(projectRoot: string, options: ModulesCommandOptions) {
  return {
    projectRoot,
    platform: 'harmony' as const,
    ...(options.nativeModulesDir === undefined ? {} : { nativeModulesDir: options.nativeModulesDir }),
    ...(options.variant === undefined ? {} : { buildType: options.variant }),
  };
}

async function runModulesCommandAsync(
  projectRoot: string,
  options: ModulesCommandOptions
): Promise<ModulesCommandResult> {
  const shared = apiOptions(projectRoot, options);

  if (options.action === 'list') {
    const result = await searchModulesAsync(shared);

    return {
      action: 'list',
      duplicates: result.duplicates,
      missingIncludes: result.missingIncludes,
      modules: result.modules.map(module => ({
        packageName: module.packageName,
        packageVersion: module.packageVersion,
        source: module.source,
        supportsHarmony: module.supportsHarmony,
      })),
      ok: result.missingIncludes.length === 0,
    };
  }

  if (options.action === 'inspect') {
    const modules = await resolveModulesAsync(shared);
    const selected = options.packageName === undefined
      ? modules
      : modules.filter(module => module.packageName === options.packageName);

    if (options.packageName !== undefined && selected.length === 0) {
      throw new HarmonyCliError(
        'ERR_HARMONY_MODULE_NOT_FOUND',
        `Harmony module '${options.packageName}' was not discovered. Run 'expo-harmony modules list' to inspect candidates.`,
        { operation: 'modules-inspect' }
      );
    }

    return { action: 'inspect', modules: selected, ok: true };
  }

  const result = await verifyModulesAsync(shared);

  return {
    action: 'verify',
    diagnostics: result.diagnostics,
    modules: result.modules,
    ok: result.valid,
  };
}

function formatDiagnostic(diagnostic: Diagnostic): string {
  const subject = diagnostic.packageName ? ` ${diagnostic.packageName}` : '';
  return `${diagnostic.severity === 'error' ? '✗' : '!'} [${diagnostic.code}]${subject}: ${diagnostic.message}`;
}

function formatModulesResult(result: ModulesCommandResult): string {
  if (result.action === 'list') {
    const lines = result.modules.map(module => (
      `${module.supportsHarmony ? '✓' : '-'} ${module.packageName}@${module.packageVersion} [${module.source}]`
    ));
    for (const packageName of result.missingIncludes) {
      lines.push(`✗ missing required package ${packageName}`);
    }
    for (const duplicate of result.duplicates) {
      lines.push(`! duplicate ${duplicate.packageName}: ${duplicate.revisions.map(item => item.version).join(', ')}`);
    }
    return lines.length === 0 ? 'No native module candidates were discovered.' : lines.join('\n');
  }

  if (result.action === 'verify') {
    if (result.diagnostics.length === 0) {
      return `✓ Verified ${result.modules.length} Harmony native module(s).`;
    }
    return result.diagnostics.map(formatDiagnostic).join('\n');
  }

  return result.modules.map((module) => {
    const arkTsModules = module.harmony.modules.join(', ') || 'none';
    const har = module.arkTs
      ? `${module.arkTs.ohPackageName} <- ${module.arkTs.harPath}`
      : 'none';
    return [
      `${module.packageName}@${module.packageVersion}`,
      `  source: ${module.source}`,
      `  packageRoot: ${module.packageRoot}`,
      `  ArkTS modules: ${arkTsModules}`,
      `  HAR: ${har}`,
    ].join('\n');
  }).join('\n');
}

export { formatModulesResult, runModulesCommandAsync };

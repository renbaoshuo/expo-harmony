import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { doctorAsync, type DoctorResult } from '../doctor/doctor';
import { resolveHarmonyEntryPoint } from '../entry';
import { HarmonyCliError } from '../errors';
import { resolveHarmonyBuildPlanAsync } from '../tools';
import { formatDiagnostics, spawnAsync } from '../process';
import { inspectPublicCliContractsAsync } from '../contract';
import { resolveExpoCli } from '../expo';
import { compileHermesAsync } from './hermes';
import {
  assertHermesBundle, assertSourceMap, exportPaths,
  publishExportAsync, validatePublishedExportAsync,
  type HarmonyExportManifest,
} from './manifest';

export interface ExportOptions {
  check?: boolean;
  resetCache?: boolean;
  skipContract?: boolean;
  skipDoctor?: boolean;
  timeoutMs?: number;
}

export interface ExportTemporary {
  assets: string;
  bundle: string;
  javascript: string;
  metroSourceMap: string;
  sourceMap: string;
}

function createExpoExportEmbedArgs(
  projectRoot: string,
  entryFile: string,
  temporary: Pick<ExportTemporary, 'assets' | 'javascript' | 'metroSourceMap'>,
  options: ExportOptions = {}
) {
  return [
    'export:embed',
    '--platform', 'harmony',
    '--entry-file', entryFile,
    '--bundle-output', temporary.javascript,
    '--assets-dest', temporary.assets,
    '--dev', 'false',
    '--minify', 'true',
    '--sourcemap-output', temporary.metroSourceMap,
    '--sourcemap-sources-root', '.',
    '--unstable-transform-profile', 'hermes-stable',
    ...(options.resetCache ? ['--reset-cache=true'] : []),
    projectRoot,
  ];
}

function assertDoctor(result: DoctorResult) {
  if (result.ok) return;

  const failing = result.checks.filter(check => check.status === 'error').map(check => check.id);
  throw new HarmonyCliError('ERR_HARMONY_EXPORT_DOCTOR', `Harmony doctor found blocking checks: ${failing.join(', ') || 'unknown'}.`, { operation: 'doctor' });
}

async function exportEmbedAsync(
  projectRoot: string,
  options: ExportOptions = {}
): Promise<HarmonyExportManifest> {
  if (!options.skipDoctor) assertDoctor(await doctorAsync(projectRoot));
  if (!options.skipContract) await inspectPublicCliContractsAsync(projectRoot);

  const plan = await resolveHarmonyBuildPlanAsync(projectRoot, { buildMode: 'release' });
  const paths = exportPaths(projectRoot, plan);

  if (options.check) return await validatePublishedExportAsync(paths);

  const entryFile = resolveHarmonyEntryPoint(projectRoot);
  const temporaryRoot = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-harmony-export-'));
  const temporary: ExportTemporary = {
    assets: path.join(temporaryRoot, 'assets'),
    bundle: path.join(temporaryRoot, 'hermes_bundle.hbc'),
    javascript: path.join(temporaryRoot, 'index.js'),
    metroSourceMap: path.join(temporaryRoot, 'index.js.map'),
    sourceMap: path.join(temporaryRoot, 'hermes_bundle.hbc.map'),
  };

  try {
    await fs.promises.mkdir(temporary.assets, { recursive: true });

    const expo = resolveExpoCli(projectRoot);
    const result = await spawnAsync(process.execPath, [
      expo.cliPath,
      ...createExpoExportEmbedArgs(projectRoot, entryFile, temporary, options),
    ], {
      capture: true,
      cwd: projectRoot,
      env: {
        ...process.env,
        EXPO_METRO_TARGET: 'harmony',
        HERMES_V1_ENABLED: 'true',
        NODE_ENV: 'production',
      },
      operation: 'expo-export-embed',
      outputLimit: 4 * 1024 * 1024,
      timeoutMs: options.timeoutMs || 10 * 60_000,
    });

    if (result.code !== 0 || result.timedOut) {
      const diagnostics = formatDiagnostics(result);
      throw new HarmonyCliError(
        'ERR_HARMONY_EXPORT_FAILED',
        `Expo export:embed exited with code ${result.code}${result.timedOut ? ' after timing out' : ''}.${diagnostics ? `\n${diagnostics}` : ''}`,
        { exitCode: result.code || 1, operation: 'expo-export-embed' }
      );
    }

    await compileHermesAsync(projectRoot, temporary, options);

    const bytecode = await assertHermesBundle(temporary.bundle);
    await assertSourceMap(temporary.sourceMap);

    return await publishExportAsync(projectRoot, paths, temporary, entryFile, bytecode);
  } finally {
    await fs.promises.rm(temporaryRoot, { force: true, recursive: true });
  }
}

export {
  exportEmbedAsync,
};

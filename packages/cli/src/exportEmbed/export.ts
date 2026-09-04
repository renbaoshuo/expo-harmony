import fs from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';

import { doctorAsync, type DoctorResult } from '../doctor/doctor';
import { resolveHarmonyEntryPoint } from '../entry';
import { HarmonyCliError } from '../errors';
import { withHarmonyProjectLockAsync } from '../projectLock';
import { resolveHarmonyBuildPlanAsync } from '../tools';
import { formatDiagnostics, spawnAsync } from '../process';
import { resolveExpoCli, resolveExpoHermesBuilder } from '../expo';
import {
  assertHermesBundle, assertSourceMap, exportPaths,
  publishExportAsync, validatePublishedExportAsync,
  type HarmonyExportManifest,
} from './manifest';

export interface ExportOptions {
  check?: boolean;
  resetCache?: boolean;
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
  temporary: ExportTemporary,
  options: ExportOptions = {}
) {
  return [
    'export:embed',
    '--platform', 'harmony',
    '--entry-file', entryFile,
    '--bundle-output', temporary.javascript,
    '--assets-dest', temporary.assets,
    '--dev', 'false',
    '--minify', 'false',
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

async function exportEmbedUnlockedAsync(
  projectRoot: string,
  options: ExportOptions = {}
): Promise<HarmonyExportManifest> {
  if (!options.skipDoctor) assertDoctor(await doctorAsync(projectRoot));

  const plan = await resolveHarmonyBuildPlanAsync(projectRoot, { buildMode: 'release' });
  const paths = exportPaths(plan);

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

    // Expo 55 only infers Hermes for iOS and Android. Keep Harmony bundling in the Expo CLI,
    // then explicitly hand its JS and source map to Expo's own Hermes exporter.
    try {
      const [code, map] = await Promise.all([
        fs.promises.readFile(temporary.javascript, 'utf8'),
        fs.promises.readFile(temporary.metroSourceMap, 'utf8'),
      ]);
      const buildHermesBundleAsync = resolveExpoHermesBuilder(projectRoot);
      // Expo resolves hermes-compiler from react-native. For Harmony, resolve it
      // from RNOH instead of the app's Android/iOS React Native installation.
      const projectRequire = createRequire(path.join(projectRoot, 'package.json'));
      const harmonyRuntime = path.dirname(projectRequire.resolve('@react-native-oh/react-native-harmony/package.json'));
      const compilerModules = path.join(temporaryRoot, 'node_modules');
      await fs.promises.mkdir(compilerModules);
      await fs.promises.symlink(harmonyRuntime, path.join(compilerModules, 'react-native'),
        process.platform === 'win32' ? 'junction' : 'dir');
      const output = await buildHermesBundleAsync({
        code,
        filename: entryFile,
        map,
        minify: true,
        projectRoot: temporaryRoot,
      });

      if (!(output?.hbc instanceof Uint8Array) || typeof output.sourcemap !== 'string') {
        throw new Error('Expo did not return Hermes bytecode and a composed source map.');
      }

      await Promise.all([
        fs.promises.writeFile(temporary.bundle, output.hbc),
        fs.promises.writeFile(temporary.sourceMap, output.sourcemap),
      ]);
    } catch (cause) {
      if (cause instanceof HarmonyCliError) throw cause;
      throw new HarmonyCliError(
        'ERR_HARMONY_EXPORT_HERMES',
        'Expo failed to compile the Harmony bundle to Hermes bytecode.',
        { cause, operation: 'expo-hermes-export' }
      );
    }

    const bytecode = await assertHermesBundle(temporary.bundle);
    await assertSourceMap(temporary.sourceMap);

    return await publishExportAsync(projectRoot, paths, temporary, entryFile, bytecode);
  } finally {
    await fs.promises.rm(temporaryRoot, { force: true, recursive: true });
  }
}

async function exportEmbedAsync(
  projectRoot: string,
  options: ExportOptions = {}
): Promise<HarmonyExportManifest> {
  return withHarmonyProjectLockAsync(
    projectRoot,
    'export:embed',
    () => exportEmbedUnlockedAsync(projectRoot, options)
  );
}

export {
  exportEmbedAsync,
};

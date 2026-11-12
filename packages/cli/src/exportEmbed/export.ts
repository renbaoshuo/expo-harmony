/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { publishEmbeddedUpdateAsync } from '../updates/export';
import { doctorAsync } from '../doctor/doctor';
import { resolveHarmonyEntryPoint } from '../entry';
import { HarmonyCliError } from '../errors';
import { withHarmonyProjectLockAsync } from '../projectLock';
import { resolveHarmonyBuildPlanAsync } from '../native/project';
import type { HarmonyBuildMode } from '../native/types';
import { formatDiagnostics, spawnAsync } from '../process';
import { resolveTimeoutMs } from '../timeout';
import { resolveExpoHermesBuilder } from '../expo';
import { readMetroRuntimeAsync, resolveMetroRuntimeRoot } from '../runtime/config';
import {
  assertHermesBundle, assertSourceMap, exportPaths,
  publishExportAsync, validatePublishedExportAsync,
  type HarmonyExportManifest,
} from './manifest';

export interface ExportOptions {
  buildMode?: HarmonyBuildMode;
  check?: boolean;
  outputDirectory?: string;
  resetCache?: boolean;
  skipDoctor?: boolean;
  timeoutMs?: number;
}

export interface ExportTemporary {
  assets: string;
  bundle: string;
  javascript: string;
  metroSourceMap: string;
  metadata: string;
  sourceMap: string;
}

async function exportEmbedUnlockedAsync(
  root: string,
  options: ExportOptions = {}
): Promise<HarmonyExportManifest> {
  const buildMode = options.buildMode ?? 'release';
  const mode = buildMode === 'release' ? 'production' : 'development';
  if (!options.skipDoctor) {
    const doctor = await doctorAsync(root, { envMode: mode, requireDeviceTools: false });
    if (!doctor.ok) {
      const checks = doctor.checks.filter(check => check.status === 'error').map(check => check.id);

      throw new HarmonyCliError('ERR_HARMONY_EXPORT_DOCTOR', `Harmony doctor found blocking checks: ${checks.join(', ') || 'unknown'}.`, { operation: 'doctor' });
    }
  }

  const plan = await resolveHarmonyBuildPlanAsync(root, { buildMode });
  const paths = options.outputDirectory
    ? {
        rawfileRoot: path.join(options.outputDirectory, 'embedded'), bundle: path.join(options.outputDirectory, 'embedded/hermes_bundle.hbc'),
        metadataRoot: options.outputDirectory, manifest: path.join(options.outputDirectory, 'export-manifest.json'),
        sourceMap: path.join(options.outputDirectory, 'hermes_bundle.hbc.map'),
      }
    : exportPaths(plan);

  if (options.check) return await validatePublishedExportAsync(paths);

  const entry = resolveHarmonyEntryPoint(root);
  const directory = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-harmony-export-'));
  const temp: ExportTemporary = {
    assets: path.join(directory, 'assets'),
    metadata: path.join(directory, 'assets.json'),
    bundle: path.join(directory, 'hermes_bundle.hbc'),
    javascript: path.join(directory, 'index.js'),
    metroSourceMap: path.join(directory, 'index.js.map'),
    sourceMap: path.join(directory, 'hermes_bundle.hbc.map'),
  };

  try {
    await fs.promises.mkdir(temp.assets, { recursive: true });

    const result = await spawnAsync(process.execPath, [
      path.resolve(__dirname, '../internal/export.js'), root,
      JSON.stringify({ update: !!options.outputDirectory, platform: 'harmony', entryFile: entry, bundleOutput: temp.javascript, assetsDest: temp.assets,
        dev: false, minify: false, sourcemapOutput: temp.metroSourceMap, sourcemapSourcesRoot: '.',
        unstableTransformProfile: 'hermes-stable', resetCache: options.resetCache }), temp.metadata,
    ], {
      capture: true,
      cwd: root,
      env: {
        ...process.env,
        NODE_ENV: process.env.NODE_ENV || mode,
        EXPO_HARMONY: '1',
        EXPO_METRO_TARGET: 'harmony',
        HERMES_V1_ENABLED: 'true',
      },
      operation: 'expo-export-embed',
      outputLimit: 4 * 1024 * 1024,
      timeoutMs: resolveTimeoutMs('expo-export-embed', 10 * 60_000, options.timeoutMs),
    });

    if (result.code !== 0 || result.timedOut) {
      const diagnostics = formatDiagnostics(result);

      throw new HarmonyCliError(
        'ERR_HARMONY_EXPORT_FAILED',
        `Expo export:embed exited with code ${result.code}${result.timedOut ? ' after timing out' : ''}.${diagnostics ? `\n${diagnostics}` : ''}`,
        { exitCode: result.code || 1, operation: 'expo-export-embed' }
      );
    }

    // Expo only infers Hermes for its built-in native platforms. Keep Harmony bundling in the Expo CLI,
    // then explicitly hand its JS and source map to Expo's own Hermes exporter.
    try {
      const [code, map] = await Promise.all([
        fs.promises.readFile(temp.javascript, 'utf8'),
        fs.promises.readFile(temp.metroSourceMap, 'utf8'),
      ]);
      const buildHermes = resolveExpoHermesBuilder(root);

      // Expo resolves hermes-compiler from react-native. For Harmony, resolve it
      // from RNOH instead of the app's Android/iOS React Native installation.
      const runtime = resolveMetroRuntimeRoot(root, await readMetroRuntimeAsync(root, mode));
      const modules = path.join(directory, 'node_modules');

      await fs.promises.mkdir(modules);
      await fs.promises.symlink(runtime, path.join(modules, 'react-native'),
        process.platform === 'win32' ? 'junction' : 'dir');

      const output = await buildHermes({
        code,
        filename: entry,
        map,
        minify: true,
        projectRoot: directory,
      });

      if (typeof output.sourcemap !== 'string') {
        throw new Error('Expo did not return a composed Hermes source map.');
      }

      await Promise.all([
        fs.promises.writeFile(temp.bundle, output.hbc),
        fs.promises.writeFile(temp.sourceMap, output.sourcemap),
      ]);
    } catch (cause) {
      if (cause instanceof HarmonyCliError) {
        throw cause;
      }

      throw new HarmonyCliError(
        'ERR_HARMONY_EXPORT_HERMES',
        'Expo failed to compile the Harmony bundle to Hermes bytecode.',
        { cause, operation: 'expo-hermes-export' }
      );
    }

    const bytecode = assertHermesBundle(temp.bundle);
    await assertSourceMap(temp.sourceMap);

    const manifest = await publishExportAsync(root, paths, temp, entry, bytecode);
    await publishEmbeddedUpdateAsync(root, paths, JSON.parse(await fs.promises.readFile(temp.metadata, 'utf8')), mode);

    return manifest;
  } finally {
    await fs.promises.rm(directory, { force: true, recursive: true });
  }
}

async function exportEmbedAsync(
  root: string,
  options: ExportOptions = {}
): Promise<HarmonyExportManifest> {
  return withHarmonyProjectLockAsync(
    root,
    'export:embed',
    canonicalRoot => exportEmbedUnlockedAsync(canonicalRoot, options)
  );
}

export { exportEmbedAsync };

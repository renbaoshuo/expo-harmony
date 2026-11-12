/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { writeHarmonyNativeInputsStampSync } from '@expo-harmony/expo-modules-autolinking/native-inputs';
import spawn from 'cross-spawn';

import { HarmonyCliError } from '../errors';
import { readHermesBytecode } from './hermes';
import { createHarmonyToolchainEnv, resolveHarmonyToolchain } from './toolchain';
import { prepareLocalOhpmOverrides } from './ohpm';

function nodeExecutable(): string {
  return process.env.EXPO_HARMONY_NODE || 'node';
}

function run(command: string, args: string[], cwd: string, env: NodeJS.ProcessEnv = {}): void {
  const result = spawn.sync(command, args, {
    cwd,
    env: { ...createHarmonyToolchainEnv(), EXPO_HARMONY: '1', EXPO_METRO_TARGET: 'harmony', HERMES_V1_ENABLED: 'true', ...env },
    stdio: 'inherit',
    timeout: 10 * 60_000,
  });

  if (result.error) throw result.error;

  if (result.status !== 0) {
    throw new HarmonyCliError('ERR_HARMONY_NATIVE_BUILD', `Harmony build command failed: ${command} (${result.status}).`, { exitCode: result.status || 1, operation: 'native-build' });
  }
}

// Hvigor configuration is synchronous; linking must finish before task execution.
export function prepareHarmonyNativeBuild(root: string, mode: 'debug' | 'release'): void {
  const harmony = path.join(root, 'harmony');

  if (process.env.EXPO_HARMONY_NATIVE_PREPARED !== '1') {
    const require = createRequire(path.join(root, 'package.json'));
    const manifest = require.resolve('@expo-harmony/expo-modules-autolinking/package.json');
    const bin = path.resolve(path.dirname(manifest), require(manifest).bin['expo-harmony-autolinking']);

    run(nodeExecutable(), [bin, 'link', '--project-root', root, '--harmony-project-path', harmony, '--build-type', mode], root);

    const { ohpm } = resolveHarmonyToolchain();
    const restore = prepareLocalOhpmOverrides(root, harmony);
    try {
      run(ohpm.command, [...ohpm.args, 'install', '--all'], harmony);
    } finally {
      restore();
    }
  }

  publishHarmonyNativeRuntime(root, mode);
  writeHarmonyNativeInputsStamp(root);
}

export function writeHarmonyNativeInputsStamp(root: string): void {
  writeHarmonyNativeInputsStampSync({
    projectRoot: root,
    harmonyRoot: path.join(root, 'harmony'),
  });
}

function embeddedBundlePath(root: string): string {
  return path.join(root, 'harmony/entry/src/main/resources/rawfile/hermes_bundle.hbc');
}

export function bundleHarmonyNativeBuild(
  root: string,
  bundle = embeddedBundlePath(root),
  mode: 'debug' | 'release' = 'release'
): void {
  if (process.env.EXPO_HARMONY_BUNDLE_PREBUILT !== '1') {
    const require = createRequire(path.join(root, 'package.json'));
    run(nodeExecutable(), [require.resolve('@expo-harmony/cli/bin/expo-harmony'), 'export:embed', root], root, {
      EXPO_HARMONY_EXPORT_EMBED_IN_HVIGOR: '1',
      EXPO_HARMONY_BUILD_TYPE: mode,
    });
  }

  try {
    readHermesBytecode(bundle);
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_EXPORT_INVALID_BUNDLE', 'The embedded Harmony bundle is missing or is not Hermes bytecode.', { cause, operation: 'native-build' });
  }
}

/** Prepares the rawfile tree before Hvigor processes resources and returns its bundle task. */
export function prepareHarmonyBundleTask(
  root: string,
  mode: 'debug' | 'release',
  onBuildFinished: (restore: () => void) => void,
  bundle = embeddedBundlePath(root)
): () => void {
  if (mode === 'release' || JSON.parse(fs.readFileSync(path.join(path.dirname(bundle), 'expo-updates/config.json'), 'utf8')).useNativeDebug === true) {
    return () => bundleHarmonyNativeBuild(root, bundle, mode);
  }
  if (!fs.existsSync(bundle)) return () => {};

  const backupRoot = path.join(root, '.expo', 'harmony');

  fs.mkdirSync(backupRoot, { recursive: true });
  const backupDir = fs.mkdtempSync(path.join(backupRoot, 'debug-build-'));
  const backup = path.join(backupDir, path.basename(bundle));

  fs.renameSync(bundle, backup);
  let pending = true;

  const restore = () => {
    if (!pending) return;
    if (!fs.existsSync(backup)) {
      pending = false;
      process.removeListener('exit', restoreOnExit);
      fs.rmSync(backupDir, { recursive: true, force: true });
      throw new Error('Cannot restore the release Harmony bundle because its debug-build backup is missing.');
    }
    if (fs.existsSync(bundle)) {
      throw new Error('Cannot restore the release Harmony bundle because its destination changed during the debug build.');
    }

    fs.renameSync(backup, bundle);
    pending = false;
    process.removeListener('exit', restoreOnExit);
    fs.rmSync(backupDir, { recursive: true, force: true });
  };
  const restoreOnExit = () => {
    try {
      restore();
    } catch (error) {
      process.stderr.write(`[expo-harmony] Failed to restore the release bundle: ${String(error)}\n`);
    }
  };

  process.once('exit', restoreOnExit);
  onBuildFinished(restore);
  return () => {};
}

export function publishHarmonyNativeRuntime(root: string, mode: 'debug' | 'release'): void {
  const require = createRequire(path.join(root, 'package.json'));
  run(nodeExecutable(), [require.resolve('@expo-harmony/cli/bin/expo-harmony'), 'runtime', root, '--publish', '--variant', mode], root);
}

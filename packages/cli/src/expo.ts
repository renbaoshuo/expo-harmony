/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { fork } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';

import type { EnvMode } from '@expo-harmony/expo__config/internal/project-config';

import { HarmonyCliError } from './errors';
import { resolveTimeoutMs } from './timeout';

interface ExpoHermesBundleOptions {
  code: string;
  filename: string;
  map: string | null;
  minify?: boolean;
  projectRoot: string;
}

interface ExpoHermesBundleOutput {
  hbc: Uint8Array;
  sourcemap: string | null;
}

type ExpoHermesBuilder = (
  options: ExpoHermesBundleOptions
) => Promise<ExpoHermesBundleOutput>;

function resolveExpoCli(projectRoot: string) {
  const projectRequire = createRequire(path.join(projectRoot, 'package.json'));
  try {
    return {
      cliPath: projectRequire.resolve('expo/bin/cli'),
      packageJsonPath: projectRequire.resolve('expo/package.json'),
    };
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_EXPO_CLI_NOT_FOUND', 'Cannot resolve the project-local Expo CLI.', { cause, operation: 'resolve-expo-cli' });
  }
}

function requireFromExpo(projectRoot: string): NodeRequire {
  const project = createRequire(path.join(projectRoot, 'package.json'));
  return createRequire(project.resolve('expo/package.json'));
}

function requireFromExpoCli(projectRoot: string): NodeRequire {
  const expo = requireFromExpo(projectRoot);
  return createRequire(expo.resolve('@expo/cli/package.json'));
}

interface HarmonyMetroRuntime {
  reactPackage: string;
  harmonyPackage: string;
  harmonyPackageRoot?: string;
}

interface HarmonyMetroMetadata {
  platform: boolean;
  extensions: boolean;
  runtime?: HarmonyMetroRuntime;
}

function readExpoConfigInChildAsync<T>(
  projectRoot: string,
  operation: 'metro' | 'native-runtime' | 'fingerprint',
  mode: EnvMode = 'development',
  input?: object
): Promise<T> {
  // Config evaluation can be async. Give it the project's dotenv values without
  // changing the environment seen by other projects or native tools.
  return new Promise((resolve, reject) => {
    const child = fork(require.resolve('./internal/projectConfig'), [mode, operation], {
      cwd: projectRoot,
      env: { ...process.env, EXPO_HARMONY: '1', EXPO_METRO_TARGET: 'harmony' },
      execArgv: [],
      stdio: ['ignore', 'ignore', 'inherit', 'ipc'],
      signal: AbortSignal.timeout(resolveTimeoutMs(operation === 'fingerprint' ? 'fingerprint' : 'project-config',
        operation === 'fingerprint' ? 300_000 : 60_000)),
    });
    child.once('message', (message: { result?: T; error?: string; code?: string }) => {
      if (message.result !== undefined) resolve(message.result);
      else reject(new HarmonyCliError(message.code || 'ERR_HARMONY_CONFIG_INVALID',
        message.error || 'Expo did not return project configuration.', { operation: 'project-config' }));
    });
    child.once('error', reject);
    child.once('close', code => reject(new Error(`Expo project config process exited with code ${code}.`)));
    if (input) {
      child.send(input, (error) => {
        if (error) reject(error);
      });
    }
  });
}

function loadHarmonyMetroMetadataAsync(projectRoot: string, mode?: EnvMode) {
  return readExpoConfigInChildAsync<HarmonyMetroMetadata>(projectRoot, 'metro', mode);
}

function resolveExpoHermesBuilder(projectRoot: string): ExpoHermesBuilder {
  const expo = requireFromExpo(projectRoot);
  const packageJsonPath = expo.resolve('@expo/metro-config/package.json');
  const modulePath = path.join(path.dirname(packageJsonPath), 'build', 'serializer', 'exportHermes.js');
  return expo(modulePath).buildHermesBundleAsync as ExpoHermesBuilder;
}

export {
  loadHarmonyMetroMetadataAsync,
  readExpoConfigInChildAsync,
  requireFromExpo,
  requireFromExpoCli,
  resolveExpoCli,
  resolveExpoHermesBuilder,
};
export type { ExpoHermesBuilder, HarmonyMetroRuntime };

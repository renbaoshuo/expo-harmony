import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { HarmonyCliError } from './errors';

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

function resolveExpoCli(projectRoot) {
  const projectRequire = createRequire(path.join(projectRoot, 'package.json'));
  let packageJsonPath;

  try {
    packageJsonPath = projectRequire.resolve('expo/package.json');
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_EXPO_CLI_NOT_FOUND', 'Cannot resolve the project-local expo package.', { cause, operation: 'resolve-expo-cli' });
  }

  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
  const bin = typeof packageJson.bin === 'string' ? packageJson.bin : packageJson.bin?.expo;

  if (typeof bin !== 'string' || !bin) {
    throw new HarmonyCliError('ERR_HARMONY_EXPO_CLI_NOT_FOUND', 'The project-local expo package has no expo binary.', { operation: 'resolve-expo-cli' });
  }

  const cliPath = path.resolve(path.dirname(packageJsonPath), bin);

  if (!fs.existsSync(cliPath)) {
    throw new HarmonyCliError('ERR_HARMONY_EXPO_CLI_NOT_FOUND', `Expo CLI binary does not exist: ${cliPath}`, { operation: 'resolve-expo-cli' });
  }

  return { cliPath, packageJsonPath };
}

function resolveExpoHermesBuilder(projectRoot: string): ExpoHermesBuilder {
  const projectRequire = createRequire(path.join(projectRoot, 'package.json'));
  let packageJsonPath;

  try {
    packageJsonPath = projectRequire.resolve('@expo/metro-config/package.json');
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_EXPORT_HERMES',
      'Cannot resolve the project-local @expo/metro-config package required for Hermes export.',
      { cause, operation: 'resolve-expo-hermes' }
    );
  }

  const modulePath = path.join(path.dirname(packageJsonPath), 'build', 'serializer', 'exportHermes.js');
  let moduleExports;

  try {
    moduleExports = projectRequire(modulePath);
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_EXPORT_HERMES',
      `Cannot load the Expo Hermes exporter: ${modulePath}`,
      { cause, operation: 'resolve-expo-hermes' }
    );
  }

  if (typeof moduleExports?.buildHermesBundleAsync !== 'function') {
    throw new HarmonyCliError(
      'ERR_HARMONY_EXPORT_HERMES',
      'The project-local @expo/metro-config package does not expose buildHermesBundleAsync().',
      { operation: 'resolve-expo-hermes' }
    );
  }

  return moduleExports.buildHermesBundleAsync as ExpoHermesBuilder;
}

export { resolveExpoCli, resolveExpoHermesBuilder };
export type { ExpoHermesBuilder };

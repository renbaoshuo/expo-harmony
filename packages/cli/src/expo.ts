import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { HarmonyCliError } from './errors';

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

export { resolveExpoCli };

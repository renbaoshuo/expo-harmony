import fs from 'node:fs';
import path from 'node:path';

import { HarmonyCliError } from '../errors';
import { formatDiagnostics, spawnAsync } from '../process';
import { resolveExpoCli } from '../expo';
import { assertSafeCleanTarget } from './clean';
import { packTemplateAsync } from './template';

interface PrebuildOptions {
  buildType?: 'debug' | 'release';
  capture?: boolean;
}

async function prebuildParsedAsync(
  projectRoot: string,
  passthrough: string[],
  options: PrebuildOptions = {}
) {
  if (passthrough.includes('--clean')) await assertSafeCleanTarget(projectRoot);

  const expo = resolveExpoCli(projectRoot);
  const packed = await packTemplateAsync(projectRoot);

  try {
    const result = await spawnAsync(process.execPath, [
      expo.cliPath,
      'prebuild', projectRoot,
      '--platform', 'harmony',
      '--template', packed.tarball,
      ...passthrough,
    ], {
      capture: Boolean(options.capture),
      cwd: projectRoot,
      env: options.buildType
        ? { ...process.env, EXPO_HARMONY_BUILD_TYPE: options.buildType }
        : process.env,
      operation: 'expo-prebuild',
      outputLimit: 4 * 1024 * 1024,
    });

    if (result.code !== 0) {
      const diagnostics = options.capture ? formatDiagnostics(result) : '';
      throw new HarmonyCliError('ERR_HARMONY_PREBUILD_FAILED', `Expo prebuild exited with code ${result.code}.${diagnostics ? `\n${diagnostics}` : ''}`, {
        exitCode: result.code,
        operation: 'expo-prebuild',
      });
    }

    const marker = path.join(projectRoot, 'harmony/.expo-harmony-template');
    const manifest = path.join(projectRoot, '.expo/harmony/cng-manifest.json');

    try {
      const parsed = JSON.parse(await fs.promises.readFile(manifest, 'utf8'));
      if (parsed.schemaVersion !== 1 || !Array.isArray(parsed.managedFiles)) throw new TypeError('invalid schema');
      await fs.promises.access(marker, fs.constants.R_OK);
    } catch (cause) {
      throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', 'Expo prebuild exited successfully but the Harmony marker or CNG manifest is invalid.', { cause, operation: 'verify-prebuild' });
    }

    return result;
  } finally {
    await packed.cleanup();
  }
}

export { prebuildParsedAsync };

import fs from 'node:fs';

import { HarmonyCliError } from '../errors';
import { formatDiagnostics, spawnAsync } from '../process';
import { resolveExpoCli } from '../expo';
import { resolveHarmonyBuildPlanAsync } from '../tools';
import { assertSafeCleanTarget } from './clean';
import { packAsync } from './template';

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
  const packed = await packAsync(projectRoot);

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
      env: {
        ...process.env,
        ...packed.env,
        ...(options.buildType ? { EXPO_HARMONY_BUILD_TYPE: options.buildType } : {}),
      },
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

    try {
      const plan = await resolveHarmonyBuildPlanAsync(projectRoot, {
        buildMode: options.buildType,
      });
      await fs.promises.access(plan.projectFiles.templateMarker, fs.constants.R_OK);
    } catch (cause) {
      throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', 'Expo prebuild exited successfully but the Harmony marker or CNG manifest is invalid.', { cause, operation: 'verify-prebuild' });
    }

    return result;
  } finally {
    await packed.cleanup();
  }
}

export { prebuildParsedAsync };

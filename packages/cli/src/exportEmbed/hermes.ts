import fs from 'node:fs';
import path from 'node:path';

import { composeSourceMaps } from 'metro-source-map';

import { HarmonyCliError } from '../errors';
import { formatDiagnostics, spawnAsync } from '../process';
import { packageMetadata } from '../contract';
import { HermesCompilerPaths, ProjectPackages } from '../upstream';
import type { ExportOptions, ExportTemporary } from './export';

function hermesExecutable(projectRoot: string) {
  const compiler = packageMetadata(projectRoot, ProjectPackages.hermesCompiler);
  const relative = HermesCompilerPaths[process.platform];

  if (!relative) {
    throw new HarmonyCliError('ERR_HARMONY_EXPORT_HERMES', `Hermes compilation is not supported on host platform ${process.platform}.`, { operation: 'resolve-hermes' });
  }

  const executable = path.join(compiler.packageRoot, ...relative.split('/'));
  if (!fs.existsSync(executable) || !fs.statSync(executable).isFile()) {
    throw new HarmonyCliError('ERR_HARMONY_EXPORT_HERMES', `${ProjectPackages.hermesCompiler}@${compiler.manifest.version || 'unknown'} does not contain the host compiler.`, { operation: 'resolve-hermes' });
  }

  return executable;
}

async function compileHermesAsync(
  projectRoot: string,
  temporary: ExportTemporary,
  options: Pick<ExportOptions, 'timeoutMs'> = {}
) {
  const result = await spawnAsync(hermesExecutable(projectRoot), [
    '-emit-binary',
    '-out', temporary.bundle,
    temporary.javascript,
    '-O',
    '-output-source-map',
  ], {
    capture: true,
    cwd: projectRoot,
    operation: 'hermes-compile',
    outputLimit: 2 * 1024 * 1024,
    timeoutMs: options.timeoutMs || 5 * 60_000,
  });

  if (result.code !== 0 || result.timedOut) {
    const diagnostics = formatDiagnostics(result);
    throw new HarmonyCliError(
      'ERR_HARMONY_EXPORT_HERMES',
      `Hermes compilation exited with code ${result.code}${result.timedOut ? ' after timing out' : ''}.${diagnostics ? `\n${diagnostics}` : ''}`,
      { exitCode: result.code || 1, operation: 'hermes-compile' }
    );
  }

  try {
    if (typeof composeSourceMaps !== 'function') throw new Error('composeSourceMaps() is unavailable.');

    const [metroMap, hermesMap] = await Promise.all([
      fs.promises.readFile(temporary.metroSourceMap, 'utf8').then(JSON.parse),
      fs.promises.readFile(`${temporary.bundle}.map`, 'utf8').then(JSON.parse),
    ]);
    const composed = composeSourceMaps([metroMap, hermesMap]);

    await fs.promises.writeFile(temporary.sourceMap, JSON.stringify(composed));
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_EXPORT_INVALID_SOURCEMAP', 'Cannot compose the Expo Metro and Hermes source maps.', { cause, operation: 'compose-source-map' });
  }
}

export { compileHermesAsync };

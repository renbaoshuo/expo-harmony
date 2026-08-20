import fs from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';

import { HarmonyCliError } from '../errors';
import { spawnAsync } from '../process';

function resolveTemplateRoot(projectRoot) {
  const projectRequire = createRequire(path.join(projectRoot, 'package.json'));
  const cliRequire = createRequire(__filename);
  let packageJsonPath;

  try {
    try {
      packageJsonPath = projectRequire.resolve('@expo-harmony/template/package.json');
    } catch {
      packageJsonPath = cliRequire.resolve('@expo-harmony/template/package.json');
    }
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', 'Cannot resolve @expo-harmony/template.', { cause, operation: 'resolve-template' });
  }

  const root = path.dirname(packageJsonPath);

  if (!fs.existsSync(path.join(root, 'harmony/.expo-harmony-template'))) {
    throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', `Template marker is missing in ${root}.`, { operation: 'resolve-template' });
  }

  return root;
}

async function packTemplateAsync(projectRoot) {
  const root = resolveTemplateRoot(projectRoot);
  const temporaryRoot = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-harmony-template-'));
  const result = await spawnAsync('npm', [
    'pack',
    '--json',
    '--ignore-scripts',
    '--cache', path.join(temporaryRoot, '.npm-cache'),
    '--pack-destination', temporaryRoot,
    root,
  ], { capture: true, cwd: projectRoot, operation: 'pack-template' });

  if (result.code !== 0) {
    await fs.promises.rm(temporaryRoot, { recursive: true, force: true });
    throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', `npm pack failed: ${result.stderr.trim()}`, {
      exitCode: result.code,
      operation: 'pack-template',
    });
  }

  let records;

  try {
    records = JSON.parse(result.stdout);
  } catch (cause) {
    await fs.promises.rm(temporaryRoot, { recursive: true, force: true });
    throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', 'npm pack returned invalid JSON.', {
      cause,
      operation: 'pack-template',
    });
  }

  const filename = records?.[0]?.filename;
  const tarball = filename && path.join(temporaryRoot, filename);

  if (!tarball || !fs.existsSync(tarball)) {
    await fs.promises.rm(temporaryRoot, { recursive: true, force: true });
    throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', 'npm pack did not create a template tarball.', { operation: 'pack-template' });
  }

  return {
    tarball,
    async cleanup() {
      await fs.promises.rm(temporaryRoot, { recursive: true, force: true });
    },
  };
}

export {
  packTemplateAsync,
};

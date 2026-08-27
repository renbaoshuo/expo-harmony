import fs from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';

import { HarmonyCliError } from '../errors';
import { spawnAsync } from '../process';

interface Api {
  ROOT_ENV: string;
  resolveBundled(): {
    root: string;
    version: string;
  };
}

function resolve(project: string) {
  const load = createRequire(path.join(project, 'package.json'));
  let api: Api;

  try {
    api = load('@expo-harmony/prebuild-config/template');
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      'Cannot load @expo-harmony/prebuild-config/template from the project. Update the project-local prebuild config to a compatible version.',
      { cause, operation: 'resolve-template' }
    );
  }

  if (typeof api?.ROOT_ENV !== 'string' || typeof api.resolveBundled !== 'function') {
    throw new HarmonyCliError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      'The project-local @expo-harmony/prebuild-config template API is invalid.',
      { operation: 'resolve-template' }
    );
  }

  let template: ReturnType<Api['resolveBundled']>;
  try {
    template = api.resolveBundled();
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      'Cannot resolve the Harmony template declared by the project-local prebuild config.',
      { cause, operation: 'resolve-template' }
    );
  }

  if (!template
    || typeof template.root !== 'string'
    || !path.isAbsolute(template.root)
    || typeof template.version !== 'string'
    || !template.version) {
    throw new HarmonyCliError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      'The project-local @expo-harmony/prebuild-config returned an invalid template descriptor.',
      { operation: 'resolve-template' }
    );
  }

  return {
    env: { [api.ROOT_ENV]: template.root },
    root: template.root,
  };
}

async function packAsync(project: string) {
  const template = resolve(project);
  const temp = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-harmony-template-'));
  const result = await spawnAsync('npm', [
    'pack',
    '--json',
    '--ignore-scripts',
    '--cache', path.join(temp, '.npm-cache'),
    '--pack-destination', temp,
    template.root,
  ], { capture: true, cwd: project, operation: 'pack-template' });

  if (result.code !== 0) {
    await fs.promises.rm(temp, { recursive: true, force: true });
    throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', `npm pack failed: ${result.stderr.trim()}`, {
      exitCode: result.code,
      operation: 'pack-template',
    });
  }

  let packs;

  try {
    packs = JSON.parse(result.stdout);
  } catch (cause) {
    await fs.promises.rm(temp, { recursive: true, force: true });
    throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', 'npm pack returned invalid JSON.', {
      cause,
      operation: 'pack-template',
    });
  }

  const filename = packs?.[0]?.filename;
  const tarball = filename && path.join(temp, filename);

  if (!tarball || !fs.existsSync(tarball)) {
    await fs.promises.rm(temp, { recursive: true, force: true });
    throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', 'npm pack did not create a template tarball.', { operation: 'pack-template' });
  }

  return {
    tarball,
    env: template.env,
    async cleanup() {
      await fs.promises.rm(temp, { recursive: true, force: true });
    },
  };
}

export {
  packAsync,
};

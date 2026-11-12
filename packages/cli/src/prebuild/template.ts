/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';

import { HarmonyCliError } from '../errors';
import { assertSafeRelative } from '../path';
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
  const api: Api = load('@expo-harmony/prebuild-config/internal/template');
  const template = api.resolveBundled();

  return {
    env: { [api.ROOT_ENV]: template.root },
    root: template.root,
  };
}

interface NpmPack {
  filename?: string;
  files?: { path: string }[];
}

async function npmPackAsync(project: string, root: string, temp: string, dryRun = false): Promise<NpmPack | undefined> {
  const result = await spawnAsync('npm', [
    'pack',
    '--json',
    '--ignore-scripts',
    ...(dryRun ? ['--dry-run'] : []),
    '--cache', path.join(temp, '.npm-cache'),
    '--pack-destination', temp,
    root,
  ], { capture: true, cwd: project, operation: 'pack-template' });

  if (result.code !== 0) {
    throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', `npm pack failed: ${result.stderr.trim()}`, {
      exitCode: result.code,
      operation: 'pack-template',
    });
  }

  try {
    const packs = JSON.parse(result.stdout);
    if (Array.isArray(packs)) return packs[0];
    if (packs && typeof packs === 'object') return Object.values<NpmPack>(packs)[0];
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', 'npm pack returned invalid JSON.', {
      cause,
      operation: 'pack-template',
    });
  }
}

async function stageWorkspaceTemplateAsync(project: string, root: string, temp: string): Promise<string> {
  const manifest = path.join(root, 'package.json');
  const pkg = JSON.parse(await fs.promises.readFile(manifest, 'utf8'));
  const defaults = Object.entries<string>(pkg.dependencies ?? {})
    .filter(([, specifier]) => typeof specifier === 'string' && specifier.startsWith('workspace:'));
  if (!defaults.length) return root;

  const load = createRequire(manifest);
  for (const [name, specifier] of defaults) {
    try {
      const range = specifier.slice('workspace:'.length);
      if (!['*', '^', '~'].includes(range)) {
        throw new Error(`Unsupported workspace dependency selector: ${specifier}`);
      }

      const dependency = load.resolve(`${name}/package.json`);
      const { version } = JSON.parse(await fs.promises.readFile(dependency, 'utf8'));
      if (typeof version !== 'string' || !version) throw new Error('Missing package version.');

      pkg.dependencies[name] = range === '*' ? version : range + version;
    } catch (cause) {
      throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', `Cannot resolve the workspace template default for ${name}: ${cause.message}`, {
        cause,
        operation: 'pack-template',
      });
    }
  }

  const pack = await npmPackAsync(project, root, temp, true);
  if (!Array.isArray(pack?.files)) {
    throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', 'npm pack did not list the workspace template files.', { operation: 'pack-template' });
  }

  const stage = path.join(temp, 'template');

  await fs.promises.mkdir(stage);
  for (const file of pack.files) {
    const relative = assertSafeRelative(file.path, 'npm pack');
    if (relative === 'package.json') continue;

    const target = path.join(stage, relative);

    await fs.promises.mkdir(path.dirname(target), { recursive: true });
    await fs.promises.copyFile(path.join(root, relative), target);
  }
  // Match the published workspace manifest so both pack paths produce the same checksum.
  await fs.promises.writeFile(path.join(stage, 'package.json'), JSON.stringify(pkg, null, 2));

  return stage;
}

async function packAsync(project: string) {
  const template = resolve(project);
  const temp = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-harmony-template-'));
  const cleanup = () => fs.promises.rm(temp, { recursive: true, force: true });
  try {
    const root = await stageWorkspaceTemplateAsync(project, template.root, temp);
    const pack = await npmPackAsync(project, root, temp);
    const filename = pack?.filename;
    const tarball = filename && path.join(temp, filename);
    if (!tarball || !fs.existsSync(tarball)) {
      throw new HarmonyCliError('ERR_HARMONY_TEMPLATE_INVALID', 'npm pack did not create a template tarball.', { operation: 'pack-template' });
    }

    return { tarball, env: template.env, cleanup };
  } catch (cause) {
    await cleanup();
    throw cause;
  }
}

export {
  packAsync,
};

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import path from 'node:path';

import { ReactNativeCommunityCliPackage, RnohCliPackage } from '../../config/constants';
import { HarmonyAutolinkingError } from '../../errors';
import { readJsonAsync, realpathExistingAsync, resolvePackageFromProject } from '../../utilities/values';

function findPackageJson(root, packageName) {
  try {
    return resolvePackageFromProject(root, `${packageName}/package.json`);
  } catch (cause) {
    throw new HarmonyAutolinkingError('RNOH_CLI_NOT_FOUND', `${packageName} is not installed.`, {
      cause,
      stage: 'rnoh-preflight',
    });
  }
}

function resolveRnohCliPackageJsonPath(): string {
  // App-local CLI versions may differ from this package's SDK toolchain.
  try {
    return require.resolve(`${RnohCliPackage}/package.json`);
  } catch (cause) {
    throw new HarmonyAutolinkingError('RNOH_CLI_NOT_FOUND', `The declared ${RnohCliPackage} dependency is missing. Reinstall the autolinking package.`, {
      cause,
      stage: 'rnoh-preflight',
    });
  }
}

async function resolveCliBinAsync(file: string, name: string, stage: string) {
  const pkg = await readJsonAsync(file, 'RNOH_CLI_NOT_FOUND', stage);
  const bin = typeof pkg.bin === 'string' ? pkg.bin : pkg.bin?.[name];
  if (typeof bin !== 'string' || !bin.trim()) {
    throw new HarmonyAutolinkingError('RNOH_CLI_NOT_FOUND', `${pkg.name} does not declare a ${name} bin entry.`, { stage });
  }

  return realpathExistingAsync(path.resolve(path.dirname(file), bin), {
    type: 'file', code: 'RNOH_CLI_NOT_FOUND', field: `${name} executable`, stage,
  });
}

function resolveAppCommunityCliPackage(root: string): string | undefined {
  try {
    return resolvePackageFromProject(root, `${ReactNativeCommunityCliPackage}/package.json`);
  } catch (cause) {
    if (cause.code !== 'MODULE_NOT_FOUND') throw cause;
    return undefined;
  }
}

async function resolveCliAsync(options) {
  const root = await realpathExistingAsync(options.projectRoot, {
    type: 'directory',
    field: 'projectRoot',
    stage: 'rnoh-preflight',
  });

  const raw = options.rnohCliPackageJsonPath
    || resolveRnohCliPackageJsonPath();
  const manifest = await realpathExistingAsync(raw, {
    type: 'file',
    code: 'RNOH_CLI_NOT_FOUND',
    field: 'RNOH CLI package.json',
    stage: 'rnoh-preflight',
  });

  const plugin = await readJsonAsync(manifest, 'RNOH_CLI_NOT_FOUND', 'rnoh-preflight');
  if (plugin.name !== RnohCliPackage) {
    throw new HarmonyAutolinkingError('RNOH_CLI_NOT_FOUND', `Expected ${RnohCliPackage}, found ${String(plugin.name)}.`, { stage: 'rnoh-preflight' });
  }

  const config = path.join(path.dirname(manifest), 'react-native.config.js');
  if (!fs.existsSync(config)) {
    throw new HarmonyAutolinkingError('RNOH_CLI_NOT_FOUND', `${RnohCliPackage} does not expose its public React Native CLI plugin config.`, { stage: 'rnoh-preflight' });
  }

  if (options.reactNativeExecutable) {
    const executable = await realpathExistingAsync(options.reactNativeExecutable, {
      type: 'file',
      code: 'RNOH_CLI_NOT_FOUND',
      field: 'project-local react-native executable',
      stage: 'rnoh-preflight',
    });

    return { executable, args: [] as string[] };
  }

  if (!resolveAppCommunityCliPackage(root)) {
    // React Native's bin delegates to a project-installed community CLI.
    // Fresh Expo projects can run the pinned community CLI directly instead.
    const file = require.resolve(`${ReactNativeCommunityCliPackage}/package.json`);
    const entry = await resolveCliBinAsync(file, 'rnc-cli', 'rnoh-preflight');
    return { executable: process.execPath, args: [entry] };
  }

  const file = await realpathExistingAsync(
    options.nodeModulesPath
      ? path.join(options.nodeModulesPath, 'react-native', 'package.json')
      : findPackageJson(root, 'react-native'),
    {
      type: 'file',
      code: 'RNOH_CLI_NOT_FOUND',
      field: 'project-local react-native package.json',
      stage: 'rnoh-preflight',
    }
  );
  const entry = await resolveCliBinAsync(file, 'react-native', 'rnoh-preflight');


  return { executable: process.execPath, args: [entry] };
}

export {
  resolveAppCommunityCliPackage,
  resolveCliAsync,
  resolveRnohCliPackageJsonPath,
};

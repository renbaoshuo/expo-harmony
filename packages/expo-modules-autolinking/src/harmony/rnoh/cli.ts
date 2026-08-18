import fs from 'node:fs';
import path from 'node:path';

import { RnohCliPackage } from '../../config/constants';
import { HarmonyAutolinkingError } from '../../errors';
import { readJsonAsync, realpathExistingAsync, resolvePackageFromProject } from '../../utilities/values';

function findPackageJson(projectRoot, packageName) {
  try {
    return resolvePackageFromProject(projectRoot, `${packageName}/package.json`);
  } catch (cause) {
    throw new HarmonyAutolinkingError('RNOH_CLI_NOT_FOUND', `${RnohCliPackage} is not installed.`, {
      cause,
      stage: 'rnoh-preflight',
    });
  }
}

async function resolveCliAsync(cliOptions) {
  const projectRoot = await realpathExistingAsync(cliOptions.projectRoot, {
    type: 'directory',
    field: 'projectRoot',
    stage: 'rnoh-preflight',
  });

  const raw = cliOptions.rnohCliPackageJsonPath
    || findPackageJson(projectRoot, RnohCliPackage);
  const pkg = await realpathExistingAsync(raw, {
    type: 'file',
    code: 'RNOH_CLI_NOT_FOUND',
    field: 'RNOH CLI package.json',
    stage: 'rnoh-preflight',
  });

  const packageJson = await readJsonAsync(pkg, 'RNOH_CLI_NOT_FOUND', 'rnoh-preflight');
  if (packageJson.name !== RnohCliPackage) {
    throw new HarmonyAutolinkingError('RNOH_CLI_NOT_FOUND', `Expected ${RnohCliPackage}, found ${String(packageJson.name)}.`, { stage: 'rnoh-preflight' });
  }

  const pluginRoot = path.dirname(pkg);
  const pluginConfig = path.join(pluginRoot, 'react-native.config.js');
  if (!fs.existsSync(pluginConfig)) {
    throw new HarmonyAutolinkingError('RNOH_CLI_NOT_FOUND', `${RnohCliPackage} does not expose its public React Native CLI plugin config.`, { stage: 'rnoh-preflight' });
  }

  const exec = cliOptions.reactNativeExecutable
    || path.join(cliOptions.nodeModulesPath || path.join(projectRoot, 'node_modules'), '.bin', 'react-native');
  const executable = await realpathExistingAsync(exec, {
    type: 'file',
    code: 'RNOH_CLI_NOT_FOUND',
    field: 'project-local react-native executable',
    stage: 'rnoh-preflight',
  });
  return {
    executable,
    packageJsonPath: pkg,
    pluginRoot,
    projectRoot,
  };
}

export {
  resolveCliAsync,
  findPackageJson,
};

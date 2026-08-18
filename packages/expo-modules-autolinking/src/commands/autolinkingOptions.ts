import { InvalidOptionArgumentError } from 'commander';

import { Platform } from '../config/constants';

function parsePositiveInt(value) {
  const parsed = Number(value);

  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new InvalidOptionArgumentError('Expected a positive integer.');
  }
  return parsed;
}

function addCommonOptions(command) {
  command
    .option('-e, --exclude <exclude...>', 'package names to exclude when looking up for modules', (value, previous = []) => previous.concat(value))
    .option('-p, --platform [platform]', 'the platform that the resulting modules must support. Available options: "harmony"', Platform)
    .option('--project-root <projectRoot>', 'the path to the root of the project. Defaults to current working directory', process.cwd())
    .option('--native-modules-dir <path>', 'replace configured local native modules directory')
    .option('--include <include...>', 'package names to verify for duplicate revisions', (value, previous = []) => previous.concat(value))
    .option('--build-type <type>', 'debug or release');

  return command;
}

function toApiOptions(options, searchPaths = undefined) {
  return {
    platform: options.platform,
    projectRoot: options.projectRoot,
    ...(searchPaths !== undefined && searchPaths !== null ? { searchPaths } : {}),
    ...(options.nativeModulesDir !== undefined ? { nativeModulesDir: options.nativeModulesDir } : {}),
    ...(options.exclude !== undefined ? { exclude: options.exclude } : {}),
    ...(options.include !== undefined ? { include: options.include } : {}),
    ...(options.buildType !== undefined ? { buildType: options.buildType } : {}),
  };
}

export { addCommonOptions, parsePositiveInt, toApiOptions };

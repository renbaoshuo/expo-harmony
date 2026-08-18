import { linkModulesAsync } from '../autolinking/link';

import { addCommonOptions, parsePositiveInt, toApiOptions } from './autolinkingOptions';
import { writeResult } from './output';

function registerLinkCommand(program, io) {
  addCommonOptions(program.command('link [searchPaths...]').description('transactionally link Expo and RNOH modules'))
    .requiredOption('--harmony-project-path <path>', 'Harmony project root')
    .option('--node-modules-path <path>', 'node_modules directory')
    .option('--react-native-executable <path>', 'explicit project-local react-native executable')
    .option('--rnoh-cli-package-json <path>', 'explicit RNOH CLI package.json')
    .option('--timeout-ms <milliseconds>', 'RNOH command timeout', parsePositiveInt)
    .option('--output-limit <bytes>', 'per-stream output capture limit', parsePositiveInt)
    .option('-j, --json', 'output results in the plain JSON format', false)
    .action(async (searchPaths, options) => {
      writeResult(io, await linkModulesAsync({
        ...toApiOptions(options, searchPaths),
        harmonyProjectPath: options.harmonyProjectPath,
        nodeModulesPath: options.nodeModulesPath,
        reactNativeExecutable: options.reactNativeExecutable,
        rnohCliPackageJsonPath: options.rnohCliPackageJson,
        timeoutMs: options.timeoutMs,
        outputLimit: options.outputLimit,
      }), options);
    });
}

export { registerLinkCommand };

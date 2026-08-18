import { writeProviderArtifactsAsync } from '../harmony/providers/artifacts';

import { addCommonOptions, toApiOptions } from './autolinkingOptions';
import { writeResult } from './output';

function registerGenerateModulesProviderCommand(program, io) {
  addCommonOptions(program.command('generate-modules-provider [searchPaths...]').description('generate the C++ Provider registration unit and CMake fragment'))
    .requiredOption('-t, --target <path>', 'owned generated C++ directory')
    .option('--packages <package...>', 'only generate Providers for these npm packages')
    .option('-j, --json', 'output results in the plain JSON format', false)
    .action(async (searchPaths, options) => {
      writeResult(io, await writeProviderArtifactsAsync({
        ...toApiOptions(options, searchPaths),
        target: options.target,
        packages: options.packages,
      }), options);
    });
}

export { registerGenerateModulesProviderCommand };

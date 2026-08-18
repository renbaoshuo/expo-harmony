import { resolveModulesAsync } from '../autolinking/resolve';

import { addCommonOptions, toApiOptions } from './autolinkingOptions';
import { writeResult } from './output';

function registerResolveCommand(program, io) {
  addCommonOptions(program.command('resolve [searchPaths...]').description('resolve Harmony module metadata'))
    .option('-j, --json', 'output results in the plain JSON format', false)
    .action(async (searchPaths, options) => {
      writeResult(io, await resolveModulesAsync(toApiOptions(options, searchPaths)), options);
    });
}

export { registerResolveCommand };

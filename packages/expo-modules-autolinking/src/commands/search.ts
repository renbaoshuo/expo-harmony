import { searchModulesAsync } from '../autolinking/search';

import { addCommonOptions, toApiOptions } from './autolinkingOptions';
import { writeResult } from './output';

function registerSearchCommand(program, io) {
  addCommonOptions(program.command('search [searchPaths...]').description('discover Harmony native module candidates'))
    .option('-j, --json', 'output results in the plain JSON format', false)
    .action(async (searchPaths, options) => {
      writeResult(io, await searchModulesAsync(toApiOptions(options, searchPaths)), options);
    });
}

export { registerSearchCommand };

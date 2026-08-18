import { verifyModulesAsync } from '../autolinking/verify';

import { addCommonOptions, toApiOptions } from './autolinkingOptions';
import { writeVerifyResult } from './output';

function registerVerifyCommand(program, io, state) {
  addCommonOptions(program.command('verify').description('verify Harmony module metadata and conflicts'))
    .option('-v, --verbose', 'output all verification details', false)
    .option('-j, --json', 'output results in the plain JSON format', false)
    .action(async (options) => {
      const result = await verifyModulesAsync(toApiOptions(options));
      writeVerifyResult(io, result, options);
      if (!result.valid) state.exitCode = 1;
    });
}

export { registerVerifyCommand };

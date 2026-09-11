import { parseCommandArgs, type Command } from '../command';
import { parseModulesArgs } from './options';

export const command: Command = async (argv, io) => {
  const args = parseCommandArgs(parseModulesArgs, argv, io);
  if (!args) return 0;

  const { projectRoot: root, options } = args;
  const { formatModulesResult, runModulesCommandAsync } = await import('./modules.js');

  const result = await runModulesCommandAsync(root, options);

  io.log(formatModulesResult(result));

  return result.ok ? 0 : 1;
};

import { parseCommandArgs, type Command } from '../command';
import { parseBuildArgs } from './options';

export const command: Command = async (argv, io) => {
  const args = parseCommandArgs(parseBuildArgs, argv, io);
  if (!args) return 0;

  const { projectRoot: root, options } = args;
  const { buildHarmonyAsync } = await import('./build.js');

  const result = await buildHarmonyAsync(root, {
    ...options,
    io,
  });

  io.log(`Built ${result.variant} HAP at ${result.hapPath}; no device actions were performed.`);

  return 0;
};

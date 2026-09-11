import { parseCommandArgs, type Command } from '../command';
import { parseRunArgs } from './options';

export const command: Command = async (argv, io) => {
  const args = parseCommandArgs(parseRunArgs, argv, io);
  if (!args) return 0;

  const { projectRoot: root, options } = args;
  const { runHarmonySessionAsync } = await import('./run.js');

  const session = await runHarmonySessionAsync(root, {
    ...options,
    interactiveBundler: true,
    io,
  });
  const { result } = session;

  io.log(`Launched ${result.bundleName} on ${result.device.id} (${result.variant}).`);
  if (session.metro.owner === 'started') {
    io.log('\n› Logs for your project will appear below. Press Ctrl+C to exit.');
    await session.metro.waitAsync();
  }

  return 0;
};

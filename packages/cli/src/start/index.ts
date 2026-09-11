import { parseCommandArgs, type Command } from '../command';
import { parseStartArgs } from './options';

export const command: Command = async (argv, io) => {
  const args = parseCommandArgs(parseStartArgs, argv, io);
  if (!args) return 0;

  const { projectRoot: root, options } = args;
  const { startExpoMetroAsync } = await import('../run/metro.js');

  const metro = await startExpoMetroAsync(root, {
    ...options,
    interactive: true,
  });

  try {
    if (metro.owner === 'existing') {
      io.log(`Expo Metro is already running on port ${metro.port}.`);
      if (options.resetCache) {
        io.warn('Stop the existing Metro server and run this command again to reset its cache.');
      }
    } else {
      io.log('\n› Logs for your project will appear below. Press Ctrl+C to exit.');
      await metro.waitAsync();
    }

    return 0;
  } finally {
    await metro.stop();
  }
};

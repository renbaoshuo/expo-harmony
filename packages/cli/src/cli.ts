import type { Command } from './command';
import { HarmonyCliError } from './errors';
import { Help } from './help';
import type { Log } from './log';

const commands: Record<string, () => Promise<{ command: Command }>> = {
  'start': () => import('./start/index.js'),
  'prebuild': () => import('./prebuild/index.js'),
  'build': () => import('./buildHap/index.js'),
  'doctor': () => import('./doctor/index.js'),
  'modules': () => import('./modules/index.js'),
  'export:embed': () => import('./exportEmbed/index.js'),
  'run': () => import('./run/index.js'),
};

export async function runAsync(argv: string[] = process.argv.slice(2), io: Log = console): Promise<number> {
  process.env.EXPO_HARMONY = '1';
  process.env.EXPO_METRO_TARGET = 'harmony';

  if (argv.length === 0 || (argv.length === 1 && ['--help', '-h'].includes(argv[0]))) {
    io.log(Help);
    return 0;
  }

  const name = argv[0];
  if (!Object.hasOwn(commands, name)) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', `Unknown command: ${name}`, { operation: 'parse-arguments' });
  }

  const { command } = await commands[name]();

  return command(argv.slice(1), io);
}

export async function mainAsync(argv: string[] = process.argv.slice(2)): Promise<void> {
  try {
    process.exitCode = await runAsync(argv);
  } catch (error) {
    console.error(`[${error.code || 'ERR_HARMONY_UNKNOWN'}] ${error.message}`);
    process.exitCode = error.exitCode || 1;
  }
}

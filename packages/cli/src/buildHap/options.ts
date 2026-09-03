import { CommonOptions, parseArgs } from '../args';
import { HarmonyCliError } from '../errors';

const BuildOptions = {
  ...CommonOptions,
  sync: { type: 'boolean' },
  variant: { type: 'string' },
} as const;

function parseBuildArgs(argv: string[]) {
  const { positionals, values } = parseArgs(BuildOptions, argv);

  if (positionals.length > 1) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', `Unexpected build positional argument: ${positionals[1]}`, {
      operation: 'parse-arguments',
    });
  }

  const variant = values.variant || 'debug';

  if (variant !== 'debug' && variant !== 'release') {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', '--variant must be debug or release.', {
      operation: 'parse-arguments',
    });
  }

  return {
    help: Boolean(values.help),
    project: positionals[0],
    sync: Boolean(values.sync),
    variant: variant as 'debug' | 'release',
  };
}

export { parseBuildArgs };

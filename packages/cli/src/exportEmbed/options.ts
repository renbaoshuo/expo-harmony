import { HarmonyCliError } from '../errors';
import { CommonOptions, parseArgs } from '../args';

const ExportEmbedOptions = {
  ...CommonOptions,
  'check': { type: 'boolean' },
  'reset-cache': { type: 'boolean' },
} as const;

function parseExportEmbedArgs(argv: string[]) {
  const { positionals, values } = parseArgs(ExportEmbedOptions, argv);

  if (positionals.length > 1) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', `Unexpected export:embed positional argument: ${positionals[1]}`, { operation: 'parse-arguments' });
  }

  return {
    check: Boolean(values.check),
    help: Boolean(values.help),
    json: Boolean(values.json),
    project: positionals[0],
    resetCache: Boolean(values['reset-cache']),
  };
}

export { parseExportEmbedArgs };

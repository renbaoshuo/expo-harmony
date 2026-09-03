import { CommonOptions, parseArgs } from '../args';
import { HarmonyCliError } from '../errors';

function parseDoctorArgs(argv: string[]) {
  const { positionals, values } = parseArgs(CommonOptions, argv);

  if (positionals.length > 1) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', `Unexpected doctor positional argument: ${positionals[1]}`, { operation: 'parse-arguments' });
  }

  return {
    help: Boolean(values.help),
    project: positionals[0],
  };
}

export { parseDoctorArgs };

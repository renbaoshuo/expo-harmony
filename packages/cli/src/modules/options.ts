import { CommonOptions, parseArgs } from '../args';
import { HarmonyCliError } from '../errors';

const ModuleOptions = {
  ...CommonOptions,
  'package': { short: 'p', type: 'string' },
  'variant': { type: 'string' },
  'native-modules-dir': { type: 'string' },
} as const;

export type ModulesAction = 'inspect' | 'list' | 'verify';

function parseModulesArgs(argv: string[]) {
  const { positionals, values } = parseArgs(ModuleOptions, argv);
  const action = positionals[0] as ModulesAction | undefined;

  if (values.help && action === undefined) {
    return {
      action: 'list' as const,
      help: true,
      project: undefined,
      packageName: values.package,
      nativeModulesDir: values['native-modules-dir'],
      variant: values.variant as 'debug' | 'release' | undefined,
    };
  }

  if (!action || !['inspect', 'list', 'verify'].includes(action)) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CONFIG_INVALID',
      'modules requires one of: list, inspect, verify.',
      { operation: 'parse-arguments' }
    );
  }

  if (positionals.length > 2) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CONFIG_INVALID',
      `Unexpected modules positional argument: ${positionals[2]}`,
      { operation: 'parse-arguments' }
    );
  }

  if (values.variant !== undefined && !['debug', 'release'].includes(values.variant)) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CONFIG_INVALID',
      `--variant must be debug or release, received: ${values.variant}`,
      { operation: 'parse-arguments' }
    );
  }

  if (values.package !== undefined && action !== 'inspect') {
    throw new HarmonyCliError(
      'ERR_HARMONY_CONFIG_INVALID',
      '--package is supported by modules inspect only.',
      { operation: 'parse-arguments' }
    );
  }

  return {
    action,
    help: Boolean(values.help),
    project: positionals[1],
    packageName: values.package,
    nativeModulesDir: values['native-modules-dir'],
    variant: values.variant as 'debug' | 'release' | undefined,
  };
}

export { parseModulesArgs };

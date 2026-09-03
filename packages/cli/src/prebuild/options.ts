import { HarmonyCliError } from '../errors';
import { CommonOptions, parseArgs } from '../args';

const PrebuildOptions = {
  ...CommonOptions,
  'bun': { type: 'boolean' },
  'check': { type: 'boolean' },
  'clean': { type: 'boolean' },
  'no-install': { type: 'boolean' },
  'npm': { type: 'boolean' },
  'platform': { short: 'p', type: 'string' },
  'pnpm': { type: 'boolean' },
  'skip-dependency-update': { type: 'string' },
  'template': { short: 't', type: 'string' },
  'yarn': { type: 'boolean' },
} as const;

function parsePrebuildArgs(argv: string[], options: { allowProject?: boolean } = {}) {
  const { positionals, values } = parseArgs(PrebuildOptions, argv);

  if (values.platform !== undefined) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CONFIG_INVALID',
      '--platform is fixed to harmony by expo-harmony.',
      { operation: 'parse-arguments' }
    );
  }

  if (values.template !== undefined) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CONFIG_INVALID',
      '--template is managed by expo-harmony.',
      { operation: 'parse-arguments' }
    );
  }

  if (positionals.length > (options.allowProject ? 1 : 0)) {
    const unexpected = positionals[options.allowProject ? 1 : 0];
    throw new HarmonyCliError(
      'ERR_HARMONY_CONFIG_INVALID',
      `Unexpected prebuild positional argument: ${unexpected}`,
      { operation: 'parse-arguments' }
    );
  }

  const packageManagerFlags = ['npm', 'yarn', 'pnpm', 'bun'].filter(name => values[name]);
  if (packageManagerFlags.length > 1) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', 'Choose at most one package manager: --npm, --yarn, --pnpm, or --bun.', { operation: 'parse-arguments' });
  }

  const passthrough: string[] = [];
  for (const name of ['clean', 'npm', 'yarn', 'pnpm', 'bun', 'no-install']) {
    if (values[name]) passthrough.push(`--${name}`);
  }

  if (values['skip-dependency-update'] !== undefined) {
    passthrough.push('--skip-dependency-update', values['skip-dependency-update']);
  }

  return {
    check: Boolean(values.check),
    clean: Boolean(values.clean),
    help: Boolean(values.help),
    passthrough,
    project: positionals[0],
  };
}

export { parsePrebuildArgs };

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { HarmonyCliError } from '../errors';
import { CommonOptions, parseArgs } from '../args';

const PrebuildOptions = {
  ...CommonOptions,
  'bun': { type: 'boolean' },
  'check': { type: 'boolean' },
  'clean': { type: 'boolean' },
  'no-clean': { type: 'boolean' },
  'no-install': { type: 'boolean' },
  'npm': { type: 'boolean' },
  'platform': { short: 'p', type: 'string' },
  'pnpm': { type: 'boolean' },
  'skip-dependency-update': { type: 'string' },
  'template': { short: 't', type: 'string' },
  'yarn': { type: 'boolean' },
} as const;

function parsePrebuildArgs(argv: string[]) {
  const { positionals, values } = parseArgs(PrebuildOptions, argv);

  if (values.platform !== undefined && values.platform !== 'harmony') {
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

  if (positionals.length > 1) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CONFIG_INVALID',
      `Unexpected prebuild positional argument: ${positionals[1]}`,
      { operation: 'parse-arguments' }
    );
  }

  const managers = ['npm', 'yarn', 'pnpm', 'bun'].filter(name => values[name]);
  if (values.clean && values['no-clean']) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', '--clean and --no-clean cannot be combined.', { operation: 'parse-arguments' });
  }
  if (managers.length > 1) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', 'Choose at most one package manager: --npm, --yarn, --pnpm, or --bun.', { operation: 'parse-arguments' });
  }

  const passthrough: string[] = [];
  for (const name of ['clean', 'no-clean', 'npm', 'yarn', 'pnpm', 'bun', 'no-install']) {
    if (values[name]) passthrough.push(`--${name}`);
  }

  if (values['skip-dependency-update'] !== undefined) {
    passthrough.push('--skip-dependency-update', values['skip-dependency-update']);
  }

  return {
    check: Boolean(values.check),
    clean: !values['no-clean'],
    help: Boolean(values.help),
    passthrough,
    project: positionals[0],
  };
}

export { parsePrebuildArgs };

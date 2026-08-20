import {
  parseArgs as parseNodeArgs,
} from 'node:util';

import { HarmonyCliError } from './errors';

type Option = {
  short?: string;
  type: 'boolean' | 'string';
};

type Options = Record<string, Option>;
type Values<T extends Options> = {
  [K in keyof T]?: T[K]['type'] extends 'boolean' ? boolean : string;
};

const CommonOptions = {
  help: { short: 'h', type: 'boolean' },
  json: { type: 'boolean' },
} as const satisfies Options;

function parseArgs<T extends Options>(
  options: T,
  argv: string[]
): { positionals: string[]; values: Values<T> } {
  try {
    return parseNodeArgs({
      allowPositionals: true,
      args: argv,
      options,
      strict: true,
    }) as { positionals: string[]; values: Values<T> };
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);

    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', message, {
      cause,
      operation: 'parse-arguments',
    });
  }
}

export { CommonOptions, parseArgs };

import { Command, CommanderError } from 'commander';

import { HarmonyAutolinkingError } from '../errors';
import { ToolVersion } from '../config/constants';
import { stringifyJson } from '../utilities/values';

import { registerGenerateModulesProviderCommand } from './generateModulesProvider';
import { registerLinkCommand } from './link';
import { registerResolveCommand } from './resolve';
import { registerSearchCommand } from './search';
import { registerVerifyCommand } from './verify';

function createProgram(io, state) {
  const program = new Command();

  program
    .name('expo-harmony-autolinking')
    .description('Expo Modules and RNOH autolinking for HarmonyOS')
    .version(ToolVersion)
    .exitOverride()
    .configureOutput({
      writeOut: value => io.stdout(value),
      writeErr: () => {},
    });

  registerSearchCommand(program, io);
  registerResolveCommand(program, io);
  registerVerifyCommand(program, io, state);
  registerGenerateModulesProviderCommand(program, io);
  registerLinkCommand(program, io);
  return program;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function runCliAsync(argv: string[], io: Record<string, any> = {}): Promise<number> {
  const streams = {
    stdout: io.stdout || (value => process.stdout.write(value)),
    stderr: io.stderr || (value => process.stderr.write(value)),
  };
  const state = { exitCode: 0 };
  const program = createProgram(streams, state);

  try {
    await program.parseAsync(argv, { from: 'user' });
    return state.exitCode;
  } catch (error) {
    if (error instanceof CommanderError && error.exitCode === 0) return 0;

    const normalized = error instanceof HarmonyAutolinkingError
      ? error
      : new HarmonyAutolinkingError('INVALID_OPTIONS', error.message || String(error), { cause: error, stage: 'cli' });

    streams.stderr(stringifyJson(normalized.toJSON()));
    return error instanceof CommanderError ? Math.max(1, error.exitCode || 2) : 2;
  }
}

export { createProgram, runCliAsync };

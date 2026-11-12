/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import path from 'node:path';

import { assertHarmonyCompatibility } from '@expo-harmony/expo-modules-autolinking/runtime';

import { CommonOptions, parseArgs } from '../args';
import { parseCommandArgs, type Command } from '../command';
import { HarmonyCliError } from '../errors';
import { resolveHarmonyBuildPlanAsync } from '../native/project';
import { publishRuntimeContractAsync, resolveRuntimeRequirementsAsync } from './contract';

export const command: Command = async (argv, io) => {
  const args = parseCommandArgs((argv) => {
    const { values, positionals } = parseArgs({
      ...CommonOptions,
      publish: { type: 'boolean' },
      client: { type: 'string' },
      variant: { type: 'string' },
    }, argv);

    if (positionals.length > 1 || (values.variant && !['debug', 'release'].includes(values.variant))
      || (values.publish && values.client)) {
      throw new HarmonyCliError(
        'ERR_HARMONY_CONFIG_INVALID',
        'Use runtime [project] [--client file | --publish] [--variant debug|release].',
        { operation: 'parse-arguments' }
      );
    }

    return { help: Boolean(values.help), project: positionals[0], ...values };
  }, argv, io);
  if (!args) return 0;

  const { projectRoot: root, options } = args;
  if (options.publish) {
    const plan = await resolveHarmonyBuildPlanAsync(root, { buildMode: options.variant as 'debug' | 'release' });
    await publishRuntimeContractAsync(root, plan);

    io.log('Published Harmony runtime capabilities.');
  } else {
    const contract = await resolveRuntimeRequirementsAsync(root);

    if (options.client) {
      const client = JSON.parse(await fs.promises.readFile(path.resolve(options.client), 'utf8'));
      assertHarmonyCompatibility(client, contract);

      io.log('Project is compatible with the fixed Harmony client.');
    } else {
      io.log(JSON.stringify(contract, null, 2));
    }
  }

  return 0;
};

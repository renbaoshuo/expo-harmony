#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import { parseArgs } from 'node:util';

import { HarmonyPatchError } from '../errors';
import { patchProjectAsync } from './patchProjectAsync';

async function main() {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      help: { type: 'boolean', short: 'h' },
      clean: { type: 'boolean' },
      platform: { type: 'string', short: 'p', default: 'harmony' },
    },
  });
  if (values.help) {
    console.log(`Usage: npx @expo-harmony/patch-project [project] [options]

Preserve manual Harmony native changes as CNG patches.

Options:
  --clean                 Delete harmony/ after successfully saving the patch
  -p, --platform <name>    harmony or all (default: harmony)
  -h, --help               Show this help`);
    return;
  }
  if (positionals.length > 1 || !['harmony', 'all'].includes(values.platform)) {
    throw new HarmonyPatchError('ERR_HARMONY_CONFIG_INVALID', 'Expected one project directory and --platform harmony or all.');
  }

  const root = await fs.realpath(path.resolve(positionals[0] || '.'));
  await fs.access(path.join(root, 'package.json'));

  process.env.EXPO_HARMONY = '1';
  process.env.EXPO_METRO_TARGET = 'harmony';

  const file = await patchProjectAsync(root, { clean: values.clean });

  console.log(file ? `Saved Harmony patch: ${file}` : 'No manual changes detected; removed previous Harmony patches.');
  if (file) console.log('Add "@expo-harmony/patch-project" to your app config plugins to apply patches during prebuild.');
}

main().catch((cause) => {
  console.error(`[${cause.code || 'ERR_HARMONY_PATCH_FAILED'}] ${cause.message}`);
  process.exitCode = 1;
});

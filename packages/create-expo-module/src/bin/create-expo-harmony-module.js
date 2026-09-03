#!/usr/bin/env node

import { runCli } from '../generator.mjs';

runCli(process.argv.slice(2)).catch((error) => {
  process.stderr.write(`create-expo-harmony-module: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});

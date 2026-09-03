#!/usr/bin/env node

import { runCli } from '../src/index.mjs';

runCli(process.argv.slice(2)).catch((error) => {
  process.stderr.write(`expo-harmony-module: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});

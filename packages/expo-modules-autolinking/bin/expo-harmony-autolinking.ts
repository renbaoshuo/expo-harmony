#!/usr/bin/env node

import { runCliAsync } from '../src/commands/cli';

runCliAsync(process.argv.slice(2)).then(
  (exitCode) => {
    process.exitCode = exitCode;
  },
  (error) => {
    const message = error instanceof Error ? error.stack || error.message : String(error);
    process.stderr.write(`${message}\n`);
    process.exitCode = 2;
  }
);

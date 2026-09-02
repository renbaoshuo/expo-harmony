import { inspect } from 'node:util';

import { stringifyJson } from '../utilities/values';

function formatResult(value) {
  return inspect(value, { depth: null, colors: false });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function writeResult(io, value, options: Record<string, any> = {}) {
  io.stdout(options.json ? stringifyJson(value) : `${formatResult(value)}\n`);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function writeVerifyResult(io, result, options: Record<string, any> = {}) {
  if (options.json) {
    writeResult(io, result, options);
    return;
  }

  if (result.diagnostics.length === 0) {
    io.stdout('✅ Everything is fine!\n');
  } else {
    for (const diagnostic of result.diagnostics) {
      const icon = diagnostic.severity === 'error' ? '❌' : '⚠️';
      const suffix = diagnostic.packageName ? ` (${diagnostic.packageName})` : '';
      io.stdout(`${icon} [${diagnostic.code}] ${diagnostic.message}${suffix}\n`);
    }
  }

  if (options.verbose) {
    io.stdout(`${formatResult({ modules: result.modules })}\n`);
  }
}

export { writeResult, writeVerifyResult };

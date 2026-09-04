import fs from 'node:fs';
import path from 'node:path';
import spawn from 'cross-spawn';

import { HarmonyCliError } from '../errors';
import { formatDiagnostics, spawnAsync } from '../process';
import type { HarmonyTool } from '../tools';

interface HarmonyEmulator {
  name: string;
  running: boolean;
}

async function listEmulatorsAsync(
  tool: HarmonyTool,
  options: { cwd?: string; timeoutMs?: number } = {}
): Promise<HarmonyEmulator[]> {
  let result;
  try {
    result = await spawnAsync(tool.command, [...tool.args, '-list', '-details'], {
      capture: true,
      cwd: options.cwd,
      operation: 'list-emulators',
      timeoutMs: options.timeoutMs || 15_000,
    });
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_EMULATOR_LIST',
      'Cannot run Emulator. Install DevEco Studio 6.1.0 or newer, add tools/emulator to PATH, or set HARMONY_EMULATOR.',
      { cause, operation: 'list-emulators' }
    );
  }

  if (result.code !== 0 || result.timedOut) {
    throw new HarmonyCliError(
      'ERR_HARMONY_EMULATOR_LIST',
      `Cannot list Harmony emulators: ${formatDiagnostics(result, 2_000) || 'Emulator timed out or exited unsuccessfully.'}`,
      { operation: 'list-emulators' }
    );
  }

  try {
    const instances: unknown = JSON.parse(result.stdout);
    if (!Array.isArray(instances)) throw new Error('Expected an array.');

    return instances.map((instance) => {
      if (!instance || typeof instance.name !== 'string' || !instance.name.trim()
        || /[\0\r\n]/u.test(instance.name)
        || ![true, false, 'true', 'false'].includes(instance.isRunning)) {
        throw new Error('Invalid emulator instance.');
      }
      return {
        name: instance.name,
        running: instance.isRunning === true || instance.isRunning === 'true',
      };
    });
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_EMULATOR_OUTPUT',
      'Emulator returned an unsupported instance list. Use DevEco Studio 6.1.0 or newer with Emulator -list -details support.',
      { cause, operation: 'list-emulators' }
    );
  }
}

function startEmulator(tool: HarmonyTool, name: string, logFile: string, cwd?: string) {
  fs.mkdirSync(path.dirname(logFile), { recursive: true });
  const log = fs.openSync(logFile, 'w', 0o600);
  let failure: string | null = null;
  try {
    // Emulator may remain alive for the whole GUI session. Give it its own
    // process group and file-backed output so it survives the CLI/Metro exit.
    // Default instance/image paths match the ones used by -list -details.
    const child = spawn(tool.command, [...tool.args, '-start', name], {
      cwd,
      detached: true,
      shell: false,
      stdio: ['ignore', log, log],
      windowsHide: false,
    });
    child.once('error', (cause) => {
      failure = cause.message;
    });
    child.once('exit', (code, signal) => {
      // Some versions use a short-lived launcher. A zero exit alone does not
      // prove readiness; the caller still checks the guest's name and boot state.
      if (code !== 0) failure = signal ? `terminated by ${signal}` : `exited with code ${code}`;
    });
    child.unref();
  } finally {
    fs.closeSync(log);
  }

  return {
    assertRunning() {
      if (failure) {
        throw new HarmonyCliError(
          'ERR_HARMONY_EMULATOR_START',
          `Cannot start Harmony emulator ${name}: ${failure}. See ${logFile}. Try starting it in DevEco Studio to resolve any license or login requirements.`,
          { operation: 'start-emulator' }
        );
      }
    },
  };
}

export { listEmulatorsAsync, startEmulator };

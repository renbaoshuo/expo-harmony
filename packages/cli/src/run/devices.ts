import { HarmonyCliError } from '../errors';
import type { HarmonyTool } from '../tools';
import { formatDiagnostics, spawnAsync, type ProcessResult } from '../process';

interface Device {
  aliases: string[];
  connectTool: string | null;
  id: string;
  location: string | null;
  state: string;
  transport: string;
}

interface HdcOptions {
  allowFailure?: boolean;
  code?: string;
  cwd?: string;
  devicePort?: number;
  message?: string;
  operation?: string;
  outputLimit?: number;
  timeoutMs?: number;
}

function parseHdcTargets(output: string): Device[] {
  const trimmed = String(output).trim();

  if (!trimmed || trimmed === '[Empty]') return [];

  return trimmed.split(/\r?\n/u).filter(Boolean).map((line) => {
    const fields = line.trim().split(/\s+/u);

    if (fields.length < 3 || !fields[0]) {
      throw new HarmonyCliError('ERR_HARMONY_DEVICE_OUTPUT', 'HDC returned an unsupported target-list format.', { operation: 'list-devices' });
    }

    return {
      aliases: [...new Set(fields)],
      connectTool: fields[4] || null,
      id: fields[0],
      location: fields[3] || null,
      state: fields[2],
      transport: fields[1],
    };
  });
}

function hasCommandFailure(result: ProcessResult): boolean {
  const output = `${result.stdout || ''}\n${result.stderr || ''}`;
  return result.code !== 0 || result.timedOut
    // HDC occasionally reports transport and package-manager failures on
    // stdout while still returning exit code 0 (for example,
    // "Connect server failed"). Treat its documented failure vocabulary as
    // authoritative regardless of where it appears on the line.
    || /\[(?:Fail|Error)\]|\b(?:Failure|failed)\b|(?:失败|错误)/iu.test(output);
}

async function runHdcAsync(
  hdc: HarmonyTool,
  args: string[],
  options: HdcOptions = {}
): Promise<ProcessResult> {
  const result = await spawnAsync(hdc.command, [
    ...hdc.args,
    ...args,
  ], {
    capture: true,
    cwd: options.cwd,
    operation: options.operation || 'hdc',
    outputLimit: options.outputLimit || 256 * 1024,
    timeoutMs: options.timeoutMs || 60_000,
  });

  if (!options.allowFailure && hasCommandFailure(result)) {
    const diagnostics = formatDiagnostics(result, 2_000);
    throw new HarmonyCliError(
      options.code || 'ERR_HARMONY_DEVICE_COMMAND',
      `${options.message || 'HDC command failed'}${diagnostics ? `: ${diagnostics}` : '.'}`,
      { exitCode: result.code || 1, operation: options.operation || 'hdc' }
    );
  }

  return result;
}

async function selectDeviceAsync(
  hdc: HarmonyTool,
  requested?: string,
  options: HdcOptions = {}
): Promise<Device> {
  if (requested && (requested.includes('\0') || requested.trim() !== requested || !requested)) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', '--device must be a non-empty HDC id or exact target name.', { operation: 'select-device' });
  }

  const result = await runHdcAsync(hdc, ['list', 'targets', '-v'], {
    code: 'ERR_HARMONY_DEVICE_LIST',
    cwd: options.cwd,
    message: 'Cannot list Harmony devices',
    operation: 'list-devices',
    timeoutMs: 15_000,
  });
  const targets = parseHdcTargets(result.stdout || result.stderr);
  const connected = targets.filter(target => target.state.toLowerCase() === 'connected');

  if (requested) {
    const matches = connected.filter(target => target.id === requested || target.aliases.includes(requested));

    if (matches.length === 1) return matches[0];

    if (matches.length > 1) {
      throw new HarmonyCliError('ERR_HARMONY_DEVICE_AMBIGUOUS', `The requested device name matches multiple connected targets: ${requested}.`, { operation: 'select-device' });
    }

    throw new HarmonyCliError('ERR_HARMONY_DEVICE_NOT_FOUND', `The requested Harmony device is not connected: ${requested}.`, { operation: 'select-device' });
  }

  if (connected.length === 1) return connected[0];

  if (connected.length === 0) {
    throw new HarmonyCliError('ERR_HARMONY_DEVICE_NOT_FOUND', 'No connected Harmony device was reported by HDC.', { operation: 'select-device' });
  }

  throw new HarmonyCliError(
    'ERR_HARMONY_DEVICE_AMBIGUOUS',
    `Multiple Harmony devices are connected (${connected.map(target => target.id).join(', ')}); use --device.`,
    { operation: 'select-device' }
  );
}

async function installHapAsync(
  hdc: HarmonyTool,
  device: Device,
  hap: string,
  options: HdcOptions = {}
): Promise<void> {
  await runHdcAsync(hdc, ['-t', device.id, 'install', '-r', hap], {
    code: 'ERR_HARMONY_INSTALL_FAILED',
    cwd: options.cwd,
    message: `Cannot install the Harmony HAP on ${device.id}`,
    operation: 'install-hap',
    timeoutMs: options.timeoutMs || 2 * 60_000,
  });
}

async function configureMetroPortAsync(
  hdc: HarmonyTool,
  device: Device,
  port: number,
  options: HdcOptions = {}
): Promise<void> {
  const deviceEndpoint = `tcp:${options.devicePort || 8081}`;
  const hostEndpoint = `tcp:${port}`;

  await runHdcAsync(hdc, ['-t', device.id, 'fport', 'rm', deviceEndpoint, hostEndpoint], {
    allowFailure: true,
    cwd: options.cwd,
    operation: 'remove-metro-port',
    timeoutMs: 15_000,
  });

  await runHdcAsync(hdc, ['-t', device.id, 'rport', deviceEndpoint, hostEndpoint], {
    code: 'ERR_HARMONY_METRO_FORWARD',
    cwd: options.cwd,
    message: `Cannot reverse Metro port ${port} for ${device.id}`,
    operation: 'reverse-metro-port',
    timeoutMs: 15_000,
  });
}

async function launchAppAsync(
  hdc: HarmonyTool,
  device: Device,
  bundleName: string,
  abilityName: string,
  options: HdcOptions = {}
): Promise<void> {
  await runHdcAsync(hdc, [
    '-t', device.id,
    'shell',
    'aa',
    'force-stop',
    bundleName,
  ], {
    allowFailure: true,
    cwd: options.cwd,
    operation: 'force-stop-app',
    timeoutMs: 15_000,
  });

  await runHdcAsync(hdc, [
    '-t', device.id,
    'shell',
    'aa',
    'start',
    '-a', abilityName,
    '-b', bundleName,
  ], {
    code: 'ERR_HARMONY_LAUNCH_FAILED',
    cwd: options.cwd,
    message: `Cannot launch ${bundleName} on ${device.id}`,
    operation: 'launch-app',
    timeoutMs: 30_000,
  });
}

export {
  configureMetroPortAsync,
  installHapAsync,
  launchAppAsync,
  selectDeviceAsync,
};

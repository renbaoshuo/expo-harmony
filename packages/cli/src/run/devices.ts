/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { setTimeout as delay } from 'node:timers/promises';

import { listEmulatorsAsync, startEmulator } from './emulators';
import { HarmonyCliError } from '../errors';
import { type HarmonyTool } from '../native/toolchain';
import { formatDiagnostics, spawnAsync, type ProcessResult } from '../process';
import { resolveTimeoutMs } from '../timeout';

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

interface DeviceSelectionOptions extends HdcOptions {
  emulator?: HarmonyTool;
  emulatorLogFile?: string;
  onProgress?: (message: string) => void;
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
      aliases: [fields[0]],
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
    // HDC can print failures to stdout while returning exit code 0.
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
    timeoutMs: resolveTimeoutMs(options.operation || 'hdc', 60_000, options.timeoutMs),
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

async function listConnectedDevicesAsync(hdc: HarmonyTool, options: HdcOptions): Promise<Device[]> {
  const result = await runHdcAsync(hdc, ['list', 'targets', '-v'], {
    code: 'ERR_HARMONY_DEVICE_LIST',
    cwd: options.cwd,
    message: 'Cannot list Harmony devices',
    operation: 'list-devices',
    timeoutMs: resolveTimeoutMs('list-devices', 15_000, options.timeoutMs),
  });
  const targets = parseHdcTargets(result.stdout || result.stderr);
  return targets.filter(target => target.state.toLowerCase() === 'connected');
}

async function selectDeviceAsync(
  hdc: HarmonyTool,
  requested?: string,
  options: DeviceSelectionOptions = {}
): Promise<Device> {
  if (requested !== undefined && (!requested || /[\0\r\n]/u.test(requested) || requested.trim() !== requested)) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', '--device must be a non-empty HDC id or exact emulator name.', { operation: 'select-device' });
  }

  const connected = await listConnectedDevicesAsync(hdc, { cwd: options.cwd });

  if (requested) {
    const matches = connected.filter(target => target.id === requested || target.aliases.includes(requested));

    if (matches.length === 1) return matches[0];

    if (matches.length > 1) {
      throw new HarmonyCliError('ERR_HARMONY_DEVICE_AMBIGUOUS', `The requested device name matches multiple connected targets: ${requested}.`, { operation: 'select-device' });
    }

    if (!options.emulator) {
      throw new HarmonyCliError('ERR_HARMONY_DEVICE_NOT_FOUND', `The requested Harmony device is not connected: ${requested}.`, { operation: 'select-device' });
    }
  } else {
    if (connected.length === 1) return connected[0];

    if (connected.length > 1) {
      throw new HarmonyCliError(
        'ERR_HARMONY_DEVICE_AMBIGUOUS',
        `Multiple Harmony devices are connected (${connected.map(target => target.id).join(', ')}); use --device.`,
        { operation: 'select-device' }
      );
    }
  }

  if (!options.emulator) {
    throw new HarmonyCliError('ERR_HARMONY_DEVICE_NOT_FOUND', 'No connected Harmony device was reported by HDC.', { operation: 'select-device' });
  }

  const instances = await listEmulatorsAsync(options.emulator, { cwd: options.cwd });
  const running = instances.filter(instance => instance.running);
  const candidates = requested
    ? instances.filter(instance => instance.name === requested)
    : running.length ? running : instances;
  if (candidates.length === 0) {
    throw new HarmonyCliError(
      'ERR_HARMONY_DEVICE_NOT_FOUND',
      requested
        ? `No connected HDC target or local emulator matches ${requested}. Available emulators: ${instances.map(instance => instance.name).join(', ') || 'none'}.`
        : 'No connected Harmony device or local emulator was found. Create an emulator in DevEco Studio Device Manager first.',
      { operation: 'select-device' }
    );
  }
  if (candidates.length > 1) {
    throw new HarmonyCliError(
      'ERR_HARMONY_DEVICE_AMBIGUOUS',
      `Multiple Harmony emulators are available (${candidates.map(instance => JSON.stringify(instance.name)).join(', ')}); use --device <emulator-name>.`,
      { operation: 'select-device' }
    );
  }

  const instance = candidates[0];
  let launch: ReturnType<typeof startEmulator> | undefined;
  if (!instance.running) {
    if (!options.emulatorLogFile) {
      throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', 'An emulator log file is required to start a Harmony emulator.', { operation: 'start-emulator' });
    }
    options.onProgress?.(`Starting Harmony emulator ${instance.name}`);
    launch = startEmulator(options.emulator, instance.name, options.emulatorLogFile, options.cwd);
  }

  options.onProgress?.(`Waiting for Harmony emulator ${instance.name} to connect`);
  const deadline = Date.now() + resolveTimeoutMs('start-emulator', 120_000, options.timeoutMs);
  while (Date.now() < deadline) {
    launch?.assertRunning();
    const devices = await listConnectedDevicesAsync(hdc, {
      cwd: options.cwd,
      timeoutMs: Math.max(1, Math.min(15_000, deadline - Date.now())),
    });
    for (const device of devices) {
      if (Date.now() >= deadline) break;
      // DevEco may report hw.hdc.port as "notset" even while running. Query
      // the guest's instance name instead of guessing from a newly seen ID.
      if (!/^(?:127\.0\.0\.1|localhost|\[::1\]):\d+$/u.test(device.id)) continue;
      const identity = await runHdcAsync(hdc, ['-t', device.id, 'shell', 'param', 'get', 'ohos.qemu.hvd.name'], {
        allowFailure: true,
        cwd: options.cwd,
        operation: 'identify-emulator',
        timeoutMs: Math.max(1, Math.min(5_000, deadline - Date.now())),
      });
      if (identity.code !== 0 || identity.timedOut || identity.stdout.trim() !== instance.name) continue;
      if (Date.now() >= deadline) break;
      const boot = await runHdcAsync(hdc, ['-t', device.id, 'shell', 'param', 'get', 'bootevent.boot.completed'], {
        allowFailure: true,
        cwd: options.cwd,
        operation: 'wait-emulator-boot',
        timeoutMs: Math.max(1, Math.min(5_000, deadline - Date.now())),
      });
      if (!hasCommandFailure(boot) && boot.stdout.trim() === 'true') return device;
    }
    if (Date.now() >= deadline) break;
    await delay(Math.min(1_000, deadline - Date.now()));
  }

  throw new HarmonyCliError(
    'ERR_HARMONY_EMULATOR_TIMEOUT',
    `Timed out waiting for Harmony emulator ${instance.name} to connect to HDC.${launch ? ` See ${options.emulatorLogFile}.` : ''} Try starting it in DevEco Studio to resolve any license or login requirements.`,
    { operation: 'start-emulator' }
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
    timeoutMs: resolveTimeoutMs('install-hap', 2 * 60_000, options.timeoutMs),
  });
}

async function configureMetroPortAsync(
  hdc: HarmonyTool,
  device: Device,
  port: number,
  options: HdcOptions = {}
): Promise<void> {
  if (options.devicePort === undefined && port !== 8081) {
    // RNOH's default provider uses 8081; launcher manifests retain Metro's
    // advertised port for the bundle, assets, HMR and inspector URLs.
    await configureMetroPortAsync(hdc, device, port, { ...options, devicePort: 8081 });
    await configureMetroPortAsync(hdc, device, port, { ...options, devicePort: port });
    return;
  }

  const deviceEndpoint = `tcp:${options.devicePort || 8081}`;
  const hostEndpoint = `tcp:${port}`;

  const forwards = await runHdcAsync(hdc, ['-t', device.id, 'fport', 'ls'], {
    cwd: options.cwd,
    operation: 'list-metro-ports',
    timeoutMs: resolveTimeoutMs('list-metro-ports', 15_000, options.timeoutMs),
  });

  for (const line of forwards.stdout.split(/\r?\n/u)) {
    const [target, remote, local, direction] = line.trim().split(/\s+/u);
    if (target !== device.id || remote !== deviceEndpoint || direction !== '[Reverse]') continue;
    if (local === hostEndpoint) return;

    await runHdcAsync(hdc, ['-t', device.id, 'fport', 'rm', remote, local], {
      cwd: options.cwd,
      operation: 'remove-metro-port',
      timeoutMs: resolveTimeoutMs('remove-metro-port', 15_000, options.timeoutMs),
    });
  }

  await runHdcAsync(hdc, ['-t', device.id, 'rport', deviceEndpoint, hostEndpoint], {
    code: 'ERR_HARMONY_METRO_FORWARD',
    cwd: options.cwd,
    message: `Cannot reverse Metro port ${port} for ${device.id}`,
    operation: 'reverse-metro-port',
    timeoutMs: resolveTimeoutMs('reverse-metro-port', 15_000, options.timeoutMs),
  });
}

async function launchAppAsync(
  hdc: HarmonyTool,
  device: Device,
  bundleName: string,
  abilityName: string,
  options: HdcOptions & { moduleName?: string } = {}
): Promise<void> {
  // Quote for the remote shell; HDC forwards this command verbatim.
  const quote = (value: string) => `'${value.replaceAll('\'', '\'\\\'\'')}'`;

  await runHdcAsync(hdc, [
    '-t', device.id,
    'shell',
    `aa force-stop ${quote(bundleName)}`,
  ], {
    allowFailure: true,
    cwd: options.cwd,
    operation: 'force-stop-app',
    timeoutMs: resolveTimeoutMs('force-stop-app', 15_000),
  });

  await runHdcAsync(hdc, [
    '-t', device.id,
    'shell',
    `aa start -a ${quote(abilityName)} -b ${quote(bundleName)}${options.moduleName ? ` -m ${quote(options.moduleName)}` : ''}`,
  ], {
    code: 'ERR_HARMONY_LAUNCH_FAILED',
    cwd: options.cwd,
    message: `Cannot launch ${bundleName} on ${device.id}`,
    operation: 'launch-app',
    timeoutMs: resolveTimeoutMs('launch-app', 30_000),
  });
}

export {
  configureMetroPortAsync,
  installHapAsync,
  launchAppAsync,
  selectDeviceAsync,
};

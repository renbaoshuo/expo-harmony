import { HarmonyCliError } from '../errors';
import { CommonOptions, parseArgs } from '../args';

const RunOptions = {
  ...CommonOptions,
  'app-id': { type: 'string' },
  'device': { type: 'string' },
  'no-bundler': { type: 'boolean' },
  'no-install': { type: 'boolean' },
  'port': { type: 'string' },
  'reset-cache': { type: 'boolean' },
  'sync': { type: 'boolean' },
  'variant': { type: 'string' },
} as const;

function parseRunArgs(argv: string[]) {
  const { positionals, values } = parseArgs(RunOptions, argv);

  if (positionals.length > 1) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', `Unexpected run positional argument: ${positionals[1]}`, {
      operation: 'parse-arguments',
    });
  }

  const variant = values.variant || 'debug';

  if (variant !== 'debug' && variant !== 'release') {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', '--variant must be debug or release.', {
      operation: 'parse-arguments',
    });
  }

  const port = values.port === undefined ? 8081 : Number(values.port);

  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', '--port must be an integer between 1 and 65535.', {
      operation: 'parse-arguments',
    });
  }

  const appId = values['app-id'];

  if (appId !== undefined && (!appId || appId.trim() !== appId || appId.includes('\0'))) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', '--app-id must be a non-empty Harmony bundle name.', {
      operation: 'parse-arguments',
    });
  }

  const device = values.device;

  if (device !== undefined && (!device || device.trim() !== device || /[\0\r\n]/u.test(device))) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', '--device must be a non-empty HDC id or exact emulator name.', {
      operation: 'parse-arguments',
    });
  }

  return {
    appId,
    device,
    help: Boolean(values.help),
    noBundler: Boolean(values['no-bundler']),
    noInstall: Boolean(values['no-install']),
    port,
    project: positionals[0],
    resetCache: Boolean(values['reset-cache']),
    sync: Boolean(values.sync),
    variant: variant as 'debug' | 'release',
  };
}

export { parseRunArgs };

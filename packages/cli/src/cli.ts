import os from 'node:os';
import path from 'node:path';

import { parseDoctorArgs } from './doctor/options';
import { HarmonyCliError } from './errors';
import { parseExportEmbedArgs } from './exportEmbed/options';
import { parsePrebuildArgs } from './prebuild/options';
import { resolveProject } from './project';
import { parseRunArgs } from './run/options';

const Help = `Usage: expo-harmony <command> [project] [options]

Commands:
  prebuild              Generate the Harmony native project with Expo CNG
  prebuild --clean      Safely recreate the managed Harmony directory
  prebuild --check      Compare generated desired state without project writes
  doctor                Validate config, versions, Metro, RNOH, SDK, and signing
  export:embed          Export validated Hermes bytecode, assets, and a source map
  run                   Build, install, and launch the Harmony app

Options:
  --no-install          Skip dependency install (prebuild) or HAP install (run)
  --npm|--yarn|--pnpm|--bun
                        Select the package manager used by prebuild dependency install
  --skip-dependency-update <packages>
                        Preserve comma-separated dependency versions
  --device <id-or-name> Select one connected HDC target for run
  --variant <mode>      Build debug or release (default: debug)
  --no-bundler          Use an already-running Expo Metro server
  --app-id <bundleName>
                        Launch another installed app (requires --no-install when different)
  --port <number>       Metro and device reverse port (default: 8081)
  --sync                Re-run prebuild when generated CNG files drift
  --check               Validate an existing export without writing
  --reset-cache         Reset Metro while exporting
  --json                Print machine-readable results without subprocess logs
  -h, --help            Show this help
`;

type Invocation = { command: 'help' }
  | { command: 'doctor'; parsed: ReturnType<typeof parseDoctorArgs>; projectRoot: string }
  | { command: 'export:embed'; parsed: ReturnType<typeof parseExportEmbedArgs>; projectRoot: string }
  | { command: 'prebuild'; parsed: ReturnType<typeof parsePrebuildArgs>; projectRoot: string }
  | { command: 'run'; parsed: ReturnType<typeof parseRunArgs>; projectRoot: string };

function parseInvocation(argv: string[]): Invocation {
  if (argv.length === 0 || (argv.length === 1 && ['--help', '-h'].includes(argv[0]))) {
    return { command: 'help' };
  }

  const command = argv[0] as Exclude<Invocation['command'], 'help'>;
  if (!['prebuild', 'doctor', 'export:embed', 'run'].includes(command)) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', `Unknown command: ${command}`, {
      operation: 'parse-arguments',
    });
  }

  const parsed = command === 'prebuild'
    ? parsePrebuildArgs(argv.slice(1), { allowProject: true })
    : command === 'doctor'
      ? parseDoctorArgs(argv.slice(1))
      : command === 'export:embed'
        ? parseExportEmbedArgs(argv.slice(1))
        : parseRunArgs(argv.slice(1));
  if (parsed.help) return { command: 'help' };

  const projectRoot = resolveProject(parsed.project ? path.resolve(parsed.project) : process.cwd());

  return { command, parsed, projectRoot } as Invocation;
}

async function runAsync(
  argv: string[] = process.argv.slice(2),
  io: Pick<Console, 'error' | 'log' | 'warn'> = console
): Promise<number> {
  const invocation = parseInvocation(argv);
  if (invocation.command === 'help') {
    io.log(Help);
    return 0;
  }

  if (invocation.command === 'doctor') {
    const { doctorAsync, formatDoctor } = await import('./doctor/doctor.js');
    const result = await doctorAsync(invocation.projectRoot, { requireBuildTools: true });

    io.log(invocation.parsed.json ? JSON.stringify(result, null, 2) : formatDoctor(result));

    return result.ok ? 0 : 1;
  }

  if (invocation.command === 'export:embed') {
    const { exportEmbedAsync } = await import('./exportEmbed/export.js');
    const result = await exportEmbedAsync(invocation.projectRoot, invocation.parsed);

    if (invocation.parsed.json) io.log(JSON.stringify({ ok: true, ...result }, null, 2));
    else if (invocation.parsed.check) io.log('Harmony export bundle, assets, and source map are valid.');
    else io.log(`Exported Hermes bytecode ${result.bundle.path} with ${result.assets.length} asset file(s).`);

    return 0;
  }

  if (invocation.command === 'run') {
    const { runHarmonyAsync } = await import('./run/run.js');
    const result = await runHarmonyAsync(invocation.projectRoot, {
      ...invocation.parsed,
      io,
    });

    if (invocation.parsed.json) io.log(JSON.stringify(result, null, 2));
    else io.log(`Launched ${result.bundleName} on ${result.device.id} (${result.variant}).`);

    return 0;
  }

  const { check, clean, json, passthrough } = invocation.parsed;

  if (json && !check) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CONFIG_INVALID',
      '--json is supported by doctor and prebuild --check only.',
      { operation: 'parse-arguments' }
    );
  }

  if (check && passthrough.length) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', '--check cannot be combined with mutating prebuild options.');
  }

  if (clean) {
    const { assertSafeCleanTarget } = await import('./prebuild/clean.js');
    await assertSafeCleanTarget(invocation.projectRoot);
  }

  const { doctorAsync, formatDoctor } = await import('./doctor/doctor.js');
  const doctor = await doctorAsync(invocation.projectRoot, {
    requireBuildTools: false,
    validateGeneratedProject: !clean,
  });
  if (!doctor.ok) {
    io.error(formatDoctor(doctor));
    throw new HarmonyCliError('ERR_HARMONY_DOCTOR_FAILED', 'Harmony doctor found blocking errors.', {
      operation: 'doctor',
    });
  }

  for (const item of doctor.checks.filter(item => item.status === 'warn')) io.warn(`! ${item.message}`);

  if (check) {
    const { checkAsync } = await import('./prebuild/check.js');
    const result = await checkAsync(invocation.projectRoot);

    if (json) io.log(JSON.stringify(result, null, 2));
    else if (result.clean) io.log('Harmony CNG output is up to date.');
    else for (const change of result.changes) io.log(`${change.type}: ${change.path}`);

    return result.clean ? 0 : 2;
  }

  const { prebuildParsedAsync } = await import('./prebuild/prebuild.js');
  await prebuildParsedAsync(invocation.projectRoot, passthrough);

  return 0;
}

function safeJsonError(error) {
  let message = String(error?.message || error || 'Unknown error').split(/\r?\n/u, 1)[0];

  for (const [value, replacement] of [
    [os.homedir(), '<home>'],
    [process.cwd(), '<project>'],
  ]) {
    if (value) message = message.split(value).join(replacement);
  }

  message = message.replace(
    /(^|[\s("'=])(?:[A-Za-z]:[\\/]|\/)[^\s)"',;]*/gu,
    '$1<path>'
  );

  return {
    error: {
      code: error?.code || 'ERR_HARMONY_UNKNOWN',
      message: message.slice(0, 1_024),
      operation: error?.operation || 'cli',
    },
    ok: false,
  };
}

async function main(argv = process.argv.slice(2)) {
  try {
    const code = await runAsync(argv);

    process.exitCode = code;
  } catch (error) {
    const code = error.code || 'ERR_HARMONY_UNKNOWN';

    if (argv.includes('--json')) console.log(JSON.stringify(safeJsonError(error), null, 2));
    else console.error(`[${code}] ${error.message}`);

    process.exitCode = error.exitCode || 1;
  }
}

export { main, runAsync };

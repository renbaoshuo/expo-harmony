import path from 'node:path';

import { parseBuildArgs } from './buildHap/options';
import { parseDoctorArgs } from './doctor/options';
import { HarmonyCliError } from './errors';
import { parseExportEmbedArgs } from './exportEmbed/options';
import { parseModulesArgs } from './modules/options';
import { parsePrebuildArgs } from './prebuild/options';
import { resolveProject } from './project';
import { withHarmonyProjectLockAsync } from './projectLock';
import { parseRunArgs } from './run/options';

const Help = `Usage: expo-harmony <command> [project] [options]

Commands:
  prebuild              Generate the Harmony native project with Expo CNG
  prebuild --clean      Safely recreate the managed Harmony directory
  prebuild --check      Compare generated desired state without project writes
  build                 Build a HAP without selecting or contacting a device
  doctor                Validate config, versions, Metro, RNOH, SDK, and signing
  modules list          List native module candidates and their discovery source
  modules inspect       Resolve Harmony metadata (--package narrows the result)
  modules verify        Validate module config, registration conflicts and safe paths
  export:embed          Export validated Hermes bytecode, assets, and a source map
  run                   Build, install, and launch the Harmony app

Options:
  --no-install          Skip dependency install (prebuild) or HAP install (run)
  --npm|--yarn|--pnpm|--bun
                        Select the package manager used by prebuild dependency install
  --skip-dependency-update <packages>
                        Preserve comma-separated dependency versions
  --device <id-or-name> Select an HDC target or start a local emulator by name
  --variant <mode>      Build debug or release (default: debug)
  --no-bundler          Use an already-running Expo Metro server
  --app-id <bundleName>
                        Launch another installed app (requires --no-install when different)
  --port <number>       Metro and device reverse port (default: 8081)
  --sync                Re-run prebuild before building
  --check               Validate an existing export without writing
  --reset-cache         Reset Metro while exporting or starting
  -h, --help            Show this help
`;

type Invocation = { command: 'help' }
  | { command: 'build'; parsed: ReturnType<typeof parseBuildArgs>; projectRoot: string }
  | { command: 'doctor'; parsed: ReturnType<typeof parseDoctorArgs>; projectRoot: string }
  | { command: 'export:embed'; parsed: ReturnType<typeof parseExportEmbedArgs>; projectRoot: string }
  | { command: 'modules'; parsed: ReturnType<typeof parseModulesArgs>; projectRoot: string }
  | { command: 'prebuild'; parsed: ReturnType<typeof parsePrebuildArgs>; projectRoot: string }
  | { command: 'run'; parsed: ReturnType<typeof parseRunArgs>; projectRoot: string };

function parseInvocation(argv: string[]): Invocation {
  if (argv.length === 0 || (argv.length === 1 && ['--help', '-h'].includes(argv[0]))) {
    return { command: 'help' };
  }

  const command = argv[0] as Exclude<Invocation['command'], 'help'>;
  if (!['build', 'prebuild', 'doctor', 'export:embed', 'modules', 'run'].includes(command)) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', `Unknown command: ${command}`, {
      operation: 'parse-arguments',
    });
  }

  const parsed = command === 'build'
    ? parseBuildArgs(argv.slice(1))
    : command === 'prebuild'
      ? parsePrebuildArgs(argv.slice(1), { allowProject: true })
      : command === 'doctor'
        ? parseDoctorArgs(argv.slice(1))
        : command === 'export:embed'
          ? parseExportEmbedArgs(argv.slice(1))
          : command === 'modules'
            ? parseModulesArgs(argv.slice(1))
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

    io.log(formatDoctor(result));

    return result.ok ? 0 : 1;
  }

  if (invocation.command === 'build') {
    const { buildHarmonyAsync } = await import('./buildHap/build.js');
    const result = await buildHarmonyAsync(invocation.projectRoot, {
      ...invocation.parsed,
      io,
    });

    io.log(`Built ${result.variant} HAP at ${result.hapPath}; no device actions were performed.`);

    return 0;
  }

  if (invocation.command === 'export:embed') {
    const { exportEmbedAsync } = await import('./exportEmbed/export.js');
    const result = await exportEmbedAsync(invocation.projectRoot, invocation.parsed);

    if (invocation.parsed.check) io.log('Harmony export bundle, assets, and source map are valid.');
    else io.log(`Exported Hermes bytecode ${result.bundle.path} with ${result.assets.length} asset file(s).`);

    return 0;
  }

  if (invocation.command === 'modules') {
    const { formatModulesResult, runModulesCommandAsync } = await import('./modules/modules.js');
    const result = await runModulesCommandAsync(invocation.projectRoot, invocation.parsed);

    io.log(formatModulesResult(result));
    return result.ok ? 0 : 1;
  }

  if (invocation.command === 'run') {
    const { runHarmonySessionAsync } = await import('./run/run.js');

    const session = await runHarmonySessionAsync(invocation.projectRoot, {
      ...invocation.parsed,
      interactiveBundler: true,
      io,
    });
    const { result } = session;

    io.log(`Launched ${result.bundleName} on ${result.device.id} (${result.variant}).`);
    if (session.metro.owner === 'started') {
      io.log('\n› Logs for your project will appear below. Press Ctrl+C to exit.');
      await session.metro.waitAsync();
    }

    return 0;
  }

  const { check, clean, passthrough } = invocation.parsed;

  if (check && passthrough.length) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', '--check cannot be combined with mutating prebuild options.');
  }

  return withHarmonyProjectLockAsync(
    invocation.projectRoot,
    check ? 'prebuild-check' : 'prebuild',
    async () => {
      if (clean) {
        const { assertSafeCleanTarget } = await import('./prebuild/clean.js');
        await assertSafeCleanTarget(invocation.projectRoot);
      }

      const { doctorAsync, formatDoctor } = await import('./doctor/doctor.js');
      const doctor = await doctorAsync(invocation.projectRoot, {
        requireBuildTools: false,
        validateGeneratedProject: !clean,
        validateModules: false,
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

        if (result.clean) io.log('Harmony CNG output is up to date.');
        else for (const change of result.changes) io.log(`${change.type}: ${change.path}`);

        return result.clean ? 0 : 2;
      }

      const { prebuildParsedAsync } = await import('./prebuild/prebuild.js');
      await prebuildParsedAsync(invocation.projectRoot, passthrough);

      return 0;
    });
}

async function main(argv = process.argv.slice(2)) {
  try {
    const code = await runAsync(argv);

    process.exitCode = code;
  } catch (error) {
    const code = error.code || 'ERR_HARMONY_UNKNOWN';

    console.error(`[${code}] ${error.message}`);

    process.exitCode = error.exitCode || 1;
  }
}

export { main, runAsync };

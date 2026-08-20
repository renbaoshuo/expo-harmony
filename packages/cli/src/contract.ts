import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { HarmonyCliError } from './errors';
import { spawnAsync } from './process';
import { resolveExpoCli } from './expo';
import { ProjectPackages, PublicCliOptions } from './upstream';

const RequiredOptions = PublicCliOptions;

function packageMetadata(projectRoot, packageName) {
  const projectRequire = createRequire(path.join(projectRoot, 'package.json'));
  let packageJsonPath;

  try {
    packageJsonPath = projectRequire.resolve(`${packageName}/package.json`);
  } catch (cause) {
    try {
      let cursor = path.dirname(projectRequire.resolve(packageName));
      while (true) {
        const candidate = path.join(cursor, 'package.json');
        if (fs.existsSync(candidate)) {
          const manifest = JSON.parse(fs.readFileSync(candidate, 'utf8'));
          if (manifest.name === packageName) {
            packageJsonPath = candidate;
            break;
          }
        }

        const parent = path.dirname(cursor);
        if (parent === cursor) {
          throw new Error(`Cannot locate package metadata for ${packageName}.`, { cause });
        }
        cursor = parent;
      }
    } catch (fallbackCause) {
      throw new HarmonyCliError(
        'ERR_HARMONY_CLI_CONTRACT',
        `Cannot resolve the project-local ${packageName} package.`,
        { cause: fallbackCause, operation: 'resolve-public-cli' }
      );
    }
  }

  try {
    const manifest = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
    return { manifest, packageJsonPath, packageRoot: path.dirname(packageJsonPath) };
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CLI_CONTRACT',
      `Cannot read the project-local ${packageName} package metadata.`,
      { cause, operation: 'resolve-public-cli' }
    );
  }
}

function resolvePackageBinary(projectRoot, packageName, binName) {
  const metadata = packageMetadata(projectRoot, packageName);
  const bin = typeof metadata.manifest.bin === 'string'
    ? metadata.manifest.bin
    : metadata.manifest.bin?.[binName];

  if (typeof bin !== 'string' || !bin) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CLI_CONTRACT',
      `${packageName}@${metadata.manifest.version || 'unknown'} does not expose the ${binName} binary.`,
      { operation: 'resolve-public-cli' }
    );
  }

  const binaryPath = path.resolve(metadata.packageRoot, bin);
  const relative = path.relative(metadata.packageRoot, binaryPath);

  if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)
    || !fs.existsSync(binaryPath) || !fs.statSync(binaryPath).isFile()) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CLI_CONTRACT',
      `${packageName}@${metadata.manifest.version || 'unknown'} exposes an invalid ${binName} binary.`,
      { operation: 'resolve-public-cli' }
    );
  }

  return {
    binaryPath,
    packageJsonPath: metadata.packageJsonPath,
    version: metadata.manifest.version || 'unknown',
  };
}

function parseHelpOptions(help) {
  return [...new Set(
    String(help).match(/--[a-z][a-z0-9-]*/gu) || []
  )].sort();
}

function assertOptions(label, help, required) {
  const options = parseHelpOptions(help);
  const missing = required.filter(option => !options.includes(option));

  if (missing.length) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CLI_CONTRACT',
      `${label} public help is missing required options: ${missing.join(', ')}.`,
      { operation: 'verify-public-cli' }
    );
  }

  return options;
}

async function readHelpAsync(
  command: string,
  args: string[],
  projectRoot: string
) {
  const result = await spawnAsync(command, args, {
    capture: true,
    cwd: projectRoot,
    operation: 'public-cli-help',
    outputLimit: 256 * 1024,
    timeoutMs: 15_000,
  });

  if (result.code !== 0 || result.timedOut) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CLI_CONTRACT',
      `Public CLI help exited with code ${result.code}${result.timedOut ? ' after timing out' : ''}.`,
      { exitCode: result.code || 1, operation: 'public-cli-help' }
    );
  }

  return result.stdout || result.stderr;
}

async function inspectPublicCliContractsAsync(projectRoot: string) {
  const expo = resolveExpoCli(projectRoot);
  const reactNative = resolvePackageBinary(
    projectRoot,
    ProjectPackages.reactNative,
    ProjectPackages.reactNative
  );
  const rnoh = packageMetadata(projectRoot, ProjectPackages.rnohCli);

  const [expoHelp, runHelp, linkHelp] = await Promise.all([
    readHelpAsync(process.execPath, [expo.cliPath, 'export:embed', '--help'], projectRoot),
    readHelpAsync(process.execPath, [reactNative.binaryPath, 'run-harmony', '--help'], projectRoot),
    readHelpAsync(process.execPath, [reactNative.binaryPath, 'link-harmony', '--help'], projectRoot),
  ]);
  const expoMetadata = packageMetadata(projectRoot, ProjectPackages.expo);

  return {
    expo: {
      help: expoHelp,
      options: assertOptions('Expo export:embed', expoHelp, RequiredOptions.expoExportEmbed),
      version: expoMetadata.manifest.version || 'unknown',
    },
    rnoh: {
      linkHelp,
      linkOptions: assertOptions('RNOH link-harmony', linkHelp, RequiredOptions.rnohLinkHarmony),
      runHelp,
      runOptions: assertOptions('RNOH run-harmony', runHelp, RequiredOptions.rnohRunHarmony),
      version: rnoh.manifest.version || 'unknown',
    },
  };
}

export {
  inspectPublicCliContractsAsync,
  packageMetadata,
};

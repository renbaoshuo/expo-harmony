/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { createHash } from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import spawn from 'cross-spawn';
import JSON5 from 'json5';
import { resolveBuildOhpmDependencies } from './ohpm/dependencies';
import { sanitizeHarmonyHar } from './har';
import { resolveHarmonyCommand } from '../utilities/toolCommand';
import { terminateProcess } from '../utilities/terminateProcess';

import { HarmonyAutolinkingError } from '../errors';
import type {
  ArkTsModulePackage,
  BuildType,
  FixedHvigorBuildDescriptor,
  MaterializedLocalSource,
  MaterializeLocalSourceOptions,
  ModuleArtifactDescriptor,
  ModuleSource,
  RnohMetadata,
} from '../types';
import { compareText, isPathInside, normalizeSlashes, resolveInsideAsync, sanitizeOutput } from '../utilities/values';
import { publishArtifactsAsync } from './transaction/publish';

const DefaultBuildTimeoutMs = 10 * 60_000;
const DefaultOutputLimit = 64 * 1024;
const HarmonyProjectPath = 'harmony';
const LocalBuildGeneratedDirectories = new Set(['.git', '.hvigor', '.cxx', 'build', 'node_modules', 'oh_modules']);

interface FixedBuildStep {
  readonly id: 'ohpm-install' | 'hvigor-build';
  readonly label: string;
  readonly executable: string;
  readonly cwd: string;
  readonly args: ReadonlyArray<string>;
}

interface MaterializeModuleArtifactOptions {
  readonly packageName: string;
  readonly packageRoot: string;
  readonly source: ModuleSource;
  readonly buildType: BuildType;
  readonly arkTs?: ArkTsModulePackage;
  readonly rnoh: RnohMetadata;
}

function createFixedHvigorBuildDescriptor(
  projectPath: string,
  buildType: BuildType,
  moduleName: string
): FixedHvigorBuildDescriptor {
  return {
    executable: 'hvigorw',
    cwd: projectPath,
    args: [
      '--mode', 'module',
      '-p', `module=${moduleName}@default`,
      '-p', 'product=default',
      '-p', `buildMode=${buildType}`,
      '--no-daemon',
      'assembleHar',
    ],
  };
}

function findHarmonyLibrary(profile, packageName: string, stage: string) {
  const library = Array.isArray(profile?.modules) && profile.modules.find(entry =>
    typeof entry?.srcPath === 'string' && path.normalize(entry.srcPath) === 'library');
  if (typeof library?.name !== 'string' || !/^[A-Za-z][A-Za-z0-9_]*$/u.test(library.name)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'Harmony source project must declare a library module.', { packageName, stage });
  }
  return {
    name: library.name as string,
    output: `library/build/default/outputs/default/${library.name}.har`,
  };
}

async function isNonEmptyRegularHarAsync(
  harPath: string,
  allowedRoot: string,
  packageName: string
): Promise<boolean> {
  const root = path.resolve(allowedRoot);
  const target = path.resolve(harPath);
  if (!isPathInside(root, target)) {
    throw new HarmonyAutolinkingError(
      'UNSAFE_SOURCE_ARTIFACT',
      'Harmony HAR path must stay inside its expected package or project root.',
      { packageName, stage: 'artifact-materialize' }
    );
  }

  let stat;
  try {
    stat = await fs.promises.lstat(target);
  } catch (cause) {
    if ((cause as NodeJS.ErrnoException).code === 'ENOENT') return false;
    throw new HarmonyAutolinkingError(
      'UNSAFE_SOURCE_ARTIFACT',
      'Harmony HAR could not be checked safely.',
      { cause, packageName, stage: 'artifact-materialize' }
    );
  }
  if (stat.isSymbolicLink() || !stat.isFile()) {
    throw new HarmonyAutolinkingError(
      'UNSAFE_SOURCE_ARTIFACT',
      'Harmony HAR must be a regular non-symlink file.',
      { packageName, stage: 'artifact-materialize' }
    );
  }

  const [realRoot, realTarget] = await Promise.all([
    fs.promises.realpath(root),
    fs.promises.realpath(target),
  ]);
  if (!isPathInside(realRoot, realTarget)) {
    throw new HarmonyAutolinkingError(
      'UNSAFE_SOURCE_ARTIFACT',
      'Harmony HAR resolves outside its expected package or project root.',
      { packageName, stage: 'artifact-materialize' }
    );
  }

  return stat.size > 0;
}

async function validateBundledArtifactsAsync(
  options: MaterializeModuleArtifactOptions
): Promise<ModuleArtifactDescriptor> {
  const harPaths = [...new Set([
    ...options.rnoh.harPaths,
    ...(options.arkTs ? [options.arkTs.harPath] : []),
  ])].sort(compareText);

  for (const relative of harPaths) {
    const harPath = path.resolve(options.packageRoot, relative);
    if (!await isNonEmptyRegularHarAsync(harPath, options.packageRoot, options.packageName)) {
      throw new HarmonyAutolinkingError(
        'SOURCE_ARTIFACT_NOT_PUBLISHED',
        `${options.packageName} has a missing or empty Harmony HAR.`,
        {
          packageName: options.packageName,
          stage: 'artifact-materialize',
          details: { harPath: relative },
        }
      );
    }
  }

  return { kind: 'bundled', harPaths };
}

async function materializeModuleArtifactAsync(
  options: MaterializeModuleArtifactOptions
): Promise<ModuleArtifactDescriptor> {
  const localArkTs = options.source === 'nativeModulesDir' && options.arkTs;
  if (!localArkTs && (
    options.rnoh.harPaths.length > 0
    || options.arkTs
  )) {
    return validateBundledArtifactsAsync(options);
  }

  if (!localArkTs) {
    return { kind: 'bundled', harPaths: [] };
  }

  const packageRoot = await fs.promises.realpath(options.packageRoot);
  const sourceRoot = await resolveInsideAsync(packageRoot, HarmonyProjectPath, 'Harmony source project', {
    packageName: options.packageName,
    type: 'directory',
  });

  const profile = JSON5.parse(await fs.promises.readFile(path.join(sourceRoot, 'build-profile.json5'), 'utf8'));
  const library = findHarmonyLibrary(profile, options.packageName, 'artifact-materialize');
  const outputPath = await resolveInsideAsync(sourceRoot, library.output, 'Harmony build output', {
    packageName: options.packageName,
    mustExist: false,
  });

  return {
    kind: 'local-source',
    outputPath,
    materialized: false,
    build: createFixedHvigorBuildDescriptor(sourceRoot, options.buildType, library.name),
  };
}

function appendBounded(current: string, chunk: Buffer, limit: number): string {
  return (current + chunk.toString('utf8')).slice(-limit);
}

function fixedLocalSourceBuildSteps(build: FixedHvigorBuildDescriptor): ReadonlyArray<FixedBuildStep> {
  return [
    {
      id: 'ohpm-install',
      label: 'OHPM dependency install',
      executable: 'ohpm',
      cwd: build.cwd,
      args: ['install', '--all'],
    },
    {
      id: 'hvigor-build',
      label: 'Hvigor build',
      ...build,
    },
  ];
}

function resolveFixedBuildStep(step: FixedBuildStep, env: NodeJS.ProcessEnv): FixedBuildStep {
  const invocation = resolveHarmonyCommand(step.executable, step.args, env);
  return { ...step, executable: invocation.command, args: invocation.args };
}

async function runFixedBuildStepAsync(
  step: FixedBuildStep,
  packageName: string,
  options: Pick<MaterializeLocalSourceOptions, 'env' | 'outputLimit' | 'timeoutMs'>
): Promise<void> {
  const timeoutMs = options.timeoutMs ?? DefaultBuildTimeoutMs;
  const outputLimit = options.outputLimit ?? DefaultOutputLimit;
  const stage = `artifact-materialize:${step.id}`;
  if (!Number.isInteger(timeoutMs) || timeoutMs <= 0
    || !Number.isInteger(outputLimit) || outputLimit <= 0) {
    throw new HarmonyAutolinkingError(
      'INVALID_OPTIONS',
      'timeoutMs and outputLimit must be positive integers.',
      { packageName, stage }
    );
  }

  const env = { ...process.env, ...options.env };
  const command = resolveFixedBuildStep(step, env);

  const result = await new Promise<{
    code: number | null;
    signal: NodeJS.Signals | null;
    output: string;
    timedOut: boolean;
  }>((resolve, reject) => {
    let output = '';
    let timedOut = false;
    let settled = false;
    let stopping: Promise<void> | undefined;
    let escalation: NodeJS.Timeout | undefined;
    let child;

    try {
      child = spawn(command.executable, [...command.args], {
        cwd: step.cwd,
        env,
        shell: false,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (cause) {
      reject(cause);
      return;
    }

    child.stdout.on('data', (chunk: Buffer) => {
      output = appendBounded(output, chunk, outputLimit);
    });
    child.stderr.on('data', (chunk: Buffer) => {
      output = appendBounded(output, chunk, outputLimit);
    });

    const finish = async (code, signal, error?) => {
      try {
        await stopping;
      } catch (cause) {
        error = cause;
      }

      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (escalation) clearTimeout(escalation);

      if (error) reject(error);
      else resolve({ code, signal, output, timedOut });
    };

    const timeout = setTimeout(() => {
      timedOut = true;
      stopping = Promise.resolve().then(() => terminateProcess(child, 'SIGTERM'));
      if (process.platform === 'win32') {
        void finish(null, 'SIGTERM');
      } else {
        stopping.catch((error) => {
          void finish(null, null, error);
        });
        escalation = setTimeout(() => {
          stopping = terminateProcess(child, 'SIGKILL');
          stopping.catch((error) => {
            void finish(null, null, error);
          });
        }, 1_000);
        escalation.unref?.();
      }
    }, timeoutMs);
    timeout.unref?.();

    child.on('error', (cause) => {
      void finish(null, null, cause);
    });
    child.on('close', (code, signal) => {
      void finish(code, signal);
    });
  }).catch((cause) => {
    throw new HarmonyAutolinkingError(
      'SOURCE_BUILD_FAILED',
      `Unable to execute the fixed ${step.label} for local Harmony source at ${step.cwd}.`,
      { cause, packageName, stage }
    );
  });

  if (result.code !== 0 || result.signal || result.timedOut) {
    const reason = result.timedOut
      ? 'timed out'
      : result.signal ? `was terminated by ${result.signal}` : `exited with code ${result.code}`;
    const output = sanitizeOutput(result.output, [step.cwd], outputLimit);
    throw new HarmonyAutolinkingError(
      'SOURCE_BUILD_FAILED',
      `Fixed ${step.label} ${reason}${output ? `: ${output}` : '.'}`,
      { packageName, stage }
    );
  }
}

async function materializeLocalSourceAsync(
  options: MaterializeLocalSourceOptions
): Promise<MaterializedLocalSource> {
  const module = options.module;

  if (module.source !== 'nativeModulesDir' || module.artifact.kind !== 'local-source') {
    throw new HarmonyAutolinkingError(
      'INVALID_OPTIONS',
      `${module.packageName} is not a nativeModulesDir local-source module.`,
      { packageName: module.packageName, stage: 'artifact-materialize' }
    );
  }

  const artifact = module.artifact;
  const project = await fs.promises.realpath(options.projectRoot);
  const root = await fs.promises.realpath(module.packageRoot);

  if (!isPathInside(project, root)) {
    throw new HarmonyAutolinkingError(
      'UNSAFE_SOURCE_ARTIFACT',
      'Harmony local modules must live inside the application project root.',
      { packageName: module.packageName, stage: 'artifact-materialize' }
    );
  }
  if (!module.arkTs) {
    throw new HarmonyAutolinkingError(
      'INVALID_METADATA',
      `${module.packageName} local-source descriptor has no derived ArkTS package.`,
      { packageName: module.packageName, stage: 'artifact-materialize' }
    );
  }

  const har = await resolveInsideAsync(
    root,
    module.arkTs.harPath,
    'Harmony materialized HAR path',
    { packageName: module.packageName, mustExist: false }
  );

  const source = await resolveInsideAsync(root, HarmonyProjectPath, 'Harmony source project', {
    packageName: module.packageName,
    type: 'directory',
  });
  if (artifact.build.cwd !== source || !isPathInside(source, artifact.outputPath)) {
    throw new HarmonyAutolinkingError('UNSAFE_SOURCE_ARTIFACT', 'Harmony build paths must stay inside the local source project.', {
      packageName: module.packageName, stage: 'artifact-materialize',
    });
  }

  const dependencies = (options.dependencies ?? []).filter(value => value.artifact.kind === 'bundled');
  const { overrides, versions } = resolveBuildOhpmDependencies(dependencies);
  // Keep the same parent so OHPM specifiers relative to sibling modules still resolve.
  const stage = await fs.promises.mkdtemp(path.join(path.dirname(root), '.expo-harmony-build-'));

  try {
    await fs.promises.cp(root, stage, {
      recursive: true,
      dereference: true,
      filter: async (entry) => {
        if (entry === har || (entry !== root && LocalBuildGeneratedDirectories.has(path.basename(entry)))) return false;
        if (!isPathInside(root, await fs.promises.realpath(entry))) {
          throw new HarmonyAutolinkingError('UNSAFE_SOURCE_ARTIFACT', `Harmony source link escapes its local module: ${path.relative(root, entry)}`, {
            packageName: module.packageName, stage: 'artifact-materialize',
          });
        }
        return true;
      },
    });
    const cwd = path.join(stage, path.relative(root, source));
    const file = path.join(cwd, 'oh-package.json5');
    const config = JSON5.parse(await fs.promises.readFile(file, 'utf8'));

    await fs.promises.writeFile(file, JSON.stringify({ ...config, overrides: { ...config.overrides, ...overrides } }, null, 2) + '\n');

    for (const step of fixedLocalSourceBuildSteps({ ...artifact.build, cwd })) {
      await runFixedBuildStepAsync(step, module.packageName, options);
    }

    const output = path.join(cwd, path.relative(source, artifact.outputPath));
    if (!await isNonEmptyRegularHarAsync(output, cwd, module.packageName)) {
      throw new HarmonyAutolinkingError(
        'SOURCE_BUILD_FAILED',
        `Hvigor did not produce a non-empty HAR at ${normalizeSlashes(path.relative(root, artifact.outputPath))}.`,
        { packageName: module.packageName, stage: 'artifact-materialize' }
      );
    }

    await sanitizeHarmonyHar(output, {
      workspaceVersions: versions,
      moduleRoot: path.join(cwd, 'library'),
    });

    // Link against immutable bytes even if another invocation refreshes library.har.
    const hash = createHash('sha256');
    for await (const chunk of fs.createReadStream(output)) hash.update(chunk);
    const builtHarPath = path.join(project, '.expo/harmony/module-builds', `local-${hash.digest('hex')}.har`);
    await publishArtifactsAsync({
      allowedRoot: project,
      lockPath: path.join(project, '.expo/harmony/module-materialize.lock'),
      files: [{ source: output, target: builtHarPath }, { source: output, target: har }],
    });

    return { packageName: module.packageName, harPath: har, builtHarPath };
  } finally {
    await fs.promises.rm(stage, { recursive: true, force: true });
  }
}

async function materializeLocalSourcesAsync(
  modules: ReadonlyArray<MaterializeLocalSourceOptions['module']>,
  options: Omit<MaterializeLocalSourceOptions, 'module'>
): Promise<ReadonlyArray<MaterializedLocalSource>> {
  const results = [];
  for (const module of [...modules].sort((left, right) => compareText(left.packageName, right.packageName))) {
    results.push(await materializeLocalSourceAsync({ ...options, module }));
  }
  return results;
}

export {
  createFixedHvigorBuildDescriptor,
  findHarmonyLibrary,
  materializeLocalSourcesAsync,
  materializeModuleArtifactAsync,
  runFixedBuildStepAsync,
  fixedLocalSourceBuildSteps,
  isNonEmptyRegularHarAsync,
};

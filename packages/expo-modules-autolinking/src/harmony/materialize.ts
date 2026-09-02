import * as fs from 'node:fs';
import * as path from 'node:path';
import { spawn } from 'node:child_process';

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
const HarmonyBuildOutputPath = 'library/build/default/outputs/default/library.har';

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

function materializationError(
  code: string,
  message: string,
  options: MaterializeModuleArtifactOptions,
  details?: unknown
): never {
  throw new HarmonyAutolinkingError(code, message, {
    packageName: options.packageName,
    stage: 'artifact-materialize',
    details,
  });
}

function createFixedHvigorBuildDescriptor(
  projectPath: string,
  buildType: BuildType
): FixedHvigorBuildDescriptor {
  return {
    executable: 'hvigorw',
    cwd: projectPath,
    args: [
      '--mode', 'module',
      '-p', 'module=library@default',
      '-p', 'product=default',
      '-p', `buildMode=${buildType}`,
      '--no-daemon',
      'assembleHar',
    ],
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
      materializationError(
        'SOURCE_ARTIFACT_NOT_PUBLISHED',
        `${options.packageName} has a missing or empty Harmony HAR.`,
        options,
        { harPath: relative }
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
  const outputPath = await resolveInsideAsync(sourceRoot, HarmonyBuildOutputPath, 'Harmony build output', {
    packageName: options.packageName,
    mustExist: false,
  });
  return {
    kind: 'local-source',
    outputPath,
    materialized: false,
    build: createFixedHvigorBuildDescriptor(sourceRoot, options.buildType),
  };
}

function appendBounded(current: string, chunk: Buffer, limit: number): string {
  if (current.length >= limit) return current;
  return current + chunk.toString('utf8').slice(0, limit - current.length);
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
  if (step.id === 'ohpm-install') {
    return env.HARMONY_OHPM ? { ...step, executable: env.HARMONY_OHPM } : step;
  }

  const configured = env.HARMONY_HVIGORW;
  if (configured) {
    return /\.(?:c|m)?js$/iu.test(configured)
      ? { ...step, executable: env.HARMONY_NODE || process.execPath, args: [configured, ...step.args] }
      : { ...step, executable: configured };
  }

  return step;
}

async function runFixedBuildStepAsync(
  step: FixedBuildStep,
  packageName: string,
  options: Pick<MaterializeLocalSourceOptions, 'env' | 'outputLimit' | 'timeoutMs'>
): Promise<void> {
  const timeoutMs = options.timeoutMs ?? DefaultBuildTimeoutMs;
  const outputLimit = options.outputLimit ?? DefaultOutputLimit;
  const stage = `artifact-materialize:${step.id}`;
  const env = { ...process.env, ...options.env };
  const resolvedStep = resolveFixedBuildStep(step, env);
  if (!Number.isInteger(timeoutMs) || timeoutMs <= 0
    || !Number.isInteger(outputLimit) || outputLimit <= 0) {
    throw new HarmonyAutolinkingError(
      'INVALID_OPTIONS',
      'timeoutMs and outputLimit must be positive integers.',
      { packageName, stage }
    );
  }

  const result = await new Promise<{
    code: number | null;
    signal: NodeJS.Signals | null;
    output: string;
    timedOut: boolean;
  }>((resolve, reject) => {
    let output = '';
    let timedOut = false;
    let settled = false;
    let killTimer: NodeJS.Timeout | undefined;
    let child;
    try {
      child = spawn(resolvedStep.executable, [...resolvedStep.args], {
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
    const timeout = setTimeout(() => {
      timedOut = true;
      child.kill('SIGTERM');
      killTimer = setTimeout(() => child.kill('SIGKILL'), 1_000);
      killTimer.unref?.();
    }, timeoutMs);
    timeout.unref?.();
    child.on('error', (cause) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (killTimer) clearTimeout(killTimer);
      reject(cause);
    });
    child.on('close', (code, signal) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (killTimer) clearTimeout(killTimer);
      resolve({ code, signal, output, timedOut });
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
  const projectRoot = await fs.promises.realpath(options.projectRoot);
  const packageRoot = await fs.promises.realpath(module.packageRoot);
  if (!isPathInside(projectRoot, packageRoot)) {
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
  const harPath = await resolveInsideAsync(
    packageRoot,
    module.arkTs.harPath,
    'Harmony materialized HAR path',
    { packageName: module.packageName, mustExist: false }
  );

  for (const step of fixedLocalSourceBuildSteps(artifact.build)) {
    await runFixedBuildStepAsync(step, module.packageName, options);
  }
  const outputReady = await isNonEmptyRegularHarAsync(
    artifact.outputPath,
    artifact.build.cwd,
    module.packageName
  );
  if (!outputReady) {
    throw new HarmonyAutolinkingError(
      'SOURCE_BUILD_FAILED',
      `Hvigor did not produce a non-empty HAR at ${normalizeSlashes(path.relative(packageRoot, artifact.outputPath))}.`,
      { packageName: module.packageName, stage: 'artifact-materialize' }
    );
  }

  await publishArtifactsAsync({
    allowedRoot: projectRoot,
    lockPath: path.join(projectRoot, '.expo/harmony/module-materialize.lock'),
    files: [{ source: artifact.outputPath, target: harPath }],
  });
  if (!await isNonEmptyRegularHarAsync(harPath, packageRoot, module.packageName)) {
    throw new HarmonyAutolinkingError(
      'SOURCE_BUILD_FAILED',
      'Harmony HAR materialization produced a missing or empty file.',
      { packageName: module.packageName, stage: 'artifact-materialize' }
    );
  }
  return {
    packageName: module.packageName,
    harPath,
  };
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
  materializeLocalSourcesAsync,
  materializeModuleArtifactAsync,
};

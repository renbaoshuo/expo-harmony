/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import crossSpawn from 'cross-spawn';
import fs from 'node:fs';
import path from 'node:path';

import { RnohArtifacts } from '../../config/constants';
import { HarmonyAutolinkingError } from '../../errors';
import { assertSafeRnohPackageList } from '../../config/options';
import { isPathInside, sanitizeOutput } from '../../utilities/values';
import { terminateProcess } from '../../utilities/terminateProcess';
import { resolveRnohMetadata } from './packageMetadata';
import { resolveCliAsync } from './cli';

const DEFAULT_TIMEOUT_MS = 120_000;
const DEFAULT_OUTPUT_LIMIT = 64 * 1024;

function appendBounded(current, chunk, limit) {
  if (current.length >= limit) return current;
  return Buffer.concat([current, chunk.subarray(0, limit - current.length)]);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function spawnBoundedAsync(executable, argv, options: Record<string, any> = {}) {
  return new Promise((resolve, reject) => {
    const outputLimit = options.outputLimit === undefined ? DEFAULT_OUTPUT_LIMIT : options.outputLimit;
    const timeoutMs = options.timeoutMs === undefined ? DEFAULT_TIMEOUT_MS : options.timeoutMs;

    if (!Number.isInteger(outputLimit) || outputLimit <= 0
      || !Number.isInteger(timeoutMs) || timeoutMs <= 0) {
      reject(new HarmonyAutolinkingError('INVALID_OPTIONS', 'timeoutMs and outputLimit must be positive integers.', { stage: 'rnoh-preflight' }));
      return;
    }

    let stdout = Buffer.alloc(0);
    let stderr = Buffer.alloc(0);
    let stdoutTruncated = false;
    let stderrTruncated = false;
    let timedOut = false;
    let escalation;
    // eslint-disable-next-line prefer-const
    let timeout;
    let settled = false;
    let stopping: Promise<void> | undefined;
    let child;

    try {
      child = crossSpawn(executable, argv, {
        cwd: options.cwd,
        env: options.env || process.env,
        shell: false,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (cause) {
      reject(cause);
      return;
    }

    child.stdout.on('data', (chunk) => {
      if (stdout.length + chunk.length > outputLimit) stdoutTruncated = true;
      stdout = appendBounded(stdout, chunk, outputLimit);
    });

    child.stderr.on('data', (chunk) => {
      if (stderr.length + chunk.length > outputLimit) stderrTruncated = true;
      stderr = appendBounded(stderr, chunk, outputLimit);
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
      clearTimeout(escalation);

      if (error) reject(error);
      else resolve({
        code,
        signal,
        timedOut,
        stdout: stdout.toString('utf8'),
        stderr: stderr.toString('utf8'),
        stdoutTruncated,
        stderrTruncated,
      });
    };

    child.on('error', (error) => {
      void finish(null, null, error);
    });

    timeout = setTimeout(() => {
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

    child.on('close', (code, signal) => {
      void finish(code, signal);
    });
  });
}

async function readGeneratedArtifactsAsync(harmony, allowedRoot) {
  const lexicalAllowed = path.resolve(allowedRoot);
  const lexicalRoot = path.resolve(harmony);
  let root;
  try {
    if (!isPathInside(lexicalAllowed, lexicalRoot)) throw new TypeError('outside staging root');
    const allowed = await fs.promises.realpath(lexicalAllowed);
    root = await fs.promises.realpath(lexicalRoot);
    const stat = await fs.promises.stat(root);
    if (!isPathInside(allowed, root) || !stat.isDirectory()) throw new TypeError('unsafe staging root');
  } catch (cause) {
    throw new HarmonyAutolinkingError(
      'GENERATED_ARTIFACT_MISSING',
      'RNOH output root must resolve to a directory inside the staging project.',
      { cause, stage: 'rnoh-validate' }
    );
  }
  const artifacts = {};

  for (const [name, relative] of Object.entries(RnohArtifacts)) {
    const target = path.join(root, relative);
    let stat;
    let realTarget;
    let artifact;
    try {
      if (!isPathInside(root, target)) throw new TypeError('outside staging root');
      stat = await fs.promises.lstat(target);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size === 0) {
        throw new TypeError('not a non-empty regular file');
      }
      realTarget = await fs.promises.realpath(target);
      if (!isPathInside(root, realTarget)) throw new TypeError('outside staging root');
      artifact = name === 'cppFactory'
        ? { path: realTarget }
        : { path: realTarget, content: await fs.promises.readFile(realTarget, 'utf8') };
    } catch (cause) {
      throw new HarmonyAutolinkingError('GENERATED_ARTIFACT_MISSING', `RNOH did not generate a non-empty regular ${relative}.`, {
        cause,
        stage: 'rnoh-validate',
        details: { artifact: relative },
      });
    }

    artifacts[name] = artifact;
  }

  return artifacts;
}

function buildLinkCommandArgs(options) {
  assertSafeRnohPackageList(options.include || [], 'include', 'rnoh-preflight');
  assertSafeRnohPackageList(options.exclude || [], 'exclude', 'rnoh-preflight');

  if (options.include?.length && options.exclude?.length) {
    throw new HarmonyAutolinkingError(
      'INVALID_OPTIONS',
      'include and exclude cannot both be set for RNOH link-harmony.',
      { stage: 'rnoh-preflight' }
    );
  }

  const argv = [
    'link-harmony',
    '--harmony-project-path', options.harmonyProjectPath,
    '--node-modules-path', options.nodeModulesPath,
    '--cmake-autolink-path-relative-to-harmony', RnohArtifacts.cmake,
    '--cpp-rnoh-packages-factory-path-relative-to-harmony', RnohArtifacts.cppFactory,
    '--ets-rnoh-packages-factory-path-relative-to-harmony', RnohArtifacts.etsFactory,
    '--oh-package-path-relative-to-harmony', RnohArtifacts.ohPackage,
  ];

  if (options.include?.length) argv.push('--include-npm-packages', options.include.join(';'));
  if (options.exclude?.length) argv.push('--exclude-npm-packages', options.exclude.join(';'));

  return argv;
}

function describeProcessFailure(result, roots) {
  const reason = result.timedOut
    ? 'timed out'
    : result.signal
      ? `was terminated by ${result.signal}`
      : `exited with code ${result.code}`;

  const stderr = sanitizeOutput(result.stderr, roots);
  return `React Native link-harmony ${reason}${stderr ? `: ${stderr}` : '.'}`;
}

function patchCmakeSource(source, descriptors) {
  let content = source;

  for (const descriptor of descriptors.filter(item => item.rnoh.harPaths.length > 0)) {
    const metadata = resolveRnohMetadata(descriptor);
    const ohPackageName = metadata.harMappings[0].ohPackageName;
    const generated = `    add_subdirectory("\${OH_MODULES_DIR}/${ohPackageName}/src/main/cpp" ./${metadata.cmakeLibraryTargetName})`;
    const guarded = [
      `    if(NOT TARGET ${metadata.cmakeLibraryTargetName})`,
      `      add_subdirectory("\${OH_MODULES_DIR}/${ohPackageName}/src/main/cpp" ./${metadata.cmakeLibraryTargetName})`,
      '    endif()',
    ].join('\n');
    const fragments = content.split(generated);
    if (fragments.length !== 2) {
      throw new HarmonyAutolinkingError(
        'GENERATED_ARTIFACT_SET_MISMATCH',
        `RNOH generated CMake did not contain exactly one add_subdirectory for ${descriptor.packageName}.`,
        { stage: 'rnoh-patch', packageName: descriptor.packageName }
      );
    }
    content = `${fragments[0]}${guarded}${fragments[1]}`;
  }

  return content;
}

async function patchCmakeAsync(artifact, descriptors) {
  const content = patchCmakeSource(artifact.content, descriptors);
  if (content !== artifact.content) {
    await fs.promises.writeFile(artifact.path, content);
    artifact.content = content;
  }
}

async function linkRnohAsync(options) {
  const command = await resolveCliAsync({
    ...options,
    nodeModulesPath: options.commandNodeModulesPath,
  });

  const spawn = {
    cwd: options.stageProjectRoot,
    env: options.env ? { ...process.env, ...options.env } : process.env,
    outputLimit: options.outputLimit,
    timeoutMs: options.timeoutMs,
  };

  let result;
  try {
    result = await spawnBoundedAsync(command.executable, [...command.args, ...buildLinkCommandArgs({
      harmonyProjectPath: options.stageHarmonyProjectPath,
      nodeModulesPath: options.nodeModulesPath,
      include: options.include,
      exclude: options.exclude,
    })], spawn);
  } catch (cause) {
    throw new HarmonyAutolinkingError('RNOH_LINK_FAILED', 'Unable to execute React Native link-harmony.', { cause, stage: 'rnoh-link' });
  }

  if (result.code !== 0 || result.signal || result.timedOut) {
    throw new HarmonyAutolinkingError(
      'RNOH_LINK_FAILED',
      describeProcessFailure(result, [options.temporaryRoot, options.projectRoot]),
      {
        stage: 'rnoh-link',
        details: {
          exitCode: result.code,
          signal: result.signal,
          timedOut: result.timedOut,
          stdoutTruncated: result.stdoutTruncated,
          stderrTruncated: result.stderrTruncated,
        },
      }
    );
  }

  let artifacts;
  try {
    artifacts = await readGeneratedArtifactsAsync(
      options.stageHarmonyProjectPath,
      options.stageProjectRoot
    );
  } catch (error) {
    const roots = [options.temporaryRoot, options.stageProjectRoot, options.projectRoot];
    const details = {
      ...(error.details || {}),
      stdout: sanitizeOutput(result.stdout, roots),
      stderr: sanitizeOutput(result.stderr, roots),
      stdoutTruncated: result.stdoutTruncated,
      stderrTruncated: result.stderrTruncated,
    };
    throw new HarmonyAutolinkingError(
      typeof error.code === 'string' ? error.code : 'RNOH_LINK_FAILED',
      error.message || 'RNOH did not generate the required artifacts.',
      {
        cause: error,
        stage: error.stage || 'rnoh-validate',
        packageName: error.packageName,
        diagnostics: error.diagnostics,
        details,
      }
    );
  }

  if (options.modules) {
    try {
      await patchCmakeAsync(artifacts.cmake, options.modules);
    } catch (error) {
      const roots = [options.temporaryRoot, options.stageProjectRoot, options.projectRoot];
      const details = {
        ...(error.details || {}),
        stdout: sanitizeOutput(result.stdout, roots),
        stderr: sanitizeOutput(result.stderr, roots),
        stdoutTruncated: result.stdoutTruncated,
        stderrTruncated: result.stderrTruncated,
      };
      throw new HarmonyAutolinkingError(
        typeof error.code === 'string' ? error.code : 'RNOH_LINK_FAILED',
        error.message || 'Unable to patch RNOH artifacts.',
        {
          cause: error,
          stage: error.stage || 'rnoh-validate',
          packageName: error.packageName,
          diagnostics: error.diagnostics,
          details,
        }
      );
    }
  }

  return artifacts;
}

export {
  linkRnohAsync,
};

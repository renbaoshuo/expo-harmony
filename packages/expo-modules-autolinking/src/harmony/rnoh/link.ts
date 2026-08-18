import childProcess from 'node:child_process';
import nodeCrypto, { type BinaryLike } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import JSON5 from 'json5';

import { RnohArtifacts } from '../../config/constants';
import { HarmonyAutolinkingError } from '../../errors';
import { assertSafeRnohPackageList } from '../../config/options';
import { isPathInside, sanitizeOutput } from '../../utilities/values';
import { resolveRnohMetadata } from './packageMetadata';
import { resolveCliAsync } from './cli';
import { syncOhpmVersions, verifyRnohArtifacts } from './verify';

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
    let killTimer;
    // eslint-disable-next-line prefer-const
    let timeout;
    let settled = false;
    let child;

    try {
      child = childProcess.spawn(executable, argv, {
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

    child.on('error', (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      clearTimeout(killTimer);
      reject(error);
    });

    timeout = setTimeout(() => {
      timedOut = true;
      child.kill('SIGTERM');
      killTimer = setTimeout(() => child.kill('SIGKILL'), 1_000);
      killTimer.unref?.();
    }, timeoutMs);
    timeout.unref?.();

    child.on('close', (code, signal) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      clearTimeout(killTimer);
      resolve({
        code,
        signal,
        timedOut,
        stdout: stdout.toString('utf8'),
        stderr: stderr.toString('utf8'),
        stdoutTruncated,
        stderrTruncated,
      });
    });
  });
}

async function snapshotTreeAsync(root) {
  const snapshot = new Map();

  async function visit(directory) {
    const entries = await fs.promises.readdir(directory, { withFileTypes: true });
    entries.sort((left, right) => left.name.localeCompare(right.name, 'en'));

    for (const entry of entries) {
      const target = path.join(directory, entry.name);
      const relative = path.relative(root, target).split(path.sep).join('/');
      if (entry.isSymbolicLink()) {
        snapshot.set(relative, `symlink:${await fs.promises.readlink(target)}`);
      } else if (entry.isDirectory()) {
        snapshot.set(`${relative}/`, 'directory');
        await visit(target);
      } else if (entry.isFile()) {
        const buffer = await fs.promises.readFile(target);
        snapshot.set(relative, nodeCrypto.createHash('sha256').update(buffer as unknown as BinaryLike).digest('hex'));
      } else {
        snapshot.set(relative, 'special');
      }
    }
  }

  await visit(root);
  return snapshot;
}

function protectedEntryType(stat) {
  if (stat.isSymbolicLink()) return 'symlink';
  if (stat.isDirectory()) return 'directory';
  if (stat.isFile()) return 'file';
  if (stat.isBlockDevice()) return 'block';
  if (stat.isCharacterDevice()) return 'character';
  if (stat.isFIFO()) return 'fifo';
  if (stat.isSocket()) return 'socket';
  return 'unknown';
}

function snapshotProtectedTreeMetadata(root, fileSystem = fs, maxDepth = Number.POSITIVE_INFINITY) {
  const snapshot = new Map();

  function visit(directory, depth) {
    const names = fileSystem.readdirSync(directory).sort((left, right) => left.localeCompare(right, 'en'));

    for (const name of names) {
      const target = path.join(directory, name);
      const relative = path.relative(root, target).split(path.sep).join('/');
      const stat = fileSystem.lstatSync(target, { bigint: true });
      const type = protectedEntryType(stat);
      const link = type === 'symlink' ? fileSystem.readlinkSync(target) : '';

      snapshot.set(relative, [
        type,
        stat.size,
        stat.mtimeNs,
        stat.ctimeNs,
        stat.mode,
        link,
      ].join(':'));
      if (type === 'directory' && depth < maxDepth) visit(target, depth + 1);
    }
  }

  visit(root, 0);
  return snapshot;
}

function assertOnlyAllowedChanges(before, after, allowed) {
  const unexpected = [];

  for (const key of new Set([...before.keys(), ...after.keys()])) {
    if (before.get(key) === after.get(key)) continue;
    if (!allowed.has(key)) unexpected.push(key);
  }

  if (unexpected.length > 0) {
    unexpected.sort();
    throw new HarmonyAutolinkingError('RNOH_LINK_FAILED', `RNOH link-harmony modified unmanaged staging paths: ${unexpected.join(', ')}`, { stage: 'rnoh-validate', details: { unexpected } });
  }
}

function assertProtectedTreesUnchanged(before, after) {
  for (const [root, saved] of before) {
    const current = after.get(root);
    const changed = [];

    for (const key of new Set([...saved.keys(), ...current.keys()])) {
      if (saved.get(key) !== current.get(key)) changed.push(key);
    }

    if (changed.length > 0) {
      changed.sort();
      throw new HarmonyAutolinkingError(
        'RNOH_LINK_FAILED',
        `RNOH link-harmony modified a protected input tree: ${changed.slice(0, 20).join(', ')}`,
        { stage: 'rnoh-validate', details: { changed: changed.slice(0, 100) } }
      );
    }
  }
}

function isJson5Object(content) {
  try {
    const value = JSON5.parse(content);
    return value != null && typeof value === 'object' && !Array.isArray(value);
  } catch (_cause) {
    return false;
  }
}

async function verifyGeneratedArtifactsAsync(harmony, forbidden = []) {
  const root = await fs.promises.realpath(harmony);
  const artifacts = {};

  for (const [name, relative] of Object.entries(RnohArtifacts)) {
    const target = path.join(root, relative);
    let stat;
    let realTarget;
    let content;
    try {
      stat = await fs.promises.lstat(target);
      if (!stat.isFile() || stat.isSymbolicLink()) throw new TypeError('not a regular file');
      realTarget = await fs.promises.realpath(target);
      if (!isPathInside(root, realTarget)) throw new TypeError('outside staging root');
      content = await fs.promises.readFile(realTarget, 'utf8');
    } catch (cause) {
      throw new HarmonyAutolinkingError('GENERATED_ARTIFACT_MISSING', `RNOH did not generate a valid ${relative}.`, {
        cause,
        stage: 'rnoh-validate',
        details: { artifact: relative },
      });
    }

    if (!content.trim()) {
      throw new HarmonyAutolinkingError('GENERATED_ARTIFACT_MISSING', `RNOH generated an empty ${relative}.`, {
        stage: 'rnoh-validate',
        details: { artifact: relative },
      });
    }

    for (const base of forbidden.filter(Boolean)) {
      if (content.includes(base)) {
        throw new HarmonyAutolinkingError('RNOH_LINK_FAILED', `${relative} contains a staging-only absolute path.`, {
          stage: 'rnoh-validate',
          details: { artifact: relative },
        });
      }
    }

    if (name === 'ohPackage' && !isJson5Object(content)) {
      throw new HarmonyAutolinkingError('GENERATED_ARTIFACT_MISSING', 'RNOH generated an invalid oh-package.json5 root.', {
        stage: 'rnoh-validate',
      });
    }

    artifacts[name] = { path: realTarget, content };
  }

  return artifacts;
}

function buildLinkCommandArgs(linkOptions) {
  assertSafeRnohPackageList(linkOptions.include || [], 'include', 'rnoh-preflight');
  assertSafeRnohPackageList(linkOptions.exclude || [], 'exclude', 'rnoh-preflight');

  if (linkOptions.include?.length && linkOptions.exclude?.length) {
    throw new HarmonyAutolinkingError(
      'INVALID_OPTIONS',
      'include and exclude cannot both be set for RNOH link-harmony.',
      { stage: 'rnoh-preflight' }
    );
  }

  const argv = [
    'link-harmony',
    '--harmony-project-path', linkOptions.harmonyProjectPath,
    '--node-modules-path', linkOptions.nodeModulesPath,
    '--cmake-autolink-path-relative-to-harmony', RnohArtifacts.cmake,
    '--cpp-rnoh-packages-factory-path-relative-to-harmony', RnohArtifacts.cppFactory,
    '--ets-rnoh-packages-factory-path-relative-to-harmony', RnohArtifacts.etsFactory,
    '--oh-package-path-relative-to-harmony', RnohArtifacts.ohPackage,
  ];

  if (linkOptions.include?.length) argv.push('--include-npm-packages', linkOptions.include.join(';'));
  if (linkOptions.exclude?.length) argv.push('--exclude-npm-packages', linkOptions.exclude.join(';'));
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

async function patchEtsFactoryAsync(artifact, descriptors) {
  let content = artifact.content;
  const generated = 'import type { RNPackageContext, RNOHPackage } from \'@rnoh/react-native-openharmony\';';
  const compatible = 'import type { RNPackage, RNPackageContext } from \'@rnoh/react-native-openharmony\';';

  if (content.includes(generated)) {
    content = content.replace(generated, compatible);
  } else if (!content.includes(compatible)) {
    throw new HarmonyAutolinkingError(
      'GENERATED_ARTIFACT_SET_MISMATCH',
      'RNOH generated an unsupported ETS Package type import.',
      { stage: 'rnoh-validate' }
    );
  }

  if (content.includes('): RNOHPackage[] {')) {
    content = content.replace('): RNOHPackage[] {', '): RNPackage[] {');
  } else if (!content.includes('): RNPackage[] {')) {
    throw new HarmonyAutolinkingError(
      'GENERATED_ARTIFACT_SET_MISMATCH',
      'RNOH generated an unsupported ETS Package factory return type.',
      { stage: 'rnoh-validate' }
    );
  }

  for (const descriptor of descriptors.filter(item => item.rnoh.harPaths.length > 0)) {
    const rnohMetadata = resolveRnohMetadata(descriptor);
    if (rnohMetadata.etsPackageImport !== 'named') continue;

    const name = rnohMetadata.harMappings[0].ohPackageName;
    const defaultImport = `import ${rnohMetadata.etsPackageClassName} from '${name}';`;
    const namedImport = `import { ${rnohMetadata.etsPackageClassName} } from '${name}';`;
    if (content.includes(defaultImport)) {
      content = content.replace(defaultImport, namedImport);
    } else if (!content.includes(namedImport)) {
      throw new HarmonyAutolinkingError(
        'GENERATED_ARTIFACT_SET_MISMATCH',
        `RNOH did not generate the expected ETS import for ${descriptor.packageName}.`,
        { packageName: descriptor.packageName, stage: 'rnoh-validate' }
      );
    }
  }

  if (content !== artifact.content) {
    await fs.promises.writeFile(artifact.path, content);
    artifact.content = content;
  }
}

async function patchCmakeAsync(artifact, descriptors) {
  let content = artifact.content;

  for (const descriptor of descriptors.filter(item => item.rnoh.harPaths.length > 0)) {
    const rnohMetadata = resolveRnohMetadata(descriptor);
    const name = rnohMetadata.harMappings[0].ohPackageName;
    const add = `    add_subdirectory("\${OH_MODULES_DIR}/${name}/src/main/cpp" ./${rnohMetadata.cmakeLibraryTargetName})`;
    const guarded = [
      `    if(NOT TARGET ${rnohMetadata.cmakeLibraryTargetName})`,
      `    ${add}`,
      '    endif()',
    ].join('\n');

    if (content.includes(add)) {
      content = content.replace(add, guarded);
    } else if (!content.includes(guarded)) {
      throw new HarmonyAutolinkingError(
        'GENERATED_ARTIFACT_SET_MISMATCH',
        `RNOH did not generate the expected CMake target for ${descriptor.packageName}.`,
        { packageName: descriptor.packageName, stage: 'rnoh-validate' }
      );
    }
  }

  if (content !== artifact.content) {
    await fs.promises.writeFile(artifact.path, content);
    artifact.content = content;
  }
}

async function linkRnohAsync(linkOptions) {
  const command = await resolveCliAsync({
    ...linkOptions,
    nodeModulesPath: linkOptions.commandNodeModulesPath || linkOptions.nodeModulesPath,
  });

  const spawn = {
    cwd: linkOptions.stageProjectRoot,
    env: linkOptions.env ? { ...process.env, ...linkOptions.env } : process.env,
    outputLimit: linkOptions.outputLimit,
    timeoutMs: linkOptions.timeoutMs,
  };

  let help;
  try {
    help = await spawnBoundedAsync(command.executable, ['link-harmony', '--help'], spawn);
  } catch (cause) {
    throw new HarmonyAutolinkingError(
      'RNOH_LINK_FAILED',
      'Unable to execute the project-local React Native CLI.',
      { cause, stage: 'rnoh-preflight' }
    );
  }

  if (help.code !== 0 || help.signal || help.timedOut
    || !help.stdout.includes('link-harmony')
    || !help.stdout.includes('--harmony-project-path')) {
    throw new HarmonyAutolinkingError('RNOH_LINK_FAILED', 'The project-local React Native CLI does not expose public link-harmony.', {
      stage: 'rnoh-preflight',
      details: {
        exitCode: help.code,
        signal: help.signal,
        timedOut: help.timedOut,
      },
    });
  }

  const before = await snapshotTreeAsync(linkOptions.stageProjectRoot);
  const roots = [
    ...(linkOptions.protectedPaths || []).map(root => ({ root, maxDepth: Number.POSITIVE_INFINITY })),
    ...(linkOptions.protectedShallowPaths || []).map(root => ({ root, maxDepth: 1 })),
  ];
  const saved = new Map();
  for (const root of roots) {
    saved.set(
      root.root,
      snapshotProtectedTreeMetadata(root.root, fs, root.maxDepth)
    );
  }

  let result;
  try {
    result = await spawnBoundedAsync(command.executable, buildLinkCommandArgs({
      harmonyProjectPath: linkOptions.stageHarmonyProjectPath,
      nodeModulesPath: linkOptions.nodeModulesPath,
      include: linkOptions.include,
      exclude: linkOptions.exclude,
    }), spawn);
  } catch (cause) {
    throw new HarmonyAutolinkingError('RNOH_LINK_FAILED', 'Unable to execute React Native link-harmony.', { cause, stage: 'rnoh-link' });
  }

  const current = new Map();
  for (const root of roots) {
    current.set(
      root.root,
      snapshotProtectedTreeMetadata(root.root, fs, root.maxDepth)
    );
  }
  assertProtectedTreesUnchanged(saved, current);

  if (result.code !== 0 || result.signal || result.timedOut) {
    throw new HarmonyAutolinkingError(
      'RNOH_LINK_FAILED',
      describeProcessFailure(result, [linkOptions.temporaryRoot, linkOptions.projectRoot]),
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
    artifacts = await verifyGeneratedArtifactsAsync(linkOptions.stageHarmonyProjectPath, [
      linkOptions.temporaryRoot,
      linkOptions.stageProjectRoot,
    ]);
  } catch (error) {
    const roots = [linkOptions.temporaryRoot, linkOptions.stageProjectRoot, linkOptions.projectRoot];
    error.details = {
      ...(error.details || {}),
      stdout: sanitizeOutput(result.stdout, roots),
      stderr: sanitizeOutput(result.stderr, roots),
      stdoutTruncated: result.stdoutTruncated,
      stderrTruncated: result.stderrTruncated,
    };
    throw error;
  }

  if (linkOptions.modules) {
    try {
      await patchEtsFactoryAsync(artifacts.etsFactory, linkOptions.modules);
      await patchCmakeAsync(artifacts.cmake, linkOptions.modules);
      syncOhpmVersions(artifacts, linkOptions.modules, linkOptions.buildType);
      verifyRnohArtifacts(artifacts, linkOptions.modules, {
        buildType: linkOptions.buildType,
        allowedUnmanagedDependencies: linkOptions.allowedUnmanagedDependencies,
      });
      await fs.promises.writeFile(artifacts.ohPackage.path, artifacts.ohPackage.content);
    } catch (error) {
      const roots = [linkOptions.temporaryRoot, linkOptions.stageProjectRoot, linkOptions.projectRoot];
      error.details = {
        ...(error.details || {}),
        stdout: sanitizeOutput(result.stdout, roots),
        stderr: sanitizeOutput(result.stderr, roots),
        stdoutTruncated: result.stdoutTruncated,
        stderrTruncated: result.stderrTruncated,
      };
      throw error;
    }
  }

  const after = await snapshotTreeAsync(linkOptions.stageProjectRoot);
  const harmonyRoot = path.relative(linkOptions.stageProjectRoot, linkOptions.stageHarmonyProjectPath)
    .split(path.sep).join('/');
  const allowed = new Set(Object.values(RnohArtifacts).map(relative => harmonyRoot ? `${harmonyRoot}/${relative}` : relative));
  assertOnlyAllowedChanges(before, after, allowed);

  return {
    artifacts,
    command: command.executable,
    stdout: result.stdout,
    stderr: result.stderr,
    stdoutTruncated: result.stdoutTruncated,
    stderrTruncated: result.stderrTruncated,
  };
}

export {
  assertOnlyAllowedChanges,
  assertProtectedTreesUnchanged,
  buildLinkCommandArgs,
  linkRnohAsync,
  snapshotProtectedTreeMetadata,
  snapshotTreeAsync,
  spawnBoundedAsync,
  verifyGeneratedArtifactsAsync,
};

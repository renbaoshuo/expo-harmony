import childProcess from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

import { RnohArtifacts } from '../../config/constants';
import { HarmonyAutolinkingError } from '../../errors';
import { assertSafeRnohPackageList } from '../../config/options';
import { isPathInside, sanitizeOutput } from '../../utilities/values';
import { createManifest } from '../manifest/generate';
import { canonicalizeOhpmManifest } from '../persistence/canonicalize';
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

function patchEtsFactorySource(source, descriptors) {
  // RNOH 0.84.1 emits this exact zero-argument factory shape. Convert only that
  // current toolchain output so any upstream change is visible in CI.
  const generated = 'import type { RNPackageContext, RNOHPackage } from \'@rnoh/react-native-openharmony\';';
  const packageTypes = 'import type { RNPackage, RNPackageContext } from \'@rnoh/react-native-openharmony\';';
  const generatedHostProvider = 'import { expoHarmonyHostProvider } from \'./generated/ExpoHarmonyHostProvider\';';
  const coreRootImport = 'import ExpoModulesCorePackage from \'@expo-harmony/expo-modules-core\';';
  const coreAutolinkingImport = 'import ExpoModulesCorePackage from \'@expo-harmony/expo-modules-core/Autolinking\';';
  const replacements = [
    [generated, `${packageTypes}\n${generatedHostProvider}`, 'RNOH package type import'],
    [coreRootImport, coreAutolinkingImport, 'Expo Modules Core package import'],
    ['): RNOHPackage[] {', '): RNPackage[] {', 'RNOH package factory return type'],
    [
      'new ExpoModulesCorePackage(ctx)',
      'new ExpoModulesCorePackage(ctx, expoHarmonyHostProvider.expoModules, expoHarmonyHostProvider.hostState)',
      'Expo Modules Core zero-argument registration',
    ],
  ];
  const namedImports = new Map();
  for (const descriptor of descriptors.filter(item => item.rnoh.harPaths.length > 0)) {
    const rnohMetadata = resolveRnohMetadata(descriptor);
    if (rnohMetadata.etsPackageImport !== 'named') continue;

    const name = rnohMetadata.harMappings[0].ohPackageName;
    const defaultImport = `import ${rnohMetadata.etsPackageClassName} from '${name}';`;
    const namedImport = `import { ${rnohMetadata.etsPackageClassName} } from '${name}';`;
    namedImports.set(defaultImport, namedImport);
  }
  for (const [defaultImport, namedImport] of namedImports) {
    replacements.push([defaultImport, namedImport, 'RNOH named package import']);
  }

  let content = source;
  for (const [generatedFragment, replacement, name] of replacements) {
    const fragments = content.split(generatedFragment);
    if (fragments.length !== 2) {
      throw new HarmonyAutolinkingError(
        'GENERATED_ARTIFACT_SET_MISMATCH',
        `RNOH 0.84.1 generated factory did not contain exactly one expected ${name}.`,
        { stage: 'rnoh-patch', details: { fragment: name } }
      );
    }
    content = `${fragments[0]}${replacement}${fragments[1]}`;
  }

  return content;
}

async function patchEtsFactoryAsync(artifact, descriptors) {
  const content = patchEtsFactorySource(artifact.content, descriptors);

  if (content !== artifact.content) {
    await fs.promises.writeFile(artifact.path, content);
    artifact.content = content;
  }
}

function patchCmakeSource(source, descriptors) {
  let content = source;
  const guardedBlocks = new Map();

  for (const descriptor of descriptors.filter(item => item.rnoh.harPaths.length > 0)) {
    const metadata = resolveRnohMetadata(descriptor);
    const generated = `    add_subdirectory("\${OH_MODULES_DIR}/${descriptor.packageName}/src/main/cpp" ./${metadata.cmakeLibraryTargetName})`;
    const guarded = [
      `    if(NOT TARGET ${metadata.cmakeLibraryTargetName})`,
      `      add_subdirectory("\${OH_MODULES_DIR}/${descriptor.packageName}/src/main/cpp" ./${metadata.cmakeLibraryTargetName})`,
      '    endif()',
    ].join('\n');
    guardedBlocks.set(metadata.cmakeLibraryTargetName, guarded);
    const fragments = content.split(generated);
    if (fragments.length !== 2) {
      throw new HarmonyAutolinkingError(
        'GENERATED_ARTIFACT_SET_MISMATCH',
        `RNOH 0.84.1 generated CMake did not contain exactly one add_subdirectory for ${descriptor.packageName}.`,
        { stage: 'rnoh-patch', packageName: descriptor.packageName }
      );
    }
    content = `${fragments[0]}${guarded}${fragments[1]}`;
  }

  // Core consumes the dependency's public CMake target. Configure Worklets
  // first instead of making Core compile a private copy of dependency sources.
  const coreBlock = guardedBlocks.get('expo_harmony__expo_modules_core');
  const workletsBlock = guardedBlocks.get('rnoh_worklets');
  if (coreBlock && workletsBlock) {
    const coreIndex = content.indexOf(coreBlock);
    const workletsIndex = content.indexOf(workletsBlock);
    if (coreIndex >= 0 && workletsIndex > coreIndex) {
      content = content.replace(`${workletsBlock}\n`, '');
      const updatedCoreIndex = content.indexOf(coreBlock);
      content = `${content.slice(0, updatedCoreIndex)}${workletsBlock}\n${content.slice(updatedCoreIndex)}`;
    }

    // The Harmony Worklets package cannot infer the Hermes ABI selected by the
    // application. Forward the real build setting after its public target has
    // been configured; Core must not hard-code or override dependency sources.
    const configuredWorkletsBlock = [
      workletsBlock,
      // Worklets 1.0.0 declares implementation files as PUBLIC sources. Do not
      // make every linked consumer compile the dependency implementation again.
      '    set_property(TARGET rnoh_worklets PROPERTY INTERFACE_SOURCES "")',
      '    set(EXPO_RNOH_PACKAGE_JSON_PATH "${OH_MODULES_DIR}/@rnoh/react-native-openharmony/oh-package.json5")',
      '    if(NOT EXISTS "${EXPO_RNOH_PACKAGE_JSON_PATH}")',
      '      message(FATAL_ERROR "Unable to locate the RNOH package manifest")',
      '    endif()',
      '    file(READ "${EXPO_RNOH_PACKAGE_JSON_PATH}" EXPO_RNOH_PACKAGE_JSON)',
      '    string(JSON EXPO_RNOH_VERSION GET "${EXPO_RNOH_PACKAGE_JSON}" version)',
      '    if(NOT EXPO_RNOH_VERSION MATCHES "^0\\\\.([0-9]+)\\\\.")',
      '      message(FATAL_ERROR "Unable to derive the React Native minor from RNOH ${EXPO_RNOH_VERSION}")',
      '    endif()',
      '    set(EXPO_RNOH_MINOR_VERSION "${CMAKE_MATCH_1}")',
      '    target_compile_definitions(rnoh_worklets PUBLIC REACT_NATIVE_MINOR_VERSION=${EXPO_RNOH_MINOR_VERSION})',
      '    if(DEFINED ENV{HERMES_V1_ENABLED} AND "$ENV{HERMES_V1_ENABLED}" STREQUAL "true")',
      '      target_compile_definitions(rnoh_worklets PRIVATE HERMES_V1_ENABLED=1)',
      '    endif()',
      '    if(EXPO_RNOH_MINOR_VERSION GREATER_EQUAL 84)',
      '      set(EXPO_WORKLETS_MODULE_SOURCE "${OH_MODULES_DIR}/@react-native-ohos/react-native-worklets/src/main/cpp/WorkletsModule.cpp")',
      '      file(READ "${EXPO_WORKLETS_MODULE_SOURCE}" EXPO_WORKLETS_MODULE_CONTENT)',
      '      set(EXPO_WORKLETS_OLD_FRAGMENT "std::shared_ptr<const BigStringBuffer> script = nullptr;")',
      '      string(FIND "${EXPO_WORKLETS_MODULE_CONTENT}" "${EXPO_WORKLETS_OLD_FRAGMENT}" EXPO_WORKLETS_FRAGMENT_OFFSET)',
      '      if(EXPO_WORKLETS_FRAGMENT_OFFSET EQUAL -1)',
      '        message(FATAL_ERROR "Worklets Harmony wrapper no longer matches the guarded RN 0.84 compatibility patch")',
      '      endif()',
      '      string(REPLACE "${EXPO_WORKLETS_OLD_FRAGMENT}" "std::shared_ptr<const JSBigStringBuffer> script = nullptr;" EXPO_WORKLETS_MODULE_CONTENT "${EXPO_WORKLETS_MODULE_CONTENT}")',
      '      set(EXPO_WORKLETS_OLD_FRAGMENT "auto jsBigString = std::make_unique<JSBigBufferString>(len);")',
      '      string(FIND "${EXPO_WORKLETS_MODULE_CONTENT}" "${EXPO_WORKLETS_OLD_FRAGMENT}" EXPO_WORKLETS_FRAGMENT_OFFSET)',
      '      if(EXPO_WORKLETS_FRAGMENT_OFFSET EQUAL -1)',
      '        message(FATAL_ERROR "Worklets Harmony bundle allocation no longer matches the guarded RN 0.84 compatibility patch")',
      '      endif()',
      '      string(REPLACE "${EXPO_WORKLETS_OLD_FRAGMENT}" "auto jsBigString = std::make_shared<JSBigBufferString>(len);" EXPO_WORKLETS_MODULE_CONTENT "${EXPO_WORKLETS_MODULE_CONTENT}")',
      '      set(EXPO_WORKLETS_OLD_FRAGMENT "char *buffer = jsBigString->data();")',
      '      string(FIND "${EXPO_WORKLETS_MODULE_CONTENT}" "${EXPO_WORKLETS_OLD_FRAGMENT}" EXPO_WORKLETS_FRAGMENT_OFFSET)',
      '      if(EXPO_WORKLETS_FRAGMENT_OFFSET EQUAL -1)',
      '        message(FATAL_ERROR "Worklets Harmony bundle buffer access no longer matches the guarded RN 0.84 compatibility patch")',
      '      endif()',
      '      string(REPLACE "${EXPO_WORKLETS_OLD_FRAGMENT}" "char *buffer = jsBigString->mutableData();" EXPO_WORKLETS_MODULE_CONTENT "${EXPO_WORKLETS_MODULE_CONTENT}")',
      '      set(EXPO_WORKLETS_OLD_FRAGMENT "script = std::make_shared<BigStringBuffer>(std::move(jsBigString));")',
      '      string(FIND "${EXPO_WORKLETS_MODULE_CONTENT}" "${EXPO_WORKLETS_OLD_FRAGMENT}" EXPO_WORKLETS_FRAGMENT_OFFSET)',
      '      if(EXPO_WORKLETS_FRAGMENT_OFFSET EQUAL -1)',
      '        message(FATAL_ERROR "Worklets Harmony bundle assignment no longer matches the guarded RN 0.84 compatibility patch")',
      '      endif()',
      '      string(REPLACE "${EXPO_WORKLETS_OLD_FRAGMENT}" "script = std::move(jsBigString);" EXPO_WORKLETS_MODULE_CONTENT "${EXPO_WORKLETS_MODULE_CONTENT}")',
      '      set(EXPO_WORKLETS_PATCH_DIR "${CMAKE_CURRENT_BINARY_DIR}/expo_worklets_compat")',
      '      file(MAKE_DIRECTORY "${EXPO_WORKLETS_PATCH_DIR}")',
      '      set(EXPO_WORKLETS_PATCHED_MODULE "${EXPO_WORKLETS_PATCH_DIR}/WorkletsModule.cpp")',
      '      file(WRITE "${EXPO_WORKLETS_PATCHED_MODULE}" "${EXPO_WORKLETS_MODULE_CONTENT}")',
      '      get_target_property(EXPO_WORKLETS_SOURCES rnoh_worklets SOURCES)',
      '      set(EXPO_WORKLETS_FILTERED_SOURCES)',
      '      foreach(EXPO_WORKLETS_SOURCE IN LISTS EXPO_WORKLETS_SOURCES)',
      '        if(NOT EXPO_WORKLETS_SOURCE MATCHES "(^|/)WorkletsModule\\\\.cpp$")',
      '          list(APPEND EXPO_WORKLETS_FILTERED_SOURCES "${EXPO_WORKLETS_SOURCE}")',
      '        endif()',
      '      endforeach()',
      '      set_property(TARGET rnoh_worklets PROPERTY SOURCES ${EXPO_WORKLETS_FILTERED_SOURCES})',
      '      target_sources(rnoh_worklets PRIVATE "${EXPO_WORKLETS_PATCHED_MODULE}")',
      '    endif()',
    ].join('\n');
    content = content.replace(workletsBlock, configuredWorkletsBlock);
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

function patchOhpmManifest(artifact, descriptors, buildType, harmonyProjectPath) {
  artifact.content = canonicalizeOhpmManifest(
    artifact.content,
    createManifest(descriptors, { buildType }),
    {
      errorCode: 'RNOH_LINK_FAILED',
      harmonyProjectPath,
      stage: 'rnoh-patch',
    }
  ).source;
}

async function linkRnohAsync(linkOptions) {
  const executable = await resolveCliAsync({
    ...linkOptions,
    nodeModulesPath: linkOptions.commandNodeModulesPath || linkOptions.nodeModulesPath,
  });

  const spawn = {
    cwd: linkOptions.stageProjectRoot,
    env: linkOptions.env ? { ...process.env, ...linkOptions.env } : process.env,
    outputLimit: linkOptions.outputLimit,
    timeoutMs: linkOptions.timeoutMs,
  };

  let result;
  try {
    result = await spawnBoundedAsync(executable, buildLinkCommandArgs({
      harmonyProjectPath: linkOptions.stageHarmonyProjectPath,
      nodeModulesPath: linkOptions.nodeModulesPath,
      include: linkOptions.include,
      exclude: linkOptions.exclude,
    }), spawn);
  } catch (cause) {
    throw new HarmonyAutolinkingError('RNOH_LINK_FAILED', 'Unable to execute React Native link-harmony.', { cause, stage: 'rnoh-link' });
  }

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
    artifacts = await readGeneratedArtifactsAsync(
      linkOptions.stageHarmonyProjectPath,
      linkOptions.stageProjectRoot
    );
  } catch (error) {
    const roots = [linkOptions.temporaryRoot, linkOptions.stageProjectRoot, linkOptions.projectRoot];
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

  if (linkOptions.modules) {
    try {
      await patchCmakeAsync(artifacts.cmake, linkOptions.modules);
      await patchEtsFactoryAsync(artifacts.etsFactory, linkOptions.modules);
      patchOhpmManifest(
        artifacts.ohPackage,
        linkOptions.modules,
        linkOptions.buildType,
        linkOptions.harmonyProjectPath
      );
      await fs.promises.writeFile(artifacts.ohPackage.path, artifacts.ohPackage.content);
    } catch (error) {
      const roots = [linkOptions.temporaryRoot, linkOptions.stageProjectRoot, linkOptions.projectRoot];
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

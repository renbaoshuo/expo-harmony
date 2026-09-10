import fs from 'node:fs';
import path from 'node:path';
import { resolveHarmonyCommand } from '@expo-harmony/expo-modules-autolinking/tool-command';

import {
  readManifestIfPresentAsync,
  resolveHarmonyBuildPath,
  type HarmonyBuildDescriptor,
} from '@expo-harmony/prebuild-config/internal';

import { HarmonyCliError } from './errors';

export interface HarmonyTool {
  args: string[];
  command: string;
  source: 'deveco' | 'override' | 'path';
}

export interface HarmonyToolchain {
  hdc: HarmonyTool;
  hvigor: HarmonyTool;
  ohpm: HarmonyTool;
  sdkHome: string | null;
  toolsRoot: string | null;
}

export interface HarmonyBuildPlan {
  abilityName: string;
  buildMode: 'debug' | 'release';
  bundleName: string;
  expectedHap: string;
  exportPaths: HarmonyBuildDescriptor['export'];
  harmonyRoot: string;
  hvigorArgs: string[];
  moduleName: string;
  moduleRoot: string;
  nativeCache: HarmonyBuildDescriptor['nativeCache'];
  nativeInputs: HarmonyBuildDescriptor['nativeInputs'];
  projectFiles: HarmonyBuildDescriptor['projectFiles'];
  productName: string;
  targetName: string;
}

function existingFile(candidates: string[]): string | null {
  return candidates.find(candidate => fs.existsSync(candidate)) || null;
}

const RequiredSdkComponents = Object.freeze([
  'default/sdk-pkg.json',
  'default/hms/ets/uni-package.json',
  'default/hms/native/uni-package.json',
  'default/hms/toolchains/uni-package.json',
  'default/openharmony/ets/oh-uni-package.json',
  'default/openharmony/native/oh-uni-package.json',
  'default/openharmony/toolchains/oh-uni-package.json',
]);

function sdkRootsNear(seed) {
  const roots = [];
  let cursor = path.resolve(seed);

  for (let depth = 0; depth < 6; depth += 1) {
    const name = path.basename(cursor).toLowerCase();
    if (name === 'default' && path.basename(path.dirname(cursor)).toLowerCase() === 'sdk') {
      roots.push(path.dirname(cursor));
    }
    if (name === 'sdk') roots.push(cursor);
    roots.push(path.join(cursor, 'sdk'));

    const parent = path.dirname(cursor);
    if (parent === cursor) break;
    cursor = parent;
  }

  return roots;
}

function resolveHarmonySdkRoot(env, platform) {
  const seeds = [
    env.DEVECO_SDK_HOME,
    env.HARMONY_HOME,
    env.OHOS_SDK_HOME,
    env.HARMONY_HVIGORW,
    env.HARMONY_OHPM,
    env.HARMONY_NODE,
    ...(env.PATH || '').split(path.delimiter).filter(Boolean),
    ...(platform === 'darwin' ? ['/Applications/DevEco-Studio.app/Contents'] : []),
  ].filter(Boolean);
  const candidates = [...new Set(seeds.flatMap(sdkRootsNear))];

  return candidates.find(root => RequiredSdkComponents.every(
    relative => fs.existsSync(path.join(root, ...relative.split('/')))
  )) || null;
}

function devEcoInstallRoots(sdkHome) {
  const ancestors = [sdkHome, path.dirname(sdkHome), path.dirname(path.dirname(sdkHome))];
  const sdkDirectory = ancestors.find(candidate => path.basename(candidate).toLowerCase() === 'sdk');
  const roots = [
    sdkDirectory && path.dirname(sdkDirectory),
    path.dirname(sdkHome),
    path.dirname(path.dirname(sdkHome)),
  ].filter(Boolean);

  return [...new Set(roots)];
}

function devEcoLayouts(sdkHome) {
  return devEcoInstallRoots(sdkHome).flatMap(root => [
    {
      nodeRoot: path.join(root, 'tools', 'node'),
      toolsRoot: path.join(root, 'tools'),
    },
    {
      nodeRoot: path.join(root, 'tool', 'node'),
      toolsRoot: root,
    },
  ]);
}

function devEcoNode(layout, platform, env) {
  if (env.HARMONY_NODE) return { command: env.HARMONY_NODE, source: 'override' };

  const executable = platform === 'win32' ? 'node.exe' : 'node';
  const command = existingFile([
    path.join(layout.nodeRoot, 'bin', executable),
    path.join(layout.nodeRoot, executable),
  ]);

  return command ? { command, source: 'deveco' } : null;
}

function resolveHarmonyToolchain(): HarmonyToolchain {
  const env = process.env;
  const platform = process.platform;

  // Hvigor expects the SDK root containing default/, not default/ itself.
  // Reject metadata-only candidates so doctor cannot claim an SDK is
  // buildable without its HMS, OpenHarmony, native, ETS, and toolchain parts.
  const sdkHome = resolveHarmonySdkRoot(env, platform);
  const layouts = sdkHome ? devEcoLayouts(sdkHome) : [];

  let ohpm: HarmonyTool;
  if (env.HARMONY_OHPM) {
    ohpm = { ...resolveHarmonyCommand('ohpm', [], env), source: 'override' };
  } else {
    const entry = layouts.map(layout => ({
      node: devEcoNode(layout, platform, { ...env, HARMONY_NODE: env.HARMONY_OHPM_NODE || env.HARMONY_NODE }),
      script: path.join(layout.toolsRoot, 'ohpm', 'bin', 'pm-cli.js'),
    })).find(candidate => candidate.node && fs.existsSync(candidate.script));
    const command = existingFile(layouts.map(layout => path.join(
      layout.toolsRoot,
      'ohpm',
      'bin',
      platform === 'win32' ? 'ohpm.bat' : 'ohpm'
    )));

    ohpm = entry
      ? { args: [entry.script], command: entry.node.command, source: 'deveco' }
      : command
        ? { args: [], command, source: 'deveco' }
        : { args: [], command: platform === 'win32' ? 'ohpm.bat' : 'ohpm', source: 'path' };
  }

  let hvigor: HarmonyTool;
  if (env.HARMONY_HVIGORW) {
    hvigor = { ...resolveHarmonyCommand('hvigorw', [], env), source: 'override' };
  } else {
    const entry = layouts.map(layout => ({
      node: devEcoNode(layout, platform, { ...env, HARMONY_NODE: env.HARMONY_HVIGOR_NODE || env.HARMONY_NODE }),
      script: path.join(layout.toolsRoot, 'hvigor', 'bin', 'hvigorw.js'),
    })).find(candidate => candidate.node && fs.existsSync(candidate.script));

    hvigor = entry
      ? { args: [entry.script], command: entry.node.command, source: 'deveco' }
      : { args: [], command: platform === 'win32' ? 'hvigorw.bat' : 'hvigorw', source: 'path' };
  }

  const toolsRoot = layouts.find(layout => (
    hvigor.args[0]?.startsWith(`${layout.toolsRoot}${path.sep}`)
    || ohpm.args[0]?.startsWith(`${layout.toolsRoot}${path.sep}`)
    || ohpm.command.startsWith(`${layout.toolsRoot}${path.sep}`)
  ))?.toolsRoot || null;

  let hdc: HarmonyTool;
  if (env.HARMONY_HDC) {
    hdc = { args: [], command: env.HARMONY_HDC, source: 'override' };
  } else {
    const executable = platform === 'win32' ? 'hdc.exe' : 'hdc';
    const sdkHdc = sdkHome && existingFile([
      path.join(sdkHome, 'default', 'openharmony', 'toolchains', executable),
      path.join(sdkHome, 'default', 'hms', 'toolchains', executable),
    ]);
    hdc = sdkHdc
      ? { args: [], command: sdkHdc, source: 'deveco' }
      : { args: [], command: executable, source: 'path' };
  }

  return { hdc, hvigor, ohpm, sdkHome, toolsRoot };
}

function createHarmonyToolchainEnv(toolchain = resolveHarmonyToolchain()): NodeJS.ProcessEnv {
  return {
    ...process.env,
    HARMONY_OHPM: toolchain.ohpm.args[0] || toolchain.ohpm.command,
    HARMONY_OHPM_NODE: toolchain.ohpm.args.length > 0 ? toolchain.ohpm.command : undefined,
    // Script-based tools must retain both their script and Node executable.
    HARMONY_HVIGORW: toolchain.hvigor.args[0] || toolchain.hvigor.command,
    HARMONY_HVIGOR_NODE: toolchain.hvigor.args.length > 0 ? toolchain.hvigor.command : undefined,
    ...(toolchain.hvigor.args.length > 0
      ? { HARMONY_NODE: toolchain.hvigor.command }
      : toolchain.ohpm.args.length > 0 ? { HARMONY_NODE: toolchain.ohpm.command } : {}),
    ...(toolchain.sdkHome && !process.env.DEVECO_SDK_HOME
      ? { DEVECO_SDK_HOME: toolchain.sdkHome }
      : {}),
  };
}

function resolveHarmonyEmulator(toolchain: HarmonyToolchain): HarmonyTool {
  if (process.env.HARMONY_EMULATOR) {
    return { args: [], command: process.env.HARMONY_EMULATOR, source: 'override' };
  }

  const executable = process.platform === 'win32' ? 'Emulator.exe' : 'Emulator';
  const roots = [
    toolchain.toolsRoot,
    ...(toolchain.sdkHome ? devEcoLayouts(toolchain.sdkHome).map(layout => layout.toolsRoot) : []),
    ...(process.platform === 'darwin' ? ['/Applications/DevEco-Studio.app/Contents/tools'] : []),
  ].filter(Boolean);
  const command = existingFile(roots.map(root => path.join(root, 'emulator', executable)));

  return command
    ? { args: [], command, source: 'deveco' }
    : { args: [], command: executable, source: 'path' };
}

function createHarmonyBuildPlan(
  projectRoot: string,
  build: HarmonyBuildDescriptor,
  mode: 'debug' | 'release'
): HarmonyBuildPlan {
  const resolve = relative => resolveHarmonyBuildPath(projectRoot, relative);
  const variant = build.variants[mode];

  return {
    abilityName: build.identity.abilityName,
    buildMode: mode,
    bundleName: build.identity.bundleName,
    expectedHap: resolve(variant.expectedHap),
    exportPaths: Object.fromEntries(
      Object.entries(build.export).map(([name, relative]) => [name, resolve(relative)])
    ) as HarmonyBuildPlan['exportPaths'],
    harmonyRoot: resolve(build.harmonyRoot),
    hvigorArgs: [...variant.hvigorArgs],
    moduleName: build.identity.moduleName,
    moduleRoot: resolve(build.moduleRoot),
    nativeCache: {
      invalidationRoots: build.nativeCache.invalidationRoots.map(resolve),
      stateFile: resolve(build.nativeCache.stateFile),
    },
    nativeInputs: {
      lockfile: resolve(build.nativeInputs.lockfile),
      manifest: resolve(build.nativeInputs.manifest),
    },
    productName: build.identity.productName,
    projectFiles: Object.fromEntries(
      Object.entries(build.projectFiles).map(([name, relative]) => [name, resolve(relative)])
    ) as HarmonyBuildPlan['projectFiles'],
    targetName: build.identity.targetName,
  };
}

async function resolveHarmonyBuildPlanIfPresentAsync(
  projectRoot: string,
  options: { buildMode?: 'debug' | 'release' } = {}
): Promise<HarmonyBuildPlan | null> {
  const mode = options.buildMode || 'debug';
  if (!['debug', 'release'].includes(mode)) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', `Harmony buildMode must be debug or release, received: ${mode}`, { operation: 'resolve-build' });
  }

  let manifest;

  try {
    manifest = await readManifestIfPresentAsync(projectRoot);
  } catch (cause) {
    throw new HarmonyCliError(
      cause.code || 'ERR_HARMONY_TEMPLATE_INVALID',
      `Cannot read the generated Harmony build descriptor: ${cause.message}`,
      { cause, operation: 'resolve-build' }
    );
  }

  if (!manifest) return null;

  return createHarmonyBuildPlan(projectRoot, manifest.build, mode);
}

async function resolveHarmonyBuildPlanAsync(
  projectRoot: string,
  options: { buildMode?: 'debug' | 'release' } = {}
): Promise<HarmonyBuildPlan> {
  const plan = await resolveHarmonyBuildPlanIfPresentAsync(projectRoot, options);
  if (!plan) {
    throw new HarmonyCliError(
      'ERR_HARMONY_MANIFEST_DRIFT',
      'Cannot read the generated Harmony build descriptor because the CNG manifest is missing.',
      { operation: 'resolve-build' }
    );
  }

  return plan;
}

export {
  createHarmonyToolchainEnv,
  resolveHarmonyBuildPlanAsync,
  resolveHarmonyBuildPlanIfPresentAsync,
  resolveHarmonyEmulator,
  resolveHarmonyToolchain,
};

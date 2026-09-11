import fs from 'node:fs';
import path from 'node:path';
import { resolveHarmonyCommand } from '@expo-harmony/expo-modules-autolinking/tool-command';

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

function sdkRootsNear(seed: string): string[] {
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

function resolveHarmonySdkRoot(env: NodeJS.ProcessEnv, platform: NodeJS.Platform): string | null {
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

function devEcoInstallRoots(sdkHome: string): string[] {
  const ancestors = [sdkHome, path.dirname(sdkHome), path.dirname(path.dirname(sdkHome))];
  const sdkDirectory = ancestors.find(candidate => path.basename(candidate).toLowerCase() === 'sdk');
  const roots = [
    sdkDirectory && path.dirname(sdkDirectory),
    path.dirname(sdkHome),
    path.dirname(path.dirname(sdkHome)),
  ].filter(Boolean);

  return [...new Set(roots)];
}

function devEcoLayouts(sdkHome: string) {
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

function devEcoNode(
  layout: { nodeRoot: string },
  platform: NodeJS.Platform,
  env: NodeJS.ProcessEnv
): Pick<HarmonyTool, 'command' | 'source'> | null {
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

  // Hvigor needs the complete SDK root containing default/, not default/ itself.
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

export { createHarmonyToolchainEnv, resolveHarmonyEmulator, resolveHarmonyToolchain };

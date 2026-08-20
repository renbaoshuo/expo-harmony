import fs from 'node:fs';
import path from 'node:path';

import { getConfig } from '@expo/config';
import { normalizeHarmonyConfig } from '@expo-harmony/prebuild-config';
import JSON5 from 'json5';

import { HarmonyCliError } from './errors';
import { isInside } from './path';

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
  buildMode: 'debug' | 'release';
  expectedHap: string;
  harmonyRoot: string;
  hvigorArgs: string[];
  moduleName: string;
  moduleRoot: string;
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
    ohpm = { args: [], command: env.HARMONY_OHPM, source: 'override' };
  } else {
    const devEcoOhpm = existingFile(layouts.map(layout => path.join(
      layout.toolsRoot,
      'ohpm',
      'bin',
      platform === 'win32' ? 'ohpm.bat' : 'ohpm'
    )));
    ohpm = devEcoOhpm
      ? { args: [], command: devEcoOhpm, source: 'deveco' }
      : { args: [], command: platform === 'win32' ? 'ohpm.bat' : 'ohpm', source: 'path' };
  }

  let hvigor: HarmonyTool;
  if (env.HARMONY_HVIGORW) {
    if (/\.(?:c|m)?js$/iu.test(env.HARMONY_HVIGORW)) {
      hvigor = {
        args: [env.HARMONY_HVIGORW],
        command: env.HARMONY_NODE || process.execPath,
        source: 'override',
      };
    } else {
      hvigor = { args: [], command: env.HARMONY_HVIGORW, source: 'override' };
    }
  } else {
    const devEcoHvigor = layouts.map(layout => ({
      layout,
      node: devEcoNode(layout, platform, env),
      script: path.join(layout.toolsRoot, 'hvigor', 'bin', 'hvigorw.js'),
    })).find(candidate => candidate.node && fs.existsSync(candidate.script));
    hvigor = devEcoHvigor
      ? { args: [devEcoHvigor.script], command: devEcoHvigor.node.command, source: 'deveco' }
      : { args: [], command: platform === 'win32' ? 'hvigorw.bat' : 'hvigorw', source: 'path' };
  }

  const toolsRoot = layouts.find(layout => (
    hvigor.args[0]?.startsWith(`${layout.toolsRoot}${path.sep}`)
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

async function resolveHarmonyBuildPlanAsync(
  projectRoot: string,
  options: { buildMode?: 'debug' | 'release' } = {}
): Promise<HarmonyBuildPlan> {
  const buildMode = options.buildMode || 'debug';
  if (!['debug', 'release'].includes(buildMode)) {
    throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', `Harmony buildMode must be debug or release, received: ${buildMode}`, { operation: 'resolve-build' });
  }

  const config = getConfig(projectRoot, {
    isModdedConfig: true,
    skipSDKVersionRequirement: true,
  }).exp;
  const normalized = normalizeHarmonyConfig(config);
  const harmonyRoot = path.join(projectRoot, 'harmony');
  const profileFile = path.join(harmonyRoot, 'build-profile.json5');
  let profile;

  try {
    profile = JSON5.parse(await fs.promises.readFile(profileFile, 'utf8'));
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      `Cannot read generated Harmony build profile: ${profileFile}`,
      { cause, operation: 'resolve-build' }
    );
  }

  const product = (Array.isArray(profile?.app?.products) ? profile.app.products : [])
    .find(item => item?.name === normalized.productName);
  const module = (Array.isArray(profile?.modules) ? profile.modules : [])
    .find(item => item?.name === normalized.moduleName);
  if (!product || !module) {
    throw new HarmonyCliError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      `Generated build profile is missing product ${normalized.productName} or module ${normalized.moduleName}.`,
      { operation: 'resolve-build' }
    );
  }

  const targetName = 'default';
  const target = (Array.isArray(module.targets) ? module.targets : [])
    .find(item => item?.name === targetName);
  if (!target || !Array.isArray(target.applyToProducts)
    || !target.applyToProducts.includes(normalized.productName)) {
    throw new HarmonyCliError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      `Harmony module ${normalized.moduleName} is not configured for product ${normalized.productName}.`,
      { operation: 'resolve-build' }
    );
  }

  const moduleRoot = path.resolve(harmonyRoot, module.srcPath || '');
  if (!isInside(harmonyRoot, moduleRoot) || moduleRoot === harmonyRoot) {
    throw new HarmonyCliError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      `Harmony module ${normalized.moduleName} has an unsafe srcPath.`,
      { operation: 'resolve-build' }
    );
  }

  const signingSuffix = typeof product.signingConfig === 'string' && product.signingConfig
    ? 'signed'
    : 'unsigned';
  const expectedHap = path.join(
    moduleRoot,
    'build',
    targetName,
    'outputs',
    targetName,
    `${normalized.moduleName}-${targetName}-${signingSuffix}.hap`
  );

  return {
    buildMode,
    expectedHap,
    harmonyRoot,
    hvigorArgs: [
      '--mode', 'module',
      '-p', `module=${normalized.moduleName}@${targetName}`,
      '-p', `product=${normalized.productName}`,
      '-p', `buildMode=${buildMode}`,
      '--no-daemon',
      'assembleHap',
    ],
    moduleName: normalized.moduleName,
    moduleRoot,
    productName: normalized.productName,
    targetName,
  };
}

export { resolveHarmonyBuildPlanAsync, resolveHarmonyToolchain };

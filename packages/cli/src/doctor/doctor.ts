/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { normalizeHarmonyConfig } from '@expo-harmony/config-plugins';
import { getHarmonyProjectConfig, type EnvMode } from '@expo-harmony/expo__config/internal/project-config';
import { resolveRnohCliPackageJsonPath, verifyModulesAsync } from '@expo-harmony/expo-modules-autolinking';
import { isRnohAutolinkingDisabled, validateHarmonySigningConfigFile } from '@expo-harmony/prebuild-config/internal';

import { spawnAsync } from '../process';
import { resolveTimeoutMs } from '../timeout';
import { withHarmonyProjectLockAsync } from '../projectLock';
import { resolveHarmonyBuildPlanIfPresentAsync } from '../native/project';
import { resolveHarmonyToolchain, type HarmonyTool } from '../native/toolchain';
import { ProjectPackages, RequiredProjectPackages } from '../upstream';
import { isBareHarmonyProject } from '../native/bare';
import { loadHarmonyMetroMetadataAsync } from '../expo';
import { resolveMetroRuntimeRoot } from '../runtime/config';

export interface DoctorCheck {
  details?: unknown;
  id: string;
  message: string;
  status: 'error' | 'pass' | 'warn';
}

export interface DoctorResult {
  checks: DoctorCheck[];
  ok: boolean;
  projectRoot: string;
}

interface DoctorOptions {
  envMode?: EnvMode;
  requireBuildTools?: boolean;
  requireDeviceTools?: boolean;
  validateGeneratedProject?: boolean;
  validateModules?: boolean;
}

function hasPlugin(plugins, name) {
  return (plugins || []).some(plugin => (Array.isArray(plugin) ? plugin[0] : plugin) === name);
}

function check(id: string, status: DoctorCheck['status'], message: string, details?: unknown): DoctorCheck {
  return { id, status, message, ...(details ? { details } : {}) };
}

function canResolvePackage(root, name) {
  const require = createRequire(path.join(root, 'package.json'));

  try {
    require.resolve(`${name}/package.json`);
    return true;
  } catch {
    try {
      require.resolve(name);
      return true;
    } catch {
      return false;
    }
  }
}

async function validateMetroConfigAsync(root: string, mode?: EnvMode) {
  const { platform, extensions, runtime } = await loadHarmonyMetroMetadataAsync(root, mode);
  if (!platform && !extensions) {
    throw new Error('The resolved Metro config must register the harmony platform or platform extensions.');
  }

  return {
    extensions,
    runtimePackage: runtime?.harmonyPackage ?? ProjectPackages.rnohRuntime,
    runtimeRoot: runtime?.harmonyPackageRoot,
  };
}

async function doctorUnlockedAsync(root: string, options: DoctorOptions = {}): Promise<DoctorResult> {
  const checks: DoctorCheck[] = [];
  const unavailable = options.requireBuildTools ? 'error' : 'warn';
  let config;
  const bare = isBareHarmonyProject(root);

  try {
    if (bare) {
      const plan = await resolveHarmonyBuildPlanIfPresentAsync(root);
      checks.push(check('native-config', 'pass', `Bare Harmony project: ${plan.bundleName} / ${plan.moduleName}. Native files own the configuration.`));
    } else {
      config = getHarmonyProjectConfig(root, {
        isModdedConfig: true,
        skipSDKVersionRequirement: true,
      }, options.envMode).exp;
      normalizeHarmonyConfig(config);
      checks.push(check('app-config', 'pass', 'Harmony app config is valid.'));
    }
  } catch (error) {
    checks.push(check(bare ? 'native-config' : 'app-config', 'error', error.message, { code: error.code || 'ERR_HARMONY_CONFIG_INVALID' }));
  }

  if (config) {
    checks.push(hasPlugin(config.plugins, '@expo-harmony/prebuild-config')
      ? check('config-plugin', 'pass', '@expo-harmony/prebuild-config is registered.')
      : check('config-plugin', 'warn', 'Harmony prebuild mods must be applied directly or through another config plugin.'));

    const harmony = (config as typeof config & {
      harmony?: { signingConfigFile?: string };
    }).harmony;

    if (harmony?.signingConfigFile) {
      try {
        const signing = await validateHarmonySigningConfigFile(root, harmony.signingConfigFile);
        checks.push(check('signing', 'pass', `Harmony signing config ${signing.name} is valid.`));
      } catch (error) {
        checks.push(check('signing', 'error', error.message, { code: error.code || 'ERR_HARMONY_SIGNING_INVALID' }));
      }
    } else {
      checks.push(check('signing', 'warn', 'No external signing config is set; unsigned generation remains available.'));
    }
  }

  let harmonyPlatformExtensions = false;
  let runtimePackage: string = ProjectPackages.rnohRuntime;
  let runtimeRoot: string | undefined;

  try {
    const metro = await validateMetroConfigAsync(root, options.envMode);
    harmonyPlatformExtensions = metro.extensions;
    runtimePackage = metro.runtimePackage;
    runtimeRoot = metro.runtimeRoot;
    checks.push(check('metro', 'pass', 'The resolved Metro config enables Harmony.'));
  } catch (error) {
    checks.push(check('metro', 'error', `Cannot load a Harmony-enabled Metro config: ${error.message}`, { code: error.code || 'ERR_HARMONY_METRO_CONFIG' }));
  }

  if (config) {
    const experiments = (config as typeof config & { experiments?: Record<string, unknown> }).experiments;
    const outOfTreePlatforms = experiments?.outOfTreePlatforms === true;

    if (outOfTreePlatforms && harmonyPlatformExtensions) {
      checks.push(check('out-of-tree', 'pass', 'harmony is registered through Expo\'s out-of-tree platform channel.'));
    } else if (!outOfTreePlatforms) {
      checks.push(check(
        'out-of-tree',
        'warn',
        'expo.experiments.outOfTreePlatforms is not enabled; Expo CLI drops harmony from its platform resolution (export options, dev server platform detection) without it.'
      ));
    } else {
      checks.push(check(
        'out-of-tree',
        'warn',
        'The Metro config does not declare unstable_platformExtensions for harmony; update @expo-harmony/metro-config to register the harmony extension chain.'
      ));
    }
  }

  const packages = RequiredProjectPackages.map(name => name === ProjectPackages.rnohRuntime ? runtimePackage : name);
  for (const name of packages) {
    let available = false;
    try {
      if (name === ProjectPackages.rnohCli) {
        available = fs.existsSync(resolveRnohCliPackageJsonPath());
      } else if (name === runtimePackage) {
        const directory = resolveMetroRuntimeRoot(root, {
          reactPackage: 'react', harmonyPackage: runtimePackage, harmonyPackageRoot: runtimeRoot,
        });
        available = fs.existsSync(path.join(directory, 'package.json'));
      } else {
        available = canResolvePackage(root, name);
      }
    } catch {
      // Package resolution failures become diagnostics below.
    }
    if (available) {
      checks.push(check(`package:${name}`, 'pass', `${name} is resolvable.`));
    } else {
      checks.push(check(`package:${name}`, 'error', `${name} is not resolvable from the app.`));
    }
  }

  if (options.validateModules !== false) {
    try {
      const result = await verifyModulesAsync({
        platform: 'harmony',
        projectRoot: root,
        ...(options.envMode === 'production' ? { buildType: 'release' } : {}),
      });
      const errors = result.diagnostics.filter(item => item.severity === 'error');
      const warnings = result.diagnostics.filter(item => item.severity === 'warning');

      if (errors.length > 0) {
        checks.push(check(
          'expo-modules',
          'error',
          `Harmony Expo Modules verification found ${errors.length} error(s). Run 'expo-harmony modules verify' for details.`,
          { diagnostics: result.diagnostics }
        ));
      } else if (warnings.length > 0) {
        checks.push(check(
          'expo-modules',
          'warn',
          `Verified ${result.modules.length} Harmony native module(s) with ${warnings.length} warning(s).`,
          { diagnostics: warnings }
        ));
      } else {
        checks.push(check('expo-modules', 'pass', `Verified ${result.modules.length} Harmony native module(s).`));
      }
    } catch (error) {
      checks.push(check(
        'expo-modules',
        'error',
        `Harmony Expo Modules verification failed: ${error.message}`,
        { code: error.code || 'ERR_HARMONY_AUTOLINKING_FAILED' }
      ));
    }
  }

  const toolchain = resolveHarmonyToolchain();
  let sdk;

  if (toolchain.sdkHome) {
    sdk = check('harmony-sdk', 'pass', `Complete Harmony SDK root was resolved at ${toolchain.sdkHome}.`);
  } else {
    sdk = check('harmony-sdk', 'warn', 'No SDK root was resolved by the CLI; Hvigor will resolve the configured SDK during the native build.');
  }

  checks.push(sdk);

  const tools: Array<[string, HarmonyTool, string[], DoctorCheck['status']]> = [
    ['ohpm', toolchain.ohpm, ['--version'], unavailable],
    ['hvigor-command', toolchain.hvigor, ['--version'], unavailable],
  ];
  if (options.requireDeviceTools !== false) {
    tools.unshift(['hdc', toolchain.hdc, ['-v'], unavailable]);
  }

  for (const [id, tool, args, status] of tools) {
    const command = [tool.command, ...tool.args].map(value => JSON.stringify(value)).join(' ');

    try {
      const result = await spawnAsync(tool.command, [...tool.args, ...args], {
        capture: true,
        cwd: root,
        operation: `doctor-${id}`,
        timeoutMs: resolveTimeoutMs('doctor', 10_000),
      });

      checks.push(result.code === 0 && !result.timedOut
        ? check(id, 'pass', `${command} is available through ${tool.source}.`)
        : check(id, status, `${command} is unavailable or unhealthy; HAP build cannot be verified.`));
    } catch {
      checks.push(check(id, status, `${command} is unavailable; generation remains available.`));
    }
  }

  if (options.validateGeneratedProject !== false) {
    try {
      const plan = await resolveHarmonyBuildPlanIfPresentAsync(root);
      if (plan && fs.existsSync(plan.harmonyRoot)) {
        if (!fs.existsSync(plan.projectFiles.rootHvigor)
          || !fs.existsSync(plan.projectFiles.moduleHvigor)) {
          checks.push(check('hvigor', 'error', 'Root and module Hvigor files are required.'));
        } else {
          const content = await fs.promises.readFile(plan.projectFiles.moduleHvigor, 'utf8');
          checks.push(isRnohAutolinkingDisabled(content)
            ? check('hvigor-autolinking', 'pass', 'RNOH duplicate autolinking is disabled.')
            : check('hvigor-autolinking', 'warn', 'Cannot confirm that duplicate RNOH autolinking is disabled from the module Hvigor source.'));
        }
      }
    } catch (error) {
      checks.push(check('harmony-project', 'error', error.message, { code: error.code || 'ERR_HARMONY_TEMPLATE_INVALID' }));
    }
  }

  return {
    checks,
    ok: checks.every(item => item.status !== 'error'),
    projectRoot: root,
  };
}

async function doctorAsync(root: string, options: DoctorOptions = {}): Promise<DoctorResult> {
  return withHarmonyProjectLockAsync(root, 'doctor', canonicalRoot => doctorUnlockedAsync(canonicalRoot, options));
}

function formatDoctor(result: DoctorResult): string {
  return result.checks.map((item) => {
    const symbol = item.status === 'pass' ? '✓' : item.status === 'warn' ? '!' : '✗';
    return `${symbol} [${item.status}] ${item.message}`;
  }).join('\n');
}

export { doctorAsync, formatDoctor };

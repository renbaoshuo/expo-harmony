import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { getConfig } from '@expo/config';
import { normalizeHarmonyConfig } from '@expo-harmony/config-plugins';
import { verifyModulesAsync } from '@expo-harmony/expo-modules-autolinking';
import { isRnohAutolinkingDisabled, validateHarmonySigningConfigFile } from '@expo-harmony/prebuild-config/internal';

import { spawnAsync } from '../process';
import { withHarmonyProjectLockAsync } from '../projectLock';
import { resolveHarmonyBuildPlanIfPresentAsync } from '../native/project';
import { resolveHarmonyToolchain, type HarmonyTool } from '../native/toolchain';
import { RequiredProjectPackages } from '../upstream';
import { isBareHarmonyProject } from '../native/bare';

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

async function validateMetroConfigAsync(root) {
  const require = createRequire(path.join(root, 'package.json'));
  let metro;

  try {
    metro = require('metro-config');
  } catch (cause) {
    throw new Error('Cannot load the project-local metro-config package.', { cause });
  }

  if (typeof metro.resolveConfig !== 'function') {
    const version = (() => {
      try {
        return require('metro-config/package.json').version;
      } catch {
        return 'unknown';
      }
    })();

    throw new Error(`metro-config ${version} does not expose resolveConfig().`);
  }

  const present = Object.hasOwn(process.env, 'EXPO_METRO_TARGET');
  const previous = process.env.EXPO_METRO_TARGET;
  let resolved;

  try {
    process.env.EXPO_METRO_TARGET = 'harmony';
    resolved = await metro.resolveConfig(undefined, root);
  } finally {
    if (present) process.env.EXPO_METRO_TARGET = previous;
    else delete process.env.EXPO_METRO_TARGET;
  }

  const config = resolved?.config;
  const platforms = config?.resolver?.platforms;
  const conditions = config?.resolver?.unstable_conditionsByPlatform?.harmony;

  if (!Array.isArray(platforms) || !platforms.includes('harmony')
    || !Array.isArray(conditions) || !conditions.includes('harmony')
    || typeof config?.resolver?.resolveRequest !== 'function') {
    throw new Error('The resolved Metro config must register the harmony platform, Harmony conditions, and a resolver.');
  }
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
      config = getConfig(root, {
        isModdedConfig: true,
        skipSDKVersionRequirement: true,
      }).exp;
      normalizeHarmonyConfig(config);
      checks.push(check('app-config', 'pass', 'Harmony app config is valid.'));
    }
  } catch (error) {
    checks.push(check(bare ? 'native-config' : 'app-config', 'error', error.message, { code: error.code || 'ERR_HARMONY_CONFIG_INVALID' }));
  }

  if (config) {
    checks.push(hasPlugin(config.plugins, '@expo-harmony/prebuild-config')
      ? check('config-plugin', 'pass', '@expo-harmony/prebuild-config is registered.')
      : check('config-plugin', 'error', 'Add @expo-harmony/prebuild-config to expo.plugins.'));

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

  try {
    await validateMetroConfigAsync(root);
    checks.push(check('metro', 'pass', 'The resolved Metro config enables Harmony.'));
  } catch (error) {
    checks.push(check('metro', 'error', `Cannot load a Harmony-enabled Metro config: ${error.message}`, { code: error.code || 'ERR_HARMONY_METRO_CONFIG' }));
  }

  for (const name of RequiredProjectPackages) {
    if (canResolvePackage(root, name)) {
      checks.push(check(`package:${name}`, 'pass', `${name} is resolvable.`));
    } else {
      checks.push(check(`package:${name}`, 'error', `${name} is not resolvable from the app.`));
    }
  }

  if (options.validateModules !== false) {
    try {
      const result = await verifyModulesAsync({ platform: 'harmony', projectRoot: root });
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
    sdk = check('harmony-sdk', unavailable, 'No complete Harmony SDK root with HMS and OpenHarmony components was found; generation works but HAP build cannot be verified.');
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
        timeoutMs: 10_000,
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
            : check('hvigor-autolinking', 'error', 'The module Hvigor file must disable duplicate RNOH autolinking.'));
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
  return withHarmonyProjectLockAsync(root, 'doctor', () => doctorUnlockedAsync(root, options));
}

function formatDoctor(result: DoctorResult): string {
  return result.checks.map((item) => {
    const symbol = item.status === 'pass' ? '✓' : item.status === 'warn' ? '!' : '✗';
    return `${symbol} [${item.status}] ${item.message}`;
  }).join('\n');
}

export { doctorAsync, formatDoctor };

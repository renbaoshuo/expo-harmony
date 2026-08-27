import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { getConfig } from '@expo/config';
import { normalizeHarmonyConfig } from '@expo-harmony/config-plugins';
import { isRnohAutolinkingDisabled } from '@expo-harmony/prebuild-config/native-project';
import { validateHarmonySigningConfigFile } from '@expo-harmony/prebuild-config/signing';

import { spawnAsync } from '../process';
import {
  resolveHarmonyBuildPlanIfPresentAsync,
  resolveHarmonyToolchain,
  type HarmonyTool,
} from '../tools';
import { RequiredProjectPackages } from '../upstream';

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
  validateGeneratedProject?: boolean;
}

function hasPlugin(plugins, packageName) {
  return (plugins || []).some(plugin => (Array.isArray(plugin) ? plugin[0] : plugin) === packageName);
}

function check(id: string, status: DoctorCheck['status'], message: string, details?: unknown): DoctorCheck {
  return { id, status, message, ...(details ? { details } : {}) };
}

function canResolvePackage(projectRoot, packageName) {
  const projectRequire = createRequire(path.join(projectRoot, 'package.json'));
  try {
    projectRequire.resolve(`${packageName}/package.json`);
    return true;
  } catch {
    try {
      projectRequire.resolve(packageName);
      return true;
    } catch {
      return false;
    }
  }
}

async function validateMetroConfigAsync(projectRoot) {
  const projectRequire = createRequire(path.join(projectRoot, 'package.json'));
  let metroConfig;

  try {
    metroConfig = projectRequire('metro-config');
  } catch (cause) {
    throw new Error('Cannot load the project-local metro-config package.', { cause });
  }

  if (typeof metroConfig.resolveConfig !== 'function') {
    const version = (() => {
      try {
        return projectRequire('metro-config/package.json').version;
      } catch {
        return 'unknown';
      }
    })();

    throw new Error(`metro-config ${version} does not expose resolveConfig().`);
  }

  const hadMetroTarget = Object.hasOwn(process.env, 'EXPO_METRO_TARGET');
  const previousMetroTarget = process.env.EXPO_METRO_TARGET;
  let resolved;

  try {
    process.env.EXPO_METRO_TARGET = 'harmony';
    resolved = await metroConfig.resolveConfig(undefined, projectRoot);
  } finally {
    if (hadMetroTarget) process.env.EXPO_METRO_TARGET = previousMetroTarget;
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

async function doctorAsync(projectRoot: string, options: DoctorOptions = {}): Promise<DoctorResult> {
  const checks: DoctorCheck[] = [];
  const unavailableToolStatus = options.requireBuildTools ? 'error' : 'warn';
  let config;

  try {
    config = getConfig(projectRoot, {
      isModdedConfig: true,
      skipSDKVersionRequirement: true,
    }).exp;
    normalizeHarmonyConfig(config);
    checks.push(check('app-config', 'pass', 'Harmony app config is valid.'));
  } catch (error) {
    checks.push(check('app-config', 'error', error.message, { code: error.code || 'ERR_HARMONY_CONFIG_INVALID' }));
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
        const signing = await validateHarmonySigningConfigFile(projectRoot, harmony.signingConfigFile);
        checks.push(check('signing', 'pass', `Harmony signing config ${signing.name} is valid.`));
      } catch (error) {
        checks.push(check('signing', 'error', error.message, { code: error.code || 'ERR_HARMONY_SIGNING_INVALID' }));
      }
    } else {
      checks.push(check('signing', 'warn', 'No external signing config is set; unsigned generation remains available.'));
    }
  }

  try {
    await validateMetroConfigAsync(projectRoot);
    checks.push(check('metro', 'pass', 'The resolved Metro config enables Harmony.'));
  } catch (error) {
    checks.push(check('metro', 'error', `Cannot load a Harmony-enabled Metro config: ${error.message}`, { code: error.code || 'ERR_HARMONY_METRO_CONFIG' }));
  }

  for (const packageName of RequiredProjectPackages) {
    if (canResolvePackage(projectRoot, packageName)) {
      checks.push(check(`package:${packageName}`, 'pass', `${packageName} is resolvable.`));
    } else {
      checks.push(check(`package:${packageName}`, 'error', `${packageName} is not resolvable from the app.`));
    }
  }

  const toolchain = resolveHarmonyToolchain();
  let sdkCheck;

  if (toolchain.sdkHome) {
    sdkCheck = check('harmony-sdk', 'pass', `Complete Harmony SDK root was resolved at ${toolchain.sdkHome}.`);
  } else {
    sdkCheck = check('harmony-sdk', unavailableToolStatus, 'No complete Harmony SDK root with HMS and OpenHarmony components was found; generation works but HAP build cannot be verified.');
  }

  checks.push(sdkCheck);

  const tools: Array<[string, HarmonyTool, string[]]> = [
    ['hdc', toolchain.hdc, ['-v']],
    ['ohpm', toolchain.ohpm, ['--version']],
    ['hvigor-command', toolchain.hvigor, ['--version']],
  ];
  for (const [id, tool, versionArgs] of tools) {
    try {
      const result = await spawnAsync(tool.command, [...tool.args, ...versionArgs], {
        capture: true,
        cwd: projectRoot,
        operation: `doctor-${id}`,
        timeoutMs: 10_000,
      });
      checks.push(result.code === 0 && !result.timedOut
        ? check(id, 'pass', `${tool.command} is available through ${tool.source}.`)
        : check(id, unavailableToolStatus, `${tool.command} is unavailable or unhealthy; HAP build cannot be verified.`));
    } catch {
      checks.push(check(id, unavailableToolStatus, `${tool.command} is unavailable; generation remains available.`));
    }
  }

  if (options.validateGeneratedProject !== false) {
    try {
      const plan = await resolveHarmonyBuildPlanIfPresentAsync(projectRoot);
      if (plan && fs.existsSync(plan.harmonyRoot)) {
        if (!fs.existsSync(plan.projectFiles.rootHvigor)
          || !fs.existsSync(plan.projectFiles.moduleHvigor)) {
          checks.push(check('hvigor', 'error', 'Generated root and module Hvigor files are required.'));
        } else {
          const content = await fs.promises.readFile(plan.projectFiles.moduleHvigor, 'utf8');
          checks.push(isRnohAutolinkingDisabled(content)
            ? check('hvigor-autolinking', 'pass', 'RNOH duplicate autolinking is disabled.')
            : check('hvigor-autolinking', 'error', 'The generated module Hvigor file must disable RNOH autolinking.'));
        }
      }
    } catch (error) {
      checks.push(check('harmony-project', 'error', error.message, { code: error.code || 'ERR_HARMONY_TEMPLATE_INVALID' }));
    }
  }

  return {
    checks,
    ok: checks.every(item => item.status !== 'error'),
    projectRoot,
  };
}

function formatDoctor(result: DoctorResult): string {
  return result.checks.map((item) => {
    const symbol = item.status === 'pass' ? '✓' : item.status === 'warn' ? '!' : '✗';
    return `${symbol} [${item.status}] ${item.message}`;
  }).join('\n');
}

export { doctorAsync, formatDoctor };

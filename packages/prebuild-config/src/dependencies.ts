/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { resolveRnohCliPackageJsonPath } from '@expo-harmony/expo-modules-autolinking';
import { HarmonyPaths } from '@expo-harmony/config-plugins';

import { mirrorHarmonyCheckPath } from './checkPath';
import { HarmonyPrebuildError } from './errors';
import { resolve as resolveTemplate } from './template';

function resolveRnohRuntimeVersion(root: string): string {
  const name = '@react-native-oh/react-native-harmony';
  const requireProject = createRequire(path.join(root, 'package.json'));
  let json: string;

  try {
    // Core owns the SDK's RNOH archive, even when an app has an older RNOH installed.
    const core = requireProject.resolve('@expo-harmony/expo-modules-core/package.json');
    json = createRequire(core).resolve(`${name}/package.json`);
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_DEPENDENCY_MISSING',
      `Unable to resolve ${name} from the project's @expo-harmony/expo-modules-core.`,
      { cause, operation: 'resolve-dependency' }
    );
  }

  let version;

  try {
    version = JSON.parse(fs.readFileSync(json, 'utf8')).version;
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_DEPENDENCY_MISSING',
      `Cannot read ${name} version.`,
      { cause, file: json, operation: 'resolve-dependency' }
    );
  }

  if (typeof version !== 'string' || !version) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_DEPENDENCY_MISSING',
      `${name} has no package version.`,
      { file: json, operation: 'resolve-dependency' }
    );
  }

  return version;
}

function resolveTemplateFile(relative) {
  const resolved = path.join(resolveTemplate().root, relative);

  if (!fs.existsSync(resolved)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_DEPENDENCY_MISSING',
      `@expo-harmony/template is missing ${relative}.`,
      { file: resolved, operation: 'resolve-dependency' }
    );
  }

  return resolved;
}

async function readTemplateSource(relative) {
  return fs.promises.readFile(resolveTemplateFile(`harmony/${relative}`), 'utf8');
}

function resolveRnohHvigorPlugin() {
  let json: string;
  try {
    json = resolveRnohCliPackageJsonPath();
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_DEPENDENCY_MISSING',
      'Unable to resolve @react-native-oh/react-native-harmony-cli from @expo-harmony/expo-modules-autolinking.',
      { cause, operation: 'resolve-dependency' }
    );
  }
  const harmony = path.join(path.dirname(json), 'harmony');

  let candidates;

  try {
    candidates = fs.readdirSync(harmony)
      .filter(name => /^rnoh-hvigor-plugin-.+\.tgz$/u.test(name))
      .sort();
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_DEPENDENCY_MISSING',
      '@react-native-oh/react-native-harmony-cli has no Harmony Hvigor plugin directory.',
      { cause, file: harmony, operation: 'resolve-dependency' }
    );
  }

  if (candidates.length !== 1) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_DEPENDENCY_MISSING',
      '@react-native-oh/react-native-harmony-cli must contain exactly one RNOH Hvigor plugin archive.',
      { file: harmony, operation: 'resolve-dependency' }
    );
  }

  return path.join(harmony, candidates[0]);
}

function toRelativeDependency(directory, file) {
  const mirror = process.env.EXPO_HARMONY_CHECK_MIRROR_ROOT;
  if (mirror && HarmonyPaths.isInside(mirror, directory)) {
    // Match the check command's filesystem mirror when rendering external tools.
    file = mirrorHarmonyCheckPath(mirror, file);
  }

  return path.relative(directory, file).split(path.sep).join('/');
}

export {
  readTemplateSource,
  resolveRnohHvigorPlugin,
  resolveRnohRuntimeVersion,
  resolveTemplateFile,
  toRelativeDependency,
};

import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { HarmonyPrebuildError } from './errors';
import { resolve as resolveTemplate } from './template';

const resolveModule = createRequire(__filename).resolve;

function resolvePackageFile(root, name, relative) {
  const logical = path.join(root, 'node_modules', ...name.split('/'), relative);

  if (fs.existsSync(logical)) return logical;

  let json;

  try {
    json = resolveModule(`${name}/package.json`, { paths: [root] });
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_DEPENDENCY_MISSING',
      `Unable to resolve ${name} from the project.`,
      { cause, operation: 'resolve-dependency' }
    );
  }

  const resolved = path.join(path.dirname(json), relative);

  if (!fs.existsSync(resolved)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_DEPENDENCY_MISSING',
      `${name} is missing ${relative}.`,
      { file: resolved, operation: 'resolve-dependency' }
    );
  }

  return resolved;
}

function resolvePackageVersion(root, name) {
  const json = resolvePackageFile(root, name, 'package.json');

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

function resolveRnohHvigorPlugin(root) {
  const json = resolvePackageFile(root, '@react-native-oh/react-native-harmony-cli', 'package.json');
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
  return path.relative(directory, file).split(path.sep).join('/');
}

export {
  readTemplateSource,
  resolvePackageVersion,
  resolveRnohHvigorPlugin,
  resolveTemplateFile,
  toRelativeDependency,
};

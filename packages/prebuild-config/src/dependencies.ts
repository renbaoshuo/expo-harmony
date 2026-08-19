import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { HarmonyPrebuildError } from './errors';

const resolveModule = createRequire(__filename).resolve;

function resolvePackageFile(projectRoot, packageName, relativePath) {
  const logical = path.join(projectRoot, 'node_modules', ...packageName.split('/'), relativePath);
  if (fs.existsSync(logical)) return logical;

  let packageJson;
  try {
    packageJson = resolveModule(`${packageName}/package.json`, { paths: [projectRoot] });
  } catch (cause) {
    throw new HarmonyPrebuildError('ERR_HARMONY_DEPENDENCY_MISSING', `Unable to resolve ${packageName} from the project.`, { cause, operation: 'resolve-dependency' });
  }

  const resolved = path.join(path.dirname(packageJson), relativePath);
  if (!fs.existsSync(resolved)) {
    throw new HarmonyPrebuildError('ERR_HARMONY_DEPENDENCY_MISSING', `${packageName} is missing ${relativePath}.`, { file: resolved, operation: 'resolve-dependency' });
  }
  return resolved;
}

function resolvePackageVersion(projectRoot, packageName) {
  const packageJson = resolvePackageFile(projectRoot, packageName, 'package.json');

  let version;
  try {
    version = JSON.parse(fs.readFileSync(packageJson, 'utf8')).version;
  } catch (cause) {
    throw new HarmonyPrebuildError('ERR_HARMONY_DEPENDENCY_MISSING', `Cannot read ${packageName} version.`, { cause, file: packageJson, operation: 'resolve-dependency' });
  }
  if (typeof version !== 'string' || !version) {
    throw new HarmonyPrebuildError('ERR_HARMONY_DEPENDENCY_MISSING', `${packageName} has no package version.`, { file: packageJson, operation: 'resolve-dependency' });
  }
  return version;
}

function resolveTemplateFile(relativePath) {
  let packageJson;
  try {
    packageJson = resolveModule('@expo-harmony/template/package.json');
  } catch (cause) {
    throw new HarmonyPrebuildError('ERR_HARMONY_DEPENDENCY_MISSING', 'Unable to resolve the declared @expo-harmony/template asset package.', { cause, operation: 'resolve-dependency' });
  }

  const resolved = path.join(path.dirname(packageJson), relativePath);
  if (!fs.existsSync(resolved)) {
    throw new HarmonyPrebuildError('ERR_HARMONY_DEPENDENCY_MISSING', `@expo-harmony/template is missing ${relativePath}.`, { file: resolved, operation: 'resolve-dependency' });
  }
  return resolved;
}

async function readTemplateSource(relativePath) {
  return fs.promises.readFile(resolveTemplateFile(`harmony/${relativePath}`), 'utf8');
}

function resolveRnohHvigorPlugin(projectRoot) {
  const packageJson = resolvePackageFile(projectRoot, '@react-native-oh/react-native-harmony-cli', 'package.json');
  const harmonyDirectory = path.join(path.dirname(packageJson), 'harmony');

  let candidates;
  try {
    candidates = fs.readdirSync(harmonyDirectory)
      .filter(name => /^rnoh-hvigor-plugin-.+\.tgz$/u.test(name))
      .sort();
  } catch (cause) {
    throw new HarmonyPrebuildError('ERR_HARMONY_DEPENDENCY_MISSING', '@react-native-oh/react-native-harmony-cli has no Harmony Hvigor plugin directory.', { cause, file: harmonyDirectory, operation: 'resolve-dependency' });
  }
  if (candidates.length !== 1) {
    throw new HarmonyPrebuildError('ERR_HARMONY_DEPENDENCY_MISSING', '@react-native-oh/react-native-harmony-cli must contain exactly one RNOH Hvigor plugin archive.', { file: harmonyDirectory, operation: 'resolve-dependency' });
  }
  return path.join(harmonyDirectory, candidates[0]);
}

function toRelativeDependency(fromDirectory, file) {
  return path.relative(fromDirectory, file).split(path.sep).join('/');
}

export {
  readTemplateSource,
  resolvePackageVersion,
  resolveRnohHvigorPlugin,
  resolveTemplateFile,
  toRelativeDependency,
};

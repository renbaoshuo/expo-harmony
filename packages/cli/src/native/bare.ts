import fs from 'node:fs';
import path from 'node:path';
import JSON5 from 'json5';

import { HarmonyCliError } from '../errors';
import type { BareHarmonyBuildPlan } from './types';

function isBareHarmonyProject(root: string): boolean {
  return fs.existsSync(path.join(root, 'harmony'))
    && !fs.existsSync(path.join(root, 'harmony/.expo-harmony-template'))
    && !fs.existsSync(path.join(root, '.expo/harmony/cng-manifest.json'));
}

function record(value: unknown, field: string): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new HarmonyCliError('ERR_HARMONY_NATIVE_PROJECT', `Native ${field} must be an object.`, { operation: 'resolve-build' });
  }

  return value as Record<string, unknown>;
}

function records(value: unknown, field: string): Record<string, unknown>[] {
  if (!Array.isArray(value)) {
    throw new HarmonyCliError('ERR_HARMONY_NATIVE_PROJECT', `Native ${field} must be an array.`, { operation: 'resolve-build' });
  }

  return value.map(item => record(item, field));
}

function readJson(file: string): Record<string, unknown> {
  try {
    return record(JSON5.parse(fs.readFileSync(file, 'utf8')), file);
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_NATIVE_PROJECT', `Cannot read native project file ${file}: ${cause.message}`, { cause, operation: 'resolve-build' });
  }
}

function identifier(value: unknown, field: string): string {
  if (typeof value !== 'string' || !/^[A-Za-z_][A-Za-z0-9_.]*$/.test(value)) {
    throw new HarmonyCliError('ERR_HARMONY_NATIVE_PROJECT', `The native project must specify a valid ${field}.`, { operation: 'resolve-build' });
  }

  return value;
}

function selectDefault(items: Record<string, unknown>[], field: string): Record<string, unknown> {
  if (items.length === 0) {
    throw new HarmonyCliError('ERR_HARMONY_NATIVE_PROJECT', `No ${field} is defined in harmony/build-profile.json5.`, { operation: 'resolve-build' });
  }

  const defaults = items.filter(item => item.name === 'default');

  if (defaults.length === 1) return defaults[0];
  if (items.length === 1) return items[0];

  throw new HarmonyCliError('ERR_HARMONY_NATIVE_PROJECT', `Multiple ${field} are defined; name the intended default "default" in harmony/build-profile.json5.`, { operation: 'resolve-build' });
}

function resolveBareHarmonyBuildPlan(root: string, mode: 'debug' | 'release'): BareHarmonyBuildPlan {
  const harmony = path.join(root, 'harmony');
  const entry = path.join(harmony, 'entry');

  for (const directory of [harmony, entry]) {
    if (!fs.existsSync(directory)
      || !fs.lstatSync(directory).isDirectory() || fs.lstatSync(directory).isSymbolicLink()) {
      throw new HarmonyCliError('ERR_HARMONY_NATIVE_PROJECT', `Bare Harmony projects require a regular directory at ${directory}.`, { operation: 'resolve-build' });
    }
  }

  const profile = readJson(path.join(harmony, 'build-profile.json5'));
  const app = record(readJson(path.join(harmony, 'AppScope/app.json5')).app, 'app');
  const module = record(readJson(path.join(entry, 'src/main/module.json5')).module, 'module');

  const name = identifier(module.name, 'module.name');
  const registration = records(profile.modules, 'modules').find(item => item.name === name);
  if (!registration || typeof registration.srcPath !== 'string'
    || path.resolve(harmony, registration.srcPath) !== entry || module.type !== 'entry') {
    throw new HarmonyCliError('ERR_HARMONY_NATIVE_PROJECT', 'Bare Harmony autolinking requires an entry module at harmony/entry, registered in build-profile.json5.', { operation: 'resolve-build' });
  }

  const config = record(profile.app, 'build-profile.app');
  const selected = selectDefault(records(config.products, 'products'), 'products');
  const product = identifier(selected.name, 'product name');
  const targets = records(registration.targets, 'module targets').filter((item) => {
    if (item.applyToProducts === undefined) return true;
    if (!Array.isArray(item.applyToProducts) || item.applyToProducts.some(value => typeof value !== 'string')) {
      throw new HarmonyCliError('ERR_HARMONY_NATIVE_PROJECT', 'Native target.applyToProducts must be an array of product names.', { operation: 'resolve-build' });
    }

    return item.applyToProducts.includes(product);
  });
  const target = identifier(selectDefault(targets, 'module targets').name, 'target name');

  const ability = identifier(module.mainElement, 'module.mainElement');
  if (!records(module.abilities, 'abilities').some(item => item.name === ability)) {
    throw new HarmonyCliError('ERR_HARMONY_NATIVE_PROJECT', `Ability ${ability} is missing from module.json5.`, { operation: 'resolve-build' });
  }

  const bundle = identifier(app.bundleName, 'app.bundleName');
  const signed = Boolean(selected.signingConfig);
  if (signed && !records(config.signingConfigs, 'signingConfigs').some(item => item.name === selected.signingConfig)) {
    throw new HarmonyCliError('ERR_HARMONY_NATIVE_PROJECT', `Signing config ${selected.signingConfig} is referenced by the product but is not defined.`, { operation: 'resolve-build' });
  }

  const rawfile = path.join(entry, 'src/main/resources/rawfile');
  const metadata = path.join(root, '.expo/harmony/export');

  return {
    workflow: 'bare',
    abilityName: ability,
    buildMode: mode,
    bundleName: bundle,
    harmonyRoot: harmony,
    moduleName: name,
    moduleRoot: entry,
    productName: product,
    targetName: target,
    expectedHap: path.join(entry, `build/${target}/outputs/${target}/${name}-${target}-${signed ? 'signed' : 'unsigned'}.hap`),
    hvigorArgs: ['--mode', 'module', '-p', `module=${name}@${target}`, '-p', `product=${product}`, '-p', `buildMode=${mode}`, '--no-daemon', 'assembleHap'],
    exportPaths: {
      bundle: path.join(rawfile, 'hermes_bundle.hbc'),
      manifest: path.join(root, '.expo/harmony/export-manifest.json'),
      metadataRoot: metadata,
      rawfileRoot: rawfile,
      sourceMap: path.join(metadata, 'hermes_bundle.hbc.map'),
    },
    nativeCache: {
      invalidationRoots: [path.join(entry, '.cxx'), path.join(entry, 'build')],
      stateFile: path.join(entry, '.cxx/.expo-harmony-native-dependencies.json'),
    },
    nativeInputs: {
      lockfile: path.join(harmony, 'oh-package-lock.json5'),
      manifest: path.join(harmony, 'oh-package.json5'),
    },
    projectFiles: {
      hvigorConfig: path.join(harmony, 'hvigor/hvigor-config.json5'),
      moduleHvigor: path.join(entry, 'hvigorfile.ts'),
      moduleJson: path.join(entry, 'src/main/module.json5'),
      projectBuildProfile: path.join(harmony, 'build-profile.json5'),
      rootHvigor: path.join(harmony, 'hvigorfile.ts'),
    },
  };
}

export { isBareHarmonyProject, resolveBareHarmonyBuildPlan };

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Buffer } from 'node:buffer';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import semver from 'semver';

import { ALL_FEATURES, detectFeatures, renderFeatureBlocks, resolveFeatures } from './features.mjs';
import { SDK_VERSIONS } from './sdk.mjs';

const require = createRequire(import.meta.url);
const DEFAULT_SDK_MAJOR = Number(require('../package.json').version.split('.')[0]);
const DEFAULT_VERSION = '1.0.0';
const NPM_NAME = /^(?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*$/;
const LEGACY_FEATURES = ALL_FEATURES.filter(feature => feature !== 'Event');
const HARMONY_PACK_FILES = ['expo-module.config.json', 'harmony/library.har', 'harmony/library/oh-package.json5'];
const CORE_PACKAGE = '@expo-harmony/expo-modules-core';
const MODULE_SCRIPTS_PACKAGE = '@expo-harmony/expo-module-scripts';
const MIN_EXISTING_PACKAGE_PREPACK_VERSION = '55.0.2-harmony.4';
const INCLUDE_PRERELEASE = { includePrerelease: true };

function pascalCase(value) {
  return value
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map(part => `${part[0].toUpperCase()}${part.slice(1)}`)
    .join('');
}

const NATIVE_IDENTIFIER = /^[A-Za-z][A-Za-z0-9_]*$/;

function deriveNames(name, nativeName, detectedName) {
  if (typeof name !== 'string' || name.trim() !== name || !NPM_NAME.test(name)) {
    throw new TypeError(`Invalid npm package name: ${name}`);
  }

  const parts = name.replace(/^@/, '').split('/');
  const basename = parts.at(-1);
  const module = nativeName ?? (NATIVE_IDENTIFIER.test(detectedName ?? '') ? detectedName : pascalCase(basename));
  if (typeof module !== 'string' || module.trim() !== module || !NATIVE_IDENTIFIER.test(module)) {
    throw new TypeError('Native module name must be an ArkTS identifier.');
  }

  const harmony = parts.join('_').replace(/[^A-Za-z0-9_]/g, '_').toLowerCase();
  const bundle = harmony.split('_').filter(Boolean)
    .map(segment => /^\d/.test(segment) ? `module${segment}` : segment).join('.');

  return {
    packageName: name,
    packageBasename: basename,
    moduleBase: module,
    moduleName: nativeName ?? detectedName ?? module,
    harmonyModule: harmony,
    bundleName: `dev.expo.modules.${bundle}`,
  };
}

async function readJson(file) {
  try {
    return JSON.parse(await fs.promises.readFile(file, 'utf8'));
  } catch {
    return undefined;
  }
}

async function findAppRoot(cwd) {
  let dir = path.resolve(cwd);

  while (true) {
    try {
      const stat = await fs.promises.stat(path.join(dir, 'package.json'));
      if (stat.isFile()) return dir;
    } catch (error) {
      if (error?.code !== 'ENOENT') {
        throw new Error(`Cannot inspect ${dir} for an Expo app root.`, { cause: error });
      }
    }

    const parent = path.dirname(dir);
    if (parent === dir) {
      throw new Error(`Cannot create a local Expo module: no package.json was found above ${path.resolve(cwd)}.`);
    }

    dir = parent;
  }
}

async function detectExpoSdkMajor(cwd) {
  for (let dir = path.resolve(cwd); ; dir = path.dirname(dir)) {
    const file = path.join(dir, 'package.json');
    const pkg = await readJson(file);
    const version = pkg?.dependencies?.expo ?? pkg?.devDependencies?.expo ?? pkg?.peerDependencies?.expo;
    if (pkg && version) {
      try {
        const installed = createRequire(file)('expo/package.json');
        return { major: semver.major(installed.version), source: file };
      } catch { /* An uninstalled project may only have a manifest. */ }
    }
    const range = typeof version === 'string' && semver.validRange(version.replace(/^npm:expo@/, ''), INCLUDE_PRERELEASE);
    const minimum = range && semver.minVersion(range, INCLUDE_PRERELEASE);
    if (minimum && semver.subset(range, `${minimum.major}.x`, INCLUDE_PRERELEASE)) {
      return { major: minimum.major, source: file };
    }
    if (path.dirname(dir) === dir) return { major: DEFAULT_SDK_MAJOR, source: 'fallback' };
  }
}

function replacements(names, sdk, options = {}) {
  const features = options.features ?? [];
  const imports = [];
  if (features.some(feature => ['Function', 'AsyncFunction', 'Event', 'View', 'SharedObject'].includes(feature))) imports.push('ExpoFunction', 'ExpoValueTypes');
  if (features.includes('SharedObject')) imports.push('ExpoSharedObject', 'ExpoSharedObjectClassDefinition');
  if (features.includes('View')) imports.push('ExpoView', 'ExpoViewContext', 'ExpoViewDefinition');

  const facade = [];
  const app = [];
  const react = new Set();
  if (features.includes('View')) {
    facade.push('requireNativeViewManager');
    app.push(`${names.moduleBase}View`, `type ${names.moduleBase}ViewRef`);
    react.add('useRef');
  }
  if (features.includes('SharedObject')) {
    app.push(`${names.moduleBase}Counter`);
  }
  if (features.includes('Event')) {
    react.add('useEffect');
    react.add('useState');
    app.push('emitChange');
  }
  if (features.includes('Constant')) app.push('platform');
  if (features.includes('Function')) app.push('echo');
  if (features.includes('AsyncFunction')) app.push('echoAsync');
  if (features.some(feature => ['AsyncFunction', 'ViewEvent', 'SharedObject'].includes(feature))) react.add('useState');

  return {
    ...SDK_VERSIONS[sdk],
    NPM_NAME: names.packageName,
    PACKAGE_VERSION: options.moduleVersion ?? DEFAULT_VERSION,
    PACKAGE_BASENAME: names.packageBasename,
    MODULE_BASE: names.moduleBase,
    MODULE_CLASS: names.moduleBase.endsWith('Module') ? names.moduleBase : `${names.moduleBase}Module`,
    MODULE_NAME: names.moduleName,
    MODULE_NAME_JSON: JSON.stringify(names.moduleName),
    HARMONY_MODULE: names.harmonyModule,
    BUNDLE_NAME: names.bundleName,
    SDK_MAJOR: String(sdk),
    DESCRIPTION_JSON: JSON.stringify(options.description ?? 'An Expo module for HarmonyOS'),
    LICENSE_JSON: JSON.stringify(options.license ?? 'MIT'),
    AUTHOR_JSON: JSON.stringify(options.authorName ?? ''),
    REPO_JSON: JSON.stringify(options.repo ?? ''),
    NATIVE_IMPORTS: imports.length ? `, ${imports.join(', ')}` : '',
    FACADE_IMPORTS: facade.length ? `, ${facade.join(', ')}` : '',
    APP_IMPORTS: app.length ? `, { ${app.join(', ')} }` : '',
    APP_REACT_IMPORTS: react.size ? `import { ${[...react].join(', ')} } from 'react';` : '',
    APP_BUTTON_IMPORT: features.some(feature => ['AsyncFunction', 'Event', 'View', 'SharedObject'].includes(feature)) ? 'Button, ' : '',
    features,
  };
}

function replaceTokens(source, values) {
  const template = renderFeatureBlocks(source, values.features ?? []);
  return template.replace(/\{\{([A-Z0-9_]+)\}\}|__([A-Z0-9_]+)__/g, (_match, braces, underscores) => {
    const key = braces ?? underscores;
    if (!Object.hasOwn(values, key)) throw new Error(`Unknown template placeholder: ${key}`);
    return values[key];
  }).replace(/\n {6};/g, ';');
}

async function renderDirectory(template, directory, values, skipExample = false) {
  const entries = await fs.promises.readdir(template, { withFileTypes: true });

  for (const entry of entries) {
    if (skipExample && entry.name === 'example') continue;
    let name = entry.name;
    if (name.endsWith('.tpl')) name = name.slice(0, -4);
    name = replaceTokens(name, values);

    const source = path.join(template, entry.name);
    const target = path.join(directory, name);

    if (entry.isDirectory()) {
      await fs.promises.mkdir(target, { recursive: true });
      await renderDirectory(source, target, values);
      continue;
    }

    if (!entry.isFile()) throw new Error(`Template contains an unsupported entry: ${source}`);

    const content = replaceTokens(await fs.promises.readFile(source, 'utf8'), values);

    await fs.promises.mkdir(path.dirname(target), { recursive: true });
    await fs.promises.writeFile(target, content, 'utf8');
  }
}

async function ensureAbsent(target) {
  try {
    await fs.promises.lstat(target);
  } catch (error) {
    if (error?.code === 'ENOENT') return;

    throw new Error(`Cannot inspect target: ${target}`, { cause: error });
  }

  throw new Error(`Target already exists: ${target}`);
}

async function writeAtomic(file, content, previous) {
  const directory = await fs.promises.mkdtemp(path.join(path.dirname(file), '.expo-harmony-manifest-'));
  const temp = path.join(directory, 'manifest.json');
  try {
    await fs.promises.writeFile(temp, content);
    if (previous) {
      const current = await readManifest(file);
      if (!current.content.equals(previous.content)) throw new Error(`Manifest changed during generation: ${file}`);
      await fs.promises.chmod(temp, current.mode);
      await fs.promises.rename(temp, file);
    } else {
      await fs.promises.link(temp, file);
    }
  } finally {
    await fs.promises.rm(directory, { recursive: true, force: true });
  }
}

async function readManifest(file, optional = false) {
  const stat = await fs.promises.lstat(file).catch((error) => {
    if (optional && error.code === 'ENOENT') return undefined;
    throw error;
  });
  if (!stat) return undefined;
  if (!stat.isFile()) throw new TypeError(`Expected a regular manifest file: ${file}`);

  return { content: await fs.promises.readFile(file), mode: stat.mode };
}

function jsonBytes(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
}

function setScriptIfAvailable(scripts, name, command) {
  if (scripts[name] !== undefined && scripts[name] !== command) {
    throw new Error(`package.json#scripts.${name} already exists; refusing to overwrite it.`);
  }

  scripts[name] = command;
}

async function sourceFiles(root) {
  const files = [];
  const ignored = new Set(['node_modules', 'build', 'dist', 'Pods', '.git', '.gradle', '__tests__', 'tests', 'test']);

  async function visit(dir, shallow = false) {
    const entries = await fs.promises.readdir(dir, { withFileTypes: true }).catch((error) => {
      if (error.code === 'ENOENT') return [];
      throw error;
    });

    for (const entry of entries) {
      const file = path.join(dir, entry.name);
      if (!shallow && entry.isDirectory() && !ignored.has(entry.name)) await visit(file);
      else if (entry.isFile() && /\.(swift|kt|tsx?|jsx?)$/.test(entry.name)
        && !/\.(types|test|spec|d)\.[jt]sx?$/.test(entry.name)) files.push(file);
    }
  }

  await Promise.all([visit(root, true), ...['src', 'ios', 'android/src'].map(dir => visit(path.join(root, dir)))]);

  return files.sort();
}

const PUBLIC_NAME = /\bName\s*\(\s*(['"])([^'"\n]+)\1\s*\)/;
const SOURCE_NAMES = [
  /\brequire(?:Optional)?NativeModule(?:<[\s\S]*?>)?\s*\(\s*(['"`])([^'"`\n]+)\1\s*\)/,
  /\bregisterWebModule\s*\(\s*[^,]+,\s*(['"`])([^'"`\n]+)\1\s*\)/,
  /\bglobalThis\.expo\??\.\s*modules\??\.?\s*\[\s*(['"`])([^'"`\n]+)\1\s*\]/,
];

function stripSourceComments(source) {
  const quotedOrComment = /("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)|\/\*[\s\S]*?\*\/|\/\/[^\n]*/g;
  return source.replace(quotedOrComment, (_match, quoted) => quoted ?? ' ');
}

async function inspectExistingModule(target, config) {
  const files = await sourceFiles(target);
  const nativeModules = [];
  let jsName;
  let entry;
  const features = new Set();
  for (const file of files) {
    const relative = path.relative(target, file).replaceAll(path.sep, '/');
    const content = stripSourceComments(await fs.promises.readFile(file, 'utf8'));
    if (/^(?:ios\/.*\.swift|android\/src\/.*\.kt)$/.test(relative)) {
      const definition = content.indexOf('ModuleDefinition');
      if (definition < 0) continue;

      const source = content.slice(definition);
      const name = source.match(PUBLIC_NAME)?.[2];
      const className = path.basename(file, path.extname(file));
      nativeModules.push({ name, className, source });
    } else if (/^(?:src\/|[^/]+$)/.test(relative) && /\.[jt]sx?$/.test(relative)) {
      const match = SOURCE_NAMES.map(pattern => content.match(pattern)).find(Boolean);
      if (match) {
        jsName ??= match[2];
        if (!relative.includes('.web.')) entry ??= relative;
      }
    }
  }
  const registered = new Set([config.apple?.modules ?? config.ios?.modules, config.android?.modules].flat()
    .filter(name => typeof name === 'string').map(name => name.split('.').at(-1)));
  const definitions = nativeModules.filter(module => registered.has(module.className));
  const candidates = definitions.length ? definitions : nativeModules;
  const name = candidates.find(module => module.name === jsName)?.name
    ?? candidates.find(module => module.name)?.name ?? jsName ?? candidates[0]?.className;
  for (const definition of candidates.filter(module => !module.name || module.name === name)) {
    for (const feature of detectFeatures(definition.source)) features.add(feature);
  }
  const paths = files.map(file => path.relative(target, file).replaceAll(path.sep, '/'));
  entry = paths.find(file => /^(?:src\/)?index\.[jt]sx?$/.test(file)) ?? entry;

  return { name, features: [...features], entry };
}

function assertInside(root, target, label) {
  const relative = path.relative(root, target);
  if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
    throw new TypeError(`${label} must be inside ${root}.`);
  }
}

async function localDirectory(project) {
  const pkg = await readJson(path.join(project, 'package.json'));
  if (!pkg) throw new TypeError(`Cannot parse the app package.json in ${project}.`);

  const shared = pkg?.expo?.autolinking ?? {};
  const harmony = shared.harmony ?? {};
  const value = Object.hasOwn(harmony, 'nativeModulesDir')
    ? harmony.nativeModulesDir
    : Object.hasOwn(shared, 'nativeModulesDir') ? shared.nativeModulesDir : 'modules';
  if (typeof value !== 'string' || !value.trim()) {
    throw new TypeError('Harmony nativeModulesDir is disabled or invalid; configure it before creating a local module.');
  }

  const directory = path.resolve(project, value);
  assertInside(project, directory, 'nativeModulesDir');
  return directory;
}

async function validateLocalTarget(project, target) {
  const directory = await localDirectory(project);
  assertInside(directory, target, 'Local module');
  const relative = path.relative(directory, target);
  if (!/^(?:@[^/\\]+[/\\])?[^./\\][^/\\]*$/.test(relative)) {
    throw new TypeError('Local module must be a direct child or scoped package of nativeModulesDir.');
  }
  if (fs.existsSync(path.join(directory, 'package.json'))) {
    throw new TypeError('nativeModulesDir already points to a package; configure a directory of local modules.');
  }
  let ancestor = target;
  while (!fs.existsSync(ancestor)) ancestor = path.dirname(ancestor);
  assertInside(await fs.promises.realpath(project), await fs.promises.realpath(ancestor), 'Local module real path');
  return relative.split(path.sep).join('/');
}

function compatibleCoreDependency(current, major, field) {
  if (current !== undefined) {
    if (typeof current !== 'string') throw new TypeError(`${field} dependency must be a string.`);
    if (semver.validRange(current, INCLUDE_PRERELEASE) && !semver.intersects(current, `${major}.x`, INCLUDE_PRERELEASE)) {
      throw new TypeError(`${field} (${current}) is incompatible with SDK ${major}; update it before adding Harmony.`);
    }
  }
  return current ?? SDK_VERSIONS[major].HARMONY_CORE_VERSION;
}

function moduleScriptsDependency(current, isPrivate) {
  const fallback = `^${SDK_VERSIONS[57].MODULE_SCRIPTS_VERSION}`;
  if (current === undefined) return fallback;
  if (typeof current !== 'string') throw new TypeError('Harmony module scripts dependency must be a string.');

  const range = semver.validRange(current, INCLUDE_PRERELEASE);
  // Older module-scripts releases reject prepack --existing-package.
  return !isPrivate && range && !semver.subset(range, `>=${MIN_EXISTING_PACKAGE_PREPACK_VERSION}`, INCLUDE_PRERELEASE)
    ? fallback
    : current;
}

async function addHarmonyToExisting(options, cwd, sdk, templates) {
  const requested = path.resolve(cwd, options.target ?? '.');
  const target = await fs.promises.realpath(requested);
  if (target === path.parse(target).root) throw new Error('Refusing to modify a filesystem root.');

  const manifest = path.join(target, 'package.json');
  const file = path.join(target, 'expo-module.config.json');
  const harmony = path.join(target, 'harmony');
  const originalPackage = await readManifest(manifest, true);
  const originalConfig = await readManifest(file);
  const config = JSON.parse(originalConfig.content);

  if (!config || typeof config !== 'object' || Array.isArray(config)) throw new TypeError('expo-module.config.json must be an object.');
  if (config.platforms !== undefined && (!Array.isArray(config.platforms) || config.platforms.some(value => typeof value !== 'string'))) {
    throw new TypeError('expo-module.config.json#platforms must be an array of strings.');
  }
  if (config.harmony !== undefined || config.platforms?.includes('harmony')) {
    throw new Error('expo-module.config.json already declares harmony; refusing to overwrite it.');
  }
  await ensureAbsent(harmony);

  const existing = await inspectExistingModule(target, config);
  const local = originalPackage === undefined;
  let localName;
  if (local) {
    const project = await findAppRoot(path.dirname(requested));
    localName = await validateLocalTarget(project, requested);
    if (!existing.entry) throw new Error('Cannot find the local module JavaScript entry point.');
  }

  const pkg = originalPackage
    ? JSON.parse(originalPackage.content)
    : {
        name: localName, version: options.moduleVersion ?? DEFAULT_VERSION,
        private: true, main: existing.entry, types: existing.entry,
      };
  if (!isVersion(pkg.version)) throw new TypeError('The existing module needs a semantic package version.');

  const names = deriveNames(pkg.name, options.moduleName, existing.name);
  const features = sdk.major === 55
    ? LEGACY_FEATURES
    : resolveFeatures(options.features ?? existing.features, options.fullExample);
  const values = replacements(names, sdk.major, {
    ...options,
    license: options.license ?? pkg.license,
    moduleVersion: pkg.version,
    features,
  });

  const scripts = { ...(pkg.scripts ?? {}) };
  setScriptIfAvailable(scripts, 'harmony:clean', 'expo-harmony-module prepare --clean-only');
  setScriptIfAvailable(scripts, 'harmony:build', 'expo-harmony-module prepare');
  setScriptIfAvailable(scripts, 'harmony:inspect', 'expo-harmony-module inspect');
  if (!pkg.private) {
    setScriptIfAvailable(scripts, 'harmony:prepack', 'expo-harmony-module prepack --existing-package');
    if (scripts.prepack) {
      // Run the existing command in its own npm script shell so an exit or
      // a trailing comment cannot skip the Harmony pack step.
      setScriptIfAvailable(scripts, 'harmony:previous-prepack', scripts.prepack);
      scripts.prepack = 'npm --ignore-scripts run harmony:previous-prepack && npm run harmony:prepack';
    } else {
      scripts.prepack = 'npm run harmony:prepack';
    }
  }

  const corePeer = compatibleCoreDependency(pkg.peerDependencies?.[CORE_PACKAGE], sdk.major, 'Harmony Core peer');
  const runtimeCore = pkg.dependencies?.[CORE_PACKAGE];
  const devCore = pkg.devDependencies?.[CORE_PACKAGE];
  compatibleCoreDependency(runtimeCore, sdk.major, 'Harmony Core runtime');
  compatibleCoreDependency(devCore, sdk.major, 'Harmony Core development');
  const nextPackage = {
    ...pkg,
    ...(Array.isArray(pkg.files) ? { files: [...new Set([...pkg.files, ...HARMONY_PACK_FILES])] } : {}),
    scripts,
    peerDependencies: {
      ...(pkg.peerDependencies ?? {}),
      [CORE_PACKAGE]: corePeer,
    },
    devDependencies: {
      ...(pkg.devDependencies ?? {}),
      ...(!pkg.private && runtimeCore === undefined && devCore === undefined ? { [CORE_PACKAGE]: corePeer } : {}),
      [MODULE_SCRIPTS_PACKAGE]: moduleScriptsDependency(pkg.devDependencies?.[MODULE_SCRIPTS_PACKAGE], pkg.private),
    },
  };

  const template = path.join(templates, `standalone/sdk-${sdk.major}`);
  const generatedConfig = JSON.parse(replaceTokens(await fs.promises.readFile(path.join(template, 'expo-module.config.json.tpl'), 'utf8'), values));
  const nextConfig = { ...config, platforms: [...(config.platforms ?? []), 'harmony'], harmony: generatedConfig.harmony };
  const writes = [{ file: manifest, content: jsonBytes(nextPackage), previous: originalPackage }];
  if (!pkg.private && !Array.isArray(pkg.files)) {
    const file = path.join(target, '.npmignore');
    const previous = await readManifest(file, true);
    const rules = previous ?? await readManifest(path.join(target, '.gitignore'), true);
    const additions = [
      '', '# Expo Harmony publish files', '!/harmony/', '/harmony/*',
      '!/harmony/library/', '/harmony/library/*', ...HARMONY_PACK_FILES.map(entry => `!/${entry}`), '',
    ];
    writes.push({ file, previous, content: Buffer.concat([rules?.content ?? Buffer.alloc(0), Buffer.from(additions.join('\n'))]) });
  }
  writes.push({ file, content: jsonBytes(nextConfig), previous: originalConfig });

  // Claim the directory before changing the manifests. A competing add cannot roll back our files.
  await fs.promises.mkdir(harmony);
  const written = [];

  try {
    await renderDirectory(path.join(template, 'harmony'), harmony, values);
    for (const write of writes) {
      await writeAtomic(write.file, write.content, write.previous);
      written.push(write);
    }
  } catch (error) {
    const rollback = await Promise.allSettled([
      fs.promises.rm(harmony, { recursive: true, force: true }),
      ...written.map(async ({ file, content, previous }) => {
        const current = await readManifest(file, true);
        if (!current?.content.equals(content)) return;
        if (previous) await writeAtomic(file, previous.content, current);
        else await fs.promises.rm(file);
      }),
    ]);
    const failures = rollback.filter(result => result.status === 'rejected').map(result => result.reason);
    if (failures.length) {
      throw new AggregateError([error, ...failures], `Adding Harmony failed and could not be fully rolled back: ${error.message}`);
    }
    throw error;
  }

  return { target, local, added: true, sdkMajor: sdk.major, sdkSource: sdk.source, features };
}

function isVersion(version) {
  return typeof version === 'string' && /^\d/.test(version) && version.trim() === version && semver.valid(version) !== null;
}

export async function createModule(options) {
  const cwd = path.resolve(options.cwd ?? process.env.INIT_CWD ?? process.cwd());
  const local = options.local === true;
  const adding = options.addToExisting === true;
  if (local && adding) throw new TypeError('--local and --add-to-existing cannot be combined.');
  if (options.platform?.some(platform => platform !== 'harmony')) throw new TypeError('Only the harmony platform is supported.');
  if (options.moduleVersion !== undefined && !isVersion(options.moduleVersion)) {
    throw new TypeError('--module-version must be a semantic version.');
  }

  const project = local ? await findAppRoot(cwd) : undefined;
  const sdk = options.sdkMajor !== undefined
    ? { major: Number(options.sdkMajor), source: 'explicit' }
    : local || adding
      ? await detectExpoSdkMajor(adding ? path.resolve(cwd, options.target ?? '.') : project)
      : { major: DEFAULT_SDK_MAJOR, source: 'cli' };
  if (!Object.hasOwn(SDK_VERSIONS, sdk.major)) {
    throw new Error(`Expo SDK ${sdk.major} is not supported; available templates: ${Object.keys(SDK_VERSIONS).join(', ')}.`);
  }

  const templates = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../templates');
  if (sdk.major === 55 && (options.features !== undefined || options.fullExample)) {
    throw new TypeError('Feature selection requires SDK 57; SDK 55 retains its original complete example.');
  }
  if (adding) return addHarmonyToExisting(options, cwd, sdk, templates);

  const features = sdk.major === 55 ? LEGACY_FEATURES : resolveFeatures(options.features, options.fullExample);
  const names = deriveNames(options.name, options.moduleName);
  const fallback = local
    ? path.join(await localDirectory(project), names.packageBasename)
    : path.join(cwd, names.packageBasename);
  const target = path.resolve(cwd, options.target ?? fallback);
  if (target === path.parse(target).root) throw new Error('Refusing to generate into a filesystem root.');
  if (local) await validateLocalTarget(project, target);
  await ensureAbsent(target);
  await fs.promises.mkdir(path.dirname(target), { recursive: true });
  const staging = await fs.promises.mkdtemp(path.join(path.dirname(target), '.create-expo-harmony-module-'));
  try {
    const values = replacements(names, sdk.major, { ...options, features });
    const skipExample = local || options.example === false;
    await renderDirectory(path.join(templates, `standalone/sdk-${sdk.major}`), staging, values, skipExample);
    if (!skipExample) {
      const file = path.join(staging, 'example/package.json');
      const pkg = JSON.parse(await fs.promises.readFile(file, 'utf8'));
      if (Object.hasOwn(pkg.dependencies, names.packageName)) {
        throw new TypeError(`${names.packageName} is required by the example app. Choose a different name or use --no-example.`);
      }
      pkg.dependencies[names.packageName] = 'file:..';
      await fs.promises.writeFile(file, jsonBytes(pkg));
    }
    if (local) {
      await renderDirectory(path.join(templates, `local/sdk-${sdk.major}`), staging, values);
      if (sdk.major === 57 && options.barrel) {
        await fs.promises.writeFile(path.join(staging, 'index.ts'), 'export { default } from \'./src\';\nexport * from \'./src\';\n');
        const pkg = await readJson(path.join(staging, 'package.json'));
        pkg.main = pkg.types = 'index.ts';
        await fs.promises.writeFile(path.join(staging, 'package.json'), jsonBytes(pkg));
      }
    }
    await fs.promises.mkdir(target);
    try {
      for (const entry of await fs.promises.readdir(staging)) {
        await fs.promises.rename(path.join(staging, entry), path.join(target, entry));
      }
    } catch (error) {
      await fs.promises.rm(target, { recursive: true, force: true });
      throw error;
    }
  } finally {
    await fs.promises.rm(staging, { recursive: true, force: true });
  }

  return { target, appRoot: project, local, added: false, sdkMajor: sdk.major, sdkSource: sdk.source, features };
}

function parseCli(argv) {
  const options = { local: false, addToExisting: false };
  let name;
  const values = { '--path': 'target', '--sdk': 'sdkMajor', '--name': 'moduleName', '--module-version': 'moduleVersion', '--license': 'license', '--description': 'description', '--author-name': 'authorName', '--repo': 'repo' };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--local') options.local = true;
    else if (argument === '--add' || argument === '--add-to-existing' || argument === 'add-platform-support') options.addToExisting = true;
    else if (argument === '--full-example') options.fullExample = true;
    else if (argument === '--barrel') options.barrel = true;
    else if (argument === '--no-example') options.example = false;
    else if (argument === '--features' || argument === '--platform' || argument === '-p') {
      const selected = [];
      while (argv[index + 1] && !argv[index + 1].startsWith('-')) selected.push(...argv[++index].split(','));
      if (!selected.length) throw new TypeError(`${argument} requires a value.`);
      options[argument === '--features' ? 'features' : 'platform'] = selected;
    } else if (values[argument]) {
      const value = argv[++index];
      if (!value || value.startsWith('--')) throw new TypeError(`${argument} requires a value.`);
      options[values[argument]] = value;
    } else if (argument.startsWith('-')) throw new TypeError(`Unknown option: ${argument}`);
    else if (name === undefined) name = argument;
    else throw new TypeError(`Unexpected argument: ${argument}`);
  }
  if (options.addToExisting && name !== undefined && options.target === undefined) {
    options.target = name;
    name = undefined;
  }
  if (!name && !options.addToExisting) throw new TypeError('A package name is required.');
  return { ...options, name };
}

export async function runCli(argv) {
  if (argv.includes('--version') || argv.includes('-v')) {
    process.stdout.write(`${require('../package.json').version}\n`);
    return;
  }
  if (argv.length === 0 || argv.includes('--help') || argv.includes('-h')) {
    process.stdout.write('Usage: create-expo-harmony-module <name> [--local] [--path <directory>] [--sdk 55|57]\n'
      + '       create-expo-harmony-module add-platform-support [directory] [--sdk 55|57]\n'
      + '       --add / --add-to-existing are aliases for add-platform-support\n'
      + `Options: --features <${ALL_FEATURES.join('|')}|all> --full-example --barrel --no-example\n`
      + '         --name <native-name> --module-version <version> --license <license> --description <text>\n'
      + '         --author-name <name> --repo <url> --platform harmony\n');
    return;
  }

  const result = await createModule(parseCli(argv));
  if (result.sdkSource === 'fallback') process.stderr.write(`Expo SDK could not be detected; using SDK ${DEFAULT_SDK_MAJOR}.\n`);
  process.stdout.write(result.added
    ? `Added Harmony support to Expo module at ${result.target}\nFeature examples are scaffolds; implement the existing module API in ArkTS.\n`
    : `Created ${result.local ? 'local' : 'standalone'} Harmony Expo module at ${result.target}\n`);
}

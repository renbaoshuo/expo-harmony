import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const DEFAULT_SDK_MAJOR = 55;
const DEFAULT_VERSION = '1.0.0';
const NPM_NAME = /^(?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*$/;

function pascalCase(value) {
  return value
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map(part => `${part[0].toUpperCase()}${part.slice(1)}`)
    .join('');
}

function deriveNames(packageName) {
  if (typeof packageName !== 'string' || !NPM_NAME.test(packageName)) {
    throw new TypeError(`Invalid npm package name: ${packageName}`);
  }

  const parts = packageName.replace(/^@/, '').split('/');
  const basename = parts.at(-1);
  const moduleName = pascalCase(basename);

  if (moduleName.length === 0 || /^[0-9]/.test(moduleName)) {
    throw new TypeError('The package name must produce a valid ArkTS identifier.');
  }

  const harmonyName = parts.join('_').replace(/[^A-Za-z0-9_]/g, '_').toLowerCase();

  return {
    packageName,
    packageBasename: basename,
    moduleBase: moduleName,
    moduleName,
    harmonyModule: harmonyName,
    bundleName: `dev.expo.modules.${harmonyName.replace(/_/g, '.')}`,
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
  let dir = path.resolve(cwd);

  while (true) {
    const pkg = await readJson(path.join(dir, 'package.json'));
    const version = pkg?.dependencies?.expo ?? pkg?.devDependencies?.expo;
    const match = typeof version === 'string' ? version.match(/(?:^|[^0-9])(\d{2})(?:\.|[^0-9]|$)/) : null;

    if (match) return { major: Number(match[1]), source: path.join(dir, 'package.json') };

    const parent = path.dirname(dir);
    if (parent === dir) return { major: DEFAULT_SDK_MAJOR, source: 'fallback' };

    dir = parent;
  }
}

function replacements(names, sdkMajor, version = DEFAULT_VERSION) {
  return {
    NPM_NAME: names.packageName,
    PACKAGE_VERSION: version,
    PACKAGE_BASENAME: names.packageBasename,
    MODULE_BASE: names.moduleBase,
    MODULE_NAME: names.moduleName,
    HARMONY_MODULE: names.harmonyModule,
    BUNDLE_NAME: names.bundleName,
    SDK_MAJOR: String(sdkMajor),
  };
}

function replaceTokens(source, values) {
  let output = source;

  for (const [key, value] of Object.entries(values)) {
    output = output.replaceAll(`{{${key}}}`, value).replaceAll(`__${key}__`, value);
  }

  return output;
}

async function renderDirectory(sourceDir, targetDir, values) {
  const entries = await fs.promises.readdir(sourceDir, { withFileTypes: true });

  for (const entry of entries) {
    let name = entry.name;
    if (name.endsWith('.tpl')) name = name.slice(0, -4);
    name = replaceTokens(name, values);

    const source = path.join(sourceDir, entry.name);
    const target = path.join(targetDir, name);

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
    await fs.promises.access(target);
  } catch (error) {
    if (error?.code === 'ENOENT') return;

    throw new Error(`Cannot inspect target: ${target}`, { cause: error });
  }

  throw new Error(`Target already exists: ${target}`);
}

async function assertRendered(root) {
  const files = [];

  const visit = async (dir) => {
    const entries = await fs.promises.readdir(dir, { withFileTypes: true });

    for (const entry of entries) {
      const file = path.join(dir, entry.name);

      if (entry.isDirectory()) await visit(file);
      else files.push(file);
    }
  };

  await visit(root);

  for (const file of files) {
    const content = await fs.promises.readFile(file, 'utf8');

    if (/\{\{[A-Z0-9_]+\}\}|__[A-Z0-9_]+__/.test(content)
      || /__[A-Z0-9_]+__/.test(path.basename(file))) {
      throw new Error(`Template placeholder remains in ${path.relative(root, file)}.`);
    }
  }
}

async function writeJsonAtomic(file, value) {
  const temp = `${file}.${process.pid}.${Date.now()}.tmp`;

  try {
    await fs.promises.writeFile(temp, `${JSON.stringify(value, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' });
    await fs.promises.rename(temp, file);
  } finally {
    await fs.promises.rm(temp, { force: true });
  }
}

function setScriptIfAvailable(scripts, name, command) {
  if (scripts[name] !== undefined && scripts[name] !== command) {
    throw new Error(`package.json#scripts.${name} already exists; refusing to overwrite it.`);
  }
  scripts[name] = command;
}

async function addHarmonyToExisting(options, cwd, sdk, templates) {
  const target = path.resolve(cwd, options.target ?? '.');
  if (target === path.parse(target).root) throw new Error('Refusing to modify a filesystem root.');

  const packagePath = path.join(target, 'package.json');
  const configPath = path.join(target, 'expo-module.config.json');
  const pkg = await readJson(packagePath);
  const config = await readJson(configPath);

  if (!pkg) throw new Error(`Cannot add Harmony support: package.json is missing in ${target}.`);
  if (!config) throw new Error(`Cannot add Harmony support: expo-module.config.json is missing in ${target}.`);
  if (typeof pkg.version !== 'string' || pkg.version.length === 0) {
    throw new TypeError(`Cannot add Harmony support: package.json has no valid version in ${target}.`);
  }
  if (config.harmony !== undefined) {
    throw new Error('expo-module.config.json already declares harmony; refusing to overwrite it.');
  }

  await ensureAbsent(path.join(target, 'harmony'));

  const names = deriveNames(pkg.name);
  const staging = await fs.promises.mkdtemp(path.join(path.dirname(target), '.add-expo-harmony-module-'));
  let complete = false;

  try {
    await renderDirectory(
      path.join(templates, `standalone/sdk-${sdk.major}`),
      staging,
      replacements(names, sdk.major, pkg.version)
    );
    await assertRendered(staging);

    const generated = await readJson(path.join(staging, 'expo-module.config.json'));

    const scripts = { ...(pkg.scripts ?? {}) };
    setScriptIfAvailable(scripts, 'harmony:clean', 'expo-harmony-module prepare --clean-only');
    setScriptIfAvailable(scripts, 'harmony:build', 'expo-harmony-module prepare');
    setScriptIfAvailable(scripts, 'harmony:inspect', 'expo-harmony-module inspect');

    const nextPackage = {
      ...pkg,
      ...(Array.isArray(pkg.files)
        ? { files: [...new Set([
            ...pkg.files,
            'harmony/*.har',
            'harmony/library/oh-package.json5',
          ])] }
        : {}),
      scripts,
      peerDependencies: {
        ...(pkg.peerDependencies ?? {}),
        '@expo-harmony/expo-modules-core': pkg.peerDependencies?.['@expo-harmony/expo-modules-core']
          ?? '^55.0.25-harmony.0',
      },
      devDependencies: {
        ...(pkg.devDependencies ?? {}),
        '@expo-harmony/expo-module-scripts': pkg.devDependencies?.['@expo-harmony/expo-module-scripts']
          ?? '^55.0.0-harmony.0',
      },
    };
    const nextConfig = {
      ...config,
      platforms: [...new Set([...(Array.isArray(config.platforms) ? config.platforms : []), 'harmony'])],
      harmony: generated.harmony,
    };

    await fs.promises.cp(path.join(staging, 'harmony'), path.join(target, 'harmony'), {
      recursive: true,
      errorOnExist: true,
      force: false,
    });
    await writeJsonAtomic(configPath, nextConfig);
    await writeJsonAtomic(packagePath, nextPackage);

    complete = true;
  } finally {
    if (!complete) {
      await fs.promises.rm(path.join(target, 'harmony'), { recursive: true, force: true });
    }

    await fs.promises.rm(staging, { recursive: true, force: true });
  }

  return {
    target,
    appRoot: undefined,
    local: false,
    added: true,
    sdkMajor: sdk.major,
    sdkSource: sdk.source,
  };
}

export async function createModule(options) {
  const cwd = path.resolve(options.cwd ?? process.cwd());
  const local = options.local === true;
  const adding = options.addToExisting === true;

  if (local && adding) {
    throw new TypeError('--local and --add-to-existing cannot be combined.');
  }

  const appRoot = local ? await findAppRoot(cwd) : undefined;
  const sdk = options.sdkMajor
    ? { major: Number(options.sdkMajor), source: 'explicit' }
    : await detectExpoSdkMajor(cwd);

  if (sdk.major !== DEFAULT_SDK_MAJOR) {
    throw new Error(`Expo SDK ${sdk.major} is not supported; available template: SDK ${DEFAULT_SDK_MAJOR}.`);
  }

  const templates = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../templates');

  if (adding) {
    return addHarmonyToExisting(options, cwd, sdk, templates);
  }

  const names = deriveNames(options.name);
  const defaultPath = local
    ? path.join(appRoot, 'modules', names.packageBasename)
    : path.join(cwd, names.packageBasename);
  const target = path.resolve(options.target ?? defaultPath);

  if (target === path.parse(target).root) throw new Error('Refusing to generate into a filesystem root.');

  await ensureAbsent(target);
  await fs.promises.mkdir(path.dirname(target), { recursive: true });

  const staging = await fs.promises.mkdtemp(path.join(path.dirname(target), '.create-expo-harmony-module-'));
  const values = replacements(names, sdk.major);

  try {
    await renderDirectory(path.join(templates, `standalone/sdk-${sdk.major}`), staging, values);

    if (local) {
      await fs.promises.rm(path.join(staging, 'example'), { recursive: true, force: true });
      await fs.promises.rm(path.join(staging, '.npmignore'), { force: true });
      await renderDirectory(path.join(templates, `local/sdk-${sdk.major}`), staging, values);
    }

    await assertRendered(staging);
    await fs.promises.rename(staging, target);
  } finally {
    await fs.promises.rm(staging, { recursive: true, force: true });
  }

  return { target, appRoot, local, added: false, sdkMajor: sdk.major, sdkSource: sdk.source };
}

function parseCli(argv) {
  const options = { local: false, addToExisting: false };
  let name;

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];

    if (argument === '--local') options.local = true;
    else if (argument === '--add' || argument === '--add-to-existing') options.addToExisting = true;
    else if (argument === '--path') options.target = argv[++index];
    else if (argument === '--sdk') options.sdkMajor = Number(argv[++index]);
    else if (argument.startsWith('-')) throw new TypeError(`Unknown option: ${argument}`);
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
  if (argv.length === 0 || argv.includes('--help') || argv.includes('-h')) {
    process.stdout.write('Usage: create-expo-harmony-module <name> [--local] [--path <directory>] [--sdk 55]\n'
      + '       create-expo-harmony-module (--add | --add-to-existing) [--path <module-directory>] [--sdk 55]\n');
    return;
  }

  const result = await createModule(parseCli(argv));

  if (result.sdkSource === 'fallback') {
    process.stderr.write(`Expo SDK could not be detected; using SDK ${DEFAULT_SDK_MAJOR}.\n`);
  }

  process.stdout.write(result.added
    ? `Added Harmony support to Expo module at ${result.target}\n`
    : `Created ${result.local ? 'local' : 'standalone'} Harmony Expo module at ${result.target}\n`);
}

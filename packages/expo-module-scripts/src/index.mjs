import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import spawn from 'cross-spawn';

import { normalizeHarmonyModuleMetadata } from '@expo-harmony/expo-modules-autolinking';
import { resolveHarmonyCommand, terminateProcess } from '@expo-harmony/expo-modules-autolinking/tool-command';
import JSON5 from 'json5';
import { sanitizeHarmonyHar } from './har.mjs';
import { findWorkspacePackages, planWorkspaceBuild, workspaceOverrides, withWorkspaceOverrides } from './workspace.mjs';

const HARMONY_PROJECT = 'harmony';
const HARMONY_MODULE = 'library';
const HARMONY_PRODUCT = 'default';
const BUNDLED_HAR = 'harmony/library.har';
const OH_PACKAGE_MANIFEST = 'harmony/library/oh-package.json5';

async function fingerprint(project) {
  const hash = createHash('sha256');
  for (const file of ['package.json', 'harmony/oh-package.json5', 'harmony/library/oh-package.json5']) {
    hash.update(await fs.promises.readFile(path.join(project.packageRoot, file)));
  }
  hash.update(await fs.promises.readFile(project.bundledHar));
  return hash.digest('hex');
}

export async function writeBuildReceipt(file, projects) {
  const records = {};
  for (const project of projects) records[project.packageRoot] = await fingerprint(project);
  await fs.promises.writeFile(file, JSON.stringify(records));
}

// Only the release process passes this short-lived receipt to its pack children.
// A missing, changed or unrecorded artifact fails closed instead of rebuilding.
async function hasBuildReceipt(project) {
  const file = process.env.EXPO_HARMONY_BUILD_RECEIPT;
  if (!file) return false;
  const records = JSON.parse(await fs.promises.readFile(file, 'utf8'));
  if (records[project.packageRoot] !== await fingerprint(project)) {
    throw new Error(`Release build receipt does not match ${project.packageRoot}. Run release preparation again.`);
  }
  return true;
}

function requiredString(value, field) {
  if (typeof value !== 'string' || value.length === 0) throw new TypeError(`${field} is required.`);
  return value;
}

function normalizeConfig(raw, pkg) {
  if (!Array.isArray(raw?.platforms) || !raw.platforms.includes('harmony')) {
    throw new TypeError('expo-module.config.json#platforms must include harmony.');
  }

  const { modules, services } = normalizeHarmonyModuleMetadata(raw.harmony, {
    packageName: requiredString(pkg.name, 'package.json#name'),
    packageVersion: typeof pkg.version === 'string' ? pkg.version : undefined,
  });

  if (modules.length === 0 && services.length === 0) throw new TypeError('harmony.modules or harmony.services must declare at least one module or service.');

  return { modules, services };
}

async function readJson(file) {
  return JSON.parse(await fs.promises.readFile(file, 'utf8'));
}

function inside(root, relative, field) {
  const resolved = path.resolve(root, relative);
  const relation = path.relative(root, resolved);

  if (relation === '..' || relation.startsWith(`..${path.sep}`) || path.isAbsolute(relation)) {
    throw new TypeError(`${field} escapes the package root.`);
  }

  return resolved;
}

async function assertExistingAncestorInside(root, target, field) {
  let ancestor = target;
  while (!(await exists(ancestor))) {
    const parent = path.dirname(ancestor);
    if (parent === ancestor) throw new TypeError(`${field} has no package-contained parent.`);

    ancestor = parent;
  }

  const realAncestor = await fs.promises.realpath(ancestor);
  const relation = path.relative(root, realAncestor);

  if (relation === '..' || relation.startsWith(`..${path.sep}`) || path.isAbsolute(relation)) {
    throw new TypeError(`${field} resolves outside the package root through a symbolic link.`);
  }
}

function harmonyModuleName(packageRoot) {
  const projectRoot = path.join(packageRoot, HARMONY_PROJECT);
  const profilePath = path.join(projectRoot, 'build-profile.json5');
  if (!fs.existsSync(profilePath)) return HARMONY_MODULE;

  const profile = JSON5.parse(fs.readFileSync(profilePath, 'utf8'));
  const moduleRoot = path.join(projectRoot, HARMONY_MODULE);
  const module = profile.modules?.find(candidate =>
    typeof candidate?.srcPath === 'string' && path.resolve(projectRoot, candidate.srcPath) === moduleRoot
  );
  const name = requiredString(module?.name, 'harmony/build-profile.json5 module name');

  if (path.basename(name) !== name) throw new TypeError('Harmony module name must not contain a path.');

  return name;
}

function modulePaths(packageRoot, moduleName = harmonyModuleName(packageRoot)) {
  const projectRoot = inside(packageRoot, HARMONY_PROJECT, 'Harmony project');
  return {
    moduleName,
    projectRoot,
    moduleRoot: inside(projectRoot, HARMONY_MODULE, 'Harmony module'),
    sourceOutput: inside(projectRoot, `library/build/default/outputs/default/${moduleName}.har`, 'Hvigor HAR output'),
    bundledHar: inside(packageRoot, BUNDLED_HAR, 'Bundled HAR'),
    ohPackageManifest: inside(packageRoot, OH_PACKAGE_MANIFEST, 'OHPM package manifest'),
  };
}

async function loadBuildConfig(root, manifest) {
  const file = path.join(root, 'expo-module.config.json');
  if (await exists(file)) {
    return normalizeConfig(await readJson(file), manifest);
  }

  // RNOH runtime packages (including expo-modules-core) have no Expo module
  // registration. Keep their existing HAR filename and metadata contract.
  const linking = manifest.harmony?.autolinking;
  if (linking?.mainHarPath === 'harmony' && linking.ohPackageName === manifest.name) return { modules: [], services: [] };

  throw new TypeError(`${manifest.name} must declare an Expo Harmony module or a Harmony RNOH package.`);
}

function projectPaths(root, config) {
  const paths = modulePaths(root);
  if (config.modules.length === 0 && config.services.length === 0) {
    paths.bundledHar = inside(root, `harmony/${paths.moduleName}.har`, 'Bundled HAR');
  }
  return paths;
}

export async function loadModuleProject(root = process.cwd()) {
  const packageRoot = await fs.promises.realpath(path.resolve(root));
  const pkg = await readJson(path.join(packageRoot, 'package.json'));

  const config = await loadBuildConfig(packageRoot, pkg);
  const paths = projectPaths(packageRoot, config);

  await assertExistingAncestorInside(packageRoot, paths.projectRoot, 'Harmony project');
  const projectRoot = await fs.promises.realpath(paths.projectRoot);
  const modulePath = inside(projectRoot, HARMONY_MODULE, 'Harmony module');
  await assertExistingAncestorInside(packageRoot, modulePath, 'Harmony module');
  const moduleRoot = await fs.promises.realpath(modulePath);
  await assertExistingAncestorInside(packageRoot, paths.sourceOutput, 'Hvigor HAR output');
  await assertExistingAncestorInside(packageRoot, paths.bundledHar, 'Bundled HAR');
  await assertNonEmptyRegularFile(paths.ohPackageManifest, 'OHPM package manifest', moduleRoot);

  const library = JSON5.parse(await fs.promises.readFile(paths.ohPackageManifest, 'utf8'));
  const project = JSON5.parse(await fs.promises.readFile(path.join(projectRoot, 'oh-package.json5'), 'utf8'));

  return {
    packageRoot,
    packageJson: pkg,
    config,
    projectRoot,
    moduleRoot,
    moduleName: paths.moduleName,
    sourceOutput: paths.sourceOutput,
    bundledHar: paths.bundledHar,
    ohPackageManifest: paths.ohPackageManifest,
    ohPackage: library,
    ohProjectPackage: project,
  };
}

async function exists(file) {
  try {
    await fs.promises.access(file);
    return true;
  } catch {
    return false;
  }
}

export async function inspectModule(root = process.cwd()) {
  const packageRoot = await fs.promises.realpath(path.resolve(root));
  const pkg = await readJson(path.join(packageRoot, 'package.json'));

  const config = await loadBuildConfig(packageRoot, pkg);
  const paths = projectPaths(packageRoot, config);

  return {
    config,
    paths: {
      project: path.relative(packageRoot, paths.projectRoot).replace(/\\/g, '/'),
      module: path.relative(packageRoot, paths.moduleRoot).replace(/\\/g, '/'),
      output: path.relative(packageRoot, paths.sourceOutput).replace(/\\/g, '/'),
      bundledHar: path.relative(packageRoot, paths.bundledHar).replace(/\\/g, '/'),
      ohPackageManifest: path.relative(packageRoot, paths.ohPackageManifest).replace(/\\/g, '/'),
    },
  };
}

async function assertNonEmptyRegularFile(file, label, allowedRoot) {
  let stat;
  try {
    stat = await fs.promises.lstat(file);
  } catch (cause) {
    if (cause.code === 'ENOENT') throw new Error(`${label} is missing: ${file}`);

    throw new Error(cause instanceof Error ? cause.message : String(cause), { cause });
  }

  if (stat.isSymbolicLink()) throw new Error(`${label} must not be a symbolic link: ${file}`);
  if (!stat.isFile()) throw new Error(`${label} must be a regular file: ${file}`);
  if (stat.size === 0) throw new Error(`${label} must not be empty: ${file}`);

  if (allowedRoot) {
    const [realRoot, realFile] = await Promise.all([
      fs.promises.realpath(allowedRoot),
      fs.promises.realpath(file),
    ]);
    const relation = path.relative(realRoot, realFile);

    if (relation === '..' || relation.startsWith(`..${path.sep}`) || path.isAbsolute(relation)) {
      throw new Error(`${label} resolves outside its allowed root: ${file}`);
    }
  }
}

export function fixedHvigorArgs(task = 'assembleHar', moduleName = HARMONY_MODULE) {
  if (task !== 'assembleHar' && task !== 'clean') throw new TypeError(`Unsupported Hvigor task: ${task}`);

  return [
    '--mode', 'module',
    '-p', `module=${moduleName}@default`,
    '-p', `product=${HARMONY_PRODUCT}`,
    '-p', 'buildMode=release',
    '--no-daemon',
    task,
  ];
}

export function resolveModuleCommand(command, args, env = process.env) {
  return resolveHarmonyCommand(command, args, env);
}

function spawnCommand(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    if (options.signal?.aborted) {
      reject(options.signal.reason || new DOMException('This operation was aborted', 'AbortError'));
      return;
    }

    const invocation = resolveModuleCommand(command, args, process.env);
    const child = spawn(invocation.command, invocation.args, {
      cwd: options.cwd,
      env: process.env,
      shell: false,
      stdio: options.capture ? ['ignore', 'pipe', 'inherit'] : 'inherit',
    });

    let output = '';
    let failure;
    let stopping;
    let settled = false;
    let timer;

    const finish = async (code) => {
      try {
        await stopping;
      } catch (error) {
        failure = error;
      }

      if (settled) return;
      settled = true;
      clearTimeout(timer);
      options.signal?.removeEventListener('abort', abort);

      if (failure) reject(failure);
      else if (code === 0) resolve(output);
      else reject(new Error(`${invocation.command} exited with code ${code}.`));
    };

    const abort = () => {
      if (stopping || settled) return;

      failure = options.signal.reason || new DOMException('This operation was aborted', 'AbortError');
      stopping = Promise.resolve().then(() => terminateProcess(child, 'SIGTERM'));
      if (process.platform === 'win32') {
        void finish(null);
      } else {
        stopping.catch(() => {
          void finish(null);
        });
        timer = setTimeout(() => {
          stopping = terminateProcess(child, 'SIGKILL');
          stopping.catch(() => {
            void finish(null);
          });
        }, 1_000);
        timer.unref?.();
      }
    };

    child.stdout?.on('data', (chunk) => {
      output += chunk;
    });
    child.on('error', (error) => {
      failure = error;
      void finish(null);
    });

    // Wait for the aborted child to stop before restoring its OHPM inputs.
    child.on('close', (code) => {
      void finish(code);
    });
    options.signal?.addEventListener('abort', abort, { once: true });
    if (options.signal?.aborted) abort();
  });
}

async function publishBuiltHar(project, dependencies = []) {
  await assertNonEmptyRegularFile(project.sourceOutput, 'Hvigor HAR output', project.projectRoot);
  await assertExistingAncestorInside(project.packageRoot, project.bundledHar, 'Bundled HAR');

  const versions = Object.fromEntries(dependencies.map(dependency => [
    dependency.ohPackage.name, dependency.ohPackage.version,
  ]));
  const temp = `${project.bundledHar}.${process.pid}.${Date.now()}.tmp`;

  await fs.promises.mkdir(path.dirname(project.bundledHar), { recursive: true });

  try {
    await fs.promises.copyFile(project.sourceOutput, temp, fs.constants.COPYFILE_EXCL);
    await sanitizeHarmonyHar(temp, {
      sourceManifest: project.ohPackage,
      workspaceVersions: versions,
    });
    await fs.promises.rename(temp, project.bundledHar);
  } finally {
    await fs.promises.rm(temp, { force: true });
  }

  await assertNonEmptyRegularFile(project.bundledHar, 'Bundled HAR', project.packageRoot);
}

async function createWorkspaceBuild(root, options = {}) {
  root = await fs.promises.realpath(root);
  const workspace = await findWorkspacePackages(root);

  if (options.all && (!workspace || workspace.root !== root)) {
    throw new Error('build-workspace must run at a package.json workspace root.');
  }

  const projects = [];
  for (const directory of workspace?.packages || [root]) {
    if (await exists(path.join(directory, OH_PACKAGE_MANIFEST))) {
      projects.push(await loadModuleProject(directory));
    }
  }

  const targets = options.all
    ? projects.filter(project => !project.packageJson.private)
    : projects.filter(project => project.packageRoot === root);
  if (targets.length === 0) throw new Error(`No Harmony module projects found in ${root}.`);

  return planWorkspaceBuild(projects, targets).map(({ project, dependencies }) => {
    const install = { command: 'ohpm', args: ['install', '--all'], cwd: project.projectRoot };
    const build = { command: 'hvigorw', args: fixedHvigorArgs('assembleHar', project.moduleName), cwd: project.projectRoot };
    const clean = options.clean ? { ...build, args: fixedHvigorArgs('clean', project.moduleName) } : undefined;
    const overrides = workspaceOverrides(project, dependencies);

    return {
      project,
      dependencies,
      plan: { ...build, packageName: project.packageJson.name, install, clean, build, overrides },
    };
  });
}

async function executeWorkspaceBuild(entries) {
  for (const { project, dependencies, plan } of entries) {
    process.stdout.write(`[Harmony] Building ${project.packageJson.name}\n`);

    for (const dependency of dependencies) {
      await assertNonEmptyRegularFile(dependency.bundledHar, 'Workspace dependency HAR', dependency.packageRoot);
    }

    await withWorkspaceOverrides(project, plan.overrides, async (signal) => {
      const options = { cwd: project.projectRoot, signal };

      await spawnCommand(plan.install.command, plan.install.args, options);
      if (plan.clean) await spawnCommand(plan.clean.command, plan.clean.args, options);
      await spawnCommand(plan.build.command, plan.build.args, options);

      await publishBuiltHar(project, dependencies);
    });
  }
}

export async function buildWorkspace(root = process.cwd(), options = {}) {
  const entries = await createWorkspaceBuild(root, { all: true, clean: options.clean });
  if (!options.dryRun) await executeWorkspaceBuild(entries);
  return { builds: entries.map(entry => entry.plan) };
}

export async function prepareModule(root = process.cwd(), options = {}) {
  if (!options.cleanOnly) {
    if (!options.dryRun && await hasBuildReceipt(await loadModuleProject(root))) return { reused: true };
    const entries = await createWorkspaceBuild(root);

    if (!options.dryRun) await executeWorkspaceBuild(entries);

    return { ...entries.at(-1).plan, workspaceBuilds: entries.map(entry => entry.plan) };
  }

  const project = await loadModuleProject(root);
  const build = { command: 'hvigorw', args: fixedHvigorArgs('clean', project.moduleName), cwd: project.projectRoot };
  const plan = { ...build, build };

  if (options.dryRun) return plan;

  await spawnCommand(build.command, build.args, { cwd: build.cwd });

  return plan;
}

function allowedPackedFile(name, runtimeFiles) {
  return runtimeFiles.has(name)
    || name === 'package.json'
    || name === 'expo-module.config.json'
    || name === 'README.md'
    || name === 'LICENSE'
    || name === 'CHANGELOG.md'
    || name === 'app.plugin.js'
    || name === 'react-native.config.js'
    || /^(?:[^/]+\.)?podspec(?:\.json)?$/.test(name)
    || name.startsWith('build/')
    || name.startsWith('src/')
    || name.startsWith('ios/')
    || name.startsWith('android/')
    || name.startsWith('web/')
    || name.startsWith('plugin/')
    || name === BUNDLED_HAR
    || name === OH_PACKAGE_MANIFEST;
}

function packageFile(value, field) {
  const raw = requiredString(value, field).replace(/\\/g, '/');
  const normalized = path.posix.normalize(raw).replace(/^\.\//, '');

  if (path.posix.isAbsolute(normalized) || path.win32.isAbsolute(raw)
    || normalized === '..' || normalized.startsWith('../')) {
    throw new TypeError(`${field} must stay inside the package root.`);
  }

  return normalized;
}

export async function prepackModule(root = process.cwd(), options = {}) {
  const project = await loadModuleProject(root);
  const entries = await createWorkspaceBuild(root, { clean: true });

  const plan = {
    clean: { command: 'hvigorw', args: fixedHvigorArgs('clean', project.moduleName) },
    install: { command: 'ohpm', args: ['install', '--all'] },
    build: { command: 'hvigorw', args: fixedHvigorArgs('assembleHar', project.moduleName) },
    pack: { command: 'npm', args: ['pack', '--dry-run', '--json', '--ignore-scripts'] },
    workspaceBuilds: entries.map(entry => entry.plan),
  };

  if (options.dryRun) return plan;

  if (!await hasBuildReceipt(project)) await executeWorkspaceBuild(entries);

  const output = await spawnCommand(plan.pack.command, plan.pack.args, { cwd: project.packageRoot, capture: true });
  const result = JSON.parse(output);
  const files = result[0]?.files?.map(entry => entry.path) ?? [];
  const runtimeFiles = new Set([
    packageFile(project.packageJson.main, 'package.json#main'),
    packageFile(project.packageJson.types, 'package.json#types'),
  ]);
  const unexpected = files.filter(file => !allowedPackedFile(file, runtimeFiles));

  if (unexpected.length > 0) throw new Error(`npm pack contains unexpected files: ${unexpected.join(', ')}`);

  const required = [
    'package.json',
    'expo-module.config.json',
    ...runtimeFiles,
    BUNDLED_HAR,
    OH_PACKAGE_MANIFEST,
  ].filter(Boolean);
  const missing = [...new Set(required)].filter(file => !files.includes(file));

  if (missing.length > 0) throw new Error(`npm pack is missing required runtime files: ${missing.join(', ')}`);

  return { files };
}

function parseCli(argv) {
  const command = argv[0];
  const options = { root: process.cwd(), dryRun: false, json: false, cleanOnly: false };

  for (let index = 1; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--dry-run') options.dryRun = true;
    else if (arg === '--json') options.json = true;
    else if (arg === '--clean-only') options.cleanOnly = true;
    else if (arg === '--root') options.root = argv[++index];
    else throw new TypeError(`Unknown option: ${arg}`);
  }

  return { command, options };
}

export async function runCli(argv) {
  if (argv.length === 0 || argv.includes('--help') || argv.includes('-h')) {
    process.stdout.write('Usage: expo-harmony-module <inspect|prepare|prepack|build-workspace> [--root <path>] [--json] [--dry-run]\n');
    return;
  }

  const { command, options } = parseCli(argv);

  if (options.cleanOnly && command !== 'prepare') {
    throw new TypeError('--clean-only is only valid with prepare.');
  }
  if (options.dryRun && command === 'inspect') {
    throw new TypeError('--dry-run is not valid with inspect.');
  }

  let result;
  if (command === 'inspect') result = await inspectModule(options.root);
  else if (command === 'prepare') result = await prepareModule(options.root, options);
  else if (command === 'prepack') result = await prepackModule(options.root, options);
  else if (command === 'build-workspace') result = await buildWorkspace(options.root, options);
  else throw new TypeError(`Unknown command: ${command}`);

  if (options.json || options.dryRun || command === 'inspect') {
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  }
}

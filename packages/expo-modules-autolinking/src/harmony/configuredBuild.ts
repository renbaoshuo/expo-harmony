/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import JSON5 from 'json5';

import type { LinkOptions, ModuleDescriptor } from '../types';
import { readModuleBuildOptionsAsync } from '../config/options';
import { HarmonyAutolinkingError } from '../errors';
import { isPathInside, resolveInsideAsync } from '../utilities/values';
import { resolveBuildOhpmDependencies } from './ohpm/dependencies';
import { sanitizeHarmonyHar } from './har';
import { createFixedHvigorBuildDescriptor, findHarmonyLibrary, fixedLocalSourceBuildSteps, isNonEmptyRegularHarAsync, runFixedBuildStepAsync } from './materialize';
import { publishArtifactsAsync } from './transaction/publish';

const Ignored = new Set(['.git', '.hvigor', '.cxx', '.native-build', 'native-deps', 'build', 'node_modules', 'oh_modules', 'local.properties', 'oh-package-lock.json5', 'BuildProfile.ets']);
type ConfiguredBuildOptions = Pick<LinkOptions,
  'projectRoot' | 'buildType' | 'moduleBuilds' | 'moduleBuildSettings' | 'env' | 'timeoutMs' | 'outputLimit'>;

async function readBuildInputs(options: ConfiguredBuildOptions) {
  if (options.moduleBuilds !== undefined) return options;

  const saved = await readModuleBuildOptionsAsync(options.projectRoot, 'configured-module-build');
  return saved ? { ...options, moduleBuilds: saved.moduleBuilds, moduleBuildSettings: saved.moduleBuildSettings } : options;
}

async function hashTree(
  hash: ReturnType<typeof crypto.createHash>, dir: string, depth = Infinity, metadataOnly = false
) {
  for (const entry of (await fs.readdir(dir, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name, 'en'))) {
    if (Ignored.has(entry.name) || entry.name.endsWith('.har')) continue;
    const file = path.join(dir, entry.name);
    if (entry.isDirectory() && depth > 0) {
      hash.update(entry.name + '/');
      await hashTree(hash, file, depth - 1, metadataOnly);
    } else if (entry.isFile() && (!metadataOnly || /(?:package|sdk-pkg)\.json$/u.test(entry.name))) {
      hash.update(entry.name + '\0').update(new Uint8Array(await fs.readFile(file)));
    }
  }
}

async function buildFingerprint(project: string, dependencies: ReturnType<typeof resolveBuildOhpmDependencies>, options: ConfiguredBuildOptions) {
  const hash = crypto.createHash('sha256');

  hash.update(new Uint8Array(await fs.readFile(__filename)));
  hash.update(JSON.stringify([options.buildType, options.moduleBuildSettings]));
  await hashTree(hash, project);

  for (const [name, specifier] of Object.entries(dependencies.overrides)) {
    hash.update(JSON.stringify([name, dependencies.versions[name]]));
    hash.update(new Uint8Array(await fs.readFile(specifier.slice('file:'.length))));
  }

  const env = { ...process.env, ...options.env };
  for (const key of Object.keys(env).sort()) {
    if (/^(HARMONY_|DEVECO_|OHOS_)|^(PATH|CC|CXX|CFLAGS|CXXFLAGS|LDFLAGS)$/u.test(key)) hash.update(key + '=' + env[key]);
  }

  if (!env.DEVECO_SDK_HOME || !env.HARMONY_HVIGORW || !env.HARMONY_OHPM) return null;

  await hashTree(hash, env.DEVECO_SDK_HOME, 3, true);
  for (const tool of [env.HARMONY_HVIGORW, env.HARMONY_OHPM]) {
    hash.update(new Uint8Array(await fs.readFile(tool)));
    const manifest = path.resolve(path.dirname(tool), '../package.json');
    try {
      hash.update(new Uint8Array(await fs.readFile(manifest)));
    } catch (error) {
      if (error.code !== 'ENOENT') {
        throw new HarmonyAutolinkingError('INVALID_OPTIONS', `Cannot read build tool metadata: ${manifest}`, {
          cause: error,
          stage: 'configured-module-build',
        });
      }
    }
  }

  return hash.digest('hex');
}

export async function buildConfiguredModulesAsync(
  modules: ReadonlyArray<ModuleDescriptor>, raw: ConfiguredBuildOptions
): Promise<ReadonlyArray<ModuleDescriptor>> {
  const options = await readBuildInputs(raw);
  const builds = options.moduleBuilds ?? {};
  if (!builds || typeof builds !== 'object' || Array.isArray(builds)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'moduleBuilds must be an object.', {
      stage: 'configured-module-build',
    });
  }

  const linked = [...modules];

  for (const name of Object.keys(builds).sort()) {
    const index = linked.findIndex(item => item.packageName === name);
    if (index < 0) {
      throw new HarmonyAutolinkingError('INVALID_OPTIONS', `Configured native module ${name} is not linked. Install it or remove its config plugin.`, {
        stage: 'configured-module-build',
      });
    }

    const item = linked[index];
    const file = item.harmony.buildOptionsFile;
    if (!item.arkTs || !file) {
      throw new HarmonyAutolinkingError('INVALID_OPTIONS', `${name} does not declare harmony.buildOptionsFile.`, {
        stage: 'configured-module-build',
      });
    }

    const source = await resolveInsideAsync(item.packageRoot, 'harmony', 'Harmony source project', { packageName: name, type: 'directory' });
    const defaultsFile = await resolveInsideAsync(source, file, 'Harmony build options', { packageName: name, type: 'file' });
    const defaults = JSON.parse(await fs.readFile(defaultsFile, 'utf8'));

    const selected = builds[name];
    if (!selected || typeof selected !== 'object' || Array.isArray(selected)) {
      throw new HarmonyAutolinkingError('INVALID_OPTIONS', `Build options for ${name} must be an object.`, {
        stage: 'configured-module-build',
      });
    }

    for (const [key, value] of Object.entries(selected)) {
      if (!Object.hasOwn(defaults, key) || !['boolean', 'string', 'number'].includes(typeof value)
        || typeof value !== typeof defaults[key] || (typeof value === 'number' && !Number.isFinite(value))) {
        throw new HarmonyAutolinkingError('INVALID_OPTIONS', `Invalid build option ${name}.${key}.`, {
          stage: 'configured-module-build',
        });
      }
    }

    const root = await fs.realpath(options.projectRoot);
    const cache = await resolveInsideAsync(root, '.expo/harmony/module-builds', 'Module build directory', { mustExist: false });
    let dir = root;

    for (const segment of ['.expo', 'harmony', 'module-builds']) {
      dir = path.join(dir, segment);
      try {
        await fs.mkdir(dir);
      } catch (error) {
        if (error.code !== 'EEXIST') {
          throw new HarmonyAutolinkingError('INVALID_OPTIONS', `Cannot create module build directory: ${dir}`, {
            cause: error,
            stage: 'configured-module-build',
          });
        }
      }

      const stat = await fs.lstat(dir);
      if (!stat.isDirectory() || stat.isSymbolicLink()) {
        throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'Module build directory must not be a symbolic link.', {
          stage: 'configured-module-build',
        });
      }
    }

    const temp = await fs.mkdtemp(path.join(cache, 'build-'));
    const project = path.join(temp, 'harmony');

    try {
      await fs.cp(source, project, {
        recursive: true,
        dereference: true,
        filter: async (entry) => {
          if (Ignored.has(path.basename(entry)) || entry.endsWith('.har')) return false;
          if (!isPathInside(item.packageRoot, await fs.realpath(entry))) {
            throw new HarmonyAutolinkingError('INVALID_OPTIONS', `Harmony source link escapes ${name}: ${path.relative(source, entry)}`, {
              stage: 'configured-module-build',
            });
          }

          return true;
        },
      });

      await fs.writeFile(path.join(project, file), JSON.stringify({ ...defaults, ...selected }, null, 2) + '\n');

      const profileFile = path.join(project, 'build-profile.json5');
      const profile = JSON5.parse(await fs.readFile(profileFile, 'utf8'));
      const library = findHarmonyLibrary(profile, name, 'configured-module-build');
      const product = Array.isArray(profile.app?.products) && profile.app.products.find(entry => entry?.name === 'default');
      if (!product) {
        throw new HarmonyAutolinkingError('INVALID_OPTIONS', `${name} must declare a default product in harmony/build-profile.json5.`, {
          stage: 'configured-module-build',
        });
      }

      const settings = options.moduleBuildSettings;
      if (settings) {
        if (!Array.isArray(settings.abiFilters)
          || settings.abiFilters.some(abi => typeof abi !== 'string' || !abi)
          || ![settings.compatibleSdkVersion, settings.targetSdkVersion].every(value => typeof value === 'string' && value.length > 0)) {
          throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'Invalid moduleBuildSettings; run Harmony prebuild again.', {
            stage: 'configured-module-build',
          });
        }

        product.compatibleSdkVersion = settings.compatibleSdkVersion;
        product.targetSdkVersion = settings.targetSdkVersion;

        const file = path.join(project, 'library/build-profile.json5');
        const build = JSON5.parse(await fs.readFile(file, 'utf8'));
        if (build.buildOption?.externalNativeOptions) {
          build.buildOption.externalNativeOptions.abiFilters = settings.abiFilters;
        }

        await fs.writeFile(file, JSON.stringify(build, null, 2) + '\n');
      }

      await fs.writeFile(profileFile, JSON.stringify(profile, null, 2) + '\n');

      const deps = linked.filter(module => module.packageName !== name);
      const dependencies = resolveBuildOhpmDependencies(deps);
      const key = await buildFingerprint(project, dependencies, options);
      const cached = key ? path.join(cache, `${key}.har`) : null;
      if (cached && await isNonEmptyRegularHarAsync(cached, cache, name)) {
        try {
          const expected = JSON.parse(await fs.readFile(cached + '.json', 'utf8')).sha256;
          const actual = crypto.createHash('sha256').update(new Uint8Array(await fs.readFile(cached))).digest('hex');
          if (expected === actual) {
            linked[index] = { ...item, arkTs: { ...item.arkTs, builtHarPath: cached } };
            continue;
          }
        } catch (error) {
          if (error.code !== 'ENOENT' && !(error instanceof SyntaxError)) {
            throw new HarmonyAutolinkingError('INVALID_OPTIONS', `Cannot inspect cached HAR for ${name}.`, {
              cause: error,
              stage: 'configured-module-build',
            });
          }
        }
      }

      const manifestPath = path.join(project, 'oh-package.json5');
      const manifest = JSON5.parse(await fs.readFile(manifestPath, 'utf8'));
      const { overrides, versions } = dependencies;

      await fs.writeFile(manifestPath, JSON.stringify({ ...manifest, overrides: { ...manifest.overrides, ...overrides } }, null, 2) + '\n');

      const build = createFixedHvigorBuildDescriptor(project, options.buildType ?? 'debug', library.name);
      for (const step of fixedLocalSourceBuildSteps(build)) await runFixedBuildStepAsync(step, name, options);

      const output = path.join(project, library.output);
      if (!await isNonEmptyRegularHarAsync(output, project, name)) {
        throw new HarmonyAutolinkingError('INVALID_OPTIONS', `${name}: Hvigor did not produce a HAR.`, {
          stage: 'configured-module-build',
        });
      }

      const sourceManifest = JSON5.parse(await fs.readFile(path.join(project, 'library/oh-package.json5'), 'utf8'));
      await sanitizeHarmonyHar(output, { sourceManifest, workspaceVersions: versions });

      const digest = crypto.createHash('sha256').update(new Uint8Array(await fs.readFile(output))).digest('hex');
      const target = cached || path.join(cache, `${digest}.har`);
      await publishArtifactsAsync({
        allowedRoot: root, lockPath: path.join(cache, 'publish.lock'), files: [{ source: output, target }, { content: JSON.stringify({ sha256: digest }) + '\n', target: target + '.json' }],
      });

      linked[index] = { ...item, arkTs: { ...item.arkTs, builtHarPath: target } };
    } finally {
      await fs.rm(temp, { recursive: true, force: true });
    }
  }

  return linked;
}

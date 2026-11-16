/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

import glob from 'fast-glob';
import JSON5 from 'json5';
import semver from 'semver';

const sections = ['dependencies', 'devDependencies', 'dynamicDependencies'];

async function readOptional(file) {
  try {
    return await fs.readFile(file);
  } catch (cause) {
    if (cause.code === 'ENOENT') return undefined;

    throw cause;
  }
}

export async function findWorkspacePackages(root) {
  root = await fs.realpath(root);

  for (let directory = root; ; directory = path.dirname(directory)) {
    const source = await readOptional(path.join(directory, 'package.json'));
    const manifest = source && JSON.parse(source);
    const patterns = Array.isArray(manifest?.workspaces) ? manifest.workspaces : manifest?.workspaces?.packages;

    if (Array.isArray(patterns)) {
      const files = await glob(patterns.map(pattern => `${pattern.replace(/\/$/u, '')}/package.json`), {
        cwd: directory,
        absolute: true,
        onlyFiles: true,
        followSymbolicLinks: false,
        ignore: ['**/node_modules/**'],
      });
      const roots = await Promise.all(files.map(file => fs.realpath(path.dirname(file))));

      const packages = [...new Set(roots)].sort();
      if (directory === root || packages.includes(root)) return { root: directory, packages };
    }

    if (path.dirname(directory) === directory) return undefined;
  }
}

// Native manifests, rather than the JS dependency graph, determine HAR build order.
export function planWorkspaceBuild(projects, targets) {
  const registry = new Map();
  for (const project of projects) {
    const { name, version } = project.ohPackage;

    if (name !== project.packageJson.name || version !== project.packageJson.version || !semver.valid(version)) {
      throw new Error(`${project.packageRoot}: npm and OHPM package names and versions must match.`);
    }
    if (registry.has(name)) throw new Error(`Duplicate workspace OHPM package: ${name}.`);

    registry.set(name, project);
  }

  const ordered = new Map();
  const visiting = [];

  function visit(project) {
    const name = project.ohPackage.name;
    if (ordered.has(name)) return ordered.get(name);
    if (visiting.includes(name)) throw new Error(`Circular Harmony workspace dependency: ${[...visiting, name].join(' -> ')}.`);

    visiting.push(name);
    const dependencies = new Map();
    const declarations = [
      ...sections.flatMap(section => Object.entries(project.ohPackage[section] || {})),
      ...sections.flatMap(section => Object.entries(project.ohProjectPackage[section] || {})
        .filter(([dependency]) => dependency !== name)),
      ...Object.entries(project.ohProjectPackage.overrides || {}).filter(([dependency]) => dependency !== name),
    ];

    for (const [target, range] of declarations) {
      const dependency = registry.get(target);
      if (!dependency) continue;

      if (typeof range !== 'string' || !semver.validRange(range) || !semver.satisfies(dependency.ohPackage.version, range)) {
        throw new Error(`${name} requires ${target}@${range}, but the workspace contains ${dependency.ohPackage.version}. Update the native dependency before building.`);
      }

      const entry = visit(dependency);
      for (const transitive of entry.dependencies) dependencies.set(transitive.ohPackage.name, transitive);
      dependencies.set(target, dependency);
    }

    visiting.pop();
    const entry = { project, dependencies: [...dependencies.values()] };
    ordered.set(name, entry);

    return entry;
  }

  for (const target of targets) visit(target);

  return [...ordered.values()];
}

export function workspaceOverrides(project, dependencies) {
  return Object.fromEntries(dependencies.map(dependency => [
    dependency.ohPackage.name,
    `file:${path.relative(project.projectRoot, dependency.bundledHar).replace(/\\/gu, '/')}`,
  ]));
}

async function snapshotBuildInput(file) {
  const stat = await fs.lstat(file).catch((error) => {
    if (error.code === 'ENOENT') return undefined;
    throw error;
  });
  if (!stat) return { file };
  if (!stat.isFile()) throw new Error(`OHPM build input must be a regular file: ${file}`);

  return { file, source: await fs.readFile(file), mode: stat.mode & 0o777 };
}

async function replaceBuildInput(file, source, mode) {
  if (source === undefined) {
    await fs.rm(file, { force: true });
    return;
  }

  const temporary = `${file}.${randomUUID()}.tmp`;
  try {
    await fs.writeFile(temporary, source, { flag: 'wx' });
    await fs.chmod(temporary, mode);
    await fs.rename(temporary, file);
  } finally {
    await fs.rm(temporary, { force: true });
  }
}

export async function withWorkspaceOverrides(project, overrides, build) {
  const lock = path.join(project.projectRoot, '.expo-harmony-build.lock');
  const backups = path.join(lock, 'inputs');
  try {
    await fs.mkdir(lock);
  } catch (cause) {
    if (cause.code === 'EEXIST') {
      throw new Error(`Harmony build already locked: ${lock}. If the previous process stopped, restore any OHPM inputs saved in ${backups} before removing the lock.`);
    }

    return Promise.reject(cause);
  }

  let snapshots = [];
  let result;
  let failure;
  const cleanupErrors = [];
  const controller = new globalThis.AbortController();
  const { signal } = controller;
  const interrupt = () => controller.abort();

  process.on('SIGINT', interrupt);
  process.on('SIGTERM', interrupt);

  try {
    if (Object.keys(overrides).length > 0) {
      const moduleLock = path.join(project.moduleRoot, 'oh-package-lock.json5');
      const files = [
        path.join(project.projectRoot, 'oh-package.json5'),
        path.join(project.projectRoot, 'oh-package-lock.json5'),
        moduleLock,
      ];

      const inputs = await Promise.all(files.map(snapshotBuildInput));
      const [input] = inputs;
      if (!input.source) throw new Error(`OHPM project manifest is missing: ${input.file}`);

      const manifest = JSON5.parse(input.source.toString());
      manifest.overrides = { ...manifest.overrides, ...overrides };

      const staging = `${backups}.tmp`;
      for (const { file, source, mode } of inputs) {
        if (source === undefined) continue;

        const directory = file === moduleLock ? path.join(staging, 'library') : staging;
        const backup = path.join(directory, path.basename(file));
        await fs.mkdir(path.dirname(backup), { recursive: true });
        await replaceBuildInput(backup, source, mode);
      }

      await fs.rename(staging, backups);
      snapshots = inputs;
      await replaceBuildInput(input.file, `${JSON5.stringify(manifest, null, 2)}\n`, input.mode);

      // A rebuilt HAR can retain its version and path, so invalidate the old resolution.
      for (const target of files.slice(1)) await fs.rm(target, { force: true });
    }

    if (signal.aborted) throw new globalThis.DOMException('This operation was aborted', 'AbortError');

    result = await build(signal);

    if (signal.aborted) throw new globalThis.DOMException('This operation was aborted', 'AbortError');
  } catch (error) {
    failure = error instanceof Error ? error : new Error(String(error), { cause: error });
  } finally {
    for (const { file, source, mode } of snapshots) {
      await replaceBuildInput(file, source, mode).catch(error => cleanupErrors.push(error));
    }

    if (cleanupErrors.length === 0) {
      await fs.rm(lock, { recursive: true, force: true }).catch(error => cleanupErrors.push(error));
    }

    process.removeListener('SIGINT', interrupt);
    process.removeListener('SIGTERM', interrupt);
  }
  if (cleanupErrors.length > 0) {
    const errors = failure ? [failure, ...cleanupErrors] : cleanupErrors;
    throw new AggregateError(errors, `Could not clean up Harmony build inputs in ${project.projectRoot}. Recovery files are kept in ${lock}: ${errors.map(error => error.message).join('. ')}`);
  }

  if (failure) return Promise.reject(failure);

  return result;
}

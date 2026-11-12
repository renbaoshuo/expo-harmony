/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { TextDecoder } from 'node:util';
import { applyPatch, parsePatch } from 'diff';

const utf8 = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });

async function patchPath(root, name) {
  if (name === '/dev/null') return null;

  const relative = name?.replace(/^[ab]\//u, '');
  if (!relative || relative.includes('\\') || relative.includes('\0')
    || path.posix.isAbsolute(relative) || path.win32.isAbsolute(relative)
    || relative.split('/').some(part => !part || part === '.' || part === '..')) {
    throw new Error(`Invalid patch path: ${name}`);
  }

  let current = root;
  for (const part of relative.split('/')) {
    current = path.join(current, part);
    const stat = await fs.lstat(current).catch((error) => {
      if (error.code === 'ENOENT') return undefined;
      throw error;
    });
    if (stat?.isSymbolicLink()) throw new Error(`Patch paths cannot contain symlinks: ${name}`);
  }
  return relative;
}

async function writeFileState(file, state, parents) {
  if (state === undefined) {
    await fs.rm(file, { force: true });
    return;
  }

  const parent = path.dirname(file);

  const created = await fs.mkdir(parent, { recursive: true });
  if (created && parents) {
    const directories = [];
    for (let directory = parent; ; directory = path.dirname(directory)) {
      directories.push(directory);
      if (directory === created) break;
    }
    parents.push(...directories.reverse());
  }
  const temporary = `${file}.${randomUUID()}.tmp`;
  try {
    await fs.writeFile(temporary, state.contents, { flag: 'wx' });
    // Opening a new file applies the current umask, including when replacing a file.
    if (state.mode !== undefined) await fs.chmod(temporary, state.mode);
    await fs.rename(temporary, file);
  } finally {
    await fs.rm(temporary, { force: true });
  }
}

export async function applyPatchFile({ root, patchFile, dryRun = false }) {
  const directory = await fs.realpath(root);
  const patches = parsePatch(utf8.decode(await fs.readFile(patchFile)));
  if (patches.length === 0) throw new Error(`No file changes found in ${patchFile}.`);

  const originals = new Map();
  const changes = new Map();

  async function read(relative) {
    if (changes.has(relative)) return changes.get(relative);

    if (!originals.has(relative)) {
      const file = path.join(directory, relative);
      const stat = await fs.stat(file).catch((error) => {
        if (error.code === 'ENOENT') return undefined;
        throw error;
      });
      if (stat && !stat.isFile()) throw new Error(`Patch target must be a regular file: ${relative}`);

      const original = stat ? { contents: utf8.decode(await fs.readFile(file)), mode: stat.mode & 0o777 } : undefined;
      originals.set(relative, original);
    }

    return originals.get(relative);
  }

  for (const patch of patches) {
    const oldPath = await patchPath(directory, patch.oldFileName);
    const newPath = await patchPath(directory, patch.newFileName);
    if (oldPath === null && newPath === null) throw new Error('A patch must name a source or destination file.');

    const original = oldPath === null ? undefined : await read(oldPath);
    if (oldPath !== null && original === undefined) throw new Error(`Patch source does not exist: ${oldPath}`);
    if (newPath !== null && newPath !== oldPath && await read(newPath) !== undefined) {
      throw new Error(`Patch destination already exists: ${newPath}`);
    }

    const contents = applyPatch(original?.contents ?? '', patch, { fuzzFactor: 0 });
    if (contents === false) throw new Error(`Could not apply ${patchFile} to ${oldPath ?? newPath}.`);
    if (newPath === null && contents !== '') throw new Error(`Deletion patch leaves content in ${oldPath}.`);

    if (oldPath !== null && oldPath !== newPath) changes.set(oldPath, undefined);
    if (newPath !== null) changes.set(newPath, { contents, mode: original?.mode });
  }

  const files = [...changes].map(([file, state]) => ({
    path: file,
    action: state === undefined ? 'delete' : originals.get(file) === undefined ? 'add' : 'modify',
  }));
  if (dryRun) return { files };

  const written = [];
  const parents = [];
  try {
    for (const [relative, state] of changes) {
      await writeFileState(path.join(directory, relative), state, parents);
      written.push(relative);
    }
  } catch (error) {
    const failures = [];
    for (const relative of written.reverse()) {
      const file = path.join(directory, relative);
      await writeFileState(file, originals.get(relative)).catch(cause => failures.push(cause));
    }
    for (const parent of parents.reverse()) {
      await fs.rmdir(parent).catch(cause => failures.push(cause));
    }
    if (failures.length > 0) {
      throw new AggregateError([error, ...failures], `Failed to roll back ${patchFile}: ${error.message}`);
    }

    throw error;
  }
  return { files };
}

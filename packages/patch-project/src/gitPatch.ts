/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import type { Stats } from 'node:fs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';

import { HarmonyPaths } from '@expo-harmony/config-plugins';
import { canonicalizeAutolinkingArtifacts } from '@expo-harmony/expo-modules-autolinking';

import { HarmonyPatchError } from './errors';

const exec = promisify(execFile);

function isProjectPath(relative: string): boolean {
  // eslint-disable-next-line no-control-regex -- Control characters are invalid native patch paths.
  return !!relative && !relative.includes('\\') && !/[\x00-\x1f\x7f]/u.test(relative)
    && !relative.split('/').some(part => !part || part === '.' || part === '..' || part.toLowerCase() === '.git')
    && !/^[A-Za-z]:/u.test(relative);
}

async function lstatIfExists(file: string): Promise<Stats | undefined> {
  try {
    return await fs.lstat(file);
  } catch (cause) {
    if (cause.code !== 'ENOENT') throw cause;
  }
}

async function resolvePatchPath(root: string, relative: string): Promise<string> {
  const directory = path.dirname(path.join(root, relative));
  let parent = root;

  for (const part of path.relative(root, directory).split(path.sep).filter(Boolean)) {
    parent = path.join(parent, part);
    const stat = await lstatIfExists(parent);
    if (!stat) break;
    if (!stat.isDirectory()) {
      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch parent must be a directory: ${parent}.`);
    }
  }

  return path.join(root, relative);
}

function resolveLinkPath(root: string, relative: string, link: string): string {
  const resolved = path.resolve(root, path.dirname(relative), link);
  const target = HarmonyPaths.toPosixRelative(root, resolved);
  const normalized = path.posix.relative(path.posix.dirname(relative), target);
  if (!isProjectPath(target) || link.replace(/^(?:\.\/)+/u, '') !== normalized) {
    throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch symlink must point inside the Harmony project: ${relative}.`);
  }

  return target;
}

async function validatePatchLink(
  root: string,
  file: string,
  resolveFile: (relative: string) => Promise<string | undefined>
): Promise<void> {
  const links = new Set<string>();
  let relative = file;

  while (!links.has(relative)) {
    const source = await resolveFile(relative);
    const stat = source ? await lstatIfExists(source) : undefined;
    if (stat?.isFile()) return;
    if (!stat?.isSymbolicLink()) break;

    links.add(relative);
    relative = resolveLinkPath(root, relative, await fs.readlink(source));
  }

  // The CNG manifest hashes managed files and requires a link to resolve to one.
  throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch symlink must point to a file: ${file}.`);
}

async function git(cwd: string, args: string[]): Promise<string> {
  // Ambient Git overrides must not redirect commands outside the staging repository.
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_')));

  try {
    return (await exec('git', [
      '-c', 'core.autocrlf=false', '-c', 'core.quotePath=false', '-c', 'core.fileMode=true',
      '-c', 'core.protectHFS=true', '-c', 'core.protectNTFS=true', ...args,
    ], {
      cwd,
      env: { ...env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: process.platform === 'win32' ? 'NUL' : '/dev/null' },
      maxBuffer: 64 * 1024 * 1024,
    })).stdout;
  } catch (cause) {
    throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Git patch operation failed: ${cause.stderr || cause.message}`, { cause, operation: 'patch-project' });
  }
}

async function listFiles(source: string): Promise<string[]> {
  const staging = await fs.mkdtemp(path.join(os.tmpdir(), 'harmony-patch-files-'));
  try {
    await git(staging, ['init', '--quiet', '--bare']);
    const output = await git(staging, [`--work-tree=${path.resolve(source)}`, 'ls-files', '--others', '--exclude-standard', '-z']);

    return output.split('\0').filter(Boolean);
  } finally {
    await fs.rm(staging, { recursive: true, force: true });
  }
}

async function snapshot(source: string, target: string, files: string[]): Promise<void> {
  await fs.mkdir(target, { recursive: true });

  for (const name of files) {
    if (!isProjectPath(name)) throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Invalid native patch path: ${name}.`);

    const from = await resolvePatchPath(source, name);
    const to = path.join(target, name);
    const stat = await lstatIfExists(from);
    if (!stat) continue;
    if (!stat.isFile() && !stat.isSymbolicLink()) throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch source must be a file: ${from}.`);
    await fs.mkdir(path.dirname(to), { recursive: true });
    await fs.cp(from, to, { verbatimSymlinks: true });
  }
}

async function getPatchStatsAsync(
  root: string, patch: string, reverse = false
): Promise<{ files: string[]; changedLines: number }> {
  const stats = await git(root, ['apply', '--numstat', '-z', ...(reverse ? ['--reverse'] : []), patch]);
  let changedLines = 0;
  const files = stats.split('\0').filter(Boolean).map((row) => {
    const match = /^(\d+|-)\t(\d+|-)\tharmony\/([\s\S]+)$/u.exec(row);
    if (!match || !isProjectPath(match[3])) {
      throw new HarmonyPatchError(
        'ERR_HARMONY_PATCH_FAILED',
        'Patch paths must remain inside the Harmony project and cannot modify Git metadata.'
      );
    }

    changedLines += (Number(match[1]) || 0) + (Number(match[2]) || 0);
    return match[3];
  });

  return { files, changedLines };
}

export async function generatePatchAsync(baseline: string, current: string): Promise<Buffer> {
  const staging = await fs.mkdtemp(path.join(os.tmpdir(), 'harmony-patch-diff-'));
  try {
    await git(staging, ['init', '--quiet']);
    const native = path.join(staging, 'harmony');
    const files = await listFiles(baseline);
    await snapshot(baseline, native, files);

    // Temporary dependency paths must not appear in patches.
    const root = await fs.realpath(path.dirname(baseline));
    const file = path.join(root, '.expo/harmony/autolinking.json');
    let manifest: string | undefined;
    try {
      manifest = await fs.readFile(file, 'utf8');
    } catch (cause) {
      if (cause.code !== 'ENOENT') {
        throw new HarmonyPatchError(
          cause.code || 'ERR_HARMONY_PATCH_FAILED',
          cause.message || `Cannot read autolinking manifest ${file}.`,
          { cause, file, operation: 'patch-project' }
        );
      }
    }

    if (manifest) {
      const file = path.join(native, HarmonyPaths.HARMONY_PATHS.rootOhPackage);
      if (!(await lstatIfExists(file))?.isFile()) {
        throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch baseline must contain a regular file: ${file}.`);
      }

      const canonical = canonicalizeAutolinkingArtifacts({
        manifestSource: manifest,
        ohPackageSource: await fs.readFile(file, 'utf8'),
        generatedProjectRoot: root,
        canonicalProjectRoot: await fs.realpath(path.dirname(current)),
        harmonyProjectPath: await fs.realpath(current),
      });
      await fs.writeFile(file, canonical.ohPackageSource);
    }

    await git(staging, ['add', '-f', '--all', '--', 'harmony']);
    await fs.rm(native, { recursive: true });
    await snapshot(current, native, [...new Set([...files, ...await listFiles(current)])]);

    // Intent-to-add includes new text and binary files without changing baseline entries.
    const untracked = (await git(staging, ['ls-files', '--others', '-z', '--', 'harmony'])).split('\0').filter(Boolean);
    if (untracked.length) await git(staging, ['add', '-f', '-N', '--', ...untracked]);

    const patch = path.join(staging, 'changes.patch');
    await git(staging, [
      'diff', '--binary', '--ignore-space-at-eol', '--no-renames', '--no-color', '--no-ext-diff', '--no-textconv',
      '--output', patch, '--', 'harmony',
    ]);
    const diff = await fs.readFile(patch);
    if (diff.length) {
      const { files } = await getPatchStatsAsync(staging, patch);
      for (const file of files) {
        if ((await lstatIfExists(path.join(native, file)))?.isSymbolicLink()) {
          await validatePatchLink(native, file, relative => resolvePatchPath(native, relative));
        }
      }
    }

    return diff;
  } finally {
    await fs.rm(staging, { recursive: true, force: true });
  }
}

export interface PatchResult {
  files: string[];
  created: string[];
  changedLines: number;
}

interface PatchWrite {
  target: string;
  staged?: string;
}

async function hasSamePatchContents(before: string, after: string): Promise<boolean> {
  const [original, updated] = await Promise.all([lstatIfExists(before), lstatIfExists(after)]);
  if (!original || !updated || original.mode !== updated.mode || original.size !== updated.size) return false;
  if (updated.isSymbolicLink()) return (await fs.readlink(before)) === (await fs.readlink(after));

  return (await fs.readFile(before)).equals(await fs.readFile(after));
}

async function matchesPreviousFile(file: string, sha256: string | undefined): Promise<boolean> {
  if (!sha256 || !(await lstatIfExists(file))?.isFile()) return false;

  return createHash('sha256').update(await fs.readFile(file)).digest('hex') === sha256;
}

async function publishPatchAsync(root: string, writes: PatchWrite[]): Promise<void> {
  if (!writes.length) return;

  const transaction = await fs.mkdtemp(path.join(root, '.expo-harmony-patch-'));
  const backups: { target: string; backup?: string }[] = [];
  const directories: string[] = [];
  let preserveBackups = false;

  try {
    for (const [index, { staged }] of writes.entries()) {
      if (staged) await fs.cp(staged, path.join(transaction, `next-${index}`), { verbatimSymlinks: true });
    }

    for (const [index, { target, staged }] of writes.entries()) {
      const parent = path.dirname(target);
      const first = await fs.mkdir(parent, { recursive: true });
      for (let directory = parent; first && HarmonyPaths.isInside(first, directory);
        directory = path.dirname(directory)) {
        directories.push(directory);
      }

      const backup = path.join(transaction, `previous-${index}`);
      const hadOriginal = await fs.rename(target, backup).then(() => true, (cause) => {
        if (cause.code !== 'ENOENT') throw cause;
        return false;
      });
      backups.push({ target, backup: hadOriginal ? backup : undefined });
      if (staged) await fs.rename(path.join(transaction, `next-${index}`), target);
    }
  } catch (cause) {
    const failures = [];
    for (const { target, backup } of backups.reverse()) {
      try {
        if (backup) await fs.rename(backup, target);
        else await fs.rm(target, { force: true });
      } catch (error) {
        failures.push(error);
      }
    }
    for (const directory of directories) {
      try {
        await fs.rmdir(directory);
      } catch (error) {
        failures.push(error);
      }
    }
    if (failures.length) {
      preserveBackups = true;
      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Cannot roll back the Harmony patch. Recovery files are in ${transaction}.`, {
        cause: new AggregateError([cause, ...failures]), file: transaction,
      });
    }
    throw cause;
  } finally {
    if (!preserveBackups) await fs.rm(transaction, { recursive: true, force: true });
  }
}

export async function applyPatchAsync(
  root: string,
  content: Uint8Array,
  previousCreatedFiles?: ReadonlyMap<string, string>,
  validateCreatedFiles?: (files: readonly string[]) => void
): Promise<PatchResult> {
  // Git text hunks may contain bytes that are not valid UTF-8. Split on ASCII headers without changing those bytes.
  const patchText = Buffer.from(content).toString('latin1');
  if (!patchText.trim()) {
    validateCreatedFiles?.([]);
    return { files: [], created: [], changedLines: 0 };
  }
  if (/(?:^|\n)(?:old mode|new mode|new file mode|deleted file mode) (?!(?:100644|100755|120000)(?:\r?\n|$))/u.test(patchText)
    || /(?:^|\n)(?:rename|copy) (?:from|to) /u.test(patchText)) {
    throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', 'Use file or symlink patches; regenerate renames as delete/add changes.');
  }

  const staging = await fs.mkdtemp(path.join(os.tmpdir(), 'harmony-patch-apply-'));

  try {
    await git(staging, ['init', '--quiet']);
    const patch = path.join(staging, 'changes.patch');
    await fs.writeFile(patch, content);
    const { files: outputNames, changedLines } = await getPatchStatsAsync(staging, patch);
    // Git can move a file when the before and after paths differ even without a rename header.
    const { files: inputNames } = await getPatchStatsAsync(staging, patch, true);
    inputNames.reverse();
    if (outputNames.length !== inputNames.length || outputNames.some((name, index) => name !== inputNames[index])) {
      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', 'Patch sections must use the same path before and after each change.');
    }

    const files = [...new Set(outputNames)];
    const native = path.join(root, 'harmony');
    const nativeStat = await lstatIfExists(native);
    if (nativeStat && !nativeStat.isDirectory()) {
      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch root must be a directory: ${native}.`);
    }

    const stagingNative = path.join(staging, 'harmony');
    await snapshot(native, stagingNative, files);

    const chunks = patchText.trimStart().split(/(?<=\n)(?=diff --git )/u);
    if (!chunks[0].startsWith('diff --git ')) {
      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', 'Expected a Git patch generated by npx @expo-harmony/patch-project.');
    }

    const sections = new Map<string, string>();
    for (const chunk of chunks) {
      await fs.writeFile(patch, chunk, 'latin1');
      const { files: names } = await getPatchStatsAsync(staging, patch);
      if (names.length !== 1) throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', 'Each patch section must modify one file.');

      sections.set(names[0], (sections.get(names[0]) ?? '') + chunk);
    }

    const created: string[] = [];
    const pending: string[] = [];
    for (const [name, source] of sections) {
      const isCreated = /(?:^|\n)new file mode /u.test(source) && !/(?:^|\n)deleted file mode /u.test(source);
      if (isCreated) created.push(name);
      const staged = path.join(stagingNative, name);
      await fs.writeFile(patch, source, 'latin1');

      try {
        await git(staging, ['apply', '--ignore-whitespace', '--check', patch]);
      } catch (cause) {
        // Other mods may regenerate only some files. Accept already-applied
        // sections independently, while validating the complete patch in staging.
        try {
          await git(staging, ['apply', '--ignore-whitespace', '--reverse', '--check', patch]);
          continue;
        } catch {
          const previousHash = isCreated ? previousCreatedFiles?.get(`harmony/${name}`) : undefined;
          if (!(await matchesPreviousFile(staged, previousHash))) {
            throw new HarmonyPatchError(cause.code, cause.message, {
              cause, file: patch, operation: cause.operation,
            });
          }

          // A revised patch can replace its own untouched output from a previous run.
          await fs.unlink(staged);
        }
      }

      await git(staging, ['apply', '--ignore-whitespace', '--binary', patch]);
      if (!(await hasSamePatchContents(path.join(native, name), staged))) {
        pending.push(name);
      }
    }

    if (sections.size !== files.length || files.some(file => !sections.has(file))) {
      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', 'Patch section paths do not match its file summary.');
    }

    const outputs = new Map<string, string>();
    const links: string[] = [];
    for (const file of files) {
      const staged = path.join(stagingNative, file);
      const stat = await lstatIfExists(staged);
      if (stat && !stat.isFile() && !stat.isSymbolicLink()) {
        throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch output must be a file: ${file}.`);
      }
      if (stat?.isSymbolicLink()) links.push(file);
      outputs.set(file, stat ? staged : undefined);
    }

    for (const file of links) {
      await validatePatchLink(native, file, async relative => (
        outputs.has(relative) ? outputs.get(relative) : resolvePatchPath(native, relative)
      ));
    }

    validateCreatedFiles?.(created);
    await publishPatchAsync(root, pending.map(file => ({
      target: path.join(native, file),
      staged: outputs.get(file),
    })));

    return { files, created, changedLines };
  } finally {
    await fs.rm(staging, { recursive: true, force: true });
  }
}

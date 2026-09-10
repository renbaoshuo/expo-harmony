import { execFile } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';

import { atomicWrite, HarmonyPaths } from '@expo-harmony/config-plugins';
import { canonicalizeAutolinkingArtifacts } from '@expo-harmony/expo-modules-autolinking';

import { HarmonyPatchError } from './errors';

const exec = promisify(execFile);

function isProjectPath(relative: string): boolean {
  // eslint-disable-next-line no-control-regex -- Control characters are invalid native patch paths.
  return !!relative && !relative.includes('\\') && !/[\x00-\x1f\x7f]/u.test(relative)
    && !relative.split('/').some(part => !part || part === '.' || part === '..' || part.toLowerCase() === '.git')
    && !/^[A-Za-z]:/u.test(relative);
}

async function git(cwd: string, args: string[]): Promise<string> {
  // Ambient Git overrides must not redirect commands outside the staging repository.
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_')));

  try {
    return (await exec('git', [
      '-c', 'core.autocrlf=false', '-c', 'core.quotePath=false', '-c', 'core.fileMode=true', ...args,
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

    await HarmonyPaths.resolveHarmonyPath(source, name);
    const from = path.join(source, name);
    const to = path.join(target, name);
    let stat;
    try {
      stat = await fs.lstat(from);
    } catch (cause) {
      if (cause.code === 'ENOENT') continue;

      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Cannot inspect ${from}.`, { cause, file: from });
    }
    if (!stat.isFile() && !stat.isSymbolicLink()) throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch source must be a file: ${from}.`);

    await fs.mkdir(path.dirname(to), { recursive: true });
    await fs.cp(from, to, { verbatimSymlinks: true });
  }
}

async function changedFiles(root: string, patch: string): Promise<string[]> {
  const stats = await git(root, ['apply', '--numstat', '-z', patch]);
  const files = stats.split('\0').filter(Boolean).map((row) => {
    const match = /^(?:\d+|-)\t(?:\d+|-)\t(harmony\/(.+))$/u.exec(row);
    if (!match || !isProjectPath(match[2])) {
      throw new HarmonyPatchError(
        'ERR_HARMONY_PATCH_FAILED',
        'Patch paths must remain inside the Harmony project and cannot modify Git metadata.'
      );
    }

    return match[2];
  });

  return [...new Set(files)];
}

export async function generatePatchAsync(baseline: string, current: string): Promise<string> {
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

    return await git(staging, [
      'diff', '--binary', '--ignore-space-at-eol', '--no-renames', '--no-color', '--no-ext-diff', '--no-textconv', '--', 'harmony',
    ]);
  } finally {
    await fs.rm(staging, { recursive: true, force: true });
  }
}

export interface PatchResult {
  files: string[];
  created: string[];
}

export async function getPatchChangedLinesAsync(file: string): Promise<number> {
  const stats = await git(path.dirname(file), ['apply', '--numstat', file]);

  return stats.split('\n').reduce((total, row) => {
    const [added, deleted] = row.split('\t', 2).map(Number);
    return total + (Number.isFinite(added) ? added : 0) + (Number.isFinite(deleted) ? deleted : 0);
  }, 0);
}

export async function applyPatchAsync(root: string, content: string): Promise<PatchResult> {
  if (!content.trim()) return { files: [], created: [] };
  if (/^(?:old mode|new mode|new file mode|deleted file mode) (?!100644$|100755$|120000$)/mu.test(content)
    || /^(?:rename|copy) (?:from|to) /mu.test(content)) {
    throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', 'Use file or symlink patches; regenerate renames as delete/add changes.');
  }

  const staging = await fs.mkdtemp(path.join(os.tmpdir(), 'harmony-patch-apply-'));
  try {
    await git(staging, ['init', '--quiet']);
    const patch = path.join(staging, 'changes.patch');
    await fs.writeFile(patch, content);
    const files = await changedFiles(staging, patch);
    const native = await HarmonyPaths.resolveHarmonyPath(root, 'harmony');

    await snapshot(native, path.join(staging, 'harmony'), files);

    const chunks = content.split(/(?=^diff --git )/mu).filter(chunk => chunk.startsWith('diff --git '));
    if (!chunks.length) {
      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', 'Expected a Git patch generated by npx @expo-harmony/patch-project.');
    }

    const sections = new Map<string, string>();
    for (const chunk of chunks) {
      await fs.writeFile(patch, chunk);
      const names = await changedFiles(staging, patch);
      if (names.length !== 1) throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', 'Each patch section must modify one file.');

      sections.set(names[0], (sections.get(names[0]) ?? '') + chunk);
    }

    const created: string[] = [];
    for (const [name, source] of sections) {
      if (/^new file mode /mu.test(source) && !/^deleted file mode /mu.test(source)) created.push(name);
      await fs.writeFile(patch, source);

      try {
        await git(staging, ['apply', '--ignore-whitespace', '--check', patch]);
      } catch (cause) {
        // Other mods may regenerate only some files. Accept already-applied
        // sections independently, while validating the complete patch in staging.
        try {
          await git(staging, ['apply', '--ignore-whitespace', '--reverse', '--check', patch]);
        } catch {
          throw new HarmonyPatchError(cause.code, cause.message, {
            cause, file: patch, operation: cause.operation,
          });
        }

        continue;
      }

      await git(staging, ['apply', '--ignore-whitespace', '--binary', patch]);
    }

    if (sections.size !== files.length || files.some(file => !sections.has(file))) {
      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', 'Patch section paths do not match its file summary.');
    }

    const writes: Array<{ target: string; content?: Uint8Array; link?: string; mode?: number }> = [];
    for (const file of files) {
      const target = await HarmonyPaths.resolveHarmonyPath(native, file);
      const staged = path.join(staging, 'harmony', file);
      let stat;
      try {
        stat = await fs.lstat(staged);
      } catch (cause) {
        if (cause.code !== 'ENOENT') {
          throw new HarmonyPatchError(
            cause.code || 'ERR_HARMONY_PATCH_FAILED',
            cause.message || `Cannot inspect staged patch output ${file}.`,
            { cause, file: staged, operation: 'patch-project' }
          );
        }
      }

      if (stat?.isSymbolicLink()) {
        const link = await fs.readlink(staged);
        if (path.isAbsolute(link) || !HarmonyPaths.isInside(native, path.resolve(path.dirname(target), link))) {
          throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch symlink must remain inside the Harmony project: ${file}.`);
        }

        await HarmonyPaths.resolveHarmonyPath(native, path.relative(native, path.resolve(path.dirname(target), link)));
        writes.push({ target, link });
      } else if (stat?.isFile()) {
        writes.push({ target, content: Uint8Array.from(await fs.readFile(staged)), mode: stat.mode & 0o777 });
      } else if (!stat) writes.push({ target });
      else throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch output must be a file: ${file}.`);
    }

    for (const { target, content, link, mode } of writes) {
      if (content) {
        await atomicWrite(target, content);
        await fs.chmod(target, mode);
      } else {
        await fs.rm(target, { force: true });
        if (link !== undefined) {
          await fs.mkdir(path.dirname(target), { recursive: true });
          await fs.symlink(link, target);
        }
      }
    }

    return { files, created };
  } finally {
    await fs.rm(staging, { recursive: true, force: true });
  }
}

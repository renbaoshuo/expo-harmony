import fs from 'node:fs';
import path from 'node:path';

import { HarmonyAutolinkingError } from '../../errors';
import { isPathInside, pathExistsAsync } from '../../utilities/values';

const MALFORMED_LOCK_GRACE_MS = 30_000;

async function processIsAliveAsync(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;

  try {
    process.kill(pid, 0);
    return true;
  } catch (cause) {
    return cause.code !== 'ESRCH';
  }
}

async function removeStaleLockAsync(lockPath) {
  let observed;
  try {
    observed = await fs.promises.lstat(lockPath);
    if (!observed.isFile() || observed.isSymbolicLink()) return false;
  } catch (_cause) {
    return false;
  }

  let contents;
  try {
    contents = JSON.parse(await fs.promises.readFile(lockPath, 'utf8'));
  } catch (_cause) {
    if (Date.now() - observed.mtimeMs < MALFORMED_LOCK_GRACE_MS) return false;
    contents = null;
  }

  if (contents && await processIsAliveAsync(contents.pid)) return false;
  try {
    const current = await fs.promises.lstat(lockPath);
    if (current.dev !== observed.dev || current.ino !== observed.ino
      || current.mtimeMs !== observed.mtimeMs || current.size !== observed.size) {
      return false;
    }
    await fs.promises.unlink(lockPath);
    return true;
  } catch (_cause) {
    return false;
  }
}

async function releasePublishLockAsync(handle, lockPath) {
  let owned;
  try {
    owned = await handle.stat();
  } catch (_cause) {
    // Closing the descriptor is still required even if its metadata is unavailable.
  }

  await handle.close().catch(() => {});
  if (!owned) return false;

  try {
    const current = await fs.promises.lstat(lockPath);
    if (current.dev !== owned.dev || current.ino !== owned.ino) return false;
    await fs.promises.unlink(lockPath);
    return true;
  } catch (_cause) {
    return false;
  }
}

async function acquirePublishLockAsync(lockPath) {
  await fs.promises.mkdir(path.dirname(lockPath), { recursive: true });

  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const handle = await fs.promises.open(lockPath, 'wx', 0o600);

      try {
        await handle.writeFile(JSON.stringify({ pid: process.pid, createdAt: new Date().toISOString() }));
        await handle.sync();
        return handle;
      } catch (cause) {
        await releasePublishLockAsync(handle, lockPath);
        throw new HarmonyAutolinkingError(
          'PUBLISH_FAILED',
          'Unable to initialize the Harmony autolinking publish lock.',
          { cause, stage: 'publish' }
        );
      }
    } catch (cause) {
      if (cause.code === 'EEXIST' && attempt === 0 && await removeStaleLockAsync(lockPath)) continue;
      if (cause.code === 'EEXIST') {
        throw new HarmonyAutolinkingError('PUBLISH_FAILED', 'Another Harmony autolinking publish is in progress.', { cause, stage: 'publish' });
      }
      throw new HarmonyAutolinkingError('PUBLISH_FAILED', 'Unable to acquire the Harmony autolinking lock.', { cause, stage: 'publish' });
    }
  }

  throw new HarmonyAutolinkingError('PUBLISH_FAILED', 'Unable to acquire the Harmony autolinking lock.', { stage: 'publish' });
}

function assertLexicallyContained(target, allowedRoot) {
  const resolved = path.resolve(target);
  const absoluteRoot = path.resolve(allowedRoot);

  if (!isPathInside(absoluteRoot, resolved)) {
    throw new HarmonyAutolinkingError('PUBLISH_FAILED', `Publish target escapes the allowed root: ${resolved}`, { stage: 'publish' });
  }

  if (resolved.split(path.sep).includes('node_modules')) {
    throw new HarmonyAutolinkingError('PUBLISH_FAILED', 'Publishing into node_modules is forbidden.', { stage: 'publish' });
  }
  return resolved;
}

async function assertSafeTargetAsync(target, allowedRoot) {
  const resolved = assertLexicallyContained(target, allowedRoot);
  const absoluteRoot = path.resolve(allowedRoot);

  if (await pathExistsAsync(resolved)) {
    const stat = await fs.promises.lstat(resolved);
    if (stat.isSymbolicLink()) {
      throw new HarmonyAutolinkingError('PUBLISH_FAILED', `Publish target must not be a symbolic link: ${resolved}`, { stage: 'publish' });
    }
  }

  if (await pathExistsAsync(absoluteRoot)) {
    const realRoot = await fs.promises.realpath(absoluteRoot);
    let ancestor = path.dirname(resolved);
    while (!(await pathExistsAsync(ancestor))) {
      const parent = path.dirname(ancestor);
      if (parent === ancestor) break;
      ancestor = parent;
    }
    const realAncestor = await fs.promises.realpath(ancestor);
    if (!isPathInside(realRoot, realAncestor)) {
      throw new HarmonyAutolinkingError('PUBLISH_FAILED', `Publish target resolves outside the allowed root: ${resolved}`, { stage: 'publish' });
    }
  }

  return resolved;
}

async function stageFileAsync(file, stagedTarget) {
  if ((file.source === undefined) === (file.content === undefined)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'Each publish file needs exactly one source or content.', { stage: 'publish' });
  }

  if (file.source !== undefined) {
    await fs.promises.copyFile(file.source, stagedTarget);
  } else {
    if (typeof file.content !== 'string' && !Buffer.isBuffer(file.content)) {
      throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'Publish file content must be a string or Buffer.', { stage: 'publish' });
    }
    await fs.promises.writeFile(stagedTarget, file.content, file.mode ? { mode: file.mode } : undefined);
  }
}

async function filesEqualAsync(left, right) {
  if (!(await pathExistsAsync(left)) || !(await pathExistsAsync(right))) return false;

  const [leftBuffer, rightBuffer] = await Promise.all([
    fs.promises.readFile(left),
    fs.promises.readFile(right),
  ]);
  return leftBuffer.equals(rightBuffer as unknown as Uint8Array);
}

async function removeEmptyParentsAsync(directory, stopAt) {
  let current = directory;

  while (isPathInside(stopAt, current) && current !== stopAt) {
    try {
      await fs.promises.rmdir(current);
    } catch (_cause) {
      break;
    }
    current = path.dirname(current);
  }
}

async function publishArtifactsAsync(options) {
  if (!Array.isArray(options?.files) || options.files.length === 0) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'A publish transaction requires at least one file.', { stage: 'publish' });
  }

  if (typeof options.allowedRoot !== 'string' || !options.allowedRoot) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'A publish transaction requires allowedRoot.', { stage: 'publish' });
  }

  const allowedRoot = path.resolve(options.allowedRoot);
  const files = [];

  for (const file of options.files) {
    if (!file || typeof file.target !== 'string' || !file.target) {
      throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'Publish file target must be a non-empty string.', { stage: 'publish' });
    }
    files.push({ ...file, target: await assertSafeTargetAsync(file.target, allowedRoot) });
  }

  if (new Set(files.map(file => file.target)).size !== files.length) {
    throw new HarmonyAutolinkingError('PUBLISH_FAILED', 'A publish transaction contains duplicate targets.', { stage: 'publish' });
  }

  const stale = [];
  for (const target of options.stale || []) {
    const safeTarget = await assertSafeTargetAsync(target, allowedRoot);
    if (!files.some(file => file.target === safeTarget) && !stale.includes(safeTarget)) stale.push(safeTarget);
  }

  const lockPath = await assertSafeTargetAsync(options.lockPath || path.join(allowedRoot, '.expo-harmony-autolinking.lock'), allowedRoot);
  await fs.promises.mkdir(path.dirname(lockPath), { recursive: true });

  const tmp = await fs.promises.mkdtemp(path.join(path.dirname(lockPath), '.expo-harmony-publish-'));
  const prepared = [];
  let lockHandle;
  const touched = [];
  const changed = [];
  const unchanged = [];

  try {
    for (let index = 0; index < files.length; index += 1) {
      const staged = path.join(tmp, `new-${index}`);
      await stageFileAsync(files[index], staged);
      prepared.push({ ...files[index], staged });
    }

    lockHandle = await acquirePublishLockAsync(lockPath);
    for (let index = 0; index < prepared.length; index += 1) {
      const file = prepared[index];
      if (await filesEqualAsync(file.staged, file.target)) {
        unchanged.push(file.target);
        continue;
      }
      const existed = await pathExistsAsync(file.target);
      const backup = existed ? path.join(tmp, `backup-${index}`) : null;
      if (backup) await fs.promises.copyFile(file.target, backup);
      touched.push({ target: file.target, existed, backup });
      await fs.promises.mkdir(path.dirname(file.target), { recursive: true });
      await fs.promises.rename(file.staged, file.target);
      if (file.mode) await fs.promises.chmod(file.target, file.mode);
      changed.push(file.target);
    }

    for (let index = 0; index < stale.length; index += 1) {
      const target = stale[index];
      if (!(await pathExistsAsync(target))) continue;
      const backup = path.join(tmp, `stale-${index}`);
      await fs.promises.copyFile(target, backup);
      touched.push({ target, existed: true, backup });
      await fs.promises.unlink(target);
      changed.push(target);
    }

    return { changed, unchanged, warnings: [] };
  } catch (cause) {
    const failures = [];

    for (const entry of [...touched].reverse()) {
      try {
        if (entry.existed) {
          await fs.promises.mkdir(path.dirname(entry.target), { recursive: true });
          await fs.promises.copyFile(entry.backup, entry.target);
        } else if (await pathExistsAsync(entry.target)) {
          await fs.promises.unlink(entry.target);
          await removeEmptyParentsAsync(path.dirname(entry.target), allowedRoot);
        }
      } catch (error) {
        failures.push({ target: entry.target, message: error.message });
      }
    }

    throw new HarmonyAutolinkingError('PUBLISH_FAILED', 'Harmony autolinking publish failed and was rolled back.', {
      cause,
      details: failures.length > 0 ? { rollbackFailures: failures } : undefined,
      stage: 'publish',
    });
  } finally {
    if (lockHandle) await releasePublishLockAsync(lockHandle, lockPath);
    await fs.promises.rm(tmp, { recursive: true, force: true }).catch(() => {});
  }
}

export {
  publishArtifactsAsync,
};

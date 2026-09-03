import { AsyncLocalStorage } from 'node:async_hooks';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

import { HarmonyCliError } from './errors';

const DefaultMalformedLockGraceMs = 30_000;
const DefaultPollIntervalMs = 100;
const DefaultWaitTimeoutMs = 5_000;
const LockRelativePath = '.expo/harmony/native-operation.lock';

interface HarmonyProjectLockLease {
  releaseAsync(): Promise<void>;
}

interface ActiveProjectLock {
  projectRoot: string;
  released: boolean;
}

interface LockOwner {
  createdAt: string;
  operation: string;
  pid: number;
  projectRoot: string;
  token: string;
}

const ActiveLock = new AsyncLocalStorage<ActiveProjectLock>();

async function canonicalProjectRootAsync(projectRoot: string): Promise<string> {
  try {
    return await fs.promises.realpath(path.resolve(projectRoot));
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_PROJECT_LOCK',
      'Cannot resolve the application project before acquiring its Harmony native operation lock.',
      { cause, operation: 'project-lock' }
    );
  }
}

function projectLockPath(projectRoot: string): string {
  return path.join(projectRoot, ...LockRelativePath.split('/'));
}

async function processIsAliveAsync(pid: unknown): Promise<boolean> {
  if (!Number.isInteger(pid) || Number(pid) <= 0) return false;

  try {
    process.kill(Number(pid), 0);
    return true;
  } catch (cause) {
    return cause?.code !== 'ESRCH';
  }
}

async function readLockOwnerAsync(lockPath: string): Promise<LockOwner | null> {
  try {
    const candidate = JSON.parse(await fs.promises.readFile(lockPath, 'utf8'));
    if (!candidate
      || typeof candidate !== 'object'
      || !Number.isInteger(candidate.pid)
      || candidate.pid <= 0
      || typeof candidate.createdAt !== 'string'
      || typeof candidate.operation !== 'string'
      || typeof candidate.projectRoot !== 'string'
      || typeof candidate.token !== 'string') {
      return null;
    }
    return candidate as LockOwner;
  } catch (_cause) {
    return null;
  }
}

async function removeStaleProjectLockAsync(
  lockPath: string
): Promise<boolean> {
  let observed;
  try {
    observed = await fs.promises.lstat(lockPath);
  } catch (_cause) {
    return false;
  }
  if (!observed.isFile() || observed.isSymbolicLink()) return false;

  const owner = await readLockOwnerAsync(lockPath);
  if (owner) {
    if (await processIsAliveAsync(owner.pid)) return false;
  } else if (Date.now() - observed.mtimeMs < DefaultMalformedLockGraceMs) {
    return false;
  }

  try {
    const current = await fs.promises.lstat(lockPath);
    if (!current.isFile() || current.isSymbolicLink()
      || current.dev !== observed.dev
      || current.ino !== observed.ino
      || current.mtimeMs !== observed.mtimeMs
      || current.size !== observed.size) {
      return false;
    }
    await fs.promises.unlink(lockPath);
    return true;
  } catch (_cause) {
    return false;
  }
}

async function releaseOwnedLockAsync(
  handle: fs.promises.FileHandle,
  lockPath: string,
  owned: fs.Stats | undefined
): Promise<boolean> {
  await handle.close().catch(() => {});
  if (!owned) return false;

  try {
    const current = await fs.promises.lstat(lockPath);
    if (!current.isFile() || current.isSymbolicLink()
      || current.dev !== owned.dev || current.ino !== owned.ino) {
      return false;
    }
    await fs.promises.unlink(lockPath);
    return true;
  } catch (_cause) {
    return false;
  }
}

function delayAsync(milliseconds: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

async function acquireHarmonyProjectLockAsync(
  projectRoot: string,
  operation: string
): Promise<HarmonyProjectLockLease> {
  const canonicalRoot = await canonicalProjectRootAsync(projectRoot);
  const lockPath = projectLockPath(canonicalRoot);
  const deadline = Date.now() + DefaultWaitTimeoutMs;

  await fs.promises.mkdir(path.dirname(lockPath), { recursive: true });

  while (true) {
    try {
      const handle = await fs.promises.open(lockPath, 'wx', 0o600);
      let owned: fs.Stats | undefined;
      const owner: LockOwner = {
        createdAt: new Date().toISOString(),
        operation,
        pid: process.pid,
        projectRoot: canonicalRoot,
        token: crypto.randomUUID(),
      };

      try {
        owned = await handle.stat();
        await handle.writeFile(`${JSON.stringify(owner)}\n`);
        await handle.sync();
      } catch (cause) {
        await releaseOwnedLockAsync(handle, lockPath, owned);
        throw new HarmonyCliError(
          'ERR_HARMONY_PROJECT_LOCK',
          'Cannot initialize the Harmony native operation lock.',
          { cause, operation: 'project-lock' }
        );
      }

      let released = false;
      return {
        async releaseAsync() {
          if (released) return;
          released = true;
          if (await releaseOwnedLockAsync(handle, lockPath, owned)) return;
          throw new HarmonyCliError(
            'ERR_HARMONY_PROJECT_LOCK',
            'The Harmony native operation lock changed before it could be released safely.',
            { operation: 'project-lock' }
          );
        },
      };
    } catch (cause) {
      if (cause instanceof HarmonyCliError) throw cause;
      if (cause?.code !== 'EEXIST') {
        throw new HarmonyCliError(
          'ERR_HARMONY_PROJECT_LOCK',
          'Cannot acquire the Harmony native operation lock.',
          { cause, operation: 'project-lock' }
        );
      }

      if (await removeStaleProjectLockAsync(lockPath)) continue;
      if (Date.now() >= deadline) {
        const owner = await readLockOwnerAsync(lockPath);
        const detail = owner?.operation ? ` (${owner.operation}, pid ${owner.pid})` : '';
        throw new HarmonyCliError(
          'ERR_HARMONY_PROJECT_BUSY',
          `Another Harmony native operation is using this project${detail}. Retry after it finishes.`,
          { operation }
        );
      }
      await delayAsync(Math.min(DefaultPollIntervalMs, Math.max(1, deadline - Date.now())));
    }
  }
}

async function withHarmonyProjectLockAsync<T>(
  projectRoot: string,
  operation: string,
  callback: () => Promise<T> | T
): Promise<T> {
  const canonicalRoot = await canonicalProjectRootAsync(projectRoot);
  const active = ActiveLock.getStore();
  if (active?.projectRoot === canonicalRoot && !active.released) return await callback();

  const lease = await acquireHarmonyProjectLockAsync(canonicalRoot, operation);
  const context: ActiveProjectLock = { projectRoot: canonicalRoot, released: false };
  try {
    return await ActiveLock.run(context, callback);
  } finally {
    context.released = true;
    await lease.releaseAsync();
  }
}

export { withHarmonyProjectLockAsync };

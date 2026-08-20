import nodeCrypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

import { isInside } from './path';

async function sha256File(file: string): Promise<string> {
  return await new Promise<string>((resolve, reject) => {
    const hash = nodeCrypto.createHash('sha256');
    const input = fs.createReadStream(file);

    input.on('error', reject);
    input.on('data', (chunk) => {
      const bytes = typeof chunk === 'string' ? new TextEncoder().encode(chunk) : Uint8Array.from(chunk);
      hash.update(bytes);
    });
    input.on('end', () => resolve(hash.digest('hex')));
  });
}

async function describeFile(file: string): Promise<{ sha256: string; size: number }> {
  const stat = await fs.promises.stat(file);

  if (!stat.isFile()) throw new Error(`Expected a regular file: ${file}`);

  return { sha256: await sha256File(file), size: stat.size };
}

async function listFiles(root: string): Promise<string[]> {
  const files: string[] = [];

  async function visit(directory: string): Promise<void> {
    const entries = await fs.promises.readdir(directory, { withFileTypes: true });

    entries.sort((left, right) => left.name.localeCompare(right.name, 'en'));

    for (const entry of entries) {
      const file = path.join(directory, entry.name);

      if (entry.isSymbolicLink()) throw new Error(`Asset output contains a symbolic link: ${entry.name}`);
      if (entry.isDirectory()) await visit(file);
      else if (entry.isFile()) files.push(file);
      else throw new Error(`Asset output contains an unsupported file: ${entry.name}`);
    }
  }

  await visit(root);

  return files;
}

async function ensureSafeParent(root: string, destination: string): Promise<void> {
  if (!isInside(root, destination) || destination === root) {
    throw new Error('Export destination escapes its owned root.');
  }

  await fs.promises.mkdir(root, { recursive: true });
  await fs.promises.mkdir(path.dirname(destination), { recursive: true });

  const [realRoot, realParent] = await Promise.all([
    fs.promises.realpath(root),
    fs.promises.realpath(path.dirname(destination)),
  ]);

  if (!isInside(realRoot, realParent)) {
    throw new Error('Export destination follows a link outside its owned root.');
  }
}

async function atomicCopy(source: string, destination: string, root: string): Promise<void> {
  await ensureSafeParent(root, destination);

  const temporary = path.join(path.dirname(destination), `.${path.basename(destination)}.expo-${nodeCrypto.randomUUID()}.tmp`);

  try {
    await fs.promises.copyFile(source, temporary, fs.constants.COPYFILE_EXCL);
    await fs.promises.rename(temporary, destination);
  } finally {
    await fs.promises.rm(temporary, { force: true });
  }
}

async function atomicWriteJson(value: unknown, destination: string, root: string): Promise<void> {
  await ensureSafeParent(root, destination);

  const temporary = path.join(path.dirname(destination), `.${path.basename(destination)}.expo-${nodeCrypto.randomUUID()}.tmp`);

  try {
    await fs.promises.writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { flag: 'wx' });
    await fs.promises.rename(temporary, destination);
  } finally {
    await fs.promises.rm(temporary, { force: true });
  }
}

async function removeEmptyParents(file: string, stop: string): Promise<void> {
  let directory = path.dirname(file);

  while (directory !== stop && isInside(stop, directory)) {
    try {
      await fs.promises.rmdir(directory);
    } catch {
      return;
    }

    directory = path.dirname(directory);
  }
}

export { atomicCopy, atomicWriteJson, describeFile, listFiles, removeEmptyParents };

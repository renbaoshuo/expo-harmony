import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import JSON5 from 'json5';

import { HarmonyConfigPluginError } from './errors';

function sortValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortValue);
  if (value && typeof value === 'object' && !Buffer.isBuffer(value)) {
    const record = value as Record<string, unknown>;
    const entries = Object.keys(record).sort().map(key => [key, sortValue(record[key])]);

    return Object.fromEntries(entries);
  }

  return value;
}

export function stableJson(value: unknown): string {
  return `${JSON.stringify(sortValue(value), null, 2)}\n`;
}

export async function readJson5<T>(file: string, fallback: T, modName: string): Promise<T> {
  try {
    const source = await fs.promises.readFile(file, 'utf8');

    return JSON5.parse(source) as T;
  } catch (cause) {
    if ((cause as NodeJS.ErrnoException).code === 'ENOENT') return structuredClone(fallback);

    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_JSON5_INVALID',
      `Cannot parse ${file} for harmony.${modName}: ${(cause as Error).message}`,
      { cause, file, operation: `harmony.${modName}.read` }
    );
  }
}

export async function readText(file: string, fallback = ''): Promise<string> {
  try {
    return await fs.promises.readFile(file, 'utf8');
  } catch (cause) {
    if ((cause as NodeJS.ErrnoException).code === 'ENOENT') return fallback;

    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_TEXT_INVALID',
      `Cannot read ${file}: ${(cause as Error).message}`,
      { cause, file, operation: 'harmony.mod.read' }
    );
  }
}

export async function atomicWrite(file: string, content: string | Uint8Array): Promise<void> {
  const directory = path.dirname(file);
  const temporary = path.join(
    directory,
    `.${path.basename(file)}.${process.pid}.${crypto.randomBytes(6).toString('hex')}.tmp`
  );

  await fs.promises.mkdir(directory, { recursive: true });

  try {
    await fs.promises.writeFile(temporary, content);
    await fs.promises.rename(temporary, file);
  } finally {
    await fs.promises.rm(temporary, { force: true }).catch(() => {});
  }
}

export async function writeJson5(file: string, value: unknown): Promise<void> {
  await atomicWrite(file, stableJson(value));
}

export async function sha256File(file: string): Promise<string> {
  const data = Uint8Array.from(await fs.promises.readFile(file));

  return crypto.createHash('sha256').update(data).digest('hex');
}

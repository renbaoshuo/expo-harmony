import fs from 'node:fs';
import path from 'node:path';

import { resolveTemplateFile } from './dependencies';

async function readTextIfExistsAsync(file: string): Promise<string | null> {
  try {
    return await fs.promises.readFile(file, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    return Promise.reject(error);
  }
}

async function writeFileAtomicAsync(file: string, content: string) {
  await fs.promises.mkdir(path.dirname(file), { recursive: true });
  const temporary = path.join(path.dirname(file), `.${path.basename(file)}.${process.pid}.tmp`);
  try {
    await fs.promises.writeFile(temporary, content);
    await fs.promises.rename(temporary, file);
  } finally {
    await fs.promises.rm(temporary, { force: true }).catch(() => {});
  }
}

async function writeFileIfChangedAsync(file: string, content: string) {
  const existing = await readTextIfExistsAsync(file);
  if (existing !== content) await writeFileAtomicAsync(file, content);
}

async function ensureGitignoreEntryAsync(file: string, entry: string) {
  const content = await readTextIfExistsAsync(file) ?? '';
  const normalized = content.replace(/\r\n?/g, '\n');
  if (normalized.split('\n').includes(entry)) return;

  const next = `${normalized.replace(/\n*$/, '')}${normalized.trim() ? '\n' : ''}${entry}\n`;
  await writeFileAtomicAsync(file, next);
}

async function writeExpoCmakeWrapperAsync(harmonyProjectPath: string) {
  const file = path.join(harmonyProjectPath, 'entry/src/main/cpp/generated/CMakeLists.txt');
  const content = await fs.promises.readFile(resolveTemplateFile('harmony/entry/src/main/cpp/generated/CMakeLists.txt'), 'utf8');
  await writeFileIfChangedAsync(file, content);
  return file;
}

export {
  ensureGitignoreEntryAsync,
  writeExpoCmakeWrapperAsync,
};

import fs from 'node:fs';
import path from 'node:path';

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

  const temp = path.join(path.dirname(file), `.${path.basename(file)}.${process.pid}.tmp`);

  try {
    await fs.promises.writeFile(temp, content);
    await fs.promises.rename(temp, file);
  } finally {
    await fs.promises.rm(temp, { force: true }).catch(() => {});
  }
}

async function ensureGitignoreEntryAsync(file: string, entry: string) {
  const content = await readTextIfExistsAsync(file) ?? '';
  const text = content.replace(/\r\n?/g, '\n');

  if (text.split('\n').includes(entry)) return;

  const next = `${text.replace(/\n*$/, '')}${text.trim() ? '\n' : ''}${entry}\n`;

  await writeFileAtomicAsync(file, next);
}

export {
  ensureGitignoreEntryAsync,
};

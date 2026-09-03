import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import JSON5 from 'json5';
import tar from 'tar';

const localDependency = /^(?:file:|link:|workspace:|\.{1,2}[\\/])|^(?:\/|[A-Za-z]:[\\/])/u;
const absoluteSourcePath = /(?:\/Users\/[^/]+\/|\/home\/[^/]+\/|[A-Za-z]:\\Users\\)/u;

export async function sanitizeHarmonyHar(harPath) {
  const tempRoot = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-har-'));
  const output = path.join(tempRoot, 'library.har');
  try {
    await tar.x({ cwd: tempRoot, file: harPath, strict: true });

    const packageRoot = path.join(tempRoot, 'package');
    const builtManifest = path.join(packageRoot, 'oh-package.json5');
    const built = JSON5.parse(await fs.promises.readFile(builtManifest, 'utf8'));

    for (const section of ['dependencies', 'devDependencies', 'dynamicDependencies']) {
      for (const [name, value] of Object.entries(built[section] || {})) {
        if (typeof value !== 'string' || !localDependency.test(value)) continue;

        throw new Error(`Cannot publish ${harPath}: ${section}.${name} must use a package version.`);
      }
    }

    await fs.promises.rm(path.join(packageRoot, 'oh-package-lock.json5'), { force: true });
    await tar.c({ cwd: tempRoot, file: output, gzip: true, portable: true }, ['package']);
    await fs.promises.copyFile(output, harPath);
  } finally {
    await fs.promises.rm(tempRoot, { recursive: true, force: true });
  }
}

export function assertPortableHarmonyHarSync(harPath) {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'expo-har-check-'));
  try {
    tar.x({ cwd: tempRoot, file: harPath, strict: true, sync: true });

    const packageRoot = path.join(tempRoot, 'package');
    for (const name of ['oh-package.json5', 'oh-package-lock.json5']) {
      const file = path.join(packageRoot, name);
      if (!fs.existsSync(file)) continue;

      const content = fs.readFileSync(file, 'utf8');
      if (absoluteSourcePath.test(content) || content.includes('file:/')) {
        throw new Error(`${harPath} leaks a local dependency path in package/${name}.`);
      }
      if (name === 'oh-package.json5') {
        const manifest = JSON5.parse(content);

        for (const section of ['dependencies', 'devDependencies', 'dynamicDependencies']) {
          for (const [dependency, version] of Object.entries(manifest[section] || {})) {
            if (typeof version === 'string' && localDependency.test(version)) {
              throw new Error(`${harPath} package/${name} ${section}.${dependency} must use a package version.`);
            }
          }
        }
      }
    }
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

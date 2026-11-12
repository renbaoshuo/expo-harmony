/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import JSON5 from 'json5';
import * as tar from 'tar';

const localDependency = /^(?:file:|link:|workspace:|\.{1,2}[\\/])|^(?:\/|[A-Za-z]:[\\/])/u;
const absoluteSourcePath = /(?:\/Users\/[^/]+\/|\/home\/[^/]+\/|[A-Za-z]:\\Users\\)/u;

export function isNativeTypeDependency(packageRoot, name, specifier) {
  if (path.basename(name) !== name || !name.endsWith('.so') || typeof specifier !== 'string') return false;

  const relative = specifier.replace(/^file:/u, '');
  if (!relative.startsWith('./')) return false;

  try {
    const root = fs.realpathSync(packageRoot);
    const directory = fs.realpathSync(path.resolve(root, relative));
    const relation = path.relative(root, directory);
    if (!relation || relation.startsWith(`..${path.sep}`) || relation === '..' || path.isAbsolute(relation)) return false;

    const manifest = JSON5.parse(fs.readFileSync(path.join(directory, 'oh-package.json5'), 'utf8'));
    if (manifest.name !== name || typeof manifest.types !== 'string' || !manifest.types.endsWith('.d.ts')) return false;

    const declaration = fs.realpathSync(path.resolve(directory, manifest.types));
    const target = path.relative(directory, declaration);
    if (target.startsWith(`..${path.sep}`) || target === '..' || path.isAbsolute(target)) return false;

    return fs.statSync(declaration).isFile();
  } catch {
    return false;
  }
}

function isBundledNativeTypeDependency(packageRoot, manifest, name, specifier) {
  if (!isNativeTypeDependency(packageRoot, name, specifier)
    || !Array.isArray(manifest.nativeComponents)
    || !manifest.nativeComponents.some(component => component?.name === name)) return false;

  try {
    const libs = path.join(fs.realpathSync(packageRoot), 'libs');

    return fs.readdirSync(libs, { withFileTypes: true }).some((architecture) => {
      const binary = path.join(libs, architecture.name, name);
      return architecture.isDirectory() && fs.existsSync(binary) && fs.lstatSync(binary).isFile();
    });
  } catch {
    return false;
  }
}

export async function sanitizeHarmonyHar(file, {
  sourceManifest: source, workspaceVersions: versions = {}, moduleRoot,
}: {
  sourceManifest?: Record<string, unknown>;
  workspaceVersions?: Record<string, string>;
  moduleRoot?: string;
} = {}) {
  const temp = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-har-'));
  const output = path.join(temp, 'library.har');

  try {
    const docs = new Set<string>();
    // Async extraction can reject while entries are still being written, racing cleanup.
    tar.x({
      cwd: temp,
      file,
      strict: true,
      sync: true,
      filter: (name, entry) => {
        if (moduleRoot && 'type' in entry && entry.type === 'SymbolicLink' && ['package/LICENSE', 'package/README.md', 'package/CHANGELOG.md'].includes(name)) {
          docs.add(path.posix.basename(name));
          return false;
        }
        return true;
      },
    });

    const root = path.join(temp, 'package');
    for (const name of docs) {
      await fs.promises.copyFile(path.join(moduleRoot, name), path.join(root, name));
    }

    const target = path.join(root, 'oh-package.json5');
    const manifest = JSON5.parse(await fs.promises.readFile(target, 'utf8'));

    for (const section of ['dependencies', 'devDependencies', 'dynamicDependencies']) {
      for (const [name, value] of Object.entries(manifest[section] || {})) {
        if (typeof value !== 'string' || !localDependency.test(value)) continue;
        if (value === './library' || value === 'file:./library') continue;
        if (isBundledNativeTypeDependency(root, manifest, name, value)) continue;

        if (Object.hasOwn(versions, name)) {
          const declared = source?.[section] as Record<string, string> | undefined;
          const version = declared?.[name] || versions[name];
          if (typeof version === 'string' && !localDependency.test(version)) {
            manifest[section][name] = version;
            continue;
          }
        }

        throw new Error(`Cannot publish ${file}: ${section}.${name} must use a package version.`);
      }
    }

    await fs.promises.writeFile(target, `${JSON5.stringify(manifest, null, 2)}\n`);
    await fs.promises.rm(path.join(root, 'oh-package-lock.json5'), { force: true });

    // Build-time timestamps must not change the content-addressed HAR path.
    await tar.c({ cwd: temp, file: output, gzip: true, portable: true, noMtime: true }, ['package']);
    await fs.promises.copyFile(output, file);
  } finally {
    await fs.promises.rm(temp, { recursive: true, force: true });
  }
}

export function assertPortableHarmonyHarSync(harPath) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'expo-har-check-'));
  try {
    tar.x({ cwd: temp, file: harPath, strict: true, sync: true });

    const root = path.join(temp, 'package');
    for (const name of ['oh-package.json5', 'oh-package-lock.json5']) {
      const file = path.join(root, name);
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
              if (version === './library' || version === 'file:./library') continue;
              if (isBundledNativeTypeDependency(root, manifest, dependency, version)) continue;
              throw new Error(`${harPath} package/${name} ${section}.${dependency} must use a package version.`);
            }
          }
        }
      }
    }
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

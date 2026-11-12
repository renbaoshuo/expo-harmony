/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

import JSON5 from 'json5';

const HarmonyNativeInputsFingerprintVersion = 3;

interface HarmonyNativeInputsFingerprint {
  artifactCount: number;
  fingerprint: string;
  fingerprintVersion: typeof HarmonyNativeInputsFingerprintVersion;
}

interface HarmonyNativeInputsFingerprintOptions {
  lockfile: string;
  manifest: string;
  projectRoot: string;
}

interface PackageManifest {
  dependencies?: Record<string, unknown>;
  devDependencies?: Record<string, unknown>;
  dynamicDependencies?: Record<string, unknown>;
  overrides?: Record<string, unknown>;
}

interface PackageLock {
  packages?: Record<string, { registryType?: string; resolved?: string }>;
}

function readOptionalFile(file: string): Uint8Array | null {
  try {
    return Uint8Array.from(fs.readFileSync(file));
  } catch (cause: unknown) {
    if (cause && typeof cause === 'object' && 'code' in cause && cause.code === 'ENOENT') return null;

    throw new Error(cause instanceof Error ? cause.message : String(cause), { cause });
  }
}

function resolveLocalHar(root: string, specifier: unknown, local = false): string | null {
  if (typeof specifier !== 'string') return null;
  const file = specifier.replace(/^(?:file|link):/u, '');
  if (!local && !path.isAbsolute(file) && !/^\.\.?[\\/]/u.test(file)) return null;
  if (/^[a-z][a-z\d+.-]*:\/\//iu.test(file)) return null;
  if (!file.toLowerCase().endsWith('.har')) return null;

  return path.resolve(root, file);
}

function findLocalHars(root: string, manifest: PackageManifest): (string | null)[] {
  const specifiers = [
    ...Object.values(manifest.dependencies ?? {}),
    ...Object.values(manifest.devDependencies ?? {}),
    ...Object.values(manifest.dynamicDependencies ?? {}),
    ...Object.values(manifest.overrides ?? {}),
  ];

  return specifiers.map(specifier => resolveLocalHar(root, specifier));
}

function findLockedHars(file: string, data: Uint8Array | null): (string | null)[] {
  if (!data) return [];

  const lock = JSON5.parse(Buffer.from(data).toString('utf8')) as PackageLock;
  const root = path.dirname(file);
  return Object.values(lock?.packages ?? {}).flatMap(entry =>
    entry?.registryType === 'local' ? [resolveLocalHar(root, entry.resolved, true)] : []
  );
}

function hashFile(hash: crypto.Hash, file: string): void {
  const handle = fs.openSync(file, 'r');
  const buffer = new Uint8Array(1024 * 1024);

  try {
    while (true) {
      const size = fs.readSync(handle, buffer, 0, buffer.length, null);
      if (size === 0) break;

      hash.update(Uint8Array.from(buffer.subarray(0, size)));
    }
  } finally {
    fs.closeSync(handle);
  }
}

function fingerprintHarmonyNativeInputsSync(
  options: HarmonyNativeInputsFingerprintOptions
): HarmonyNativeInputsFingerprint {
  const data = fs.readFileSync(options.manifest);
  const lock = readOptionalFile(options.lockfile);

  const manifest = JSON5.parse(data.toString('utf8')) as PackageManifest;
  const root = path.dirname(options.manifest);

  // The installer restores portable manifest overrides after OHPM has resolved
  // their local paths. The lock describes the archives that were actually used.
  const files = [...new Set([
    ...findLocalHars(root, manifest),
    ...findLockedHars(options.lockfile, lock),
  ])].filter((file): file is string => file !== null).sort();

  const hash = crypto.createHash('sha256');
  hash.update(`expo-harmony-native-dependencies-v${HarmonyNativeInputsFingerprintVersion}\0`);
  hash.update(Uint8Array.from(data));
  if (lock) hash.update(lock);

  for (const file of files) {
    if (!fs.statSync(file).isFile()) {
      throw new Error(`Cannot fingerprint Harmony native artifact: ${file}`);
    }

    const relative = path.relative(options.projectRoot, file).split(path.sep).join('/');

    hash.update('\0artifact\0');
    hash.update(relative);
    hash.update('\0');
    hashFile(hash, file);
  }

  return {
    artifactCount: files.length,
    fingerprint: hash.digest('hex'),
    fingerprintVersion: HarmonyNativeInputsFingerprintVersion,
  };
}

function writeHarmonyNativeInputsStampSync(options: { projectRoot: string; harmonyRoot: string }): void {
  const { projectRoot, harmonyRoot } = options;
  const { fingerprint, artifactCount } = fingerprintHarmonyNativeInputsSync({
    projectRoot,
    manifest: path.join(harmonyRoot, 'oh-package.json5'),
    lockfile: path.join(harmonyRoot, 'oh-package-lock.json5'),
  });
  const file = path.join(harmonyRoot, '.hvigor/expo-harmony/native-inputs.cmake');
  const content = `# Generated native dependency fingerprint.\n# Native HAR artifacts: ${artifactCount}\nadd_compile_definitions(EXPO_HARMONY_NATIVE_INPUTS_SHA256_${fingerprint}=1)\n`;
  const previous = readOptionalFile(file);
  if (previous && Buffer.from(previous).toString('utf8') === content) return;

  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${crypto.randomUUID()}.tmp`;

  try {
    fs.writeFileSync(temp, content, { flag: 'wx' });
    fs.renameSync(temp, file);
  } finally {
    fs.rmSync(temp, { force: true });
  }
}

export {
  HarmonyNativeInputsFingerprintVersion,
  fingerprintHarmonyNativeInputsSync,
  writeHarmonyNativeInputsStampSync,
};
export type {
  HarmonyNativeInputsFingerprint,
  HarmonyNativeInputsFingerprintOptions,
};

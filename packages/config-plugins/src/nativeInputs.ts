import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

import JSON5 from 'json5';

const HarmonyNativeInputsFingerprintVersion = 1;

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
  overrides?: Record<string, unknown>;
}

function readOptionalFile(file: string): Uint8Array | null {
  try {
    return Uint8Array.from(fs.readFileSync(file));
  } catch (cause: unknown) {
    if (cause && typeof cause === 'object' && 'code' in cause && cause.code === 'ENOENT') return null;

    throw new Error(cause instanceof Error ? cause.message : String(cause), { cause });
  }
}

function resolveLocalHar(root: string, specifier: unknown): string | null {
  if (typeof specifier !== 'string' || !/^\.\.?[\\/]/u.test(specifier)) return null;
  if (!specifier.toLowerCase().endsWith('.har')) return null;

  return path.resolve(root, specifier);
}

function findLocalHars(root: string, manifest: PackageManifest): string[] {
  const specifiers = [
    ...Object.values(manifest.dependencies ?? {}),
    ...Object.values(manifest.overrides ?? {}),
  ];

  return [...new Set(specifiers.map(specifier => resolveLocalHar(root, specifier)))]
    .filter((value): value is string => value !== null)
    .sort();
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
  const files = findLocalHars(root, manifest);

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

export {
  HarmonyNativeInputsFingerprintVersion,
  fingerprintHarmonyNativeInputsSync,
};
export type {
  HarmonyNativeInputsFingerprint,
  HarmonyNativeInputsFingerprintOptions,
};

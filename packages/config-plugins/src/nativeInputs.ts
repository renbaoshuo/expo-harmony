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

function readFileIfPresent(file: string): Uint8Array | null {
  try {
    return Uint8Array.from(fs.readFileSync(file));
  } catch (error: unknown) {
    if (error && typeof error === 'object' && 'code' in error && error.code === 'ENOENT') return null;

    throw new Error(error instanceof Error ? error.message : String(error), { cause: error });
  }
}

function resolveLocalHar(root: string, specifier: unknown): string | null {
  if (typeof specifier !== 'string' || !/^\.\.?[\\/]/u.test(specifier)) return null;
  if (!specifier.toLowerCase().endsWith('.har')) return null;

  return path.resolve(root, specifier);
}

function findLocalHarArtifacts(root: string, manifest: PackageManifest): string[] {
  const specifiers = [
    ...Object.values(manifest.dependencies ?? {}),
    ...Object.values(manifest.overrides ?? {}),
  ];

  return [...new Set(specifiers.map(specifier => resolveLocalHar(root, specifier)))]
    .filter((value): value is string => value !== null)
    .sort();
}

function hashFile(hash: crypto.Hash, file: string): void {
  const fd = fs.openSync(file, 'r');
  const chunk = new Uint8Array(1024 * 1024);

  try {
    while (true) {
      const size = fs.readSync(fd, chunk, 0, chunk.length, null);
      if (size === 0) break;

      hash.update(Uint8Array.from(chunk.subarray(0, size)));
    }
  } finally {
    fs.closeSync(fd);
  }
}

function fingerprintHarmonyNativeInputsSync(
  options: HarmonyNativeInputsFingerprintOptions
): HarmonyNativeInputsFingerprint {
  const source = fs.readFileSync(options.manifest);
  const lock = readFileIfPresent(options.lockfile);

  const manifest = JSON5.parse(source.toString('utf8')) as PackageManifest;
  const root = path.dirname(options.manifest);
  const artifacts = findLocalHarArtifacts(root, manifest);
  const hash = crypto.createHash('sha256');

  hash.update(`expo-harmony-native-dependencies-v${HarmonyNativeInputsFingerprintVersion}\0`);
  hash.update(Uint8Array.from(source));
  if (lock) hash.update(lock);

  for (const artifact of artifacts) {
    if (!fs.statSync(artifact).isFile()) {
      throw new Error(`Cannot fingerprint Harmony native artifact: ${artifact}`);
    }

    const relative = path.relative(options.projectRoot, artifact).split(path.sep).join('/');
    hash.update('\0artifact\0');
    hash.update(relative);
    hash.update('\0');
    hashFile(hash, artifact);
  }

  return {
    artifactCount: artifacts.length,
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

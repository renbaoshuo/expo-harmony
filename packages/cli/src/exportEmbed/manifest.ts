import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HarmonyCliError } from '../errors';
import { atomicCopy, atomicWriteJson, describeFile, listFiles, removeEmptyParents } from '../file';
import { assertSafeRelative, isInside, toPosixPath } from '../path';
import type { ExportTemporary } from './export';

export interface HarmonyExportFile {
  path: string;
  sha256: string;
  size: number;
}

export interface HarmonyExportManifest {
  assets: HarmonyExportFile[];
  bundle: HarmonyExportFile & { bytecodeVersion: number };
  entryFile: string;
  platform: 'harmony';
  schemaVersion: 1;
  sourceMap: HarmonyExportFile;
  transformProfile: 'hermes-stable';
}

const HermesMagic = Buffer.from('c61fbc03c103191f', 'hex');
const ManifestSchemaVersion = 1;

function exportPaths(plan: {
  exportPaths: {
    bundle: string;
    manifest: string;
    metadataRoot: string;
    rawfileRoot: string;
    sourceMap: string;
  };
}) {
  return plan.exportPaths;
}

async function assertHermesBundle(file) {
  let handle;
  try {
    handle = await fs.promises.open(file, 'r');
    const header = Buffer.alloc(12);
    const { bytesRead } = await handle.read(header, 0, header.length, 0);
    const stat = await handle.stat();

    if (bytesRead < header.length || stat.size <= header.length
      || header.subarray(0, HermesMagic.length).toString('hex') !== HermesMagic.toString('hex')) {
      throw new Error('Expo export did not produce non-empty Hermes bytecode.');
    }

    return { bytecodeVersion: header.readUInt32LE(8), size: stat.size };
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_EXPORT_INVALID_BUNDLE', 'The Harmony export output is not a valid Hermes bytecode bundle.', { cause, operation: 'validate-export' });
  } finally {
    await handle?.close();
  }
}

async function assertSourceMap(file) {
  try {
    const contents = await fs.promises.readFile(file, 'utf8');
    const sourceMap = JSON.parse(contents);
    const paths = JSON.stringify({ sourceRoot: sourceMap?.sourceRoot, sources: sourceMap?.sources });
    const sourcePaths = [sourceMap?.sourceRoot, ...(sourceMap?.sources || [])]
      .filter(value => typeof value === 'string');
    const hasAbsoluteSource = sourcePaths.some(value => (
      path.posix.isAbsolute(value) || path.win32.isAbsolute(value) || /^[A-Za-z][A-Za-z0-9+.-]*:\/\//u.test(value)
    ));

    if (sourceMap?.version !== 3 || !Array.isArray(sourceMap.sources)
      || hasAbsoluteSource || paths.includes(os.homedir())) {
      throw new Error('Invalid or host-specific source map.');
    }

    return await describeFile(file);
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_EXPORT_INVALID_SOURCEMAP', 'Expo export did not produce a portable source map.', { cause, operation: 'validate-export' });
  }
}

async function readPreviousManifest(file: string): Promise<HarmonyExportManifest | null> {
  try {
    const manifest = JSON.parse(await fs.promises.readFile(file, 'utf8'));
    if (manifest?.schemaVersion !== ManifestSchemaVersion || !Array.isArray(manifest.assets)) {
      throw new Error('Unsupported export manifest schema.');
    }

    for (const asset of manifest.assets) {
      assertSafeRelative(asset?.path, 'Previous export manifest');
    }

    return manifest;
  } catch (cause) {
    if (cause.code === 'ENOENT') return null;
    throw new HarmonyCliError('ERR_HARMONY_EXPORT_MANIFEST', 'Cannot read the previous Harmony export manifest.', { cause, operation: 'publish-export' });
  }
}

async function publishExportAsync(
  projectRoot: string,
  paths: ReturnType<typeof exportPaths>,
  temporary: ExportTemporary,
  entryFile: string,
  bytecode: Awaited<ReturnType<typeof assertHermesBundle>>
) {
  const previous = await readPreviousManifest(paths.manifest);
  const previouslyOwned = new Set((previous?.assets || []).map(asset => asset.path));
  const assetFiles = await listFiles(temporary.assets);
  const assetOutputs = [];

  for (const source of assetFiles) {
    const relative = toPosixPath(path.relative(temporary.assets, source));
    const nativeRelative = assertSafeRelative(relative, 'Expo asset output');
    const destination = path.join(paths.rawfileRoot, nativeRelative);
    if (await fs.promises.lstat(destination).catch(error => error.code === 'ENOENT' ? null : Promise.reject(error))) {
      if (!previouslyOwned.has(relative)) {
        throw new HarmonyCliError('ERR_HARMONY_EXPORT_COLLISION', `Expo asset output collides with an unmanaged raw resource: ${relative}.`, { operation: 'publish-export' });
      }
    }

    assetOutputs.push({ descriptor: { path: relative, ...(await describeFile(source)) }, source });
  }

  assetOutputs.sort((left, right) => left.descriptor.path.localeCompare(right.descriptor.path, 'en'));
  const assets = assetOutputs.map(output => output.descriptor);

  const bundle = await describeFile(temporary.bundle);
  const sourceMap = await describeFile(temporary.sourceMap);
  const manifest: HarmonyExportManifest = {
    assets,
    bundle: {
      bytecodeVersion: bytecode.bytecodeVersion,
      path: toPosixPath(path.relative(projectRoot, paths.bundle)),
      ...bundle,
    },
    entryFile: toPosixPath(path.relative(projectRoot, entryFile)),
    platform: 'harmony',
    schemaVersion: ManifestSchemaVersion,
    sourceMap: {
      path: toPosixPath(path.relative(projectRoot, paths.sourceMap)),
      ...sourceMap,
    },
    transformProfile: 'hermes-stable',
  };

  try {
    await atomicCopy(temporary.bundle, paths.bundle, paths.rawfileRoot);
    await atomicCopy(temporary.sourceMap, paths.sourceMap, paths.metadataRoot);
    for (const output of assetOutputs) {
      const relative = output.descriptor.path;
      await atomicCopy(
        output.source,
        path.join(paths.rawfileRoot, assertSafeRelative(relative, 'Expo asset output')),
        paths.rawfileRoot
      );
    }
    await atomicWriteJson(manifest, paths.manifest, path.dirname(paths.manifest));

    const nextOwned = new Set(assets.map(asset => asset.path));
    for (const stale of previouslyOwned) {
      if (nextOwned.has(stale)) continue;
      const destination = path.join(paths.rawfileRoot, assertSafeRelative(stale, 'Previous export manifest'));
      if (!isInside(paths.rawfileRoot, destination)) continue;
      await fs.promises.rm(destination, { force: true });
      await removeEmptyParents(destination, paths.rawfileRoot);
    }
  } catch (cause) {
    if (cause instanceof HarmonyCliError) {
      throw new HarmonyCliError(cause.code, cause.message, {
        cause,
        exitCode: cause.exitCode,
        operation: cause.operation,
      });
    }

    throw new HarmonyCliError('ERR_HARMONY_EXPORT_PUBLISH', 'Cannot publish the validated Harmony bundle and assets.', { cause, operation: 'publish-export' });
  }

  return manifest;
}

async function validatePublishedExportAsync(paths: ReturnType<typeof exportPaths>) {
  const manifest = await readPreviousManifest(paths.manifest);
  if (!manifest) {
    throw new HarmonyCliError('ERR_HARMONY_EXPORT_MANIFEST', 'Harmony export manifest does not exist. Run expo-harmony export:embed first.', { operation: 'check-export' });
  }

  const bytecode = await assertHermesBundle(paths.bundle);
  const sourceMap = await assertSourceMap(paths.sourceMap);
  const expectedBundle = await describeFile(paths.bundle);
  if (manifest.bundle?.sha256 !== expectedBundle.sha256
    || manifest.bundle?.size !== expectedBundle.size
    || manifest.bundle?.bytecodeVersion !== bytecode.bytecodeVersion
    || manifest.sourceMap?.sha256 !== sourceMap.sha256
    || manifest.sourceMap?.size !== sourceMap.size) {
    throw new HarmonyCliError('ERR_HARMONY_EXPORT_MANIFEST', 'Harmony bundle or source map differs from the export manifest.', { operation: 'check-export' });
  }

  for (const asset of manifest.assets) {
    const file = path.join(paths.rawfileRoot, assertSafeRelative(asset.path, 'Export manifest'));
    const actual = await describeFile(file).catch((cause) => {
      throw new HarmonyCliError('ERR_HARMONY_EXPORT_MANIFEST', `Harmony export asset is missing or invalid: ${asset.path}.`, { cause, operation: 'check-export' });
    });
    if (actual.sha256 !== asset.sha256 || actual.size !== asset.size) {
      throw new HarmonyCliError('ERR_HARMONY_EXPORT_MANIFEST', `Harmony export asset differs from the manifest: ${asset.path}.`, { operation: 'check-export' });
    }
  }

  return manifest;
}

export {
  HermesMagic,
  assertHermesBundle,
  assertSourceMap,
  exportPaths,
  publishExportAsync,
  validatePublishedExportAsync,
};

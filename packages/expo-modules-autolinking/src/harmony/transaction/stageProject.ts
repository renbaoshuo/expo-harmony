/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { ReactNativeCommunityCliPackage, RnohArtifacts } from '../../config/constants';
import { HarmonyAutolinkingError } from '../../errors';
import { createManifest } from '../manifest/generate';
import { resolveHarPath } from '../ohpm/dependencies';
import { canonicalizeOhpmManifest } from '../persistence/canonicalize';
import { resolveAppCommunityCliPackage, resolveRnohCliPackageJsonPath } from '../rnoh/cli';
import {
  isPathInside, pathExistsAsync, realpathExistingAsync, resolveInsideAsync,
  stringifyJson, sortedUniqueStrings,
} from '../../utilities/values';

function buildRnohMetadata(descriptor) {
  return {
    ...(descriptor.rnoh.ohPackageName === undefined
      ? {}
      : {
          ohPackageName: Array.isArray(descriptor.rnoh.ohPackageName)
            ? descriptor.rnoh.ohPackageName.map(mapping => ({ ...mapping }))
            : descriptor.rnoh.ohPackageName,
        }),
    mainHarPath: descriptor.rnoh.mainHarPath,
    ...(descriptor.rnoh.etsPackageClassName
      ? { etsPackageClassName: descriptor.rnoh.etsPackageClassName }
      : {}),
    ...(descriptor.rnoh.cppPackageClassName
      ? { cppPackageClassName: descriptor.rnoh.cppPackageClassName }
      : {}),
    ...(descriptor.rnoh.cmakeLibraryTargetName
      ? { cmakeLibraryTargetName: descriptor.rnoh.cmakeLibraryTargetName }
      : {}),
  };
}

async function stageCuratedPackageAsync(stage, descriptor) {
  const paths = sortedUniqueStrings([
    ...descriptor.rnoh.harPaths,
    ...(descriptor.arkTs ? [descriptor.arkTs.harPath] : []),
  ]);

  await fs.promises.mkdir(stage, { recursive: true });
  await fs.promises.writeFile(path.join(stage, 'package.json'), stringifyJson({
    name: descriptor.packageName,
    version: descriptor.packageVersion,
    ...(descriptor.rnoh.harPaths.length > 0
      ? { harmony: { autolinking: buildRnohMetadata(descriptor) } }
      : {}),
  }));

  for (const harPath of paths) {
    const selected = resolveHarPath(descriptor, harPath);
    const source = selected === descriptor.arkTs?.builtHarPath ? selected
      : await resolveInsideAsync(descriptor.packageRoot, harPath, 'descriptor HAR path', { packageName: descriptor.packageName, type: 'file' });
    const destination = path.resolve(stage, ...harPath.split('/'));
    if (!isPathInside(stage, destination)) {
      throw new HarmonyAutolinkingError('PATH_OUTSIDE_PACKAGE', 'A curated HAR path escapes its staging package.', {
        packageName: descriptor.packageName,
        stage: 'staging',
      });
    }

    await fs.promises.mkdir(path.dirname(destination), { recursive: true });
    await fs.promises.copyFile(source, destination, fs.constants.COPYFILE_FICLONE);
  }
}

async function readOhpmManifestSourceAsync(harmony: string): Promise<string | undefined> {
  const file = path.join(harmony, RnohArtifacts.ohPackage);
  try {
    const stat = await fs.promises.lstat(file);
    if (!stat.isFile() || stat.isSymbolicLink()) {
      throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'harmony/oh-package.json5 must be a regular file.', { stage: 'staging' });
    }
    return await fs.promises.readFile(file, 'utf8');
  } catch (cause) {
    if (cause.code === 'ENOENT') return undefined;
    throw cause;
  }
}

async function stageProjectAsync(options) {
  const root = await realpathExistingAsync(options.projectRoot, {
    type: 'directory',
    field: 'projectRoot',
    stage: 'staging',
  });

  const harmony = await realpathExistingAsync(options.harmonyProjectPath, {
    type: 'directory',
    field: 'harmonyProjectPath',
    stage: 'staging',
  });

  if (!isPathInside(root, harmony)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'harmonyProjectPath must be inside projectRoot.', { stage: 'staging' });
  }

  const source = options.nodeModulesPath && await realpathExistingAsync(options.nodeModulesPath, {
    type: 'directory',
    field: 'nodeModulesPath',
    stage: 'staging',
  });

  const pkg = await realpathExistingAsync(
    options.rnohCliPackageJsonPath || resolveRnohCliPackageJsonPath(),
    { type: 'file', code: 'RNOH_CLI_NOT_FOUND', field: 'RNOH CLI package.json', stage: 'rnoh-preflight' }
  );
  const plugin = await realpathExistingAsync(path.join(path.dirname(pkg), 'react-native.config.js'), {
    type: 'file',
    code: 'RNOH_CLI_NOT_FOUND',
    field: 'RNOH CLI plugin config',
    stage: 'rnoh-preflight',
  });

  const tmp = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-harmony-autolinking-'));

  try {
    const project = path.join(tmp, 'project');
    const relative = path.relative(root, harmony);
    const target = path.join(project, relative);
    const modules = path.join(project, 'node_modules');

    await fs.promises.mkdir(target, { recursive: true });
    await fs.promises.writeFile(path.join(project, 'package.json'), stringifyJson({
      name: 'expo-harmony-autolinking-stage',
      private: true,
    }));

    await fs.promises.writeFile(
      path.join(project, 'react-native.config.js'),
      `module.exports = require(${JSON.stringify(plugin)});\n`
    );

    const runtime = [];
    const selected = options.modules.filter(descriptor => (
      descriptor.rnoh.harPaths.length > 0 || descriptor.arkTs
    ));

    await fs.promises.mkdir(modules, { recursive: true });

    for (const descriptor of selected) {
      const segments = descriptor.packageName.split('/');
      const valid = segments.length === 1
        ? segments[0] && !segments[0].startsWith('@')
        : segments.length === 2 && segments[0].startsWith('@') && segments[0].length > 1 && segments[1];
      if (!valid || segments.some(segment => segment === '.' || segment === '..' || segment.includes('\\'))) {
        throw new HarmonyAutolinkingError('INVALID_METADATA', `Invalid npm package name for curated staging: ${descriptor.packageName}`, {
          packageName: descriptor.packageName,
          stage: 'staging',
        });
      }

      const stage = path.join(modules, ...segments);
      await fs.promises.mkdir(path.dirname(stage), { recursive: true });
      await stageCuratedPackageAsync(stage, descriptor);
    }

    const communityCli = resolveAppCommunityCliPackage(root);
    if (communityCli) {
      const packageRoot = await fs.promises.realpath(path.dirname(communityCli));
      const target = path.join(modules, ...ReactNativeCommunityCliPackage.split('/'));
      if (!(await pathExistsAsync(target))) {
        await fs.promises.mkdir(path.dirname(target), { recursive: true });
        await fs.promises.symlink(packageRoot, target, process.platform === 'win32' ? 'junction' : 'dir');
      }
      runtime.push(ReactNativeCommunityCliPackage);
    }

    for (const relative of Object.values(RnohArtifacts)) {
      await fs.promises.mkdir(path.dirname(path.join(target, relative)), { recursive: true });
    }

    const previousOhpmManifest = await readOhpmManifestSourceAsync(harmony);
    const manifest = createManifest(options.modules, { buildType: options.buildType });
    const ohpmManifest = canonicalizeOhpmManifest(previousOhpmManifest ?? '{}\n', manifest, {
      previousManagedOhpmPackageNames: options.previousManagedOhpmPackageNames,
      stage: 'staging',
    }).source;
    await fs.promises.writeFile(path.join(target, RnohArtifacts.ohPackage), ohpmManifest);

    return {
      projectRoot: root,
      harmonyProjectPath: harmony,
      sourceNodeModulesPath: source,
      previousOhpmManifest,
      ohpmManifest,
      nodeModulesPath: modules,
      rnohRuntimePackages: runtime,
      temporaryRoot: tmp,
      stageProjectRoot: project,
      stageHarmonyProjectPath: target,
    };
  } catch (cause) {
    let warning;

    try {
      await fs.promises.rm(tmp, { recursive: true, force: true });
    } catch (error) {
      warning = {
        severity: 'warning',
        code: 'ERR_EXPO_HARMONY_STAGING_CLEANUP_FAILED',
        message: 'Unable to remove a partially-created Harmony autolinking staging directory.',
        stage: 'cleanup',
        details: { message: error.message },
      };
    }

    throw new HarmonyAutolinkingError(
      typeof cause.code === 'string' ? cause.code : 'STAGING_FAILED',
      cause.message || 'Unable to stage the Harmony project.',
      {
        cause,
        stage: cause.stage || 'staging',
        packageName: cause.packageName,
        diagnostics: cause.diagnostics,
        details: warning
          ? { ...(cause.details || {}), cleanupWarning: warning }
          : cause.details,
      }
    );
  }
}

async function cleanupStagingProjectAsync(staging) {
  try {
    await fs.promises.rm(staging.temporaryRoot, { recursive: true, force: true });
    return null;
  } catch (cause) {
    return {
      severity: 'warning',
      code: 'ERR_EXPO_HARMONY_STAGING_CLEANUP_FAILED',
      message: 'Unable to remove the Harmony autolinking staging directory.',
      stage: 'cleanup',
      cause,
    };
  }
}

export {
  cleanupStagingProjectAsync,
  readOhpmManifestSourceAsync,
  stageProjectAsync,
};

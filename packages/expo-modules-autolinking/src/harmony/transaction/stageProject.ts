import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import JSON5 from 'json5';

import { RnohArtifacts, RnohCliPackage } from '../../config/constants';
import { HarmonyAutolinkingError } from '../../errors';
import { resolveProviderSource } from '../providers/source';
import { collectOhpmDeps, resolveOhpmSpecifier, normalizeLocalOhpmSpecifier } from '../ohpm/dependencies';
import {
  isPathInside, pathExistsAsync, realpathExistingAsync, resolveInsideAsync,
  resolvePackageFromProject, stringifyJson, sortedUniqueStrings,
} from '../../utilities/values';

async function findLocalOhpmDepsAsync(content, harmony) {
  let dependencies;
  try {
    const parsed = JSON5.parse(content);
    dependencies = parsed && typeof parsed.dependencies === 'object' && !Array.isArray(parsed.dependencies)
      ? parsed.dependencies
      : {};
  } catch (_cause) {
    return [];
  }

  const result = [];

  for (const [name, specifier] of Object.entries(dependencies)) {
    const relative = normalizeLocalOhpmSpecifier(specifier);
    if (!relative) continue;

    const harPath = path.resolve(harmony, relative);
    if (!(await pathExistsAsync(harPath))) continue;

    const marker = `${path.sep}node_modules${path.sep}`;
    const markerIndex = harPath.lastIndexOf(marker);
    if (markerIndex < 0) continue;

    const rest = harPath.slice(markerIndex + marker.length).split(path.sep);
    const packageSegments = rest[0]?.startsWith('@') ? rest.slice(0, 2) : rest.slice(0, 1);
    if (packageSegments.length === 0 || packageSegments.some(segment => !segment)) continue;

    const packageName = packageSegments.join('/');
    const packageRoot = path.join(harPath.slice(0, markerIndex + marker.length), ...packageSegments);

    try {
      const packageJson = JSON.parse(await fs.promises.readFile(path.join(packageRoot, 'package.json'), 'utf8'));
      if (packageJson.name !== packageName) continue;
      result.push({
        ohPackageName: name,
        specifier,
        packageName,
        packageRoot: await fs.promises.realpath(packageRoot),
      });
    } catch (_cause) {
      // RNOH would not be able to preserve an unreadable package reference either.
    }
  }

  return result;
}

async function findNodeModulesAsync(projectRoot) {
  let directory = projectRoot;

  while (true) {
    const candidate = path.join(directory, 'node_modules');
    if (await pathExistsAsync(candidate)) return candidate;
    const parent = path.dirname(directory);
    if (parent === directory) return path.join(projectRoot, 'node_modules');
    directory = parent;
  }
}

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
  await fs.promises.mkdir(stage, { recursive: true });
  await fs.promises.writeFile(path.join(stage, 'package.json'), stringifyJson({
    name: descriptor.packageName,
    version: descriptor.packageVersion,
    ...(descriptor.rnoh.harPaths.length > 0
      ? { harmony: { autolinking: buildRnohMetadata(descriptor) } }
      : {}),
  }));

  const harPaths = sortedUniqueStrings([
    ...descriptor.rnoh.harPaths,
    ...(descriptor.expo.providerHar ? [descriptor.expo.providerHar.harPath] : []),
  ]);

  for (const harPath of harPaths) {
    const source = await resolveInsideAsync(descriptor.packageRoot, harPath, 'descriptor.rnoh.harPaths', { packageName: descriptor.packageName, type: 'file' });
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

async function updateOhpmManifestAsync(manifestPath, descriptors, options) {
  const deps = collectOhpmDeps(descriptors, options.buildType);
  let manifest;
  try {
    manifest = JSON5.parse(await fs.promises.readFile(manifestPath, 'utf8')) as Record<string, any>;
  } catch (cause) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'harmony/oh-package.json5 must contain a JSON5 object.', {
      cause,
      stage: 'staging',
    });
  }

  if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'harmony/oh-package.json5 must contain a JSON5 object.', { stage: 'staging' });
  }

  for (const field of ['dependencies', 'overrides']) {
    if (manifest[field] !== undefined && (!manifest[field] || typeof manifest[field] !== 'object' || Array.isArray(manifest[field]))) {
      throw new HarmonyAutolinkingError('INVALID_OPTIONS', `harmony/oh-package.json5 ${field} must be an object.`, { stage: 'staging' });
    }
  }

  manifest.dependencies = { ...(manifest.dependencies || {}) };
  manifest.overrides = { ...(manifest.overrides || {}) };
  const previous = new Set<string>(options.previousManagedOhpmPackageNames || []);

  for (const packageName of previous) {
    delete manifest.dependencies[packageName];
    delete manifest.overrides[packageName];
  }

  for (const { descriptor, mapping } of deps) {
    const specifier = resolveOhpmSpecifier(descriptor, mapping);
    manifest.dependencies[mapping.ohPackageName] = specifier;
    manifest.overrides[mapping.ohPackageName] = specifier;
  }

  await fs.promises.writeFile(manifestPath, `${JSON5.stringify(manifest, null, 2)}\n`);
}

async function stageProjectAsync(options) {
  const projectRoot = await realpathExistingAsync(options.projectRoot, {
    type: 'directory',
    field: 'projectRoot',
    stage: 'staging',
  });

  const harmony = await realpathExistingAsync(options.harmonyProjectPath, {
    type: 'directory',
    field: 'harmonyProjectPath',
    stage: 'staging',
  });

  if (!isPathInside(projectRoot, harmony)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'harmonyProjectPath must be inside projectRoot.', { stage: 'staging' });
  }

  const requested = options.nodeModulesPath || await findNodeModulesAsync(projectRoot);
  const source = await realpathExistingAsync(requested, {
    type: 'directory',
    field: 'nodeModulesPath',
    stage: 'staging',
  });

  const tmp = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-harmony-autolinking-'));
  try {
    const stageRoot = path.join(tmp, 'project');
    const relative = path.relative(projectRoot, harmony);
    const stageHarmony = path.join(stageRoot, relative);
    const modules = path.join(stageRoot, 'node_modules');
    await fs.promises.mkdir(stageHarmony, { recursive: true });
    await fs.promises.writeFile(path.join(stageRoot, 'package.json'), stringifyJson({
      name: 'expo-harmony-autolinking-stage',
      private: true,
    }));

    let plugin = `${RnohCliPackage}/react-native.config.js`;
    try {
      const pkg = options.rnohCliPackageJsonPath
        ? await fs.promises.realpath(options.rnohCliPackageJsonPath)
        : resolvePackageFromProject(projectRoot, `${RnohCliPackage}/package.json`);
      plugin = await fs.promises.realpath(path.join(path.dirname(pkg), 'react-native.config.js'));
    } catch (_cause) {
      // Preflight emits the actionable package/CLI diagnostic. Keeping the public
      // package request here also lets callers inspect a stage without installing RNOH.
    }

    await fs.promises.writeFile(
      path.join(stageRoot, 'react-native.config.js'),
      `module.exports = require(${JSON.stringify(plugin)});\n`
    );

    const roots = [];
    const runtime = [];
    const allowed = {};

    if (options.modules === undefined) {
      await fs.promises.symlink(source, modules, process.platform === 'win32' ? 'junction' : 'dir');
    } else {
      await fs.promises.mkdir(modules, { recursive: true });
      const staged = options.modules.filter(descriptor =>
        descriptor.rnoh.harPaths.length > 0
        || resolveProviderSource(descriptor, options.buildType) !== null
      );

      for (const descriptor of staged) {
        const segments = descriptor.packageName.split('/');
        const validName = segments.length === 1
          ? segments[0] && !segments[0].startsWith('@')
          : segments.length === 2 && segments[0].startsWith('@') && segments[0].length > 1 && segments[1];
        if (!validName || segments.some(segment => segment === '.' || segment === '..' || segment.includes('\\'))) {
          throw new HarmonyAutolinkingError('INVALID_METADATA', `Invalid npm package name for curated staging: ${descriptor.packageName}`, {
            packageName: descriptor.packageName,
            stage: 'staging',
          });
        }
        const stage = path.join(modules, ...segments);
        await fs.promises.mkdir(path.dirname(stage), { recursive: true });
        await stageCuratedPackageAsync(stage, descriptor);
        roots.push(descriptor.packageRoot);
      }

      const actual = path.join(harmony, RnohArtifacts.ohPackage);
      if (await pathExistsAsync(actual)) {
        const content = await fs.promises.readFile(actual, 'utf8');
        const previous = new Set(options.previousManagedOhpmPackageNames || []);
        const verified = new Set(staged.map(item => item.packageName));

        for (const dependency of await findLocalOhpmDepsAsync(content, harmony)) {
          if (previous.has(dependency.ohPackageName)) continue;
          allowed[dependency.ohPackageName] = dependency.specifier;
          if (verified.has(dependency.packageName)) continue;
          const target = path.join(modules, ...dependency.packageName.split('/'));
          if (!(await pathExistsAsync(target))) {
            await fs.promises.mkdir(path.dirname(target), { recursive: true });
            await fs.promises.symlink(
              dependency.packageRoot,
              target,
              process.platform === 'win32' ? 'junction' : 'dir'
            );
          }
          runtime.push(dependency.packageName);
        }
      }

      try {
        const packageName = '@react-native-community/cli';
        const pkg = resolvePackageFromProject(projectRoot, `${packageName}/package.json`);
        const packageRoot = await fs.promises.realpath(path.dirname(pkg));
        const target = path.join(modules, ...packageName.split('/'));
        if (!(await pathExistsAsync(target))) {
          await fs.promises.mkdir(path.dirname(target), { recursive: true });
          await fs.promises.symlink(packageRoot, target, process.platform === 'win32' ? 'junction' : 'dir');
        }
        runtime.push(packageName);
      } catch (_cause) {
        // Explicit/fake executables need not install the React Native wrapper runtime.
      }
    }

    for (const relativePath of Object.values(RnohArtifacts)) {
      await fs.promises.mkdir(path.dirname(path.join(stageHarmony, relativePath)), { recursive: true });
    }

    const actual = path.join(harmony, RnohArtifacts.ohPackage);
    const stage = path.join(stageHarmony, RnohArtifacts.ohPackage);
    if (await pathExistsAsync(actual)) {
      const stat = await fs.promises.lstat(actual);
      if (!stat.isFile() || stat.isSymbolicLink()) {
        throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'harmony/oh-package.json5 must be a regular file.', { stage: 'staging' });
      }
      await fs.promises.copyFile(actual, stage);
    } else {
      await fs.promises.writeFile(stage, '{\n  dependencies: {}\n}\n');
    }

    if (options.modules !== undefined) {
      await updateOhpmManifestAsync(stage, options.modules, {
        buildType: options.buildType,
        harmonyProjectPath: stageHarmony,
        nodeModulesPath: modules,
        previousManagedOhpmPackageNames: options.previousManagedOhpmPackageNames,
      });
    }

    return {
      projectRoot,
      harmonyProjectPath: harmony,
      sourceNodeModulesPath: source,
      nodeModulesPath: modules,
      rnohPackageRoots: roots,
      rnohRuntimePackages: runtime,
      allowedUnmanagedDependencies: allowed,
      temporaryRoot: tmp,
      stageProjectRoot: stageRoot,
      stageHarmonyProjectPath: stageHarmony,
    };
  } catch (cause) {
    try {
      await fs.promises.rm(tmp, { recursive: true, force: true });
    } catch (cleanupCause) {
      cause.cleanupWarning = {
        severity: 'warning',
        code: 'ERR_EXPO_HARMONY_STAGING_CLEANUP_FAILED',
        message: 'Unable to remove a partially-created Harmony autolinking staging directory.',
        stage: 'cleanup',
        details: { message: cleanupCause.message },
      };
    }

    throw cause;
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
  stageProjectAsync,
  findLocalOhpmDepsAsync,
  updateOhpmManifestAsync,
};

import path from 'node:path';

import type { NormalizedHarmonyConfig } from '@expo-harmony/config-plugins';

const BuildDescriptorSchemaVersion = 1;
const BuildModes = Object.freeze(['debug', 'release'] as const);

type HarmonyBuildMode = typeof BuildModes[number];

interface HarmonyBuildVariantDescriptor {
  expectedHap: string;
  hvigorArgs: string[];
}

interface HarmonyBuildDescriptor {
  export: {
    bundle: string;
    manifest: string;
    metadataRoot: string;
    rawfileRoot: string;
    sourceMap: string;
  };
  harmonyRoot: string;
  identity: {
    abilityName: string;
    bundleName: string;
    moduleName: string;
    productName: string;
    targetName: string;
  };
  moduleRoot: string;
  nativeCache: {
    invalidationRoots: string[];
    stateFile: string;
  };
  nativeInputs: {
    lockfile: string;
    manifest: string;
  };
  schemaVersion: typeof BuildDescriptorSchemaVersion;
  variants: Record<HarmonyBuildMode, HarmonyBuildVariantDescriptor>;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isSafeRelativePath(value: unknown): value is string {
  if (!isNonEmptyString(value)
    || value.includes('\\')
    || path.posix.isAbsolute(value)
    || path.win32.isAbsolute(value)
    || path.posix.normalize(value) !== value) {
    return false;
  }

  const segments = value.split('/');
  return segments.every(segment => segment && segment !== '.' && segment !== '..');
}

function isStrictDescendant(root: string, target: string): boolean {
  const relative = path.posix.relative(root, target);
  return Boolean(relative)
    && relative !== '..'
    && !relative.startsWith('../')
    && !path.posix.isAbsolute(relative);
}

function validateVariant(value: unknown): HarmonyBuildVariantDescriptor {
  if (!isRecord(value)
    || !isSafeRelativePath(value.expectedHap)
    || !Array.isArray(value.hvigorArgs)
    || value.hvigorArgs.length === 0
    || value.hvigorArgs.some(argument => !isNonEmptyString(argument) || /\0|[\r\n]/u.test(argument))) {
    throw new TypeError('Harmony build descriptor contains an invalid build variant.');
  }

  return value as unknown as HarmonyBuildVariantDescriptor;
}

function validateHarmonyBuildDescriptor(value: unknown): HarmonyBuildDescriptor {
  if (!isRecord(value) || value.schemaVersion !== BuildDescriptorSchemaVersion) {
    throw new TypeError(`Unsupported Harmony build descriptor schema: ${isRecord(value) ? value.schemaVersion : 'invalid'}.`);
  }

  if (!isSafeRelativePath(value.harmonyRoot)
    || !isSafeRelativePath(value.moduleRoot)
    || !isStrictDescendant(value.harmonyRoot, value.moduleRoot)) {
    throw new TypeError('Harmony build descriptor contains invalid project roots.');
  }

  const identity = value.identity;
  if (!isRecord(identity)
    || ['abilityName', 'bundleName', 'moduleName', 'productName', 'targetName']
      .some(field => !isNonEmptyString(identity[field]))) {
    throw new TypeError('Harmony build descriptor contains an invalid identity.');
  }

  const inputs = value.nativeInputs;
  if (!isRecord(inputs)
    || !isSafeRelativePath(inputs.manifest)
    || !isSafeRelativePath(inputs.lockfile)
    || !isStrictDescendant(value.harmonyRoot, inputs.manifest)
    || !isStrictDescendant(value.harmonyRoot, inputs.lockfile)) {
    throw new TypeError('Harmony build descriptor contains invalid native input paths.');
  }

  const cache = value.nativeCache;
  if (!isRecord(cache)
    || !isSafeRelativePath(cache.stateFile)
    || !isStrictDescendant(value.moduleRoot, cache.stateFile)
    || !Array.isArray(cache.invalidationRoots)
    || cache.invalidationRoots.length === 0
    || cache.invalidationRoots.some(item => (
      !isSafeRelativePath(item) || !isStrictDescendant(value.moduleRoot as string, item)
    ))) {
    throw new TypeError('Harmony build descriptor contains invalid native cache paths.');
  }

  const output = value.export;
  if (!isRecord(output)) {
    throw new TypeError('Harmony build descriptor contains invalid export paths.');
  }

  const invalidPath = ['bundle', 'manifest', 'metadataRoot', 'rawfileRoot', 'sourceMap']
    .some(field => !isSafeRelativePath(output[field]));
  if (invalidPath
    || !isStrictDescendant(value.moduleRoot, output.rawfileRoot as string)
    || !isStrictDescendant(output.rawfileRoot as string, output.bundle as string)
    || !isStrictDescendant(output.metadataRoot as string, output.sourceMap as string)) {
    throw new TypeError('Harmony build descriptor contains invalid export paths.');
  }

  if (!isRecord(value.variants)
    || Object.keys(value.variants).length !== BuildModes.length
    || BuildModes.some(mode => !Object.hasOwn(value.variants as object, mode))) {
    throw new TypeError('Harmony build descriptor must define debug and release variants.');
  }

  for (const mode of BuildModes) {
    const variant = validateVariant(value.variants[mode]);
    if (!isStrictDescendant(value.moduleRoot, variant.expectedHap)) {
      throw new TypeError(`Harmony ${mode} HAP output must be inside the module root.`);
    }
  }

  return value as unknown as HarmonyBuildDescriptor;
}

function createHarmonyBuildDescriptor(
  config: NormalizedHarmonyConfig,
  signing: string | null
): HarmonyBuildDescriptor {
  const harmony = 'harmony';
  const module = `${harmony}/entry`;
  const target = 'default';
  const rawfile = `${module}/src/main/resources/rawfile`;
  const suffix = signing ? 'signed' : 'unsigned';

  const variants = Object.fromEntries(BuildModes.map(mode => [mode, {
    expectedHap: `${module}/build/${target}/outputs/${target}/${config.moduleName}-${target}-${suffix}.hap`,
    hvigorArgs: [
      '--mode', 'module',
      '-p', `module=${config.moduleName}@${target}`,
      '-p', `product=${config.productName}`,
      '-p', `buildMode=${mode}`,
      '--no-daemon',
      'assembleHap',
    ],
  }])) as Record<HarmonyBuildMode, HarmonyBuildVariantDescriptor>;

  return validateHarmonyBuildDescriptor({
    export: {
      bundle: `${rawfile}/hermes_bundle.hbc`,
      manifest: '.expo/harmony/export-manifest.json',
      metadataRoot: '.expo/harmony/export',
      rawfileRoot: rawfile,
      sourceMap: '.expo/harmony/export/hermes_bundle.hbc.map',
    },
    harmonyRoot: harmony,
    identity: {
      abilityName: config.abilityName,
      bundleName: config.bundleName,
      moduleName: config.moduleName,
      productName: config.productName,
      targetName: target,
    },
    moduleRoot: module,
    nativeCache: {
      invalidationRoots: [`${module}/.cxx`, `${module}/build`],
      stateFile: `${module}/.cxx/.expo-harmony-native-dependencies.json`,
    },
    nativeInputs: {
      lockfile: `${harmony}/oh-package-lock.json5`,
      manifest: `${harmony}/oh-package.json5`,
    },
    schemaVersion: BuildDescriptorSchemaVersion,
    variants,
  });
}

function harmonyModuleSourcePath(build: HarmonyBuildDescriptor): string {
  return `./${path.posix.relative(build.harmonyRoot, build.moduleRoot)}`;
}

export {
  BuildDescriptorSchemaVersion,
  BuildModes,
  createHarmonyBuildDescriptor,
  harmonyModuleSourcePath,
  validateHarmonyBuildDescriptor,
};
export type {
  HarmonyBuildDescriptor,
  HarmonyBuildMode,
  HarmonyBuildVariantDescriptor,
};

import { promises as fs } from 'node:fs';
import path from 'node:path';

import JSON5 from 'json5';

import { HarmonyPlatformDirectory } from './buildDescriptor';
import { HarmonyPrebuildError } from './errors';

const MaterialFields = [
  'certpath', 'storePassword', 'keyAlias', 'keyPassword',
  'profile', 'signAlg', 'storeFile',
] as const;
type MaterialField = typeof MaterialFields[number];
type MaterialPathField = Extract<MaterialField, 'certpath' | 'profile' | 'storeFile'>;
const MaterialPathFields = new Set<MaterialField>(['certpath', 'profile', 'storeFile']);

interface SigningFile {
  config: {
    material: Record<MaterialField, string>;
    name: string;
    type: 'HarmonyOS';
    [key: string]: unknown;
  };
  file: string;
  materialFiles: Partial<Record<MaterialPathField, string>>;
}

interface HarmonySigningConfig {
  file: string;
  materialFiles: Partial<Record<'certpath' | 'profile' | 'storeFile', string>>;
  name: string;
  type: 'HarmonyOS';
}

function isInside(root, target) {
  const relative = path.relative(root, target);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function mirrorAbsolutePath(temp, source) {
  const absolute = path.resolve(source);
  const parsed = path.parse(absolute);
  const volume = parsed.root.replace(/[^A-Za-z0-9]+/gu, '') || 'root';
  const segments = absolute.slice(parsed.root.length).split(path.sep).filter(Boolean);

  return path.join(temp, 'filesystem', volume, ...segments);
}

function resolveSigningPath(base, reference) {
  const resolved = path.resolve(base, reference);
  const mirror = process.env.EXPO_HARMONY_CHECK_MIRROR_ROOT;

  return mirror && path.isAbsolute(reference)
    ? mirrorAbsolutePath(path.resolve(mirror), resolved)
    : resolved;
}

function selectSigningConfig(parsed, file) {
  const source = parsed?.app?.signingConfigs ?? parsed?.signingConfigs ?? parsed;
  const candidates = Array.isArray(source) ? source : [source];
  const configs = candidates.filter(item => item && typeof item === 'object' && !Array.isArray(item));

  if (configs.length !== candidates.length || configs.length === 0) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_SIGNING_INVALID',
      'Signing config file must contain a signing config object or a non-empty signingConfigs array.',
      { file, operation: 'validate-signing' }
    );
  }

  const config = configs.find(item => item.name === 'default') || (configs.length === 1 ? configs[0] : null);

  if (!config) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_SIGNING_INVALID',
      'Signing config file contains multiple entries but none is named default.',
      { file, operation: 'validate-signing' }
    );
  }

  return config;
}

async function readSigningConfigFile(root: string, reference: string): Promise<SigningFile> {
  const file = resolveSigningPath(root, reference);
  const harmony = path.join(root, HarmonyPlatformDirectory);

  if (isInside(harmony, file)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_SIGNING_INVALID',
      'harmony.signingConfigFile must be outside the generated harmony directory so --clean cannot delete it.',
      { file, operation: 'validate-signing' }
    );
  }

  let content;

  try {
    const stat = await fs.stat(file);
    if (!stat.isFile()) {
      throw new HarmonyPrebuildError(
        'ERR_HARMONY_SIGNING_INVALID',
        'Harmony signing config reference must be a regular file.',
        { file, operation: 'validate-signing' }
      );
    }

    content = await fs.readFile(file, 'utf8');
  } catch (cause) {
    if (cause?.code === 'ERR_HARMONY_SIGNING_INVALID') return Promise.reject(cause);

    throw new HarmonyPrebuildError(
      'ERR_HARMONY_SIGNING_INVALID',
      'Cannot read harmony.signingConfigFile.',
      { cause, file, operation: 'validate-signing' }
    );
  }

  let parsed;

  try {
    parsed = JSON5.parse(content);
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_SIGNING_INVALID',
      'Cannot parse harmony.signingConfigFile as JSON5.',
      { cause, file, operation: 'validate-signing' }
    );
  }

  const config = selectSigningConfig(parsed, file);

  if (typeof config.name !== 'string' || !config.name.trim()) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_SIGNING_INVALID',
      'Harmony signing config name must be a non-empty string.',
      { file, operation: 'validate-signing' }
    );
  }
  if (config.type !== undefined && config.type !== 'HarmonyOS') {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_SIGNING_INVALID',
      'Harmony signing config type must be HarmonyOS.',
      { file, operation: 'validate-signing' }
    );
  }
  if (!config.material || typeof config.material !== 'object' || Array.isArray(config.material)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_SIGNING_INVALID',
      'Harmony signing config material must be an object.',
      { file, operation: 'validate-signing' }
    );
  }

  const material = { ...config.material };
  const files: Partial<Record<MaterialPathField, string>> = {};

  for (const field of MaterialFields) {
    const value = material[field];
    if (typeof value !== 'string' || !value.trim()) {
      throw new HarmonyPrebuildError(
        'ERR_HARMONY_SIGNING_INVALID',
        `Harmony signing material field ${field} must be a non-empty string.`,
        { file, operation: 'validate-signing' }
      );
    }

    if (MaterialPathFields.has(field)) {
      const resolved = resolveSigningPath(path.dirname(file), value);

      if (isInside(harmony, resolved)) {
        throw new HarmonyPrebuildError(
          'ERR_HARMONY_SIGNING_INVALID',
          `Harmony signing material field ${field} must be outside the generated harmony directory so --clean cannot delete it.`,
          { file, operation: 'validate-signing' }
        );
      }

      try {
        const stat = await fs.stat(resolved);
        if (!stat.isFile()) {
          throw new HarmonyPrebuildError(
            'ERR_HARMONY_SIGNING_INVALID',
            `Harmony signing material field ${field} must reference a regular file.`,
            { file, operation: 'validate-signing' }
          );
        }
      } catch (cause) {
        if (cause?.code === 'ERR_HARMONY_SIGNING_INVALID') return Promise.reject(cause);

        throw new HarmonyPrebuildError(
          'ERR_HARMONY_SIGNING_INVALID',
          `Cannot read the file referenced by Harmony signing material field ${field}.`,
          { cause, file, operation: 'validate-signing' }
        );
      }

      const relative = path.relative(harmony, resolved);

      if (!relative || path.isAbsolute(relative)) {
        throw new HarmonyPrebuildError(
          'ERR_HARMONY_SIGNING_INVALID',
          `Harmony signing material field ${field} must be on the same filesystem volume as the project.`,
          { file, operation: 'validate-signing' }
        );
      }

      material[field] = relative.split(path.sep).join('/');
      files[field as MaterialPathField] = resolved;
    }
  }

  if (material.signAlg !== 'SHA256withECDSA') {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_SIGNING_INVALID',
      'Harmony signing material signAlg must be SHA256withECDSA.',
      { file, operation: 'validate-signing' }
    );
  }

  return {
    config: {
      ...config,
      name: config.name.trim(),
      type: 'HarmonyOS',
      material,
    },
    file,
    materialFiles: files,
  };
}

async function validateHarmonySigningConfigFile(root: string, reference: string): Promise<HarmonySigningConfig> {
  const signing = await readSigningConfigFile(root, reference);

  return {
    file: signing.file,
    materialFiles: signing.materialFiles,
    name: signing.config.name,
    type: signing.config.type,
  };
}

export {
  MaterialFields,
  readSigningConfigFile,
  validateHarmonySigningConfigFile,
};
export type {
  HarmonySigningConfig,
};

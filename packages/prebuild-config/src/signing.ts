import { promises as fs } from 'node:fs';
import path from 'node:path';

import JSON5 from 'json5';

import { HarmonySigningError } from './errors';

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

function mirrorAbsolutePath(temporaryRoot, source) {
  const absolute = path.resolve(source);
  const parsed = path.parse(absolute);
  const volume = parsed.root.replace(/[^A-Za-z0-9]+/gu, '') || 'root';
  const segments = absolute.slice(parsed.root.length).split(path.sep).filter(Boolean);
  return path.join(temporaryRoot, 'filesystem', volume, ...segments);
}

function resolveSigningPath(base, reference) {
  const resolved = path.resolve(base, reference);
  const mirrorRoot = process.env.EXPO_HARMONY_CHECK_MIRROR_ROOT;
  return mirrorRoot && path.isAbsolute(reference)
    ? mirrorAbsolutePath(path.resolve(mirrorRoot), resolved)
    : resolved;
}

function selectSigningConfig(parsed, file) {
  const source = parsed?.app?.signingConfigs ?? parsed?.signingConfigs ?? parsed;
  const candidates = Array.isArray(source) ? source : [source];
  const objects = candidates.filter(item => item && typeof item === 'object' && !Array.isArray(item));
  if (objects.length !== candidates.length || objects.length === 0) {
    throw new HarmonySigningError('Signing config file must contain a signing config object or a non-empty signingConfigs array.', { file });
  }
  const selected = objects.find(item => item.name === 'default') || (objects.length === 1 ? objects[0] : null);
  if (!selected) {
    throw new HarmonySigningError('Signing config file contains multiple entries but none is named default.', { file });
  }
  return selected;
}

async function readSigningConfigFile(projectRoot: string, reference: string): Promise<SigningFile> {
  const file = resolveSigningPath(projectRoot, reference);
  const harmonyRoot = path.join(projectRoot, 'harmony');
  if (isInside(harmonyRoot, file)) {
    throw new HarmonySigningError('harmony.signingConfigFile must be outside the generated harmony directory so --clean cannot delete it.', { file });
  }

  let source;
  try {
    const stat = await fs.stat(file);
    if (!stat.isFile()) {
      throw new HarmonySigningError('Harmony signing config reference must be a regular file.', { file });
    }
    source = await fs.readFile(file, 'utf8');
  } catch (cause) {
    if (cause?.code === 'ERR_HARMONY_SIGNING_INVALID') return Promise.reject(cause);
    throw new HarmonySigningError('Cannot read harmony.signingConfigFile.', { cause, file });
  }

  let parsed;
  try {
    parsed = JSON5.parse(source);
  } catch (cause) {
    throw new HarmonySigningError('Cannot parse harmony.signingConfigFile as JSON5.', { cause, file });
  }

  const selected = selectSigningConfig(parsed, file);
  if (typeof selected.name !== 'string' || !selected.name.trim()) {
    throw new HarmonySigningError('Harmony signing config name must be a non-empty string.', { file });
  }
  if (selected.type !== undefined && selected.type !== 'HarmonyOS') {
    throw new HarmonySigningError('Harmony signing config type must be HarmonyOS.', { file });
  }
  if (!selected.material || typeof selected.material !== 'object' || Array.isArray(selected.material)) {
    throw new HarmonySigningError('Harmony signing config material must be an object.', { file });
  }

  const material = { ...selected.material };
  const materialFiles: Partial<Record<MaterialPathField, string>> = {};
  for (const field of MaterialFields) {
    const value = material[field];
    if (typeof value !== 'string' || !value.trim()) {
      throw new HarmonySigningError(`Harmony signing material field ${field} must be a non-empty string.`, { file });
    }
    if (MaterialPathFields.has(field)) {
      const resolved = resolveSigningPath(path.dirname(file), value);
      if (isInside(harmonyRoot, resolved)) {
        throw new HarmonySigningError(`Harmony signing material field ${field} must be outside the generated harmony directory so --clean cannot delete it.`, { file });
      }
      try {
        const stat = await fs.stat(resolved);
        if (!stat.isFile()) {
          throw new HarmonySigningError(`Harmony signing material field ${field} must reference a regular file.`, { file });
        }
      } catch (cause) {
        if (cause?.code === 'ERR_HARMONY_SIGNING_INVALID') return Promise.reject(cause);
        throw new HarmonySigningError(`Cannot read the file referenced by Harmony signing material field ${field}.`, { cause, file });
      }
      const serialized = path.relative(harmonyRoot, resolved);
      if (!serialized || path.isAbsolute(serialized)) {
        throw new HarmonySigningError(`Harmony signing material field ${field} must be on the same filesystem volume as the project.`, { file });
      }
      material[field] = serialized.split(path.sep).join('/');
      materialFiles[field as MaterialPathField] = resolved;
    }
  }
  if (material.signAlg !== 'SHA256withECDSA') {
    throw new HarmonySigningError('Harmony signing material signAlg must be SHA256withECDSA.', { file });
  }

  return {
    config: {
      ...selected,
      name: selected.name.trim(),
      type: 'HarmonyOS',
      material,
    },
    file,
    materialFiles,
  };
}

async function validateHarmonySigningConfigFile(projectRoot: string, reference: string): Promise<HarmonySigningConfig> {
  const result = await readSigningConfigFile(projectRoot, reference);

  return {
    file: result.file,
    materialFiles: result.materialFiles,
    name: result.config.name,
    type: result.config.type,
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

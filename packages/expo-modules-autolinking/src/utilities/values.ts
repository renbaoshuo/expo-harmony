/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { createRequire } from 'node:module';
import * as fs from 'node:fs';
import * as path from 'node:path';

import { HarmonyAutolinkingError } from '../errors';

function isObject(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function isArkTsIdentifier(value: unknown): value is string {
  return typeof value === 'string' && /^[$_\p{ID_Start}][$_\u200C\u200D\p{ID_Continue}]*$/u.test(value);
}

function compareText(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function sortedUniqueStrings(items: ReadonlyArray<string>): string[] {
  return [...new Set(items)].sort(compareText);
}

function uniqueStrings(items: ReadonlyArray<string>): string[] {
  return [...new Set(items)];
}

function stringifyJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function normalizeSlashes(value) {
  return value.split(path.sep).join('/');
}

async function readJsonAsync(file, code = 'INVALID_METADATA', stage = 'metadata') {
  try {
    return JSON.parse(await fs.promises.readFile(file, 'utf8'));
  } catch (cause) {
    throw new HarmonyAutolinkingError(code, `Unable to read valid JSON from ${file}.`, { cause, stage });
  }
}

async function pathExistsAsync(target) {
  try {
    await fs.promises.access(target);
    return true;
  } catch (_cause) {
    return false;
  }
}

function resolvePackageFromProject(projectRoot, specifier) {
  return createRequire(path.join(projectRoot, 'package.json')).resolve(specifier);
}

function isPathInside(parent, child) {
  const relative = path.relative(parent, child);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function realpathExistingAsync(target, options: Record<string, any> = {}) {
  const type = options.type || 'path';
  const code = options.code || 'INVALID_OPTIONS';
  const stage = options.stage || 'validation';
  const field = options.field || 'path';

  try {
    const resolved = await fs.promises.realpath(path.resolve(target));
    const stat = await fs.promises.stat(resolved);

    if (type === 'directory' && !stat.isDirectory()) throw new TypeError('not a directory');
    if (type === 'file' && !stat.isFile()) throw new TypeError('not a file');
    return resolved;
  } catch (cause) {
    throw new HarmonyAutolinkingError(code, `${field} does not reference an existing ${type}: ${target}`, {
      cause,
      stage,
    });
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function resolveInsideAsync(root, relative, field, options: Record<string, any> = {}) {
  const mustExist = options.mustExist !== false;
  const type = options.type || 'path';
  const packageName = options.packageName;
  const stage = options.stage || 'metadata';

  if (typeof relative !== 'string' || !relative.trim() || relative.includes('\0')
    || path.isAbsolute(relative) || path.win32.isAbsolute(relative)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field} must be a non-empty package-relative path.`, {
      packageName,
      stage,
    });
  }

  const realRoot = await fs.promises.realpath(root);
  const lexical = path.resolve(realRoot, relative);

  if (!isPathInside(realRoot, lexical)) {
    throw new HarmonyAutolinkingError('PATH_OUTSIDE_PACKAGE', `${field} escapes package root.`, {
      packageName,
      stage,
    });
  }
  if (!mustExist) return lexical;

  let resolved;
  try {
    resolved = await fs.promises.realpath(lexical);
  } catch (cause) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field} does not exist: ${relative}`, {
      cause,
      packageName,
      stage,
    });
  }

  if (!isPathInside(realRoot, resolved)) {
    throw new HarmonyAutolinkingError('PATH_OUTSIDE_PACKAGE', `${field} resolves outside package root.`, {
      packageName,
      stage,
    });
  }
  const stat = await fs.promises.stat(resolved);

  if (type === 'file' && !stat.isFile()) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field} must reference a file: ${relative}`, {
      packageName,
      stage,
    });
  }
  if (type === 'directory' && !stat.isDirectory()) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field} must reference a directory: ${relative}`, {
      packageName,
      stage,
    });
  }
  return resolved;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function requireNonEmptyString(value, field, options: Record<string, any> = {}) {
  if (typeof value !== 'string' || !value.trim()) {
    throw new HarmonyAutolinkingError(options.code || 'INVALID_METADATA', `${field} must be a non-empty string.`, {
      packageName: options.packageName,
      stage: options.stage || 'metadata',
    });
  }
  return value;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function normalizeStringArray(value, field, options: Record<string, any> = {}) {
  if (value == null && options.optional) return [];

  const values = Array.isArray(value) ? value : options.allowScalar ? [value] : null;
  if (!values || values.some(item => typeof item !== 'string' || !item.trim())) {
    throw new HarmonyAutolinkingError(options.code || 'INVALID_OPTIONS', `${field} must be an array of non-empty strings.`, {
      packageName: options.packageName,
      stage: options.stage || 'options',
    });
  }

  return [...new Set(values)];
}

function sanitizeOutput(value, roots = [], limit = 8192) {
  let result = String(value || '');

  for (const root of roots.filter(Boolean)) result = result.split(root).join('<path>');
  return result.slice(0, limit);
}

function emitLog(logger, level, message, details) {
  if (logger && typeof logger[level] === 'function') logger[level](message, details);
}

export {
  compareText,
  emitLog,
  isObject,
  isArkTsIdentifier,
  isPathInside,
  normalizeSlashes,
  pathExistsAsync,
  resolvePackageFromProject,
  readJsonAsync,
  realpathExistingAsync,
  requireNonEmptyString,
  resolveInsideAsync,
  sanitizeOutput,
  stringifyJson,
  sortedUniqueStrings,
  normalizeStringArray,
  uniqueStrings,
};

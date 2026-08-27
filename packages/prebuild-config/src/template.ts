import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import {
  HarmonyPlatformDirectory,
  HarmonyTemplateMarker,
} from './buildDescriptor';
import { HarmonyPrebuildError } from './errors';

const PACKAGE = '@expo-harmony/template';
const ROOT_ENV = 'EXPO_HARMONY_TEMPLATE_ROOT';
const TEMPLATE_SCHEMA_VERSION = 2;
const TEMPLATE_PLACEHOLDERS = Object.freeze({
  abilityName: '__EXPO_HARMONY_ABILITY_NAME__',
  appLabel: '__EXPO_HARMONY_APP_LABEL__',
  bundlePath: '__EXPO_HARMONY_BUNDLE_PATH__',
});
const resolveModule = createRequire(__filename).resolve;

interface Template {
  readonly marker: string;
  readonly schemaVersion: typeof TEMPLATE_SCHEMA_VERSION;
  readonly json: string;
  readonly root: string;
  readonly harmony: string;
  readonly version: string;
}

let bundled: Template | undefined;
let selected: Template | undefined;
let selectedRoot: string | undefined;

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function readSchema(marker: string): typeof TEMPLATE_SCHEMA_VERSION {
  let schema: unknown;
  try {
    schema = JSON.parse(fs.readFileSync(marker, 'utf8'));
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      `Cannot read the Harmony template schema at ${marker}.`,
      { cause, file: marker, operation: 'resolve-template' }
    );
  }

  if (!isRecord(schema) || schema.schemaVersion !== TEMPLATE_SCHEMA_VERSION) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      `Unsupported Harmony template schema: ${isRecord(schema) ? schema.schemaVersion : 'invalid'}.`,
      { file: marker, operation: 'resolve-template' }
    );
  }

  const placeholders = schema.placeholders;
  const names = Object.keys(TEMPLATE_PLACEHOLDERS) as Array<keyof typeof TEMPLATE_PLACEHOLDERS>;
  if (!isRecord(placeholders)
    || Object.keys(placeholders).length !== names.length
    || names.some(name => placeholders[name] !== TEMPLATE_PLACEHOLDERS[name])) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      'Harmony template schema has an invalid placeholder contract.',
      { file: marker, operation: 'resolve-template' }
    );
  }

  return TEMPLATE_SCHEMA_VERSION;
}

function read(input: string): Template {
  if (!path.isAbsolute(input)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      `${ROOT_ENV} must be an absolute path.`,
      { operation: 'resolve-template' }
    );
  }

  let root: string;
  try {
    root = fs.realpathSync(input);
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      `Cannot access the selected Harmony template at ${input}.`,
      { cause, file: input, operation: 'resolve-template' }
    );
  }

  const json = path.join(root, 'package.json');
  let pkg;
  try {
    pkg = JSON.parse(fs.readFileSync(json, 'utf8'));
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      `Cannot read the selected Harmony template package at ${root}.`,
      { cause, file: json, operation: 'resolve-template' }
    );
  }

  if (pkg.name !== PACKAGE || typeof pkg.version !== 'string' || !pkg.version) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      `The selected template must be a versioned ${PACKAGE} package.`,
      { file: json, operation: 'resolve-template' }
    );
  }

  const harmony = path.join(root, HarmonyPlatformDirectory);
  const marker = path.join(harmony, HarmonyTemplateMarker);
  const schemaVersion = readSchema(marker);

  return Object.freeze({
    marker,
    schemaVersion,
    json,
    root,
    harmony,
    version: pkg.version,
  });
}

function resolveBundled(): Template {
  if (bundled) return bundled;

  let json: string;
  try {
    json = resolveModule(`${PACKAGE}/package.json`);
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      `Unable to resolve the ${PACKAGE} declared by @expo-harmony/prebuild-config.`,
      { cause, operation: 'resolve-template' }
    );
  }

  bundled = read(path.dirname(json));
  return bundled;
}

function resolve(): Template {
  const root = process.env[ROOT_ENV];
  if (!root) return resolveBundled();

  if (selected && selectedRoot === root) return selected;

  selected = read(root);
  selectedRoot = root;
  return selected;
}

export {
  ROOT_ENV,
  TEMPLATE_PLACEHOLDERS,
  TEMPLATE_SCHEMA_VERSION,
  resolve,
  resolveBundled,
};
export type { Template };

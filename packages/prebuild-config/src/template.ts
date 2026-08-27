import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { HarmonyPrebuildError } from './errors';

const PACKAGE = '@expo-harmony/template';
const ROOT_ENV = 'EXPO_HARMONY_TEMPLATE_ROOT';
const resolveModule = createRequire(__filename).resolve;

interface Template {
  readonly json: string;
  readonly root: string;
  readonly harmony: string;
  readonly version: string;
}

let bundled: Template | undefined;
let selected: Template | undefined;
let selectedRoot: string | undefined;

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

  const harmony = path.join(root, 'harmony');
  const marker = path.join(harmony, '.expo-harmony-template');
  if (!fs.existsSync(marker)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_TEMPLATE_INVALID',
      `Template marker is missing in ${root}.`,
      { file: marker, operation: 'resolve-template' }
    );
  }

  return Object.freeze({
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
  resolve,
  resolveBundled,
};
export type { Template };

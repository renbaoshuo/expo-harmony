/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { canonicalDevelopmentManifestURL, DevLauncherError, parseHTTPURL, RUNTIME_CONTRACT_ASSET } from './DevLauncherProtocol';
import { resourceManager } from '@kit.LocalizationKit';
import util from '@ohos.util';
import url from '@ohos.url';

type JsonObject = Record<string, ESObject>;

const VERSION_FIELDS: string[] = ['runtimeVersion', 'expo', 'expoModulesCore', 'rnoh', 'react', 'hermes'];
const SETTING_FIELDS: string[] = ['permissions', 'querySchemes', 'backgroundModes', 'abiFilters'];
const MODULE_FIELDS: string[] = ['modules', 'services', 'registrations', 'artifacts'];
const DIGEST = /^[a-f0-9]{64}$/;

function object(value: ESObject): JsonObject | undefined {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : undefined;
}

function nonEmptyString(value: ESObject): value is string {
  return typeof value === 'string' && value.length > 0;
}

function strings(value: ESObject): string[] | undefined {
  if (!Array.isArray(value) || value.some((item: ESObject): boolean => !nonEmptyString(item))) return undefined;
  const result = value as string[];
  return new Set(result).size === result.length ? result : undefined;
}

function apiVersion(value: ESObject, schema: ESObject): boolean {
  return (typeof value === 'number' && Number.isSafeInteger(value) && value > 0)
    || (schema === 2 && typeof value === 'string' && /^\d+\.\d+\.\d+$/.test(value));
}

function validate(value: ESObject, label: string): JsonObject {
  const contract = object(value);
  if (contract === undefined) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${label} runtime contract must be an object.`);

  const schema = contract.schemaVersion;
  if (schema !== 1 && schema !== 2) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${label} schemaVersion must be 1 or 2.`);

  const fixed: Record<string, string> = {
    platform: 'harmony', engine: 'hermes-v1', bundleFormat: 'js-source', renderer: 'rnoh',
  };
  for (const [field, expected] of Object.entries(fixed)) {
    if (contract[field] !== expected) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${label}.${field} must be ${expected}.`);
  }
  if (typeof contract.development !== 'boolean') throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${label}.development must be boolean.`);
  for (const field of VERSION_FIELDS) {
    if (!nonEmptyString(contract[field])) {
      throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${label}.${field} must be an explicit version.`);
    }
  }
  if (!Array.isArray(contract.modules)) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${label}.modules must be an array.`);

  const packages = new Set<string>();
  for (const raw of contract.modules as ESObject[]) {
    const module = object(raw);
    if (module === undefined || !nonEmptyString(module.packageName) || !nonEmptyString(module.packageVersion) || packages.has(module.packageName)) {
      throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${label}.modules contains an invalid or duplicate package.`);
    }
    packages.add(module.packageName);

    for (const field of MODULE_FIELDS) {
      const items = strings(module[field]);
      if (items === undefined || (field === 'artifacts' && items.some((item: string): boolean => !DIGEST.test(item)))) {
        throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${label}.modules.${module.packageName}.${field} is invalid.`);
      }
    }
  }

  const config = object(contract.config);
  if (config === undefined || !nonEmptyString(config.nativeCompiler)) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${label}.config is invalid.`);

  const target = config.targetApiVersion === undefined || apiVersion(config.targetApiVersion, schema);
  const compatible = apiVersion(config.compatibleApiVersion, schema);
  if (!target || !compatible) {
    throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${label}.config API versions are invalid.`);
  }
  for (const field of SETTING_FIELDS) {
    const items = strings(config[field]);
    if (items === undefined) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${label}.config.${field} is invalid.`);
  }
  if (config.nativeLibFilterHash !== undefined && (schema !== 2 || typeof config.nativeLibFilterHash !== 'string' || !DIGEST.test(config.nativeLibFilterHash))) {
    throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${label}.config.nativeLibFilterHash is invalid.`);
  }

  return contract;
}

function requireObject(parent: JsonObject, field: string): JsonObject {
  const result = object(parent[field]);
  if (result === undefined) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `Development manifest field '${field}' must be an object.`);
  return result;
}

export async function readClientRuntime(manager: resourceManager.ResourceManager): Promise<JsonObject> {
  try {
    const bytes = await manager.getRawFileContent(RUNTIME_CONTRACT_ASSET);

    const text = util.TextDecoder.create('utf-8').decodeToString(bytes);

    return validate(JSON.parse(text), 'client');
  } catch (error) {
    if (error instanceof DevLauncherError) throw new DevLauncherError(error.code, error.message);
    throw new DevLauncherError('ERR_HARMONY_RUNTIME_CONTRACT', `Unable to read ${RUNTIME_CONTRACT_ASSET}.`, error as Object);
  }
}

export function validateDevelopmentManifest(client: JsonObject, manifest: JsonObject, requested: string): void {
  const launch = requireObject(manifest, 'launchAsset');
  const extra = requireObject(manifest, 'extra');
  const harmony = requireObject(extra, 'harmony');
  const requirements = validate(harmony.requirements, 'requirements');
  const bundle = launch.url;
  if (launch.key !== 'bundle' || launch.contentType !== 'application/javascript' || typeof bundle !== 'string') {
    throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', 'Expected a Harmony development JavaScript source launch asset.');
  }

  let origin: string;

  try {
    if (typeof harmony.manifestUrl !== 'string'
      || canonicalDevelopmentManifestURL(harmony.manifestUrl) !== canonicalDevelopmentManifestURL(requested)) {
      throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', 'The development manifest URL does not match the requested URL.');
    }
    origin = new url.URL(requested).origin;
  } catch (_) {
    throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', 'The development manifest URL does not match the requested URL.');
  }
  if (manifest.runtimeVersion !== requirements.runtimeVersion) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', 'Manifest and native runtime versions differ.');

  checkCompatibility(validate(client, 'client'), requirements);

  let asset: url.URL;

  try {
    asset = parseHTTPURL(bundle);
  } catch (_) {
    throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', 'The bundle URL is invalid.');
  }
  if (asset.origin !== origin || !asset.pathname.endsWith('.bundle')) {
    throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', 'Manifest and bundle must use the same HTTP(S) origin and a .bundle launch asset.');
  }

  const expected: Record<string, string> = {
    platform: 'harmony', dev: 'true', 'transform.engine': 'hermes', 'transform.bytecode': '0',
  };

  for (const [name, value] of Object.entries(expected)) {
    const matches = asset.searchParams.getAll(name);
    if (matches.length !== 1 || matches[0] !== value) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `Bundle query parameter ${name} must be ${value}.`);
  }
}

function checkCompatibility(client: JsonObject, requirements: JsonObject): void {
  for (const field of VERSION_FIELDS) {
    if (client[field] !== requirements[field]) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `${field}: project requires ${requirements[field]}, client provides ${client[field]}.`);
  }
  if (requirements.development === true && client.development !== true) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', 'This client was built without native development support.');

  const modules = client.modules as JsonObject[];
  for (const required of requirements.modules as JsonObject[]) {
    const available = modules.find((candidate: JsonObject): boolean => candidate.packageName === required.packageName);
    if (available === undefined) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `Client is missing native package ${required.packageName}.`);
    if (available.packageVersion !== required.packageVersion) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `Native package version differs for ${required.packageName}.`);
    for (const field of MODULE_FIELDS) {
      const present = available[field] as string[];
      const needed = required[field] as string[];
      if (present.length !== needed.length || needed.some((item: string): boolean => !present.includes(item))) {
        throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `Native contract differs for ${required.packageName}.${field}.`);
      }
    }
  }

  const available = client.config as JsonObject;
  const required = requirements.config as JsonObject;
  for (const field of ['nativeCompiler', 'targetApiVersion', 'compatibleApiVersion', 'nativeLibFilterHash']) {
    if (field === 'targetApiVersion' && (available[field] === undefined || required[field] === undefined)) continue;
    if (available[field] !== required[field]) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `Native build setting ${field} differs.`);
  }

  for (const field of SETTING_FIELDS) {
    const present = available[field] as string[];
    for (const item of required[field] as string[]) {
      if (!present.includes(item)) throw new DevLauncherError('ERR_HARMONY_INCOMPATIBLE', `Client build is missing ${field}: ${item}.`);
    }
  }
}

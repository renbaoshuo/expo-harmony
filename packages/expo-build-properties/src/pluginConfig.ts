/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import path from 'node:path';

import {
  normalizeHarmonyConfig,
  parseHarmonySdkVersion,
  type ExpoConfigWithHarmony,
} from '@expo-harmony/config-plugins';

import { ExpoBuildPropertiesError } from './errors';

export interface NativeLibFilter {
  excludes?: string[];
  pickFirsts?: string[];
  pickLasts?: string[];
  enableOverride?: boolean;
  select?: NativeLibSelection[];
}

export interface NativeLibSelection {
  package: string;
  version?: string;
  include?: string[];
  exclude?: string[];
  includePattern?: string[];
  excludePattern?: string[];
}

export interface DebugSymbol {
  strip?: boolean;
  /** Hvigor semantics: exceptions to strip=true, or the only stripped libraries when strip=false. */
  exclude?: string[];
}

export interface HarmonyBuildProperties {
  compatibleSdkVersion?: number | string;
  targetSdkVersion?: number | string;
  abiFilters?: string[];
  nativeCompiler?: string;
  nativeLib?: { filter?: NativeLibFilter };
  compressNativeLibs?: boolean;
  extractNativeLibs?: boolean;
  release?: {
    debugSymbol?: DebugSymbol;
    obfuscation?: {
      enable: boolean;
      files?: string[];
    };
  };
}

export interface PluginConfigType {
  harmony?: HarmonyBuildProperties;
}

function object(value: unknown, field: string, keys?: readonly string[]): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoBuildPropertiesError(`${field} must be an object.`);
  }

  for (const key of Object.keys(value)) {
    if (keys && !keys.includes(key)) throw new ExpoBuildPropertiesError(`${field}.${key} is not supported.`);
  }

  return value as Record<string, unknown>;
}

function boolean(value: unknown, field: string): boolean {
  if (typeof value !== 'boolean') throw new ExpoBuildPropertiesError(`${field} must be a boolean.`);
  return value;
}

function string(value: unknown, field: string): string {
  if (typeof value !== 'string' || !value.trim() || /[\r\n\0]/.test(value)) {
    throw new ExpoBuildPropertiesError(`${field} must be a non-empty string.`);
  }

  return value;
}

function strings(value: unknown, field: string): string[] {
  const message = `${field} must be an array of non-empty strings.`;
  if (!Array.isArray(value)) throw new ExpoBuildPropertiesError(message);

  const items = new Set<string>();
  for (const item of value) {
    if (typeof item !== 'string' || !item.trim() || /[\r\n\0]/.test(item)) {
      throw new ExpoBuildPropertiesError(message);
    }
    items.add(item);
  }

  return [...items];
}

export function validateAbiFilters(values: string[], field: string): string[] {
  if (!values.length || values.some(value => value !== 'arm64-v8a' && value !== 'x86_64')) {
    throw new ExpoBuildPropertiesError(`${field} must select at least one of arm64-v8a and x86_64.`);
  }

  return values;
}

function selections(value: unknown): NativeLibSelection[] {
  const field = 'nativeLib.filter.select';
  if (!Array.isArray(value)) throw new ExpoBuildPropertiesError(`${field} must be an array.`);

  return Array.from(value, (item, index) => {
    const name = `${field}[${index}]`;
    const rule = object(item, name, ['package', 'version', 'include', 'exclude', 'includePattern', 'excludePattern']);

    const result: NativeLibSelection = { package: string(rule.package, `${name}.package`) };
    if (rule.version !== undefined) result.version = string(rule.version, `${name}.version`);

    for (const key of ['include', 'exclude', 'includePattern', 'excludePattern'] as const) {
      if (rule[key] !== undefined) result[key] = strings(rule[key], `${name}.${key}`);
    }

    if (result.include === undefined && result.exclude === undefined
      && result.includePattern === undefined && result.excludePattern === undefined) {
      throw new ExpoBuildPropertiesError(`${name} must specify an include or exclude field.`);
    }
    if ((result.include !== undefined || result.exclude !== undefined)
      && (result.includePattern !== undefined || result.excludePattern !== undefined)) {
      throw new ExpoBuildPropertiesError(`${name} cannot mix exact filenames and glob patterns.`);
    }

    return result;
  });
}

function validateBuildProperties(value: unknown): HarmonyBuildProperties {
  const props = object(value, 'build-properties.harmony', [
    'compatibleSdkVersion', 'targetSdkVersion', 'abiFilters', 'nativeCompiler',
    'nativeLib', 'compressNativeLibs', 'extractNativeLibs', 'release',
  ]);

  const result: HarmonyBuildProperties = {};

  for (const key of ['compatibleSdkVersion', 'targetSdkVersion'] as const) {
    if (props[key] !== undefined) result[key] = parseHarmonySdkVersion(props[key], key).native;
  }

  if (props.abiFilters !== undefined) {
    result.abiFilters = validateAbiFilters(strings(props.abiFilters, 'abiFilters'), 'abiFilters');
  }

  if (props.nativeCompiler !== undefined) {
    if (props.nativeCompiler !== 'Original' && props.nativeCompiler !== 'BiSheng') {
      throw new ExpoBuildPropertiesError('nativeCompiler must be Original or BiSheng.');
    }

    result.nativeCompiler = props.nativeCompiler;
  }

  for (const key of ['compressNativeLibs', 'extractNativeLibs'] as const) {
    if (props[key] !== undefined) result[key] = boolean(props[key], key);
  }

  if (props.nativeLib !== undefined) {
    const native = object(props.nativeLib, 'nativeLib', ['filter']);
    result.nativeLib = {};

    if (native.filter !== undefined) {
      const filter = object(native.filter, 'nativeLib.filter', ['excludes', 'pickFirsts', 'pickLasts', 'enableOverride', 'select']);
      const output: NativeLibFilter = {};

      for (const key of ['excludes', 'pickFirsts', 'pickLasts'] as const) {
        if (filter[key] !== undefined) output[key] = strings(filter[key], `nativeLib.filter.${key}`);
      }
      if (filter.enableOverride !== undefined) output.enableOverride = boolean(filter.enableOverride, 'nativeLib.filter.enableOverride');
      if (filter.select !== undefined) output.select = selections(filter.select);

      result.nativeLib.filter = output;
    }
  }

  if (props.release !== undefined) {
    const release = object(props.release, 'release', ['debugSymbol', 'obfuscation']);
    result.release = {};

    if (release.debugSymbol !== undefined) {
      const symbol = object(release.debugSymbol, 'release.debugSymbol', ['strip', 'exclude']);

      result.release.debugSymbol = {
        ...(symbol.strip === undefined ? {} : { strip: boolean(symbol.strip, 'release.debugSymbol.strip') }),
        ...(symbol.exclude === undefined ? {} : { exclude: strings(symbol.exclude, 'release.debugSymbol.exclude') }),
      };
    }

    if (release.obfuscation !== undefined) {
      const rules = object(release.obfuscation, 'release.obfuscation', ['enable', 'files']);
      const enable = boolean(rules.enable, 'release.obfuscation.enable');

      result.release.obfuscation = { enable };
      if (rules.files !== undefined) {
        const files = strings(rules.files, 'release.obfuscation.files');
        result.release.obfuscation.files = [...new Set(files.map(file => path.normalize(file)))];
      }
    }
  }

  return result;
}

export function validatePluginConfig(value: unknown): HarmonyBuildProperties {
  const config = object(value, 'build-properties', ['harmony']);
  return validateBuildProperties(config.harmony === undefined ? {} : config.harmony);
}

export function getBuildProperties(config: Pick<ExpoConfigWithHarmony, '_internal'>): HarmonyBuildProperties | undefined {
  return config._internal?.harmonyBuildProperties;
}

export function applyBuildPropertiesConfig<Config extends ExpoConfigWithHarmony>(
  config: Config, props: HarmonyBuildProperties
): Config {
  const harmony = { ...config.harmony! };

  for (const key of ['compatibleSdkVersion', 'targetSdkVersion'] as const) {
    const value = props[key];
    if (value === undefined) continue;

    harmony[key] = value;
  }

  if (props.abiFilters !== undefined) {
    harmony.abiFilters = props.abiFilters;
  }

  const result = { ...config, harmony };
  normalizeHarmonyConfig(result);

  return result;
}

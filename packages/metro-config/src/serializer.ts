import type { InputConfigT } from 'metro-config';

import { HarmonyPlatform } from './constants';
import { HarmonyMetroTypeError } from './errors';
import type { BootstrapModules, PathNormalizer } from './runtime';

type MetroSerializer = NonNullable<InputConfigT['serializer']>;
type GetModulesHook = NonNullable<MetroSerializer['getModulesRunBeforeMainModule']>;
type Mutable<T> = { -readonly [Key in keyof T]: T[Key] };

function unique<T>(values: Iterable<T>): T[] {
  return [...new Set(values)];
}

export function composeSerializer(
  serializer: InputConfigT['serializer'],
  normalizePath: PathNormalizer,
  serializers: readonly InputConfigT['serializer'][] = [serializer],
  bootstrap?: BootstrapModules
): InputConfigT['serializer'] {
  const moduleHooks = unique(serializers
    .map(candidate => candidate?.getModulesRunBeforeMainModule)
    .filter((hook): hook is GetModulesHook => typeof hook === 'function'));
  const getPolyfills = serializer?.getPolyfills;
  const serialize = serializer?.customSerializer;
  if (moduleHooks.length === 0 && typeof serialize !== 'function' && !bootstrap) {
    return serializer;
  }

  const composed: Mutable<MetroSerializer> = { ...serializer };
  if (bootstrap) {
    composed.getPolyfills = function getHarmonyPolyfills(options) {
      const polyfills = typeof getPolyfills === 'function' ? getPolyfills.call(this, options) : [];
      if (!Array.isArray(polyfills)) {
        throw new HarmonyMetroTypeError(
          'ERR_EXPO_HARMONY_INVALID_BOOTSTRAP',
          'A Metro serializer getPolyfills hook returned a non-array value; '
          + 'the required Harmony runtime installer cannot be preserved.'
        );
      }
      if (options.platform !== HarmonyPlatform) return polyfills;

      return unique([...polyfills.map(normalizePath), bootstrap.runtimeInstaller]);
    };
  }

  if (moduleHooks.length > 0 || bootstrap) {
    composed.getModulesRunBeforeMainModule = function getHarmonyBootstrap(entryFilePath) {
      const modules: string[] = [];
      for (const hook of moduleHooks) {
        const result = hook.call(this, entryFilePath);
        if (!Array.isArray(result)) {
          throw new HarmonyMetroTypeError(
            'ERR_EXPO_HARMONY_INVALID_BOOTSTRAP',
            'A Metro serializer getModulesRunBeforeMainModule hook returned a non-array value; '
            + 'the required Harmony bootstrap cannot be preserved.'
          );
        }
        modules.push(...result);
      }

      const normalized = unique(modules.map(normalizePath));
      if (!bootstrap) return normalized;

      const required = [bootstrap.initializeCore, bootstrap.expoWinter, bootstrap.metroRuntime];
      const requiredSet = new Set(required);

      return [...required, ...normalized.filter(module => !requiredSet.has(module))];
    };
  }

  if (typeof serialize === 'function') {
    composed.customSerializer = function serializeHarmony(entryPoint, preModules, graph, options) {
      const transform = graph.transformOptions;
      const custom = transform.customTransformOptions;
      const needsHermes = transform.platform === HarmonyPlatform
        && custom?.bytecode === '1'
        && custom.engine !== 'hermes';
      const harmonyGraph = needsHermes
        ? {
            ...graph,
            transformOptions: {
              ...transform,
              customTransformOptions: { ...custom, engine: 'hermes' },
            },
          }
        : graph;

      return serialize.call(this, entryPoint, preModules, harmonyGraph, options);
    };
  }

  return composed;
}

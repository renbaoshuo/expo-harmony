import fs from 'node:fs/promises';

import { withBaseMod, type ExportedConfig, type ModPlatform } from '@expo/config-plugins';
import JSON5 from 'json5';

import { HarmonyConfigPluginError } from './errors';
import { atomicWrite, stableJson } from './files';
import { recordManagedFile, registerMod } from './mods';
import { getHarmonyConfigPlugins, normalizeHarmonyConfigPlugins, registerHarmonyConfigPlugin } from './ownership';
import { ManagedPaths, ResourcePaths, resolveHarmonyPath } from './paths';
import type { HarmonyConfigPlugin, HarmonyModAction, HarmonyModConfig } from './pluginTypes';

export interface HarmonyFileModOptions<T> {
  path: string;
  owner: string;
  parse: (source: string | null) => T;
  serialize: (value: T) => string;
  isIntrospective?: boolean;
}

type Definition = Omit<HarmonyFileModOptions<unknown>, 'parse' | 'serialize'> & { parse: unknown; serialize: unknown };
interface CustomProvider { expoHarmonyLateActions?: unknown }
const providers = new WeakMap<object, Definition>();

export function createHarmonyFileMod<T>(options: HarmonyFileModOptions<T>): HarmonyConfigPlugin<HarmonyModAction<T>> {
  const definition = Object.freeze({ ...options });
  const { path: relative, owner, parse, serialize, isIntrospective = false } = definition;

  normalizeHarmonyConfigPlugins([{ owner, files: [relative] }]);

  const reserved = Object.values(ManagedPaths).includes(relative)
    || Object.values(ResourcePaths).some(scopes => Object.values(scopes).some(file => relative === file))
    || Object.values(ResourcePaths.media).some(directory => relative.startsWith(`${directory}/`));
  if (reserved || relative.split('/').some(part => part === '.git') || relative.startsWith('.expo/')) {
    throw new HarmonyConfigPluginError('ERR_HARMONY_PATH_INVALID', `Use the built-in mod for reserved path ${relative}.`);
  }
  if (typeof parse !== 'function' || typeof serialize !== 'function') {
    throw new TypeError('A file mod requires parse and serialize functions.');
  }

  const name = `file:${relative}`;

  return (config, action) => {
    const mods = (config as ExportedConfig).mods as Record<string, Record<string, CustomProvider>> | undefined;
    const provider = mods?.harmony?.[name];
    if (provider) {
      const stored = providers.get(provider);
      if (!stored || stored.owner !== owner || stored.parse !== parse
        || stored.serialize !== serialize || !!stored.isIntrospective !== isIntrospective) {
        throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `Conflicting providers for ${relative}. Reuse the same file mod definition.`);
      }
    }

    const claims = getHarmonyConfigPlugins(config).find(plugin => plugin.owner === owner);
    registerHarmonyConfigPlugin(config, owner, {
      ...claims, files: [...new Set([...(claims?.files ?? []), relative])],
    });

    if (!provider) {
      const actions: HarmonyModAction<T>[] = [];
      withBaseMod<T>(config as ExportedConfig, {
        platform: 'harmony' as ModPlatform,
        mod: name,
        isProvider: true,
        isIntrospective,
        saveToInternal: isIntrospective,
        async action(value) {
          const { nextMod: _next, ...request } = value.modRequest;
          const file = await resolveHarmonyPath(request.platformProjectRoot, relative);
          let source: string | null = null;

          if (!request.ignoreExistingNativeFiles) {
            try {
              source = await fs.readFile(file, 'utf8');
            } catch (cause) {
              if ((cause as NodeJS.ErrnoException).code !== 'ENOENT') {
                throw new HarmonyConfigPluginError(
                  'ERR_HARMONY_TEXT_INVALID',
                  `Cannot read ${file}: ${(cause as Error).message}`,
                  { cause, file, operation: `harmony.${name}.read` }
                );
              }
            }
          }

          let result = {
            ...value,
            modRequest: { ...request, modFile: file, modFileExists: source !== null },
            modResults: parse(source),
          } as unknown as HarmonyModConfig<T>;
          for (let index = actions.length - 1; index >= 0; index--) {
            result = await actions[index](result) as HarmonyModConfig<T>;
          }

          const output = serialize(result.modResults);
          if (typeof output !== 'string') throw new TypeError(`Serializer for ${relative} must return a string.`);

          if (!request.introspect) {
            await atomicWrite(file, output);
            recordManagedFile(result, file, owner);
          }

          return result as unknown as typeof value;
        },
      });

      const table = ((config as ExportedConfig).mods as Record<string, Record<string, CustomProvider>>).harmony;
      table[name].expoHarmonyLateActions = actions;
      providers.set(table[name], definition);

      // CNG must fingerprint custom outputs after they have been written.
      for (const stage of ['patch', 'manifest']) {
        if (table[stage]) {
          const provider = table[stage];
          delete table[stage];
          table[stage] = provider;
        }
      }
    }

    return registerMod(config, name, action);
  };
}

function parseJson(source: string | null): Record<string, unknown> {
  const value = source === null ? {} : JSON5.parse(source);
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError('A Harmony JSON file must contain an object.');
  }

  return value;
}

export interface HarmonyJsonFileOptions {
  path: string;
  owner: string;
  action: HarmonyModAction<Record<string, unknown>>;
}

export const withHarmonyJsonFile: HarmonyConfigPlugin<HarmonyJsonFileOptions> = (config, { path, owner, action }) => (
  createHarmonyFileMod({ path, owner, parse: parseJson, serialize: stableJson, isIntrospective: true })(config, action)
);

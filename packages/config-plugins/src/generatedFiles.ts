import fs from 'node:fs';
import path from 'node:path';

import { HarmonyConfigPluginError } from './errors';
import { atomicWrite } from './files';
import { recordManagedFile, withHarmonyDangerousMod } from './mods';
import { getHarmonyConfigPlugins, registerHarmonyConfigPlugin } from './ownership';
import { resolveHarmonyPath } from './paths';
import type { HarmonyConfigPlugin } from './pluginTypes';

export type HarmonyFileDescriptor
  = | { source: string; content?: never }
    | { source?: never; content: string | Uint8Array };
export type HarmonyFileMap = Record<string, HarmonyFileDescriptor>;
export interface HarmonyGeneratedFilesOptions {
  owner: string;
  files: HarmonyFileMap;
}

export const withHarmonyGeneratedFiles: HarmonyConfigPlugin<HarmonyGeneratedFilesOptions> = (config, options) => {
  const { owner, files } = options;
  if (!files || typeof files !== 'object' || Array.isArray(files)) {
    throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', 'Generated files must be a path-to-descriptor map.');
  }

  const claims = getHarmonyConfigPlugins(config).find(plugin => plugin.owner === owner);
  const paths = [...new Set([...(claims?.files ?? []), ...Object.keys(files)])];
  config = registerHarmonyConfigPlugin(config, owner, { ...claims, files: paths });

  return withHarmonyDangerousMod(config, async (mod) => {
    if (mod.modRequest.introspect) return mod;

    const writes: Array<{ file: string; content: string | Uint8Array }> = [];
    for (const [relative, input] of Object.entries(files)) {
      if (!input || typeof input !== 'object'
        || Object.hasOwn(input, 'source') === Object.hasOwn(input, 'content')) {
        throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `${relative} must define exactly one of source or content.`);
      }

      const file = await resolveHarmonyPath(mod.modRequest.platformProjectRoot, relative);
      let content: string | Uint8Array;
      if (Object.hasOwn(input, 'source')) {
        if (typeof input.source !== 'string' || !input.source) {
          throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `${relative} source must be a non-empty path.`);
        }

        const source = path.resolve(mod.modRequest.projectRoot, input.source);
        content = Uint8Array.from(await fs.promises.readFile(source));
      } else {
        if (typeof input.content !== 'string' && !(input.content instanceof Uint8Array)) {
          throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `${relative} content must be a string or Uint8Array.`);
        }

        content = input.content;
      }

      writes.push({ file, content });
    }

    for (const { file, content } of writes) {
      await atomicWrite(file, content);
      recordManagedFile(mod, file, owner);
    }

    return mod;
  });
};

export const withRawfile: HarmonyConfigPlugin<HarmonyGeneratedFilesOptions> = (config, { owner, files }) => {
  if (!files || typeof files !== 'object' || Array.isArray(files)) {
    throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', 'Rawfiles must be a path-to-descriptor map.');
  }

  const prefix = 'entry/src/main/resources/rawfile/';
  const output: HarmonyFileMap = {};
  for (const [relative, input] of Object.entries(files)) {
    if (!relative || relative.includes('\\') || relative.split('/').some(part => !part || part === '.' || part === '..')) {
      throw new HarmonyConfigPluginError('ERR_HARMONY_PATH_ESCAPE', `Invalid rawfile path: ${relative}`);
    }

    output[prefix + relative] = input;
  }

  return withHarmonyGeneratedFiles(config, { owner, files: output });
};

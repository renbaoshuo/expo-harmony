/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';

import { atomicWrite, HarmonyPaths, stableHarmonyJson } from '@expo-harmony/config-plugins';
import { isManagedManifestConfig, type ManagedManifestConfig } from '@expo-harmony/config-plugins/internal';
import { isManagedBuildProperties, type ManagedBuildProperties } from '@expo-harmony/expo-build-properties/internal';
import JSON5 from 'json5';

import { isManagedModuleConfig, type ManagedModuleConfig } from './moduleConfig';

const JournalPath = '.expo/harmony/pending-json-ownership.json';
const Paths = HarmonyPaths.HARMONY_PATHS;
const FileScopes = {
  [Paths.projectBuildProfile]: ['product'],
  [Paths.entryBuildProfile]: ['entry', 'release'],
  [Paths.moduleJson]: ['module'],
} as const;
interface Ownership {
  buildProperties: ManagedBuildProperties;
  moduleConfig: ManagedModuleConfig;
  pluginChanges: ManagedManifestConfig[];
}
type Journal = Record<string, Record<string, Partial<Ownership>>>;
interface JsonOwnershipJournal {
  applied: Ownership;
  managed: Ownership;
  beforeWrite(target: string, original: Record<string, unknown> | undefined, content: string): Promise<void>;
  finish(): Promise<void>;
}

function hash(content: string): string {
  return createHash('sha256').update(content).digest('hex');
}

async function readJournal(file: string): Promise<Journal> {
  try {
    return JSON.parse(await fs.readFile(file, 'utf8'));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return {};
    throw error;
  }
}

async function prepareJsonOwnershipJournal(
  project: string, platform: string, previous: Partial<Ownership>, fresh: boolean,
  introspect: boolean
): Promise<JsonOwnershipJournal> {
  const file = await HarmonyPaths.resolveHarmonyPath(project, JournalPath);
  const journal = fresh ? {} : await readJournal(file);
  const applied: Ownership = {
    buildProperties: { ...previous.buildProperties },
    moduleConfig: previous.moduleConfig ?? { permissions: [], querySchemes: [], skills: [] },
    pluginChanges: previous.pluginChanges ?? [],
  };
  const managed: Ownership = {
    buildProperties: {},
    moduleConfig: { permissions: [], querySchemes: [], skills: [] },
    pluginChanges: [],
  };

  if (fresh && !introspect) await fs.rm(file, { force: true });

  for (const [relative, entries] of Object.entries(journal)) {
    if (!Object.hasOwn(FileScopes, relative)) continue;

    const target = await HarmonyPaths.resolveHarmonyPath(platform, relative);
    const source = await fs.readFile(target, 'utf8').catch((error) => {
      if (error.code === 'ENOENT') return undefined;
      throw error;
    });
    if (source === undefined) continue;

    const ownership = entries?.[hash(stableHarmonyJson(JSON5.parse(source)))];
    if (!ownership || !isManagedBuildProperties(ownership.buildProperties ?? {})
      || !isManagedManifestConfig(ownership.pluginChanges ?? [])
      || (ownership.moduleConfig !== undefined && !isManagedModuleConfig(ownership.moduleConfig))) continue;

    for (const scope of FileScopes[relative]) {
      const change = ownership.buildProperties?.[scope];
      if (change) applied.buildProperties[scope] = change;
      else delete applied.buildProperties[scope];
    }
    if (relative === Paths.moduleJson) {
      applied.moduleConfig = ownership.moduleConfig ?? applied.moduleConfig;
      applied.pluginChanges = ownership.pluginChanges ?? [];
    }
  }

  async function beforeWrite(target: string, original: Record<string, unknown> | undefined, content: string) {
    if (!HarmonyPaths.isInside(platform, target)) return;
    const relative = HarmonyPaths.toPosixRelative(platform, target);
    if (!Object.hasOwn(FileScopes, relative)) return;
    const scopes = FileScopes[relative];
    const ownershipForFile = ({ buildProperties, moduleConfig, pluginChanges }: Ownership): Partial<Ownership> => {
      const selected = Object.fromEntries(
        scopes.flatMap(scope => buildProperties[scope] === undefined ? [] : [[scope, buildProperties[scope]]])
      );
      return {
        ...(Object.keys(selected).length ? { buildProperties: selected } : {}),
        ...(relative === Paths.moduleJson ? { moduleConfig, pluginChanges } : {}),
      };
    };
    const before = ownershipForFile(applied);
    const after = ownershipForFile(managed);
    if (!journal[relative] && !Object.keys(before).length && !Object.keys(after).length) return;

    // The native write may still fail. Retain ownership for whichever version
    // actually survives, including a previous partial generation.
    journal[relative] = {
      ...(original === undefined ? {} : { [hash(stableHarmonyJson(original))]: before }),
      [hash(content)]: after,
    };
    await atomicWrite(file, stableHarmonyJson(journal));
  }

  return { applied, managed, beforeWrite, finish: () => fs.rm(file, { force: true }) };
}

export { prepareJsonOwnershipJournal };

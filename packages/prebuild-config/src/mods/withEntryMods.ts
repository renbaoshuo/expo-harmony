/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import path from 'node:path';

import {
  normalizeHarmonyConfig,
  HarmonyPaths,
  HarmonyResources,
  withColors,
  withEntryBuildProfile,
  withEntryHvigor,
  withEntryOhPackage,
  withMedia,
  withModuleJson,
  withProfiles,
  withStrings,
  type HarmonyConfigPluginOwnership,
  type HarmonyMediaDescriptor,
} from '@expo-harmony/config-plugins';
import { getHarmonyConfigPlugins } from '@expo-harmony/config-plugins/internal';

import {
  createHarmonyBuildDescriptor,
  HarmonyPlatformDirectory,
} from '../buildDescriptor';
import { readTemplateSource, resolveTemplateFile } from '../dependencies';
import { HarmonyPrebuildError } from '../errors';
import { reconcileModuleList, reconcileModulePermissions } from '../moduleConfig';
import {
  appendUnique,
  readRecord,
  upsertManagedNamed,
  upsertNamed,
} from '../reconcile';
import * as render from '../renderers';
import { removeStaleExtensionAbilities, removeStaleResources } from '../stale';

interface IconFile {
  extension: string;
  media: HarmonyMediaDescriptor;
}

const IconExtensionByMimeType: Readonly<Record<string, string>> = {
  'image/png': '.png',
  'image/jpeg': '.jpg',
  'image/svg+xml': '.svg',
  'image/webp': '.webp',
};

function replaceMediaBase(files: Record<string, HarmonyMediaDescriptor>, base: string, icon?: IconFile) {
  for (const name of Object.keys(files)) {
    if (path.parse(name).name === base) delete files[name];
  }

  if (icon) {
    files[`${base}${icon.extension}`] = { ...icon.media, replaceBase: true };
  }
}

function reconcileAbilityValue(
  value: unknown,
  fallback: string,
  field: keyof NonNullable<HarmonyConfigPluginOwnership['ability']>,
  previous: readonly HarmonyConfigPluginOwnership[],
  current: readonly HarmonyConfigPluginOwnership[]
) {
  if (typeof value !== 'string' || !value) return fallback;
  const removed = previous.some(plugin => plugin.ability?.[field] === value)
    && !current.some(plugin => plugin.ability?.[field] === value);
  return removed ? fallback : value;
}

function getSourceExtension(value: string, source: string = value) {
  const extension = path.extname(value).toLowerCase();

  if (!['.png', '.jpg', '.jpeg', '.svg', '.webp'].includes(extension)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_CONFIG_INVALID',
      `Unsupported Harmony icon format: ${extension || '(none)'}`,
      { file: source, operation: 'render-icons' }
    );
  }

  return extension;
}

function createLocalIcon(source: string): IconFile {
  return { extension: getSourceExtension(source), media: { source } };
}

async function resolveIcon(root: string, source: string): Promise<IconFile> {
  if (!/^https?:\/\//iu.test(source)) return createLocalIcon(resolveInputFile(root, source));

  try {
    const response = await fetch(source);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const mime = response.headers.get('content-type')?.split(';', 1)[0].trim().toLowerCase();
    const extension = mime && Object.hasOwn(IconExtensionByMimeType, mime)
      ? IconExtensionByMimeType[mime]
      : getSourceExtension(new URL(response.url || source).pathname, source);
    const content = new Uint8Array(await response.arrayBuffer());

    return { extension, media: { content } };
  } catch (cause) {
    if (cause instanceof HarmonyPrebuildError) throw cause;
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_CONFIG_INVALID',
      `Cannot download the Harmony icon: ${source}`,
      { cause, file: source, operation: 'render-icons' }
    );
  }
}

function resolveInputFile(root, value) {
  const file = path.resolve(root, value);

  let stat;

  try {
    stat = fs.statSync(file);
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_CONFIG_INVALID',
      `Harmony input file does not exist: ${file}`,
      { cause, file, operation: 'render-icons' }
    );
  }

  if (!stat.isFile()) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_CONFIG_INVALID',
      `Harmony input is not a file: ${file}`,
      { file, operation: 'render-icons' }
    );
  }

  return file;
}

function withEntryMods(config) {
  config = withEntryBuildProfile(config, (mod) => {
    const build = readRecord(mod.modResults.buildOption);
    const native = readRecord(build.externalNativeOptions);

    mod.modResults = {
      ...mod.modResults,
      apiType: 'stageMode',
      buildOption: {
        ...build,
        externalNativeOptions: {
          ...native,
          path: './src/main/cpp/CMakeLists.txt',
        },
      },
      targets: upsertNamed(
        upsertNamed(mod.modResults.targets, 'default', existing => ({
          ...existing,
          name: 'default',
          runtimeOS: 'HarmonyOS',
        })),
        'ohosTest',
        existing => ({ ...existing, name: 'ohosTest' })
      ),
    };

    return mod;
  });

  config = withEntryOhPackage(config, (mod) => {
    const harmony = normalizeHarmonyConfig(mod.modRawConfig);

    mod.modResults = {
      ...mod.modResults,
      name: harmony.moduleName,
      version: harmony.versionName,
      description: `${harmony.label} Harmony entry module`,
      license: mod.modResults.license || 'MIT',
      dependencies: mod.modResults.dependencies || {},
    };

    return mod;
  });

  config = withEntryHvigor(config, async (mod) => {
    const harmony = normalizeHarmonyConfig(mod.modRawConfig);
    const build = createHarmonyBuildDescriptor(harmony, mod._internal?.harmonySigningConfig?.name ?? null);
    const relative = path.posix.relative(build.harmonyRoot, build.projectFiles.moduleHvigor);

    mod.modResults = render.renderCanonical(
      await readTemplateSource(relative),
      build.projectFiles.moduleHvigor
    );

    return mod;
  });

  config = withModuleJson(config, (mod) => {
    const harmony = normalizeHarmonyConfig(mod.modRawConfig);
    const legacyHome = {
      entities: ['entity.system.home'],
      actions: ['action.system.home'],
    };
    const home = { ...legacyHome, actions: [...legacyHome.actions, 'ohos.want.action.home'] };
    const module = removeStaleExtensionAbilities(
      readRecord(mod.modResults.module),
      HarmonyPaths.toPosixRelative(
        mod.modRequest.projectRoot,
        path.join(mod.modRequest.platformProjectRoot, HarmonyPaths.HARMONY_PATHS.moduleJson)
      ),
      mod._internal?.harmonyStalePluginFiles || []
    );
    const previous = mod._internal?.harmonyPreviousManagedIdentity;
    const previousConfig = mod._internal?.harmonyPreviousManagedModuleConfig;
    const previousPlugins = mod._internal?.harmonyPreviousConfigPlugins ?? [];
    const plugins = getHarmonyConfigPlugins(mod);
    const permissions = reconcileModulePermissions(
      module.requestPermissions, previousConfig?.permissions ?? [], harmony.permissions
    );
    const querySchemes = reconcileModuleList(
      module.querySchemes, previousConfig?.querySchemes ?? [], harmony.querySchemes
    );
    const currentAbility = Array.isArray(module.abilities)
      ? module.abilities.find(ability => ability?.name === (previous?.abilityName ?? 'EntryAbility'))
      : undefined;
    const skills = reconcileModuleList(currentAbility?.skills, [
      ...(previousConfig?.skills ?? []), legacyHome,
    ], [home, ...harmony.skills]);

    const abilities = upsertManagedNamed(
      module.abilities,
      harmony.abilityName,
      previous?.abilityName,
      'EntryAbility',
      existing => ({
        ...existing,
        name: harmony.abilityName,
        srcEntry: './ets/entryability/EntryAbility.ets',
        description: '$string:expo_harmony_ability_desc',
        icon: '$media:app_icon',
        label: '$string:expo_harmony_ability_label',
        startWindowIcon: reconcileAbilityValue(
          existing.startWindowIcon, '$media:app_icon', 'startWindowIcon', previousPlugins, plugins
        ),
        startWindowBackground: reconcileAbilityValue(
          existing.startWindowBackground, '$color:expo_harmony_start_window_background', 'startWindowBackground',
          previousPlugins, plugins
        ),
        exported: true,
        visible: true,
        orientation: harmony.nativeOrientation,
        skills: skills.values,
      }),
      'abilityName'
    );
    mod.modResults = {
      ...mod.modResults,
      module: {
        ...module,
        name: harmony.moduleName,
        type: 'entry',
        srcEntry: './ets/abilitystage/EntryAbilityStage.ets',
        description: '$string:expo_harmony_module_desc',
        mainElement: harmony.abilityName,
        deviceTypes: harmony.deviceTypes,
        deliveryWithInstall: true,
        installationFree: false,
        pages: '$profile:main_pages',
        requestPermissions: permissions.values,
        querySchemes: querySchemes.values,
        abilities,
      },
    };
    mod._internal ??= {};
    Object.assign(mod._internal.harmonyManagedModuleConfig ??= {}, structuredClone({
      permissions: permissions.managed,
      querySchemes: querySchemes.managed,
      skills: skills.managed,
    }));

    return mod;
  });

  config = withStrings(config, (mod) => {
    const harmony = normalizeHarmonyConfig(mod.modRawConfig);

    mod.modResults = removeStaleResources(
      mod.modResults,
      'strings',
      mod._internal?.harmonyStaleConfigPlugins || [],
      getHarmonyConfigPlugins(mod)
    );

    const app = mod.modResults.app ??= {};
    const entry = mod.modResults.entry ??= {};

    HarmonyResources.setString(app, { name: 'app_name', value: harmony.label });
    HarmonyResources.setString(entry, { name: 'expo_harmony_ability_desc', value: `${harmony.label} main ability` });
    HarmonyResources.setString(entry, { name: 'expo_harmony_ability_label', value: harmony.label });
    HarmonyResources.setString(entry, { name: 'expo_harmony_module_desc', value: `${harmony.label} entry module` });

    for (const file of [app, entry]) file.string.sort((left, right) => left.name.localeCompare(right.name, 'en'));

    return mod;
  });

  config = withColors(config, (mod) => {
    const harmony = normalizeHarmonyConfig(mod.modRawConfig);

    mod.modResults = removeStaleResources(
      mod.modResults,
      'colors',
      mod._internal?.harmonyStaleConfigPlugins || [],
      getHarmonyConfigPlugins(mod)
    );

    const entry = mod.modResults.entry ??= {};

    mod.modResults.entryDark ??= {};

    HarmonyResources.setColor(entry, { name: 'expo_harmony_start_window_background', value: harmony.backgroundColor });
    entry.color.sort((left, right) => left.name.localeCompare(right.name, 'en'));

    return mod;
  });

  config = withMedia(config, async (mod) => {
    const harmony = normalizeHarmonyConfig(mod.modRawConfig);

    mod.modResults = removeStaleResources(
      mod.modResults,
      'media',
      mod._internal?.harmonyStaleConfigPlugins || [],
      getHarmonyConfigPlugins(mod)
    );

    const icon = harmony.icon
      ? await resolveIcon(mod.modRequest.projectRoot, harmony.icon)
      : null;
    const icons = icon
      ? { app: icon, entry: icon }
      : {
          app: createLocalIcon(resolveTemplateFile(`${HarmonyPlatformDirectory}/${HarmonyPaths.RESOURCE_PATHS.media.app}/app_icon.svg`)),
          entry: createLocalIcon(resolveTemplateFile(`${HarmonyPlatformDirectory}/${HarmonyPaths.RESOURCE_PATHS.media.entry}/app_icon.svg`)),
        };

    for (const [scope, file] of Object.entries(icons)) {
      mod.modResults[scope] ??= {};
      replaceMediaBase(mod.modResults[scope], 'app_icon', file);
      replaceMediaBase(mod.modResults[scope], 'app_icon_round');
    }

    return mod;
  });

  config = withProfiles(config, (mod) => {
    mod.modResults = {
      ...mod.modResults,
      src: appendUnique(mod.modResults.src, ['pages/Index']),
    };

    return mod;
  });

  return config;
}

export { withEntryMods };

import fs from 'node:fs';
import path from 'node:path';

import {
  getHarmonyConfigPlugins,
  HarmonyPaths,
  withColors,
  withEntryBuildProfile,
  withEntryHvigor,
  withEntryOhPackage,
  withMedia,
  withModuleJson,
  withProfiles,
  withStrings,
} from '@expo-harmony/config-plugins';

import {
  createHarmonyBuildDescriptor,
  HarmonyPlatformDirectory,
} from '../buildDescriptor';
import { readTemplateSource, resolveTemplateFile } from '../dependencies';
import { HarmonyPrebuildError } from '../errors';
import {
  appendUnique,
  readRecord,
  upsertManagedNamed,
  upsertNamed,
} from '../reconcile';
import * as render from '../renderers';
import { removeStaleResources } from '../stale';

function setResource(items, name, value) {
  const resources = (Array.isArray(items) ? items : [])
    .filter(item => item?.name !== name);

  resources.push({ name, value });
  resources.sort((left, right) => left.name.localeCompare(right.name, 'en'));

  return resources;
}

function replaceMediaBase(files, base, descriptor?) {
  for (const name of Object.keys(files)) {
    if (path.parse(name).name === base) delete files[name];
  }

  if (descriptor) {
    files[descriptor.name] = { source: descriptor.source, replaceBase: true };
  }
}

function reconcileRuntimeMetadata(items) {
  const names = new Set([
    'OPTLazyForEach',
    'can_preview_text',
    'halfLeading',
  ]);

  return (Array.isArray(items) ? items : [])
    .filter(item => !names.has(item?.name))
    .concat([
      { name: 'OPTLazyForEach', value: 'true' },
      { name: 'can_preview_text', value: 'true' },
      { name: 'halfLeading', value: 'true' },
    ]);
}

function isAbilityValueClaimed(plugins, field, value) {
  return plugins.some(plugin => plugin.ability?.[field] === value);
}

function getSourceExtension(value) {
  const extension = path.extname(value || '').toLowerCase();

  if (!['.png', '.jpg', '.jpeg', '.svg', '.webp'].includes(extension)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_CONFIG_INVALID',
      `Unsupported Harmony icon format: ${extension || '(none)'}`,
      { file: value, operation: 'render-icons' }
    );
  }

  return extension;
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

function withEntryMods(config, harmony) {
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
          abiFilters: harmony.abiFilters,
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
    const build = createHarmonyBuildDescriptor(harmony, mod._internal?.harmonySigningConfig?.name ?? null);
    const relative = path.posix.relative(build.harmonyRoot, build.projectFiles.moduleHvigor);

    mod.modResults = render.renderCanonical(
      await readTemplateSource(relative),
      build.projectFiles.moduleHvigor
    );

    return mod;
  });

  config = withModuleJson(config, (mod) => {
    const home = {
      entities: ['entity.system.home'],
      actions: ['action.system.home'],
    };
    const module = readRecord(mod.modResults.module);
    const previous = mod._internal?.harmonyPreviousManagedIdentity;
    const plugins = getHarmonyConfigPlugins(mod);

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
        startWindowIcon: isAbilityValueClaimed(
          plugins,
          'startWindowIcon',
          existing.startWindowIcon
        )
          ? existing.startWindowIcon
          : '$media:app_icon',
        startWindowBackground: isAbilityValueClaimed(
          plugins,
          'startWindowBackground',
          existing.startWindowBackground
        )
          ? existing.startWindowBackground
          : '$color:expo_harmony_start_window_background',
        exported: true,
        visible: true,
        orientation: harmony.nativeOrientation,
        skills: appendUnique([home], harmony.skills),
      }),
      'abilityName'
    );
    const metadata = reconcileRuntimeMetadata(module.metadata);

    mod.modResults = {
      ...mod.modResults,
      module: {
        ...module,
        name: harmony.moduleName,
        type: 'entry',
        description: '$string:expo_harmony_module_desc',
        mainElement: harmony.abilityName,
        deviceTypes: harmony.deviceTypes,
        deliveryWithInstall: true,
        installationFree: false,
        pages: '$profile:main_pages',
        requestPermissions: harmony.permissions,
        querySchemes: harmony.querySchemes,
        metadata,
        abilities,
      },
    };

    return mod;
  });

  config = withStrings(config, (mod) => {
    mod.modResults = removeStaleResources(
      mod.modResults,
      'strings',
      mod._internal?.harmonyStaleConfigPlugins || []
    );
    mod.modResults.app ??= {};
    mod.modResults.entry ??= {};

    mod.modResults.app.string = setResource(
      mod.modResults.app.string,
      'app_name',
      harmony.label
    );

    let strings = mod.modResults.entry.string || [];

    strings = setResource(
      strings,
      'expo_harmony_ability_desc',
      `${harmony.label} main ability`
    );
    strings = setResource(strings, 'expo_harmony_ability_label', harmony.label);
    strings = setResource(
      strings,
      'expo_harmony_module_desc',
      `${harmony.label} entry module`
    );
    mod.modResults.entry.string = strings;

    return mod;
  });

  config = withColors(config, (mod) => {
    mod.modResults = removeStaleResources(
      mod.modResults,
      'colors',
      mod._internal?.harmonyStaleConfigPlugins || []
    );
    mod.modResults.entry ??= {};
    mod.modResults.entryDark ??= {};

    mod.modResults.entry.color = setResource(
      mod.modResults.entry.color,
      'expo_harmony_start_window_background',
      harmony.backgroundColor
    );

    return mod;
  });

  config = withMedia(config, (mod) => {
    mod.modResults = removeStaleResources(
      mod.modResults,
      'media',
      mod._internal?.harmonyStaleConfigPlugins || []
    );

    const icon = harmony.icon
      ? resolveInputFile(mod.modRequest.projectRoot, harmony.icon)
      : null;
    const sources = icon
      ? { app: icon, entry: icon }
      : {
          app: resolveTemplateFile(`${HarmonyPlatformDirectory}/${HarmonyPaths.RESOURCE_PATHS.media.app}/app_icon.svg`),
          entry: resolveTemplateFile(`${HarmonyPlatformDirectory}/${HarmonyPaths.RESOURCE_PATHS.media.entry}/app_icon.svg`),
        };

    for (const [scope, source] of Object.entries(sources)) {
      mod.modResults[scope] ??= {};
      replaceMediaBase(mod.modResults[scope], 'app_icon', {
        name: `app_icon${getSourceExtension(source)}`,
        source,
      });
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

import fs from 'node:fs';
import path from 'node:path';

import {
  getHarmonyConfigPlugins,
  withColors,
  withEntryBuildProfile,
  withEntryHvigor,
  withEntryOhPackage,
  withMedia,
  withModuleJson,
  withProfiles,
  withStrings,
} from '@expo-harmony/config-plugins';

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
  const filtered = (Array.isArray(items) ? items : [])
    .filter(item => item?.name !== name);
  filtered.push({ name, value });
  filtered.sort((left, right) => left.name.localeCompare(right.name, 'en'));
  return filtered;
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
    'expo.harmony.minApiVersion',
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

function isAbilityValueClaimed(configPlugins, field, value) {
  return configPlugins.some(plugin => plugin.ability?.[field] === value);
}

function getSourceExtension(value) {
  const extension = path.extname(value || '').toLowerCase();
  if (!['.png', '.jpg', '.jpeg', '.svg', '.webp'].includes(extension)) {
    throw new HarmonyPrebuildError('ERR_HARMONY_CONFIG_INVALID', `Unsupported Harmony icon format: ${extension || '(none)'}`, { file: value, operation: 'render-icons' });
  }
  return extension;
}

function resolveInputFile(projectRoot, value) {
  const file = path.resolve(projectRoot, value);

  let stat;
  try {
    stat = fs.statSync(file);
  } catch (cause) {
    throw new HarmonyPrebuildError('ERR_HARMONY_CONFIG_INVALID', `Harmony input file does not exist: ${file}`, { cause, file, operation: 'render-icons' });
  }
  if (!stat.isFile()) {
    throw new HarmonyPrebuildError('ERR_HARMONY_CONFIG_INVALID', `Harmony input is not a file: ${file}`, { file, operation: 'render-icons' });
  }
  return file;
}

function withEntryMods(config, normalized) {
  config = withEntryBuildProfile(config, (value) => {
    const buildOption = readRecord(value.modResults.buildOption);
    const externalNativeOptions = readRecord(buildOption.externalNativeOptions);
    value.modResults = {
      ...value.modResults,
      apiType: 'stageMode',
      buildOption: {
        ...buildOption,
        externalNativeOptions: {
          ...externalNativeOptions,
          path: './src/main/cpp/CMakeLists.txt',
          abiFilters: normalized.abiFilters,
        },
      },
      targets: upsertNamed(
        upsertNamed(value.modResults.targets, 'default', existing => ({
          ...existing,
          name: 'default',
          runtimeOS: 'HarmonyOS',
        })),
        'ohosTest',
        existing => ({ ...existing, name: 'ohosTest' })
      ),
    };
    return value;
  });

  config = withEntryOhPackage(config, (value) => {
    value.modResults = {
      ...value.modResults,
      name: normalized.moduleName,
      version: normalized.versionName,
      description: `${normalized.label} Harmony entry module`,
      license: value.modResults.license || 'MIT',
      dependencies: value.modResults.dependencies || {},
    };
    return value;
  });

  config = withEntryHvigor(config, async (value) => {
    value.modResults = render.renderCanonical(
      await readTemplateSource('entry/hvigorfile.ts'),
      'harmony/entry/hvigorfile.ts'
    );
    return value;
  });

  config = withModuleJson(config, (value) => {
    const homeSkill = {
      entities: ['entity.system.home'],
      actions: ['action.system.home'],
    };
    const moduleValue = readRecord(value.modResults.module);
    const previousIdentity = value._internal?.harmonyPreviousManagedIdentity;
    const configPlugins = getHarmonyConfigPlugins(value);
    const abilities = upsertManagedNamed(
      moduleValue.abilities,
      normalized.abilityName,
      previousIdentity?.abilityName,
      'EntryAbility',
      existing => ({
        ...existing,
        name: normalized.abilityName,
        srcEntry: './ets/entryability/EntryAbility.ets',
        description: '$string:expo_harmony_ability_desc',
        icon: '$media:app_icon',
        label: '$string:expo_harmony_ability_label',
        startWindowIcon: isAbilityValueClaimed(
          configPlugins,
          'startWindowIcon',
          existing.startWindowIcon
        )
          ? existing.startWindowIcon
          : '$media:app_icon',
        startWindowBackground: isAbilityValueClaimed(
          configPlugins,
          'startWindowBackground',
          existing.startWindowBackground
        )
          ? existing.startWindowBackground
          : '$color:expo_harmony_start_window_background',
        exported: true,
        visible: true,
        orientation: normalized.nativeOrientation,
        skills: appendUnique([homeSkill], normalized.skills),
      }),
      'abilityName'
    );
    const metadata = reconcileRuntimeMetadata(moduleValue.metadata);
    value.modResults = {
      ...value.modResults,
      module: {
        ...moduleValue,
        name: normalized.moduleName,
        type: 'entry',
        description: '$string:expo_harmony_module_desc',
        mainElement: normalized.abilityName,
        deviceTypes: normalized.deviceTypes,
        deliveryWithInstall: true,
        installationFree: false,
        pages: '$profile:main_pages',
        requestPermissions: normalized.permissions,
        querySchemes: normalized.querySchemes,
        metadata,
        abilities,
      },
    };
    return value;
  });

  config = withStrings(config, (value) => {
    value.modResults = removeStaleResources(
      value.modResults,
      'strings',
      value._internal?.harmonyStaleConfigPlugins || []
    );
    value.modResults.app ??= {};
    value.modResults.entry ??= {};
    value.modResults.app.string = setResource(
      value.modResults.app.string,
      'app_name',
      normalized.label
    );

    let strings = value.modResults.entry.string || [];
    strings = setResource(
      strings,
      'expo_harmony_ability_desc',
      `${normalized.label} main ability`
    );
    strings = setResource(strings, 'expo_harmony_ability_label', normalized.label);
    strings = setResource(
      strings,
      'expo_harmony_module_desc',
      `${normalized.label} entry module`
    );
    value.modResults.entry.string = strings;
    return value;
  });

  config = withColors(config, (value) => {
    value.modResults = removeStaleResources(
      value.modResults,
      'colors',
      value._internal?.harmonyStaleConfigPlugins || []
    );
    value.modResults.entry ??= {};
    value.modResults.entryDark ??= {};
    value.modResults.entry.color = setResource(
      value.modResults.entry.color,
      'expo_harmony_start_window_background',
      normalized.backgroundColor
    );
    return value;
  });

  config = withMedia(config, (value) => {
    value.modResults = removeStaleResources(
      value.modResults,
      'media',
      value._internal?.harmonyStaleConfigPlugins || []
    );
    const customIcon = normalized.icon
      ? resolveInputFile(value.modRequest.projectRoot, normalized.icon)
      : null;
    const sources = customIcon
      ? { app: customIcon, entry: customIcon }
      : {
          app: resolveTemplateFile(
            'harmony/AppScope/resources/base/media/app_icon.svg'
          ),
          entry: resolveTemplateFile(
            'harmony/entry/src/main/resources/base/media/app_icon.svg'
          ),
        };

    for (const [scope, source] of Object.entries(sources)) {
      value.modResults[scope] ??= {};
      replaceMediaBase(value.modResults[scope], 'app_icon', {
        name: `app_icon${getSourceExtension(source)}`,
        source,
      });
      replaceMediaBase(value.modResults[scope], 'app_icon_round');
    }
    return value;
  });

  config = withProfiles(config, (value) => {
    value.modResults = {
      ...value.modResults,
      src: appendUnique(value.modResults.src, ['pages/Index']),
    };
    return value;
  });

  return config;
}

export { withEntryMods };

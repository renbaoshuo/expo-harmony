'use strict';

const fs = require('node:fs');
const path = require('node:path');

const { createRunOncePlugin } = require('@expo/config-plugins');
const {
  recordManagedFile,
  registerHarmonyConfigPlugin,
  withHarmonyDangerousMod,
  withModuleJson,
  withProfiles,
} = require('@expo-harmony/config-plugins');

const NAME = 'expo-harmony-demo-intent-launcher-fixture';
const ABILITY = 'IntentLauncherAbility';
const PAGE = 'pages/IntentLauncher';

function withIntentLauncherFixture(config) {
  if (!config.harmony?.bundleName && !config.platforms?.includes('harmony')) return config;

  config = registerHarmonyConfigPlugin(config, NAME);
  config = withModuleJson(config, (mod) => {
    const module = mod.modResults.module;
    module.abilities = [
      ...(module.abilities ?? []).filter(ability => ability.name !== ABILITY),
      {
        name: ABILITY,
        srcEntry: `./ets/intentlauncher/${ABILITY}.ets`,
        exported: false,
        launchType: 'standard',
        startWindowIcon: '$media:app_icon',
        startWindowBackground: '$color:expo_splash_screen_background',
      },
    ];

    return mod;
  });
  config = withProfiles(config, (mod) => {
    const pages = mod.modResults;
    pages.src = [...new Set([...pages.src, PAGE])];

    return mod;
  });

  return withHarmonyDangerousMod(config, async (mod) => {
    const root = path.join(mod.modRequest.platformProjectRoot, 'entry/src/main/ets');
    const files = [
      [`${ABILITY}.ets`, `intentlauncher/${ABILITY}.ets`],
      ['IntentLauncher.ets', `${PAGE}.ets`],
    ];
    for (const [source, relative] of files) {
      const file = path.join(root, relative);
      await fs.promises.mkdir(path.dirname(file), { recursive: true });
      await fs.promises.copyFile(path.join(__dirname, '../native/intent-launcher', source), file);
      recordManagedFile(mod, file, NAME);
    }

    return mod;
  });
}

module.exports = createRunOncePlugin(withIntentLauncherFixture, NAME, '1.0.0');

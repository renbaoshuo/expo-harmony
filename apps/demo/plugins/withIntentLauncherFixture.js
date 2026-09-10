'use strict';

const path = require('node:path');

const { createRunOncePlugin } = require('@expo/config-plugins');
const {
  registerHarmonyConfigPlugin,
  withHarmonyGeneratedFiles,
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

  return withHarmonyGeneratedFiles(config, {
    owner: NAME,
    files: {
      [`entry/src/main/ets/intentlauncher/${ABILITY}.ets`]: {
        source: path.join(__dirname, '../native/intent-launcher', `${ABILITY}.ets`),
      },
      [`entry/src/main/ets/${PAGE}.ets`]: {
        source: path.join(__dirname, '../native/intent-launcher/IntentLauncher.ets'),
      },
    },
  });
}

module.exports = createRunOncePlugin(withIntentLauncherFixture, NAME, '1.0.0');

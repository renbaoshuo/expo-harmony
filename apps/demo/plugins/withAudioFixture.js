'use strict';

const fs = require('node:fs');
const path = require('node:path');

const { createRunOncePlugin } = require('@expo/config-plugins');
const {
  recordManagedFile,
  registerHarmonyConfigPlugin,
  withHarmonyDangerousMod,
} = require('@expo-harmony/config-plugins');

const PLUGIN_NAME = 'expo-harmony-demo-audio-fixture';
const RAWFILE_PATH = 'audio/probe.wav';
const ASSET_PATH = 'assets/audio/probe.wav';
const RAWFILE_URI = `rawfile://${RAWFILE_PATH}`;
const ASSET_URI = 'asset://audio/probe.wav';
const FIXTURE_BASE64
  = 'UklGRkQDAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YSADAAAAAJ4GcwzQEC8TShMeEesMMQedAPf5B/SC7/Dsn+yZ7qHyPvjG/nMFewsnEOsSchOsEdANUQjXASX7BvUz8D/tguwT7sPxIveN/UMEdwpvD5MShhMpEqcOaQkOA1f8D/bz8KDteOyg7fPwD/ZX/A4DaQmnDikShhOTEm8PdwpDBI39IvfD8RPuguw/7TPwBvUl+9cBUQjQDawRchPrEicQewtzBcb+Pvih8pnun+zw7ILvB/T3+Z0AMQfrDB4RShMvE9AQcwyeBgAAYvmN8zDv0ey27OLuFfPP+GP/CQb5C34QEBNhE2cRXw3CBzoBjfqF9NnvFe2O7FTuMPKv9yn+2wT6Cs0PwRJ+E+0RPQ7eCHMCvfuJ9ZHwbe167NftWfGX9vL8qQPxCQ0PYBKIE2ASDQ/xCakD8vyX9lnx1+167G3tkfCJ9b37cwLeCD0O7RF+E8ESzQ/6CtsEKf6v9zDyVO6O7BXt2e+F9I36OgHCB18NZxFhExATfhD5CwkGY//P+BXz4u627NHsMO+N82L5AACeBnMM0BAvE0oTHhHrDDEHnQD3+Qf0gu/w7J/sme6h8j74xv5zBXsLJxDrEnITrBHQDVEI1wEl+wb1M/A/7YLsE+7D8SL3jf1DBHcKbw+TEoYTKRKnDmkJDgNX/A/28/Cg7XjsoO3z8A/2V/wOA2kJpw4pEoYTkxJvD3cKQwSN/SL3w/ET7oLsP+0z8Ab1JfvXAVEI0A2sEXIT6xInEHsLcwXG/j74ofKZ7p/s8OyC7wf09/mdADEH6wweEUoTLxPQEHMMngYAAGL5jfMw79Hstuzi7hXzz/hj/wkG+Qt+EBATYRNnEV8Nwgc6AY36hfTZ7xXtjuxU7jDyr/cp/tsE+grND8ESfhPtET0O3ghzAr37ifWR8G3teuzX7Vnxl/by/KkD8QkND2ASiBNgEg0P8QmpA/L8l/ZZ8dfteuxt7ZHwifW9+3MC3gg9Du0RfhPBEs0P+grbBCn+r/cw8lTujuwV7dnvhfSN+joBwgdfDWcRYRMQE34Q+QsJBmP/z/gV8+LutuzR7DDvjfNi+Q==';

function fixtureBytes() {
  return Buffer.from(FIXTURE_BASE64, 'base64');
}

function withAudioFixture(config) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  config = registerHarmonyConfigPlugin(config, PLUGIN_NAME);

  return withHarmonyDangerousMod(config, async (mod) => {
    const root = path.join(mod.modRequest.platformProjectRoot, 'entry', 'src', 'main', 'resources', 'rawfile');
    const bytes = fixtureBytes();

    for (const relative of [RAWFILE_PATH, ASSET_PATH]) {
      const destination = path.join(root, relative);

      await fs.promises.mkdir(path.dirname(destination), { recursive: true });
      await fs.promises.writeFile(destination, bytes);
      recordManagedFile(mod, destination, PLUGIN_NAME);
    }

    return mod;
  });
}

module.exports = createRunOncePlugin(withAudioFixture, PLUGIN_NAME);
module.exports.ASSET_URI = ASSET_URI;
module.exports.RAWFILE_URI = RAWFILE_URI;
module.exports.fixtureBytes = fixtureBytes;
module.exports.withAudioFixture = withAudioFixture;

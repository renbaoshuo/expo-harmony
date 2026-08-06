'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const { createWithHarmonyConfig } = require('../src/createWithHarmonyConfig');

function mergeConfig(base, override) {
  return {
    ...base,
    ...override,
    resolver: {
      ...base.resolver,
      ...override.resolver,
    },
    serializer: {
      ...base.serializer,
      ...override.serializer,
    },
    transformer: {
      ...base.transformer,
      ...override.transformer,
    },
  };
}

function createHarness() {
  const calls = [];
  const createHarmonyMetroConfig = options => ({
    resolver: {
      blockList: [/\.cxx/u],
      platforms: ['ios'],
      resolveRequest(context, moduleName, platform) {
        calls.push({ kind: 'harmony', moduleName, options, platform });
        return context.resolveRequest(context, `rnoh:${moduleName}`, platform);
      },
    },
    serializer: {
      harmony: true,
    },
  });

  return {
    calls,
    withHarmonyConfig: createWithHarmonyConfig({
      createHarmonyMetroConfig,
      mergeConfig,
    }),
  };
}

function createContext(calls) {
  return {
    originModulePath: '/app/index.js',
    resolveRequest(_context, moduleName, platform) {
      calls.push({ kind: 'metro', moduleName, platform });
      return { type: 'sourceFile', filePath: `${platform}:${moduleName}` };
    },
  };
}

test('merges RNOH defaults and preserves resolver collections', () => {
  const { calls, withHarmonyConfig } = createHarness();
  const config = withHarmonyConfig(
    {
      projectRoot: '/app',
      resolver: {
        blockList: /ignored/u,
        platforms: ['android', 'ios'],
        unstable_conditionsByPlatform: {
          harmony: ['custom'],
          web: ['browser'],
        },
      },
    },
    {
      conditions: ['react-native', 'custom'],
    }
  );

  assert.deepEqual(config.resolver.platforms, ['android', 'ios', 'harmony']);
  assert.equal(config.resolver.blockList.length, 2);
  assert.deepEqual(config.resolver.unstable_conditionsByPlatform, {
    harmony: ['custom', 'react-native'],
    web: ['browser'],
  });
  assert.equal(config.serializer.harmony, true);

  const result = config.resolver.resolveRequest(createContext(calls), 'example', 'harmony');
  assert.deepEqual(result, { type: 'sourceFile', filePath: 'harmony:rnoh:example' });
});

test('keeps non-Harmony requests on the original resolver', () => {
  const { calls, withHarmonyConfig } = createHarness();
  const baseResolver = (context, moduleName, platform) => {
    calls.push({ kind: 'expo', moduleName, platform });
    return context.resolveRequest(context, `expo:${moduleName}`, platform);
  };
  const config = withHarmonyConfig({ resolver: { resolveRequest: baseResolver } });

  const result = config.resolver.resolveRequest(createContext(calls), 'example', 'ios');

  assert.deepEqual(result, { type: 'sourceFile', filePath: 'ios:expo:example' });
  assert.deepEqual(calls.map(call => call.kind), ['expo', 'metro']);
});

test('bridges RNOH back into the original Expo resolver', () => {
  const { calls, withHarmonyConfig } = createHarness();
  const baseResolver = (context, moduleName, platform) => {
    calls.push({ kind: 'expo', moduleName, platform });
    return context.resolveRequest(context, `expo:${moduleName}`, platform);
  };
  const config = withHarmonyConfig({ resolver: { resolveRequest: baseResolver } });

  const result = config.resolver.resolveRequest(createContext(calls), 'react-native', 'harmony');

  assert.deepEqual(result, {
    type: 'sourceFile',
    filePath: 'harmony:expo:rnoh:react-native',
  });
  assert.deepEqual(calls.map(call => call.kind), ['harmony', 'expo', 'metro']);
});

test('supports empty modules, exact redirects, and longest prefix aliases', () => {
  const { calls, withHarmonyConfig } = createHarness();
  const config = withHarmonyConfig(
    { projectRoot: '/app', resolver: {} },
    {
      aliases: new Map([
        ['@', '/app'],
        ['@/components', '/app/special-components'],
        ['react', 'react-harmony'],
      ]),
      emptyModules: [/MaterialSymbols/u],
      redirects: {
        'expo-blur': '/app/adapters/expo-blur.harmony.js',
        'optional-package': false,
      },
    }
  );
  const context = createContext(calls);

  assert.deepEqual(config.resolver.resolveRequest(context, 'MaterialSymbolsRounded', 'harmony'), {
    type: 'empty',
  });
  assert.deepEqual(config.resolver.resolveRequest(context, 'optional-package', 'harmony'), {
    type: 'empty',
  });
  assert.equal(
    config.resolver.resolveRequest(context, 'expo-blur', 'harmony').filePath,
    'harmony:/app/adapters/expo-blur.harmony.js'
  );
  assert.equal(
    config.resolver.resolveRequest(context, '@/components/button', 'harmony').filePath,
    'harmony:/app/special-components/button'
  );
  assert.equal(
    config.resolver.resolveRequest(context, 'react/jsx-runtime', 'harmony').filePath,
    'harmony:react-harmony/jsx-runtime'
  );
});

test('allows contextual hooks to resolve, empty, or delegate', () => {
  const { calls, withHarmonyConfig } = createHarness();
  const config = withHarmonyConfig(
    { resolver: {} },
    {
      projectRoot: '/workspace',
      redirects: {
        delegated: 'redirected',
      },
      resolveRequest(request) {
        if (request.moduleName === './SplashScreen') {
          return {
            type: 'sourceFile',
            filePath: path.join(request.projectRoot, 'SplashScreen.harmony.js'),
          };
        }
        if (request.moduleName === 'unused') {
          return false;
        }
        if (request.moduleName === 'through-expo') {
          return request.resolve('expo-target');
        }
      },
    }
  );
  const context = createContext(calls);

  assert.equal(
    config.resolver.resolveRequest(context, './SplashScreen', 'harmony').filePath,
    '/workspace/SplashScreen.harmony.js'
  );
  assert.deepEqual(config.resolver.resolveRequest(context, 'unused', 'harmony'), { type: 'empty' });
  assert.equal(
    config.resolver.resolveRequest(context, 'through-expo', 'harmony').filePath,
    'harmony:expo-target'
  );
  assert.equal(
    config.resolver.resolveRequest(context, 'delegated', 'harmony').filePath,
    'harmony:redirected'
  );
});

test('forwards RNOH options and configures the environment', () => {
  const { calls, withHarmonyConfig } = createHarness();
  const previousExpoHarmony = process.env.EXPO_HARMONY;
  const previousIsHarmony = process.env.IS_HARMONY;

  try {
    const config = withHarmonyConfig(
      {
        resolver: {},
      },
      {
        env: { IS_HARMONY: 'true' },
        harmonyConfigOptions: { custom: true },
        reactNativeHarmonyPackageName: 'custom-rnoh',
      }
    );
    config.resolver.resolveRequest(createContext(calls), 'example', 'harmony');

    const harmonyCall = calls.find(call => call.kind === 'harmony');
    assert.deepEqual(harmonyCall.options, {
      custom: true,
      reactNativeHarmonyPackageName: 'custom-rnoh',
    });
    assert.equal(process.env.EXPO_HARMONY, 'true');
    assert.equal(process.env.IS_HARMONY, 'true');
  } finally {
    if (previousExpoHarmony === undefined) {
      delete process.env.EXPO_HARMONY;
    } else {
      process.env.EXPO_HARMONY = previousExpoHarmony;
    }
    if (previousIsHarmony === undefined) {
      delete process.env.IS_HARMONY;
    } else {
      process.env.IS_HARMONY = previousIsHarmony;
    }
  }
});

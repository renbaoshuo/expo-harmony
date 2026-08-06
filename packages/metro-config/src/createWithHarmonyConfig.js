'use strict';

const fs = require('node:fs');
const path = require('node:path');

const HARMONY_PLATFORM = 'harmony';
const DEFAULT_REACT_NATIVE_HARMONY_PACKAGE = '@react-native-oh/react-native-harmony';
const APP_PRELUDE_MODULE = '@expo-harmony/entry/app-prelude';
const NO_RESOLUTION = Symbol('NO_RESOLUTION');

function findFile(filePaths) {
  for (const filePath of filePaths) {
    try {
      if (fs.statSync(filePath).isFile()) {
        return filePath;
      }
    } catch {
      // Try the next application prelude candidate.
    }
  }

  return null;
}

function getApplicationPrelude(projectRoot, platform) {
  const candidates = [];

  if (typeof platform === 'string' && /^[a-z0-9_-]+$/iu.test(platform)) {
    candidates.push(path.join(projectRoot, `prelude.${platform}.js`));
  }

  candidates.push(path.join(projectRoot, 'prelude.js'));

  return findFile(candidates);
}

function assertObject(value, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError(`${name} must be an object.`);
  }
}

function entries(value, name) {
  if (value === undefined) {
    return [];
  }

  if (value instanceof Map) {
    return [...value.entries()];
  }

  assertObject(value, name);
  return Object.entries(value);
}

function validateOptions(options) {
  assertObject(options, 'options');

  if (options.resolveRequest !== undefined && typeof options.resolveRequest !== 'function') {
    throw new TypeError('options.resolveRequest must be a function.');
  }

  if (options.emptyModules !== undefined && !Array.isArray(options.emptyModules)) {
    throw new TypeError('options.emptyModules must be an array.');
  }
  if (options.emptyModules?.some(matcher => typeof matcher !== 'string' && !(matcher instanceof RegExp) && typeof matcher !== 'function')) {
    throw new TypeError('options.emptyModules entries must be strings, regular expressions, or functions.');
  }

  if (options.conditions !== undefined) {
    if (!Array.isArray(options.conditions) || options.conditions.some(condition => typeof condition !== 'string')) {
      throw new TypeError('options.conditions must be an array of strings.');
    }
  }

  for (const [alias, target] of entries(options.aliases, 'options.aliases')) {
    if (typeof alias !== 'string' || typeof target !== 'string') {
      throw new TypeError('options.aliases must map strings to strings.');
    }
  }

  for (const [moduleName, target] of entries(options.redirects, 'options.redirects')) {
    if (typeof moduleName !== 'string') {
      throw new TypeError('options.redirects keys must be strings.');
    }
    if (!['string', 'function', 'object', 'undefined'].includes(typeof target) && target !== false) {
      throw new TypeError(`Unsupported redirect target for "${moduleName}".`);
    }
  }

  if (options.env !== undefined && options.env !== false) {
    for (const [name, value] of entries(options.env, 'options.env')) {
      if (typeof value !== 'string') {
        throw new TypeError(`options.env["${name}"] must be a string.`);
      }
    }
  }
}

function setEnvironmentVariables(env) {
  if (env === false) {
    return;
  }

  Object.assign(process.env, {
    EXPO_HARMONY: 'true',
    ...env,
  });
}

function toArray(value) {
  if (value === undefined || value === null) {
    return [];
  }
  return Array.isArray(value) ? value : [value];
}

function unique(values) {
  return [...new Set(values)];
}

function mergeBlockLists(baseBlockList, harmonyBlockList) {
  const blockList = [...toArray(baseBlockList), ...toArray(harmonyBlockList)];
  if (blockList.length === 0) {
    return undefined;
  }
  return blockList;
}

function matches(matcher, request) {
  if (typeof matcher === 'string') {
    return request.moduleName === matcher;
  }

  if (matcher instanceof RegExp) {
    matcher.lastIndex = 0;
    return matcher.test(request.moduleName);
  }

  if (typeof matcher === 'function') {
    return matcher(request);
  }

  throw new TypeError('emptyModules entries must be strings, regular expressions, or functions.');
}

function findEntry(collection, moduleName) {
  if (collection === undefined) {
    return NO_RESOLUTION;
  }

  if (collection instanceof Map) {
    return collection.has(moduleName) ? collection.get(moduleName) : NO_RESOLUTION;
  }

  return Object.prototype.hasOwnProperty.call(collection, moduleName)
    ? collection[moduleName]
    : NO_RESOLUTION;
}

function findAlias(aliasEntries, moduleName) {
  for (const [alias, target] of aliasEntries) {
    if (moduleName === alias) {
      return target;
    }
    if (moduleName.startsWith(`${alias}/`)) {
      return `${target}${moduleName.slice(alias.length)}`;
    }
  }

  return NO_RESOLUTION;
}

function resolveTarget(target, request) {
  const result = typeof target === 'function' ? target(request) : target;

  if (result === undefined || result === null) {
    return NO_RESOLUTION;
  }
  if (result === false) {
    return { type: 'empty' };
  }
  if (typeof result === 'string') {
    return request.resolve(result);
  }
  if (typeof result === 'object') {
    return result;
  }

  throw new TypeError('A resolver hook must return a Metro resolution, a module name, false, null, or undefined.');
}

function resolveConfiguredRequest(options, aliasEntries, request) {
  if ((options.emptyModules ?? []).some(matcher => matches(matcher, request))) {
    return { type: 'empty' };
  }

  if (options.resolveRequest) {
    const customResolution = resolveTarget(options.resolveRequest, request);
    if (customResolution !== NO_RESOLUTION) {
      return customResolution;
    }
  }

  const redirect = findEntry(options.redirects, request.moduleName);
  if (redirect !== NO_RESOLUTION) {
    const redirectedResolution = resolveTarget(redirect, request);
    if (redirectedResolution !== NO_RESOLUTION) {
      return redirectedResolution;
    }
  }

  const alias = findAlias(aliasEntries, request.moduleName);
  if (alias !== NO_RESOLUTION) {
    return request.resolve(alias);
  }

  return request.resolveHarmony();
}

function createResolver({ baseResolver, harmonyResolver, options, projectRoot }) {
  const aliasEntries = entries(options.aliases, 'options.aliases').sort(
    ([left], [right]) => right.length - left.length
  );

  return function resolveRequest(context, moduleName, platform) {
    const metroResolver = context.resolveRequest;

    const resolveBase = (targetModuleName, targetPlatform = platform, targetContext = context) => {
      if (!baseResolver) {
        return metroResolver(targetContext, targetModuleName, targetPlatform);
      }

      return baseResolver(
        {
          ...targetContext,
          resolveRequest: metroResolver,
        },
        targetModuleName,
        targetPlatform
      );
    };

    if (moduleName === APP_PRELUDE_MODULE) {
      const appPrelude = getApplicationPrelude(projectRoot, platform);
      if (appPrelude) {
        return { type: 'sourceFile', filePath: appPrelude };
      }

      return resolveBase(moduleName, platform);
    }

    if (platform !== HARMONY_PLATFORM) {
      return resolveBase(moduleName, platform);
    }

    const resolveHarmony = (
      targetModuleName = moduleName,
      targetPlatform = platform,
      targetContext = context
    ) => {
      const harmonyContext = {
        ...targetContext,
        resolveRequest(innerContext, innerModuleName, innerPlatform) {
          return resolveBase(innerModuleName, innerPlatform, innerContext);
        },
      };

      return harmonyResolver(harmonyContext, targetModuleName, targetPlatform);
    };

    return resolveConfiguredRequest(
      options,
      aliasEntries,
      {
        context,
        moduleName,
        platform,
        projectRoot,
        resolve: resolveBase,
        resolveHarmony,
      }
    );
  };
}

function createWithHarmonyConfig({ createHarmonyMetroConfig, mergeConfig }) {
  if (typeof createHarmonyMetroConfig !== 'function' || typeof mergeConfig !== 'function') {
    throw new TypeError('createWithHarmonyConfig requires Metro configuration functions.');
  }

  return function withHarmonyConfig(config, options = {}) {
    assertObject(config, 'config');
    validateOptions(options);
    setEnvironmentVariables(options.env);

    const reactNativeHarmonyPackageName = options.reactNativeHarmonyPackageName ?? DEFAULT_REACT_NATIVE_HARMONY_PACKAGE;
    const harmonyConfig = createHarmonyMetroConfig({
      ...options.harmonyConfigOptions,
      reactNativeHarmonyPackageName,
    });
    const mergedConfig = mergeConfig(config, harmonyConfig);
    const baseResolver = config.resolver?.resolveRequest;
    const harmonyResolver = mergedConfig.resolver?.resolveRequest;

    if (typeof harmonyResolver !== 'function') {
      throw new TypeError('createHarmonyMetroConfig() did not return a resolver.resolveRequest function.');
    }

    const conditions = options.conditions ?? ['react-native'];
    const existingHarmonyConditions = mergedConfig.resolver?.unstable_conditionsByPlatform?.[HARMONY_PLATFORM] ?? [];
    const blockList = mergeBlockLists(config.resolver?.blockList, harmonyConfig.resolver?.blockList);
    const projectRoot = options.projectRoot ?? mergedConfig.projectRoot ?? process.cwd();

    return {
      ...mergedConfig,
      resolver: {
        ...mergedConfig.resolver,
        ...(blockList ? { blockList } : {}),
        platforms: unique([
          ...(config.resolver?.platforms ?? []),
          ...(harmonyConfig.resolver?.platforms ?? []),
          ...(mergedConfig.resolver?.platforms ?? []),
          HARMONY_PLATFORM,
        ]),
        unstable_conditionsByPlatform: {
          ...mergedConfig.resolver?.unstable_conditionsByPlatform,
          [HARMONY_PLATFORM]: unique([...existingHarmonyConditions, ...conditions]),
        },
        resolveRequest: createResolver({
          baseResolver,
          harmonyResolver,
          options,
          projectRoot,
        }),
      },
    };
  };
}

module.exports = { createWithHarmonyConfig };

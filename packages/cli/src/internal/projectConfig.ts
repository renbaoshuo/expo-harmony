/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { Options } from '@expo/fingerprint';

import { requireFromExpo, requireFromExpoCli } from '../expo';

async function main() {
  const root = process.cwd();
  const [, , mode, operation] = process.argv;
  const input = operation === 'fingerprint'
    ? new Promise<Options>(resolve => process.once('message', resolve))
    : undefined;
  const { setNodeEnv, loadEnvFiles } = requireFromExpoCli(root)('./build/src/utils/nodeEnv');
  setNodeEnv(mode);
  loadEnvFiles(root, { silent: true });

  if (input) {
    const options = await input;
    const { createFingerprintAsync } = await import('@expo/fingerprint');
    // SDK 57's explicit extraSources replace those from the user config.
    // Use its own config loader to preserve configured sources and precedence.
    const { loadConfigAsync } = await import('@expo/fingerprint/build/Config.js');
    const config = await loadConfigAsync(root);
    return createFingerprintAsync(root, {
      ...options,
      extraSources: [...config?.extraSources ?? [], ...options.extraSources ?? []],
    });
  }

  if (operation === 'native-runtime') {
    const { evaluateProjectNativeRuntimeAsync } = await import('../runtime/config.js');
    return evaluateProjectNativeRuntimeAsync(root);
  }

  const metro = requireFromExpo(root)('@expo/metro/metro-config');
  const { config } = await metro.resolveConfig(undefined, root);
  const platforms = config?.resolver?.platforms;
  const extensions = config?.resolver?.unstable_platformExtensions?.harmony;
  return {
    platform: Array.isArray(platforms) && platforms.includes('harmony'),
    extensions: Array.isArray(extensions) && extensions.includes('harmony'),
    runtime: config?.resolver?.resolveRequest?.harmonyRuntime,
  };
}

main().then(
  result => process.send?.({ result }, () => process.exit()),
  error => process.send?.({ error: error.message, code: error.code }, () => process.exit(1))
);

/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { parseCommandArgs, type Command } from '../command';
import { parseExportEmbedArgs } from './options';

export const command: Command = async (argv, io) => {
  const args = parseCommandArgs(parseExportEmbedArgs, argv, io);
  if (!args) return 0;

  const { projectRoot: root, options } = args;
  const { exportEmbedAsync } = await import('./export.js');

  const inHvigor = process.env.EXPO_HARMONY_EXPORT_EMBED_IN_HVIGOR === '1';
  const result = await exportEmbedAsync(root, {
    ...options,
    buildMode: inHvigor && process.env.EXPO_HARMONY_BUILD_TYPE === 'debug' ? 'debug' : 'release',
    skipDoctor: inHvigor,
  });

  if (options.check) io.log('Harmony export bundle, assets, and source map are valid.');
  else io.log(`Exported Hermes bytecode ${result.bundle.path} with ${result.assets.length} asset file(s).`);

  return 0;
};

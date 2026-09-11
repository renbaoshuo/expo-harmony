import { parseCommandArgs, type Command } from '../command';
import { parseExportEmbedArgs } from './options';

export const command: Command = async (argv, io) => {
  const args = parseCommandArgs(parseExportEmbedArgs, argv, io);
  if (!args) return 0;

  const { projectRoot: root, options } = args;
  const { exportEmbedAsync } = await import('./export.js');

  const result = await exportEmbedAsync(root, options);

  if (options.check) io.log('Harmony export bundle, assets, and source map are valid.');
  else io.log(`Exported Hermes bytecode ${result.bundle.path} with ${result.assets.length} asset file(s).`);

  return 0;
};

import fs from 'node:fs';
import path from 'node:path';
import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { createRNOHModulePlugin } from '@rnoh/hvigor-plugin';

const projectRoot = path.resolve('..');
function resolveNodeModulesPath() {
  let directory = projectRoot;
  while (true) {
    const candidate = path.join(directory, 'node_modules');
    if (fs.existsSync(candidate)) return candidate;
    const parent = path.dirname(directory);
    if (parent === directory) throw new Error('Unable to find node_modules for the Harmony project.');
    directory = parent;
  }
}
const nodeModulesPath = resolveNodeModulesPath();

export default {
  system: hapTasks,
  plugins: [
    createRNOHModulePlugin({
      nodeModulesPath,
      codegen: {
        rnohModulePath: './oh_modules/@rnoh/react-native-openharmony',
        cppOutputPath: './entry/src/main/cpp/rnoh_codegen/generated',
      },
      autolinking: null,
    }),
  ],
};

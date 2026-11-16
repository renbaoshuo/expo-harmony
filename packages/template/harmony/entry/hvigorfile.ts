/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import path from 'node:path';
import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { createRNOHModulePlugin } from '@rnoh/hvigor-plugin';

const projectRoot = path.resolve('..');
function resolveNodeModulesPath(): string {
  const executable = process.platform === 'win32' ? 'react-native.cmd' : 'react-native';
  let dir = projectRoot;

  while (true) {
    const candidate = path.join(dir, 'node_modules');
    if (fs.existsSync(path.join(candidate, '.bin', executable))) return candidate;

    const parent = path.dirname(dir);
    if (parent === dir) throw new Error('Unable to find the React Native CLI in node_modules/.bin for Harmony Codegen.');
    dir = parent;
  }
}

const nodeModulesPath = resolveNodeModulesPath();

export default {
  system: hapTasks,
  plugins: [
    createRNOHModulePlugin({
      nodeModulesPath,
      codegen: {
        projectRootPath: projectRoot,
        etsOutputPath: './entry/src/main/ets/rnoh_codegen',
        cppOutputPath: './entry/src/main/cpp/rnoh_codegen/generated',
      },
      autolinking: null,
      // The CLI forwards Metro to the selected device when running the app.
      metro: null,
    }),
  ],
};

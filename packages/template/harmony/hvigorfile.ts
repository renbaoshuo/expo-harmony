/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import path from 'node:path';
import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { prepareHarmonyBundleTask, publishHarmonyNativeRuntime } from '@expo-harmony/cli/native-build';
import { createRNOHProjectPlugin } from '@rnoh/hvigor-plugin';

import { writeStamp } from './native-inputs-stamp';

process.env.HERMES_V1_ENABLED = 'true';

const ProjectRoot = path.resolve('..');
const HarmonyRoot = path.join(ProjectRoot, 'harmony');
const NodeModules = findNodeModules();
const EmbeddedBundle = path.join(ProjectRoot, '__EXPO_HARMONY_BUNDLE_PATH__');

writeStamp(ProjectRoot, HarmonyRoot);

function findNodeModules(): string {
  let directory = ProjectRoot;

  while (true) {
    const candidate = path.join(directory, 'node_modules');
    if (fs.existsSync(candidate)) return candidate;

    const parent = path.dirname(directory);
    if (parent === directory) throw new Error('Unable to find node_modules for the Harmony project.');
    directory = parent;
  }
}

const BundlerPlugin = {
  pluginId: 'expo-harmony-bundler',
  apply(node) {
    hvigor.nodesEvaluated(() => {
      const app = node.getContext(OhosPluginId.OHOS_APP_PLUGIN);
      const mode = app.getBuildMode() === 'release' ? 'release' : 'debug';

      publishHarmonyNativeRuntime(ProjectRoot, mode);
      const bundle = prepareHarmonyBundleTask(
        ProjectRoot, mode, finish => hvigor.buildFinished(finish), EmbeddedBundle
      );

      node.subNodes((moduleNode) => {
        const hapContext = moduleNode.getContext(OhosPluginId.OHOS_HAP_PLUGIN);
        if (hapContext?.getModuleType() !== 'entry') return;

        hapContext.targets((target) => {
          const targetName = target.getTargetName();

          moduleNode.registerTask({
            name: `${targetName}@ExpoHarmonyBundle`,
            run: bundle,
            dependencies: [`${targetName}@ProcessResource`],
            postDependencies: [`${targetName}@CompileResource`],
          });
        });
      });
    });
  },
};

export default {
  system: appTasks,
  plugins: [
    createRNOHProjectPlugin({
      nodeModulesPath: NodeModules,
      bundler: { enabled: false },
    }),
    BundlerPlugin,
  ],
};
